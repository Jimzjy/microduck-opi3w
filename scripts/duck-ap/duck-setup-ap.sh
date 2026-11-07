#!/bin/bash
# duck-setup-ap: first-boot WiFi provisioning.
#
# Logic:
#   1. marker /var/lib/robot/ap-provisioned present -> this device already has
#      working WiFi; do nothing on every later boot.
#   2. otherwise wait up to WAIT_FOR_WIFI seconds for wlan0 to get an IPv4
#      address. Got one -> write the marker and exit (existing config works).
#   3. still nothing -> the device has no usable WiFi config. Start a setup
#      access point (hostapd + dnsmasq + a config page on port 80) and stay
#      running until the page writes credentials and a client connection
#      succeeds, then tear the AP down and write the marker.
#
# Channel note: channel 149 (5 GHz, 5745 MHz) is used because on this board's
# AIC8800 the low 5 GHz channels are DFS-flagged for AP mode and hostapd
# refuses them ("Primary frequency not allowed", flags 0x1979 RADAR).
#
# The AP runs on a separate virtual interface (wlan0ap), so a STA connection
# on wlan0 keeps working while the AP is up (tested: SSH survives).
set -u
MARKER=/var/lib/robot/ap-provisioned
RUN=/run/duck-ap
WAIT_FOR_WIFI=${DUCK_AP_WAIT:-45}
WLAN=${DUCK_AP_WLAN:-wlan0}

log() { echo "duck-ap: $*"; }

# DUCK_AP_FORCE=1: manual test of the AP path without touching the real WiFi
# config — skips the marker check and the wait, never writes the marker.
if [ "${DUCK_AP_FORCE:-0}" = "1" ]; then
    log "FORCE mode: starting setup AP regardless of wlan0 state"
elif [ -e "$MARKER" ]; then
    log "marker present, already provisioned"; exit 0
else
    # wait for an existing WiFi configuration to associate
    deadline=$(( $(date +%s) + WAIT_FOR_WIFI ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if ip -4 addr show "$WLAN" 2>/dev/null | grep -q ' inet '; then
            log "$WLAN has an address, existing WiFi config works"
            mkdir -p "$(dirname "$MARKER")"; touch "$MARKER"
            exit 0
        fi
        sleep 3
    done
    log "no WiFi address after ${WAIT_FOR_WIFI}s, starting setup AP"
fi

mkdir -p "$RUN"
systemctl stop dnsmasq 2>/dev/null || true

# AP SSID: microduck-XXXX from the interface MAC
mac=$(cat /sys/class/net/$WLAN/address | tr -d ':')
suffix=${mac: -4}
APDEV=${WLAN}ap
# virtual AP interface needs the parent link; fail loudly if it cannot be created
iw dev "$WLAN" interface add "$APDEV" type __ap || { log "cannot create $APDEV"; exit 1; }
ip link set "$APDEV" up
ip addr add 192.168.4.1/24 dev "$APDEV"

cat > "$RUN/hostapd.conf" <<EOF
interface=$APDEV
driver=nl80211
ssid=microduck-$suffix
country_code=CN
hw_mode=a
channel=149
ieee80211n=1
ieee80211ac=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=12345678
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

cat > "$RUN/dnsmasq.conf" <<EOF
interface=$APDEV
bind-interfaces
dhcp-range=192.168.4.10,192.168.4.50,12h
except-interface=lo
EOF

hostapd -B "$RUN/hostapd.conf" || { log "hostapd failed to start"; exit 1; }
dnsmasq -C "$RUN/dnsmasq.conf" --pid-file="$RUN/dnsmasq.pid"
log "setup AP is up: microduck-$suffix, http://192.168.4.1"

ap_teardown() {
    pkill -f "hostapd.conf" 2>/dev/null || true
    [ -f "$RUN/dnsmasq.pid" ] && kill "$(cat "$RUN/dnsmasq.pid")" 2>/dev/null || true
    ip addr del 192.168.4.1/24 dev "$APDEV" 2>/dev/null || true
    iw dev "$APDEV" del 2>/dev/null || true
}
# run on TERM (systemctl stop) and on normal exit — not only after the server
trap ap_teardown TERM INT EXIT

# 3. serve the config page until credentials are applied (the server tears
#    down the AP itself on success and exits 0; on stop, systemd cleans up).
python3 /usr/local/bin/duck-ap-server.py --wlan "$WLAN"
rc=$?

log "setup AP stopped (server rc=$rc)"
trap - TERM INT EXIT
exit "$rc"
