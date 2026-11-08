#!/usr/bin/env bash
# padd 交叉编译（x86_64 Debian/WSL → aarch64 A733）
#
# 依赖：sysroot 由 microduck-runtime/scripts/cross-sysroot.sh 生成（含 libudev-dev），
#       交叉工具链 aarch64-linux-gnu-gcc。
# 产物：microduck-runtime/target/aarch64-unknown-linux-gnu/release/padd
#
# 说明：padd 依赖 gilrs → libudev-sys，pkg-config 必须在 sysroot 里找 libudev.pc，
#       并让链接器在 sysroot 里找到 libudev.so 的传递依赖（libcap）。
set -euo pipefail

RT=${RT:-/mnt/c/Users/JC/.dsh/bot/workspace/microduck/microduck-runtime}
SYSROOT=${SYSROOT:-$HOME/duck-aarch64-sysroot}
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_ALLOW_CROSS=1
export RUSTFLAGS="-L $SYSROOT/usr/lib/aarch64-linux-gnu"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc

cd "$RT"
cargo build --release --target aarch64-unknown-linux-gnu -p padd
ls -l target/aarch64-unknown-linux-gnu/release/padd
md5sum target/aarch64-unknown-linux-gnu/release/padd
