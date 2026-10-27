#!/usr/bin/env bash
# scripts/smoke-commissioning.sh — 标定台架冒烟（host x86_64，无需真机）
#
# 把 robotd 以 `--fake --commissioning` 跑起来，证明：台架模式能起、策略被关掉、
# 控制环在跑、`robot.health` 能回话。路由/字段/握手逻辑本身由单元测试覆盖
# （robotd/src/commissioning.rs + main.rs 里的 bench 用例，FakeIo 上跑），这里只验
# 「另一个模式还是同一个守护进程」这一层。
#
# 前置：cargo build -p robotd -p robotctl（debug 即可）
# 用法：bash scripts/smoke-commissioning.sh
set -euo pipefail

RUNTIME="${RUNTIME:-/mnt/c/Users/JC/.dsh/bot/workspace/microduck/microduck-runtime}"
SOCKET="${SOCKET:-/tmp/robotd-commissioning.sock}"
LOG="${LOG:-/tmp/robotd-commissioning.log}"
BIN="$RUNTIME/target/debug"

[ -x "$BIN/robotd" ] || { echo "robotd 未编译：先在 microduck-runtime 里 cargo build -p robotd -p robotctl"; exit 1; }

rm -f "$SOCKET" "$LOG"
"$BIN/robotd" --fake --commissioning --socket "$SOCKET" > "$LOG" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do [ -S "$SOCKET" ] && break; sleep 0.25; done
[ -S "$SOCKET" ] || { echo "socket 没出现，看 $LOG"; exit 1; }
sleep 1.5

fail=0
grep -q "commissioning mode: no policy, no motion" "$LOG" || { echo "FAIL: 没有进入标定模式"; fail=1; }
grep -q "policy disabled; holding the startup pose" "$LOG" || { echo "FAIL: 策略没有被关掉"; fail=1; }
grep -q "control loop running" "$LOG" || { echo "FAIL: 控制环没起来"; fail=1; }

echo "--- robotctl health ---"
"$BIN/robotctl" --robot-socket "$SOCKET" health | head -8 || fail=1

if [ "$fail" -eq 0 ]; then
  echo "=== commissioning smoke: 3/3 + health OK ==="
else
  echo "=== commissioning smoke: FAILED（日志 $LOG）==="
fi
exit "$fail"
