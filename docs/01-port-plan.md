# 移植总计划：Radxa ZERO 3W → Orange Pi Zero 3W

状态标记：✅ 已验证 / 🔨 进行中 / ⏳ 待办（多数需板子到手）

## 目标

保留 kissqy 固件与 HD1910 训练成果（ONNX 策略、标定、训练链），只更换主控底座：
Radxa ZERO 3W（RK3566）→ Orange Pi Zero 3W（全志 A733：2×A76 + 6×A55，LPDDR5，
3 TOPS VIP9000 NPU，Wi-Fi 6）。

## 阶段

### 1. 编译链与固件 ✅

在 WSL Debian 13 已完成：

```bash
# 工具链：Rust 1.99.0 + cargo-zigbuild 0.23.4 + Zig 0.15.1，aarch64 target
# sysroot（GStreamer 1.26.2 + libudev，Debian trixie arm64 包）
cd firmware
DUCK_DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian \
DUCK_SYSROOT=$HOME/duck-aarch64-sysroot \
sh scripts/cross-sysroot.sh
eval "$(sh scripts/cross-sysroot.sh 2>/dev/null | grep ^export)"
cargo board --bins   # 已验证：robotd/robotctl/padd/btd/mediad/configd/sounds/pet-detect
```

实测二进制最高依赖 GLIBC 2.30，仅链接 libc/libm/pthread/dl —— 固件可原样运行于任何 glibc ≥ 2.31 的 aarch64 系统。

### 2. A733 系统镜像 ⏳

原「镜像 R1」绑定 RK3566 内核/DTB，不可用。候选：Orange Pi 官方 Debian/Ubuntu（A733）。
验收标准：串口/SSH 可用、40-pin 总线 UART 可配、I2S/I2C 音频可配。
待确认：官方镜像 NPU 驱动（galcore.ko）与用户态运行时是否内置。

### 3. 板侧依赖 ⏳

对照 kissqy 的 scripts/setup-board.sh 移植：
- ONNX Runtime ≥ 1.23（固件 floor），装 aarch64 .so（通用，无需改）
- GStreamer 1.26（mediad WebRTC 用，apt 装）
- rknn 运行时 **不装**（duck-detect 见 docs/05）
- 舵机总线 UART 引脚与 1 Mbps 配置（A733 设备树 overlay）

### 4. HAT 移植 ⏳（方案见 docs/02）

功能电路保留，改与主控的接口层：排针重映射 + 供电外置。

### 5. 装配 / 标定 / 运动 ⏳

与 kissqy 文档一致：15 关节标定 + IMU（原样），无 RK 专属步骤。

## 风险清单

| 风险 | 缓解 |
| --- | --- |
| OPi Zero 3W 官方镜像 NPU 支持不成熟 | duck-detect 先 CPU 兜底（跑 ONNX），NPU 后端做成可选 |
| A733 UART 1 Mbps 半双工时序 | 飞特总线是普通 UART，重点核对设备树与 DMA/中断配置 |
| 音频 codec 设备树 | TLV320AIC3104 是常见 I2S codec，主线内核有驱动，写 DT 即可 |
