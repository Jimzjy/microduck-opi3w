#!/usr/bin/env bash
#
# build-aic31xx-module.sh — out-of-tree 交叉编译 snd-soc-tlv320aic31xx.ko
# （A733 音频 codec TLV320AIC3104 的驱动；Armbian trixie vendor 6.6.98 内核
#   实测 # CONFIG_SND_SOC_TLV320AIC31XX is not set，必须自己编模块）
#
# ⚠ 本脚本记录的是在 WSL2 Debian（root）里人工执行过的完整流程。其中
#   多步是对 headers 包裁剪缺失文件的手工补丁，无法一条 make 走完，
#   所以写成带注释的分步脚本；换内核版本时按注释重对版本号即可。
#
# 用法（WSL，root）：
#   bash build-aic31xx-module.sh <linux-headers-*.deb> <驱动源码目录> [输出目录]
#
# 依赖：
#   apt install gcc-aarch64-linux-gnu binutils make gawk   # 交叉工具链
#   headers 包：apt.armbian.com 的 linux-headers-vendor-sun60iw2_*_arm64.deb
#   驱动源码：厂商树 orangepi-xunlong/linux-orangepi 分支 orange-pi-6.6-sun60iw2
#     sound/soc/codecs/tlv320aic31xx.c + tlv320aic31xx.h（记录 commit 号！）
#
# 产物：<输出目录>/snd-soc-tlv320aic31xx.ko
#   vermagic 必须 = 6.6.98-vendor-sun60iw2（脚本末尾自检）

set -euo pipefail

DEB="${1:?usage: build-aic31xx-module.sh <headers.deb> <srcdir> [outdir]}"
SRC="${2:?usage: build-aic31xx-module.sh <headers.deb> <srcdir> [outdir]}"
OUT="${3:-$(pwd)/aic31xx-module}"
REL="6.6.98-vendor-sun60iw2"
K="/root/hdr/usr/src/linux-headers-$REL"
CC="aarch64-linux-gnu-"

say() { printf '%s\n' "$*"; }

# ── 0. 解 headers 包 ─────────────────────────────────────────────────────────
mkdir -p /root/hdr
dpkg-deb -x "$DEB" /root/hdr
[ -d "$K" ] || { say "error: headers 解包后找不到 $K"; exit 1; }
cd "$K"

# ── 1. modules_prepare 会死循环（tools/bpf/resolve_btfids 无限递归），不跑；
#       只补最小必需品。headers 包裁掉了 fixdep → host 编一个：
gcc -O2 -Wall -o scripts/basic/fixdep scripts/basic/fixdep.c

# ── 2. prepare 还会生成 arch/arm64/tools/ 头，headers 缺生成器和输入 →
#       从内核源码 commit 拉回（版本必须与 headers 同源）：
#         arch/arm64/tools/gen-cpucaps.awk gen-sysreg.awk cpucaps sysreg
#       并手写 tools/Makefile（见仓库 img/arm64-tools-Makefile 留档）：
#         kapi 目标生成 include/generated/cpucaps.h 与 sysreg-defs.h
[ -f arch/arm64/tools/gen-cpucaps.awk ] || {
	say "!! 缺 arch/arm64/tools/* 生成器，请先从厂商树同 commit 拉回再重跑"
	exit 1
}

# ── 3. modpost 也是 headers 缺的（make scripts 因 prepare 未完而不动）。
#       手工构建：
#   3a) elfconfig.h：host gcc 编 empty.o + mk_elfconfig
gcc -O2 -o /tmp/empty.o -x c /dev/null -c
gcc -O2 -o scripts/mod/mk_elfconfig scripts/mod/mk_elfconfig.c
(cd scripts/mod && ./mk_elfconfig < /tmp/empty.o > elfconfig.h)
#   3b) devicetable-offsets.h：交叉 gcc -S 出 .s（行格式 .ascii "->NAME VALUE EXPR"），
#       awk 抽出写 #define（真正的 kbuild sed 语法不同，别照抄内核脚本）
gcc "$CC" -S -o /tmp/dto.s scripts/mod/devicetable-offsets.c || true
#   3c) modpost 本体：host gcc 链四个 .c
# gcc -O2 -Wall -o scripts/mod/modpost scripts/mod/modpost.c \
#     scripts/mod/file2alias.c scripts/mod/sumversion.c scripts/mod/symsearch.c \
#     -I scripts/mod
# （file2alias 需要 devicetable-offsets.h 存在；3b 的 .s→.h 转换见 img/build-modpost-manual2.sh）

# ── 4. 关键坑：modules_prepare 会把 include/config/kernel.release 和
#       include/generated/utsrelease.h 重写成 "6.6.98"（headers 无 git，
#       setlocalversion 丢后缀）→ 编出的 .ko vermagic 错、板上拒载。
#       每次编译前强制写回：
mkdir -p include/config include/generated
printf '%s\n' "$REL" > include/config/kernel.release
printf '#define UTS_RELEASE "%s"\n' "$REL" > include/generated/utsrelease.h

# ── 5. 编模块 ────────────────────────────────────────────────────────────────
mkdir -p "$OUT"
cp -f "$SRC"/tlv320aic31xx.c "$SRC"/tlv320aic31xx.h "$OUT/"
cat >"$OUT/Makefile" <<'MK'
obj-m += snd-soc-tlv320aic31xx.o
snd-soc-tlv320aic31xx-objs := tlv320aic31xx.o
MK
make -C "$K" M="$OUT" ARCH=arm64 CROSS_COMPILE="$CC" modules 2>&1 | tail -4

# ── 6. 自检 ──────────────────────────────────────────────────────────────────
VM=$(modinfo "$OUT/snd-soc-tlv320aic31xx.ko" | awk -F': *' '/^vermagic/{print $2}')
say "vermagic: $VM"
case "$VM" in
"$REL "*) say "OK: .ko ready at $OUT/snd-soc-tlv320aic31xx.ko" ;;
*) say "FATAL: vermagic mismatch, expect prefix $REL"; exit 1 ;;
esac
