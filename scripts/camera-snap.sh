#!/usr/bin/env bash
# One fresh frame, with the camera started only for as long as it takes.
#
#   camera-snap [OUT.uyvy]
#
# mediad is normally stopped (camera-launcher keeps it that way); this starts it if the
# snapshot socket is not there yet, asks for one frame, and lets the launcher's idle rule
# stop it again about ten seconds later. Nothing keeps a video stream open.
set -eu

out=${1:-/tmp/snap.uyvy}
sock=/run/mediad/media.sock

if [ ! -S "$sock" ]; then
    systemctl start mediad
fi

i=0
while [ "$i" -lt 200 ]; do
    if [ -S "$sock" ] && robotctl frame --output "$out" 2>/tmp/camera-snap.geom; then
        cat /tmp/camera-snap.geom >&2
        echo "$out"
        exit 0
    fi
    i=$((i + 1))
    sleep 0.1
done

echo "camera-snap: mediad did not deliver a frame within 20 s" >&2
exit 1
