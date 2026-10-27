# 移植总计划：Radxa ZERO 3W → Orange Pi Zero 3W（A733）

状态标记：✅ 已验证 / 🔨 进行中 / ⏳ 待办（多数需板子到手）

## 目标

保留 kissqy 固件与 HD1910 训练成果（ONNX 策略、标定、训练链），只更换主控底座：
Radxa ZERO 3W（RK3566）→ Orange Pi Zero 3W（全志 A733：2×A76 + 6×A55，LPDDR5，Wi-Fi 6）。

不做的事：NPU / `duck-detect`（那是 RK3588 的 rknn 路线，A733 上用不了，已从本仓移除）；
不复制上游代码，固件是固定 commit 的子模块，软件层按需拉取（见 [00-upstreams.md](00-upstreams.md)、[03-software-stack.md](03-software-stack.md)）。

## 阶段

### 1. 编译链与固件 ✅

在 WSL Debian 13 已完成：

```bash
# 工具链：Rust 1.99.0 + cargo-zigbuild 0.23.4 + Zig 0.15.1，aarch64 target
# sysroot（GStreamer 1.26.2 + libudev，Debian trixie arm64 包）
cd firmware/microduck-hd1910/firmware
DUCK_DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian \
DUCK_SYSROOT=$HOME/duck-aarch64-sysroot \
sh scripts/cross-sysroot.sh
eval "$(sh scripts/cross-sysroot.sh 2>/dev/null | grep ^export)"
cargo board --bins   # 已验证：robotd/robotctl/padd/btd/mediad/configd/sounds/pet-detect
```

实测二进制最高依赖 GLIBC 2.30，仅链接 libc/libm/pthread/dl —— 固件可原样运行于任何 glibc ≥ 2.31 的 aarch64 系统。

### 2. A733 系统镜像 ⏳

原「镜像 R1」绑定 RK3566 内核/DTB，不可用。候选：Orange Pi 官方 Debian/Ubuntu（A733）或 Armbian。
验收标准：串口/SSH 可用、40-pin 总线 UART 可配、I2S/I2C 音频可配。
镜像里的 `setup-gstreamer.sh` / `setup-rkaiq.sh` / `setup-npu.sh` 是 RK 专属，A733 上跳过或用 apt 替代。

### 3. 板侧依赖 ⏳（脚本已备好：[../scripts/setup-board-a733.sh](../scripts/setup-board-a733.sh)）

对照 kissqy 的 `scripts/setup-board.sh` 移植（脚本已写好，待上板验证）：
- ONNX Runtime ≥ 1.23（固件 floor），装 aarch64 .so（通用，无需改）
- 舵机总线 uart2 overlay：✅ `hardware/overlay/uart2-dxl.dts` 已编译 + fdtoverlay 回归验证
  （2026-10-27，dtc 1.7.2，target-path 写法不依赖基础 dtb 符号表）
- GStreamer 1.26（mediad WebRTC 用，apt 装）

### 4. HAT 移植 ✅（方案见 [02-hat-porting.md](02-hat-porting.md)）

功能电路保留，改与主控的接口层：排针重映射（DXL 改走 11/13 的 uart2）+ 供电外置。
原理图已收敛：62 器件 / 187 导线 / 34 网络，DRC 0 error。

### 5. 软件层 ⏳（方案见 [03-software-stack.md](03-software-stack.md)）

固件照旧；Studio（replica，Apache-2.0）按需拉取后上板，接口逐页验证；镜像自己按 A733 写。

### 6. 装配 / 标定 / 运动 ⏳

与 kissqy 文档一致：15 关节标定 + IMU（原样），无 RK 专属步骤。

## 风险清单

| 风险 | 缓解 |
| --- | --- |
| A733 官方镜像缺 codec 驱动（TLV320AIC3104 / sunxi sound mach） | 先看 `/proc/config.gz`，没开就编模块；overlay 已确认 `i2s0_mach` 的 codec 子节点是留空的，可外挂 |
| A733 UART 1 Mbps 半双工时序 | 总线方向由 HAT 硬件自动切换，内核侧只是普通串口；重点核对 pinctrl 与 DMA/中断 |
| Studio 是照着 replica 的 fork 写的 | 方法名已对得上，字段未实测；上板后逐页点，差异记录到 03-software-stack.md |
| 供电：HAT 只吃外部 5V（U11），电池另走 HUB 板 | 调试期务必只插一处电源；USB-C 与端子是硬并联 |
