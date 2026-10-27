#!/usr/bin/env bash
# scripts/smoke-fake.sh — 全链路台架冒烟测试（host x86_64，无需真机）
#
# 在任意 Linux 主机（WSL2 可）上把 robotd 完整跑起来：--fake 伪总线 +
# onnxruntime + 测试 fixture 策略 + robotctl 全链路 IPC。验证的是 0.17.9+Feetech
# 移植版的配置解析、策略加载、控制环、IPC——板子到手前能测的全部。
#
# 前置（WSL Debian，root）：
#   1. rustup stable（scripts 仓外，img/install-rustup.sh）+ cargo build --release -p robotd -p robotctl
#   2. onnxruntime x64 ≥1.23 解到 $ORT_DIR（默认 /root/ort-x64，含 lib/libonnxruntime.so）
#      https://github.com/microsoft/onnxruntime/releases/download/v1.28.0/onnxruntime-linux-x64-1.28.0.tgz
# 用法：sudo ./smoke-fake.sh [--keep]   # --keep 不杀 robotd，方便手动 robotctl
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${RUNTIME:-$(cd "$REPO/.." && pwd)/microduck-runtime}"
ORT_DIR="${ORT_DIR:-/root/ort-x64}"
SOCKET=/tmp/robotd-smoke.sock
PD=/opt/robot/policies/current
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1

[ -x "$RUNTIME/target/release/robotd" ] || { echo "robotd 未编译：先 cargo build --release -p robotd -p robotctl"; exit 1; }
[ -f "$ORT_DIR/lib/libonnxruntime.so" ] || { echo "缺 $ORT_DIR/lib/libonnxruntime.so"; exit 1; }

export RUST_LOG=info LD_LIBRARY_PATH="$ORT_DIR/lib"
FIX="$RUNTIME/duck-control/tests/fixtures"

pkill -f 'target/release/robotd' 2>/dev/null || true; sleep 1
rm -f "$SOCKET"

# 策略槽位循环补 fixture（lstm.onnx 形状能过加载校验），直到没有 "No such file" 报错
mkdir -p "$PD"
for _ in 1 2 3 4 5 6 7 8; do
  nohup "$RUNTIME/target/release/robotd" --fake --socket "$SOCKET" \
        --params "$RUNTIME/deploy/robotd.toml" >/tmp/robotd-smoke.log 2>&1 &
  sleep 3
  miss=$(grep -oP 'reading /opt/robot/policies/current/\S+\.onnx: No such file' /tmp/robotd-smoke.log \
         | grep -oP '[\w]+\.onnx' | head -1 || true)
  if [ -n "$miss" ]; then
    echo "policy slot 缺 $miss → 放入 fixture"
    cp "$FIX/lstm.onnx" "$PD/$miss"
    pkill -f 'target/release/robotd' || true; sleep 1
  else
    break
  fi
done

CTL="$RUNTIME/target/release/robotctl --robot-socket $SOCKET"
fail=0
check() { # check <描述> <命令...>
  local desc="$1"; shift
  if out=$("$@" 2>&1); then echo "  ✓ $desc"; else echo "  ✗ $desc：$(echo "$out" | head -2)"; fail=1; fi
}

echo "== 冒烟项 =="
check "robotctl health → healthy" bash -c "$CTL health | grep -q 'robot     healthy'"
check "robotctl robot init（站立）" bash -c "$CTL robot init | grep -q 'standing up'"
check "robotctl robot mode → walk" bash -c "$CTL robot mode | grep -qw walk"
check "monitor JSON 状态流"        bash -c "timeout 2 $CTL monitor --json --hz 5 2>/dev/null | grep -q 'robot.state'"
# quack 预期失败（无 ALSA/无语音库）——验证的是 fail-soft 而不是通过
check "quack fail-soft（无音频报错而非崩溃）" bash -c "! $CTL quack 2>&1 | grep -qi 'panic'"

echo; echo "== health 摘要 =="
$CTL health | head -7
echo; echo "== robotd 日志（policy 行）=="
grep -i 'policy loaded' /tmp/robotd-smoke.log | head -2 || true

if [ "$KEEP" = 1 ]; then
  echo; echo "robotd 保持运行：robotctl --robot-socket $SOCKET <命令>（relax 前关节带电状态为伪总线，无实际输出）"
else
  pkill -f 'target/release/robotd' || true
fi

[ "$fail" = 0 ] && { echo; echo "冒烟全部通过 ✅"; exit 0; }
echo; echo "冒烟有失败项 ❌（详见 /tmp/robotd-smoke.log）"; exit 1
