#!/usr/bin/env bash
# 把 padd 装到板子上（A733 布局：/usr/local/bin + /etc/systemd/system）。幂等，可重跑。
#
#   ./deploy-padd.sh /path/to/padd [/path/to/padd.service]
#
# 做六件事：
#   1. robotd.service 加 Group=robot（socket 是 0660 root:robot，padd 不加组连不上）
#   2. 建 padd 用户（sysusers）
#   3. 装二进制与 unit
#   4. robotd.toml 里 [netpad] enabled = false（padd 的 --should-run 开关；netpadd 与本进程互斥）
#   5. 当前这次运行先 chgrp robot /run/robotd.sock（不改 robotd，不重启）
#   6. enable + restart padd
set -euo pipefail
H=${DUCK_HOST:-192.168.100.144}
P=${DUCK_PASS:-123456}
SSHP="sshpass -p $P ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@$H"
SCP="sshpass -p $P scp -o StrictHostKeyChecking=no"
HERE=$(cd "$(dirname "$0")" && pwd)
BIN="${1:?usage: deploy-padd.sh <padd> [padd.service]}"
UNIT="${2:-$HERE/padd.service}"

$SCP "$BIN"  root@$H:/tmp/padd
$SCP "$UNIT" root@$H:/tmp/padd.service

$SSHP 'bash -s' <<'EOS'
set -eu
echo "== 1. robotd.service 加 Group=robot（不重启，下次 robotd 重启生效）"
if ! grep -q '^Group=robot' /etc/systemd/system/robotd.service; then
    cp -a /etc/systemd/system/robotd.service /etc/systemd/system/robotd.service.bak-padd
    awk '{print} /^ExecStart=/ && !done {print "Group=robot"; done=1}' \
        /etc/systemd/system/robotd.service.bak-padd > /etc/systemd/system/robotd.service
    echo "   added"
else
    echo "   already there"
fi

echo "== 2. padd 用户 / 组"
install -d /usr/lib/sysusers.d
cat > /usr/lib/sysusers.d/padd.conf <<'CONF'
u padd - "Robot gamepad intent client" - -
CONF
systemd-sysusers padd.conf
id padd

echo "== 3. padd 二进制 + unit"
install -m 755 /tmp/padd /usr/local/bin/padd
install -m 644 /tmp/padd.service /etc/systemd/system/padd.service
systemctl daemon-reload

echo "== 4. [netpad] enabled=false（padd --should-run 的开关）"
cp -a /etc/robot/robotd.toml /etc/robot/robotd.toml.bak-padd
awk '
    /^\[netpad\]/ {insec=1; print; next}
    /^\[/ && insec {insec=0}
    insec && /^[[:space:]]*enabled[[:space:]]*=/ {$0="enabled = false"}
    {print}
' /etc/robot/robotd.toml.bak-padd > /etc/robot/robotd.toml
grep -A2 '^\[netpad\]' /etc/robot/robotd.toml

echo "== 5. 让 padd 现在就能连 robotd（临时；robotd 下次重启后由 Group=robot 接管）"
chgrp robot /run/robotd.sock 2>/dev/null || true
ls -l /run/robotd.sock

echo "== 6. 启动"
systemctl enable padd.service
systemctl restart padd.service
sleep 3
systemctl is-active padd.service
journalctl -u padd -n 15 --no-pager -o cat
EOS
