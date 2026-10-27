#!/usr/bin/env bash
# 交叉编译 microduck 运行时（robotd/robotctl）并布进镜像 payload。
# 在 WSL Debian 里跑：bash scripts/build-runtime.sh
#
# 前置（一次性）：
#   rustup stable + rustup target add aarch64-unknown-linux-gnu
#   apt install gcc-aarch64-linux-gnu        # 链接器
#   shellcheck（本脚本自检用）
#
# 产物：img/payload/runtime-bin/{robotd,robotctl,robotd.toml}
#   → apply-rootfs.sh --payload img/payload 布进镜像
#   → 板上首开 setup-board-a733.sh 检测到 payload 后装 /usr/local/bin 并启用 robotd.service
#
# 源：microduck-runtime 仓库 opi3w-feetech 分支
#   （pollen-robotics/microduck daemon-v0.17.9 + cherry-pick 8db8f00 Feetech 后端 + 移植修正 145c068）。
# GLIBC 基线实测 2.39（readelf 符号版本）→ 目标底图 Armbian trixie（glibc 2.41）满足。
# onnxruntime 由 ort crate 静态链入，板上无需 libonnxruntime.so。
set -euo pipefail

WS_ROOT=/mnt/c/Users/JC/.dsh/bot/workspace/microduck
RT="$WS_ROOT/microduck-runtime"
IMG="$WS_ROOT/img"
TARGET=aarch64-unknown-linux-gnu

# rustup 装在 ~/.cargo/bin，非交互 shell（wsl -u root -- bash ...）的 PATH 里没有它。
export PATH="${HOME}/.cargo/bin:${PATH}"

command -v cargo >/dev/null || { echo "cargo not found — run install-rustup.sh first"; exit 1; }
command -v aarch64-linux-gnu-gcc >/dev/null || { echo "aarch64-linux-gnu-gcc not found"; exit 1; }
command -v shellcheck >/dev/null || echo "warn: shellcheck missing, skip lint"

# 运行时改动过就先跑受影响 crate 的测试（全绿再出产物）
if [ -n "${SKIP_TEST:-}" ]; then
    echo ">> SKIP_TEST set — skipping cargo test"
else
    echo ">> cargo test (duck-control, robotd, robotd-params)"
    (cd "$RT" && cargo test -p duck-control -p robotd -p robotd-params --quiet)
fi

echo ">> cargo build --release --target $TARGET (robotd, robotctl)"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
(cd "$RT" && cargo build --release --target "$TARGET" -p robotd -p robotctl)

echo ">> verify ELF"
for bin in robotd robotctl; do
    f="$RT/target/$TARGET/release/$bin"
    [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' ')" = "7f454c46" ] || { echo "$bin: not ELF"; exit 1; }
    echo "   $bin $(stat -c%s "$f") bytes"
done

echo ">> stage payload"
mkdir -p "$IMG/payload/runtime-bin"
cp -f "$RT/target/$TARGET/release/robotd"   "$IMG/payload/runtime-bin/robotd"
cp -f "$RT/target/$TARGET/release/robotctl" "$IMG/payload/runtime-bin/robotctl"
cp -f "$RT/deploy/robotd.toml"              "$IMG/payload/runtime-bin/robotd.toml"

echo ">> shellcheck setup-board-a733.sh"
shellcheck "$WS_ROOT/microduck-opi3w/scripts/setup-board-a733.sh"

echo "done: img/payload/runtime-bin/ ready — apply-rootfs.sh --payload img/payload 布进镜像"
