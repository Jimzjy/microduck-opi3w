#!/usr/bin/env bash
#
# apply-rootfs.sh — 把 microduck-opi3w 的改动叠进 Armbian trixie 底图，产出可烧录 img。
#
# 底图（2026-10-27 定）：Armbian_26.8.1_Orangepizero3w_trixie_vendor_6.6.98_minimal
#   - 单 ext4 分区，从扇区 65536（32 MiB）开始；Allwinner boot0/u-boot 在前面裸区
#   - /boot 在 rootfs 内（armbianEnv.txt + dtb/ + overlay-user/）
#   - 蓝牙 AIC8800D80 走 ttyS1 HCI（Armbian 板配置 SUN60IW2_UART_BT=yes）
#
# 做的事（幂等）：
#   1. looper 分区挂载底图 rootfs
#   2. overlay：uart2-dxl.dtbo + audio-a733.dtbo → /boot/overlay-user/，
#      armbianEnv.txt 追加 user_overlays=uart2-dxl audio-a733
#   3. 板侧脚本 setup-board-a733.sh → /usr/local/sbin/，
#      并装 microduck-firstboot.service（首次开机自动跑一次）
#   4. 可选 --payload <目录>：整体拷进 /opt/robot/payload/（固件二进制、robotd.toml、
#      Studio 等，由 firmware 仓库的 install 布局决定；没有就跳过，板侧手工装）
#
# 不做的事：
#   - 不动 boot0/u-boot 裸区（Armbian 出厂即 A733 版）
#   - 不在镜像里跑 apt（保最小改动，依赖装留给 setup 脚本在板上做/离线做）
#
# 用法（需要 root + loop 设备；WSL2 默认内核没有 loop 模块，请在真机 Linux/CI 里跑）：
#   sudo ./apply-rootfs.sh <base.img>            # 原地改 img
#   sudo ./apply-rootfs.sh <base.img> --payload <dir>
#
# 产物：改完的 <base.img> 即可 balenaEtcher/ Rufus 烧卡。

set -euo pipefail

BASE_IMG=""
PAYLOAD_DIR=""

say() { printf '%s\n' "$*"; }
die() { say "error: $*"; exit 1; }

usage() {
	say "usage: sudo $0 <base.img> [--payload <dir>]"
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--payload)
		[ $# -ge 2 ] || usage
		PAYLOAD_DIR="$2"
		shift 2
		;;
	-*) usage ;;
	*)
		[ -z "$BASE_IMG" ] || usage
		BASE_IMG="$1"
		shift
		;;
	esac
done

[ -n "$BASE_IMG" ] || usage
[ "$(id -u)" = 0 ] || die "needs root"
[ -f "$BASE_IMG" ] || die "not a file: $BASE_IMG"
[ "$(command -v losetup)" ] || die "losetup not found (WSL2 默认内核没有 loop 模块，请在真机 Linux 运行)"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY_DIR="$REPO_DIR/hardware/overlay"
SETUP_SH="$REPO_DIR/scripts/setup-board-a733.sh"

for f in "$OVERLAY_DIR/uart2-dxl.dtbo" "$OVERLAY_DIR/audio-a733.dtbo" "$SETUP_SH"; do
	[ -f "$f" ] || die "missing: $f（dtbo 用 dtc -@ 编译 .dts 生成）"
done

# ── 挂载 ─────────────────────────────────────────────────────────────────────
# 单分区 ext4，起点 = 扇区 65536 × 512B = 32 MiB（用 fdisk 实测，不写死）
PART_START=$(sfdisk -d "$BASE_IMG" 2>/dev/null | awk '/start=/{print $4; exit}')
[ -n "$PART_START" ] || die "cannot find partition start in $BASE_IMG"
OFFSET=$((PART_START * 512))
say ">> partition starts at sector $PART_START (offset $OFFSET)"

LOOP_DEV=$(losetup --find --show --offset "$OFFSET" "$BASE_IMG")
MNT=$(mktemp -d)
cleanup() {
	umount "$MNT" 2>/dev/null || true
	losetup -d "$LOOP_DEV" 2>/dev/null || true
	rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

mount "$LOOP_DEV" "$MNT"
say ">> mounted $LOOP_DEV at $MNT"

# ── 1. overlay ───────────────────────────────────────────────────────────────
mkdir -p "$MNT/boot/overlay-user"
install -m 0644 "$OVERLAY_DIR/uart2-dxl.dtbo" "$MNT/boot/overlay-user/"
install -m 0644 "$OVERLAY_DIR/audio-a733.dtbo" "$MNT/boot/overlay-user/"

ENV_TXT="$MNT/boot/armbianEnv.txt"
[ -f "$ENV_TXT" ] || die "armbianEnv.txt not found in image"
# 幂等：已有 user_overlays 行就整体替换，没有就追加
if grep -q '^user_overlays=' "$ENV_TXT"; then
	sed -i 's/^user_overlays=.*/user_overlays=uart2-dxl audio-a733/' "$ENV_TXT"
else
	printf 'user_overlays=uart2-dxl audio-a733\n' >>"$ENV_TXT"
fi
say ">> overlays installed, user_overlays=uart2-dxl audio-a733"

# ── 2. 板侧 bring-up + firstboot 服务 ────────────────────────────────────────
install -m 0755 "$SETUP_SH" "$MNT/usr/local/sbin/setup-board-a733.sh"

cat >"$MNT/etc/systemd/system/microduck-firstboot.service" <<'UNIT'
[Unit]
Description=microduck first-boot bring-up (setup-board-a733.sh)
ConditionPathExists=!/var/lib/robot/firstboot-done
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/setup-board-a733.sh
ExecStartPost=/bin/mkdir -p /var/lib/robot
ExecStartPost=/bin/touch /var/lib/robot/firstboot-done
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
UNIT

mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sfn /etc/systemd/system/microduck-firstboot.service \
	"$MNT/etc/systemd/system/multi-user.target.wants/microduck-firstboot.service"
say ">> setup-board-a733.sh + microduck-firstboot.service installed"

# ── 3. 可选 payload ──────────────────────────────────────────────────────────
if [ -n "$PAYLOAD_DIR" ]; then
	[ -d "$PAYLOAD_DIR" ] || die "payload dir not found: $PAYLOAD_DIR"
	mkdir -p "$MNT/opt/robot/payload"
	cp -a "$PAYLOAD_DIR"/. "$MNT/opt/robot/payload/"
	say ">> payload copied to /opt/robot/payload/ ($(du -sh "$MNT/opt/robot/payload" | cut -f1))"
else
	say ">> no --payload given, skip (固件二进制可在板上手工安装)"
fi

# ── 校验回显 ────────────────────────────────────────────────────────────────
say ">> verify: $(ls "$MNT/boot/overlay-user")"
say ">> verify: $(grep '^user_overlays=' "$ENV_TXT")"
say ">> done: $BASE_IMG is ready to flash."
