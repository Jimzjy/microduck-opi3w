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
#   5. 可选 --module <.ko>：out-of-tree 内核模块装进 /lib/modules/<kver>/kernel/
#      并跑 depmod（当前只有 snd-soc-tlv320aic31xx.ko，codec 驱动 vendor 内核没编）
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
MODULE_KO=""
MOUNT_DIR=""

say() { printf '%s\n' "$*"; }
die() { say "error: $*"; exit 1; }

usage() {
	say "usage: sudo $0 <base.img> [--module <.ko>] [--payload <dir>]"
	say "       sudo $0 --mount <已挂载的rootfs目录> [--module <.ko>] [--payload <dir>]"
	say "（--mount 给没有 loop 设备的环境用：比如 WSL2 里 wsl --mount --vhd 挂进来的分区）"
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--payload)
		[ $# -ge 2 ] || usage
		PAYLOAD_DIR="$2"
		shift 2
		;;
	--module)
		[ $# -ge 2 ] || usage
		MODULE_KO="$2"
		shift 2
		;;
	--mount)
		[ $# -ge 2 ] || usage
		MOUNT_DIR="$2"
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

[ -n "$BASE_IMG" ] || [ -n "$MOUNT_DIR" ] || usage
[ -z "$BASE_IMG" ] || [ -z "$MOUNT_DIR" ] || die "--mount 和 <base.img> 二选一"
[ "$(id -u)" = 0 ] || die "needs root"
[ -z "$BASE_IMG" ] || [ -f "$BASE_IMG" ] || die "not a file: $BASE_IMG"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY_DIR="$REPO_DIR/hardware/overlay"
SETUP_SH="$REPO_DIR/scripts/setup-board-a733.sh"

for f in "$OVERLAY_DIR/uart2-dxl.dtbo" "$OVERLAY_DIR/audio-a733.dtbo" "$SETUP_SH"; do
	[ -f "$f" ] || die "missing: $f（dtbo 用 dtc -@ 编译 .dts 生成）"
done

# ── 挂载 ─────────────────────────────────────────────────────────────────────
if [ -n "$MOUNT_DIR" ]; then
	[ -d "$MOUNT_DIR/boot" ] || die "$MOUNT_DIR 不像挂载好的 rootfs（没有 /boot）"
	MNT="$MOUNT_DIR"
	say ">> using pre-mounted rootfs at $MNT"
else
	# 单分区 ext4，起点 = 扇区 65536 × 512B = 32 MiB（用 fdisk 实测，不写死）
	[ "$(command -v losetup)" ] || die "losetup not found（WSL2 没有 loop，请用 --mount 模式或真机 Linux）"
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
fi

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

# ── 3b. USB gadget 虚拟网卡（OTG 口的救命调试通道）───────────────────────────
# HAT 装上后串口被盖住；OTG Type-C 变 RNDIS+NCM 网卡：ssh root@10.55.0.1
install -m 0755 "$REPO_DIR/scripts/usb-gadget.sh" "$MNT/usr/local/sbin/usb-gadget.sh"

cat >"$MNT/etc/systemd/system/usb-gadget.service" <<'UNIT'
[Unit]
Description=USB RNDIS+NCM ethernet gadget on OTG port
After=systemd-modules-load.service
Before=systemd-networkd.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/usb-gadget.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

ln -sfn /etc/systemd/system/usb-gadget.service \
	"$MNT/etc/systemd/system/multi-user.target.wants/usb-gadget.service"

mkdir -p "$MNT/etc/systemd/network"
cat >"$MNT/etc/systemd/network/20-usb0.network" <<'NETDEV'
[Match]
Name=usb0

[Network]
Address=10.55.0.1/24
NETDEV
say ">> usb-gadget (RNDIS+NCM) installed, usb0 = 10.55.0.1/24"

# ── 4. 可选内核模块（--module）──────────────────────────────────────────────
if [ -n "$MODULE_KO" ]; then
	[ -f "$MODULE_KO" ] || die "module not found: $MODULE_KO"
	KVER=$(find "$MNT/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)
	[ -n "$KVER" ] || die "no kernel modules dir in image"
	KVER_COUNT=$(find "$MNT/lib/modules" -mindepth 1 -maxdepth 1 -type d | wc -l)
	[ "$KVER_COUNT" -eq 1 ] || die "multiple kernel versions in /lib/modules, ambiguous target: $KVER_COUNT"
	mkdir -p "$MNT/lib/modules/$KVER/kernel/sound/soc/codecs"
	install -m 0644 "$MODULE_KO" \
		"$MNT/lib/modules/$KVER/kernel/sound/soc/codecs/$(basename "$MODULE_KO")"
	depmod -b "$MNT" "$KVER"
	say ">> module installed for $KVER: $(basename "$MODULE_KO")"
fi

# ── 5. 可选 payload ──────────────────────────────────────────────────────────
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
if [ -n "$BASE_IMG" ]; then
	say ">> done: $BASE_IMG is ready to flash."
else
	say ">> done: mounted rootfs updated（如果是 wsl --mount 的 VHD，记得 wsl --unmount 后转回 img 再烧卡）"
fi
