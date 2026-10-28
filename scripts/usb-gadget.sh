#!/bin/sh
# usb-gadget.sh — 把 OTG Type-C 口变成 USB 虚拟网卡（RNDIS+NCM）。
#
# 背景：装上 HAT 后 40-pin 被盖住，串口没法接；WiFi 挂了/系统半死时，
# 这条 USB 网线是最后的调试通道（Windows 直接 ssh root@10.55.0.1）。
#
# vendor 内核实测：CONFIG_USB_CONFIGFS=y、F_RNDIS/F_NCM=y、USB_SUNXI_DWC3=y，
# 全内置，不需要任何模块安装。
#
# 用法：由 usb-gadget.service 在开机时调用（也可手工跑）。
# Windows 侧：OTG 口插电脑 → 出现 RNDIS 网卡 → 手动设 IP 10.55.0.2/24
#             → ssh root@10.55.0.1
set -e

CONFIGFS=/sys/kernel/config
GADGET="$CONFIGFS/usb_gadget/duck"

# configfs 没挂就挂
[ -d "$CONFIGFS/usb_gadget" ] || mountpoint -q "$CONFIGFS" || mount -t configfs none "$CONFIGFS"
mkdir -p "$CONFIGFS/usb_gadget"

# 已配置过且 UDC 已绑定：幂等退出
if [ -f "$GADGET/UDC" ] && [ -s "$GADGET/UDC" ]; then
	echo "usb-gadget: already bound to $(cat "$GADGET/UDC"), nothing to do"
	exit 0
fi

mkdir -p "$GADGET"
cd "$GADGET"

# Linux Foundation 的 VID/PID（社区通用，多配置 gadget 惯例）
echo 0x1d6b >idVendor
echo 0x0104 >idProduct
echo 0x0100 >bcdDevice
echo 0x0200 >bcdUSB

mkdir -p strings/0x409
echo "microduck-opi3w" >strings/0x409/manufacturer
echo "MicroDuck USB debug" >strings/0x409/product
echo "duck0001" >strings/0x409/serialnumber

mkdir -p functions/rndis.usb0 functions/ncm.usb0

# config c.1 = RNDIS（Windows 免驱），c.2 = NCM（Linux/macOS）
mkdir -p configs/c.1/strings/0x409 configs/c.2/strings/0x409
echo "RNDIS" >configs/c.1/strings/0x409/configuration
echo "NCM" >configs/c.2/strings/0x409/configuration
ln -sf functions/rndis.usb0 configs/c.1/
ln -sf functions/ncm.usb0 configs/c.2/

# MSFT OS 描述符：让 Win10/11 自动把 c.1 绑成 RNDIS 网卡，不用装驱动
echo 1 >os_desc/use
echo 0xcd >os_desc/b_vendor_code
echo "MSFT100" >os_desc/qw_sign
echo 1 >functions/rndis.usb0/os_desc/use
echo "RNDIS" >functions/rndis.usb0/os_desc/interface.rndis/compatible_id
echo "5162001" >functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
ln -sf configs/c.1 os_desc/g.1

UDC=$(find /sys/class/udc -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | head -1)
[ -n "$UDC" ] || {
	echo "usb-gadget: no UDC (not an OTG port, or cable in host mode)" >&2
	exit 0
}
echo "$UDC" >UDC
echo "usb-gadget: bound to $UDC (rndis+ncm)"
