#!/bin/bash
# 板侧：从 A733 的 IMX219 抓 N 帧原始图（RG10 / 10bit Bayer）。
#
#   ./camera-snapshot.sh [设备] [输出文件] [帧数]
#   ./camera-snapshot.sh /dev/video0 /tmp/snap.raw 1
#
# ── 为什么必须带 --set-input=0 ──────────────────────────────────────────────
# 全志 vendor 的 vin_v4l2 把「打开 pipeline」放在 VIDIOC_S_INPUT 里，而不是
# open() 里：__vin_s_input() → __vin_sensor_setup_link() +
# __vin_pipeline_open(prepare=true) → 传感器 s_power（开 MCLK、上电）＋
# ISP/scaler init。没有 S_INPUT 时 open() 只置 VIN_LPM/VIN_BUSY：
#   - S_FMT 能过（probe 时 prepare 过一遍），但整条链路没有 configure；
#   - STREAMON 不报错，传感器 s_stream 从不被调用，MCLK 一直是关的，
#     中断计数恒为 0，一帧都拿不到。
# 这就是「设备在、格式能设、就是没图」的全部原因；换回原厂模块也一样，
# 所以不要为此改驱动（本仓试过，错误的修法）。
#
# 抓完是原始 Bayer：RG10 = 每像素 16-bit 小端、低 10 位有效，高度按 8 行
# 对齐（1920x1080 实际 1920x1088）。转 PNG 在 PC 上跑 scripts/cam-raw2png.py。
set -euo pipefail

DEV=${1:-/dev/video0}
OUT=${2:-/tmp/snap.raw}
COUNT=${3:-1}

[ -e "$DEV" ] || { echo "no $DEV — modprobe vin_v4l2（开机自启见 /etc/modules-load.d/vin_v4l2.conf）" >&2; exit 1; }
command -v v4l2-ctl >/dev/null || { echo "v4l2-ctl missing: apt install v4l-utils" >&2; exit 1; }
lsmod | grep -q '^vin_v4l2' || echo "warning: vin_v4l2 not loaded; trying anyway" >&2

# 每次 v4l2-ctl 都是独立的 open/close，S_INPUT 必须和抓帧在同一个进程里：
# 单独执行一次 v4l2-ctl --set-input=0 会随进程退出把 pipeline 关掉。
# timeout 兜底：驱动在某些失败路径上会卡在 DQBUF 里不返回。
timeout 30 v4l2-ctl -d "$DEV" \
    --set-input=0 \
    --set-fmt-video=width=1920,height=1080,pixelformat=RG10 \
    --stream-mmap=4 --stream-count="$COUNT" --stream-to="$OUT"

sz=$(stat -c%s "$OUT" 2>/dev/null || echo 0)
echo "captured ${COUNT} frame(s) → $OUT (${sz} B)"
if [ "$sz" = 0 ]; then
    echo "0 字节 = 没有帧。先确认 bldo2（VCC_3V3_CSI）是 enabled，再 dmesg | tail" >&2
    exit 1
fi
echo "PC 上转 PNG: python cam-raw2png.py $OUT out.png"
