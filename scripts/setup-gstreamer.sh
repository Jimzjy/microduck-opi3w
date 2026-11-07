#!/bin/bash
# 板侧：装齐 mediad 要用的 GStreamer，以及它没有 Debian 包的 webrtcsink。
#
#   ./setup-gstreamer.sh              # 装（用板子当前的 apt 源）
#   ./setup-gstreamer.sh --mirror     # 先把 Debian 源换成清华镜像再装（国内网络）
#   ./setup-gstreamer.sh --status     # 只体检，不改任何东西
#
# ── 为什么需要这三件事 ──────────────────────────────────────────────────────
# 1. 镜像里根本没有 GStreamer。mediad 是 GStreamer 程序，`ldd /usr/local/bin/mediad`
#    全是 `libgstwebrtc.so ... not found`，跑不起来。
# 2. bayer2rgb 在 gstreamer1.0-plugins-bad 里。A733 的 vin_v4l2 只能出 Bayer
#    （RG10），debayer 只能软件做；实测 1080p → UYVY 在 A733 的八核上 32 fps，
#    720p 档位绰绰有余。
# 3. webrtcsink 在 Debian **任何** suite 里都没有（它在 gst-plugins-rs，Debian 不
#    打这个包），而 mediad 建 pipeline 时硬性要求它（pipeline.rs:558）。上游
#    pollen-robotics 已经把 A733 能用的预编译件发在 microduck-gst-plugins 的
#    release 里，直接装机，不用在板子上装 Rust 从头编（板子也没 cargo）。
#
# 装完用这个验：
#   gst-inspect-1.0 webrtcsink | head -3     # rswebrtc，WebRTCSink
#   gst-inspect-1.0 bayer2rgb  | head -3
#   gst-inspect-1.0 rsrtp      | grep Version
set -euo pipefail

MODE=install
case "${1:-}" in
    --status) MODE=status ;;
    --mirror) MODE=mirror ;;
    "") ;;
    *) echo "usage: $(basename "$0") [--mirror|--status]" >&2; exit 2 ;;
esac

# mediad 运行时真正用到的元素分散在 base/good/bad/ugly 四个包里，一个一个点出来：
#   - base：videoconvert / videoscale / appsrc 的注册、videotestsrc
#   - good：v4l2src（别的板子走这条）、rtph264pay、rtspsrc
#   - bad：bayer2rgb（本板唯一的 debayer 手段）、openh264enc（没硬件编码时用它）
#   - ugly：x264enc 式的兜底
# v4l-utils 是硬依赖：mediad 用 media-ctl 钉 sensor 模式、用 v4l2-ctl 抓帧和写曝光。
PACKAGES=(
    gstreamer1.0-tools
    gstreamer1.0-plugins-base
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
    gstreamer1.0-nice
    v4l-utils
)

# microduck-gst-plugins v3（2026-08-25），gst-plugins-rs 0.15.3 编的 aarch64 件。
# 里面三个 .so：libgstrswebrtc.so（webrtcsink）、libgstrsrtp.so（rsrtp）、
# libgstrockchipmpp.so（瑞芯微 MPP，A733 上没用，且缺 librockchip_mpp，不装）。
PLUGIN_URL=https://github.com/pollen-robotics/microduck-gst-plugins/releases/download/v3/microduck-gst-plugins-v3-aarch64.tar.gz
PLUGIN_SHA256=5cd133133587467b9724fe386639888b40e420517626199049ff52ca0b4e56a9
PLUGIN_SOS=(libgstrswebrtc.so libgstrsrtp.so)

PLUGIN_DIR=$(pkg-config --variable=pluginsdir gstreamer-1.0 2>/dev/null || echo /usr/lib/aarch64-linux-gnu/gstreamer-1.0)

