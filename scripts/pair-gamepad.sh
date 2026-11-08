#!/usr/bin/env bash
# 在板上配一个蓝牙手柄（Xbox One S / 经典蓝牙那一类）。
#
#   ./pair-gamepad.sh EC:83:50:7C:B5:EC [adapter-mac]
#
# 为什么要一个脚本、而不是几条 bluetoothctl 命令：
#   * 扫描出来的设备在 scan off 后就不在 bluetoothctl 的缓存里了，单独 connect 会报
#     "Device ... not available"——发现和连接必须在同一个会话里。
#   * 连接前必须停掉 discovery，否则 Connect() 会间歇失败。
#   * agent 要显式注册，否则配对时无人应答 IO capability。
# 顺序（BR/EDR，Xbox One S / DualSense / 无名 Pro Controller）：
#   pair → trust → connect。反过来（先 connect）会留下 "Paired: yes / Bonded: no" 的假配对，
#   HID 通道被蓝耳拒绝（hidp_add_connection: Rejected connection from !bonded device），
#   /dev/input 里永远不会有 js0。
# LE 手柄（Xbox Series 那一类）顺序相反：connect → trust，先 Pair() 会 AuthenticationCanceled。
set -euo pipefail
H=${DUCK_HOST:-192.168.100.144}
P=${DUCK_PASS:-123456}
MAC=${1:?usage: pair-gamepad.sh <MAC> [adapter-mac]}
ADAPTER=${2:-B4:65:DC:91:6E:00}
SSHP="sshpass -p $P ssh -o StrictHostKeyChecking=no -o ConnectTimeout=6 root@$H"

$SSHP "MAC=$MAC ADAPTER=$ADAPTER bash -s" <<'EOS'
set -u
echo "== power on"
bluetoothctl power on >/dev/null 2>&1 || true
(
  echo 'agent NoInputNoOutput'
  echo 'default-agent'
  sleep 1
  echo 'scan on'
  sleep 8
  echo 'scan off'
  sleep 1
  echo "pair $MAC"
  sleep 20
  echo "trust $MAC"
  sleep 2
  echo "connect $MAC"
  sleep 15
  echo "info $MAC"
  sleep 2
  echo 'quit'
) | timeout 100 bluetoothctl 2>&1 | grep -vE 'RSSI|ServiceData|^  [0-9a-f]{2} |DEL\]' | tail -30

echo "== post state"
bluetoothctl info "$MAC" 2>&1 | sed -n '1,16p'
echo "== bond files"
ls -la "/var/lib/bluetooth/$ADAPTER/$MAC/" 2>&1
echo "== input nodes"
ls /dev/input/ | tr '\n' ' '; echo
echo "== hid journal"
journalctl -u bluetooth --no-pager -n 6 2>&1 | tail -6
EOS