say() { printf '\n── %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

status() {
    local ok=0
    say "apt 包"
    for p in "${PACKAGES[@]}"; do
        if dpkg -s "$p" >/dev/null 2>&1; then
            printf '  %-40s %s\n' "$p" "$(dpkg-query -W -f='${Version}' "$p")"
        else
            printf '  %-40s MISSING\n' "$p"; ok=1
        fi
    done

    say "webrtcsink（预编译件）"
    for so in "${PLUGIN_SOS[@]}"; do
        if [ -e "$PLUGIN_DIR/$so" ]; then
            printf '  %-24s %s (md5 %s)\n' "$so" "$(stat -c%s "$PLUGIN_DIR/$so") B" \
                "$(md5sum "$PLUGIN_DIR/$so" | cut -d' ' -f1)"
        else
            printf '  %-24s MISSING\n' "$so"; ok=1
        fi
    done

    say "元素"
    for e in webrtcsink rsrtp bayer2rgb videoconvert videoscale v4l2src openh264enc; do
        if gst-inspect-1.0 "$e" >/dev/null 2>&1; then
            printf '  %-14s ok\n' "$e"
        else
            printf '  %-14s MISSING\n' "$e"; ok=1
        fi
    done

    say "工具"
    for t in v4l2-ctl media-ctl; do
        if command -v "$t" >/dev/null; then printf '  %-14s %s\n' "$t" "$(command -v "$t")"
        else printf '  %-14s MISSING\n' "$t"; ok=1; fi
    done

    [ "$ok" = 0 ] && echo && echo "GStreamer 这一层齐了。" || { echo; echo "有缺项，跑 $(basename "$0") 补上。"; return 1; }
}

# 只换 Debian 的源，不碰 apt.armbian.com：rambian-config 那个源走 GitHub，
# 国内经常把 apt-get update 卡死五分钟以上，脚本里不动它，卡了先禁用。
mirror() {
    local f=/etc/apt/sources.list.d/debian.sources
    [ -f "$f" ] || die "no $f (not a deb822 Debian install?)"
    [ -f "$f.bak-gst" ] || cp -a "$f" "$f.bak-gst"
    # 只改 debian / debian-security 两个 stanza 的 URIs 行，Suite/Components 一概不动：
    # 以前把 trixie-security 的路径写成主库，apt 直接报
    # "The repository '... trixie-security Release' does not have a Release file"。
    python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
def fix(match):
    stanza = match.group(0)
    if 'trixie-security' in stanza:
        return re.sub(r'^URIs:.*$', 'URIs: http://mirrors.tuna.tsinghua.edu.cn/debian-security', stanza, flags=re.M)
    return re.sub(r'^URIs:.*$', 'URIs: http://mirrors.tuna.tsinghua.edu.cn/debian', stanza, flags=re.M)
open(path, 'w').write(re.sub(r'^Types:.*?(?=\n\n|\Z)', fix, text, flags=re.M | re.S))
PY
    say "已换源（原文件备份在 $f.bak-gst）"
    grep -E '^(URIs|Suites):' "$f"
}

install_plugins() {
    local tmp; tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    say "下载 microduck-gst-plugins v3"
    curl -fsSL --retry 3 -o "$tmp/gstplug.tar.gz" "$PLUGIN_URL" ||
        die "下载失败：国内网络先 export https_proxy=http://<代理>:10808 再跑"
    echo "$PLUGIN_SHA256  $tmp/gstplug.tar.gz" | sha256sum -c - ||
        die "sha256 不符：上游 release 换了？核对 PLUGIN_SHA256 再装"
    tar -xzf "$tmp/gstplug.tar.gz" -C "$tmp"
    local dir; dir=$(find "$tmp" -maxdepth 1 -type d -name 'microduck-gst-plugins-*' | head -1)
    [ -n "$dir" ] || die "tar 包里没有预期目录"
    install -d "$PLUGIN_DIR"
    for so in "${PLUGIN_SOS[@]}"; do
        install -m 644 "$dir/$so" "$PLUGIN_DIR/$so"
        printf '  %-24s → %s\n' "$so" "$PLUGIN_DIR/$so"
    done
}

[ "$(id -u)" = 0 ] || die "以 root 跑（它要装包、往 $PLUGIN_DIR 写文件）"

if [ "$MODE" = status ]; then status; exit $?; fi

[ "$MODE" = mirror ] && mirror

say "apt-get update"
apt-get update

say "装 GStreamer 与 v4l-utils（${#PACKAGES[@]} 包）"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACKAGES[@]}"

install_plugins

status
