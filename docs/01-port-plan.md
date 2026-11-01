# 移植要点: Radxa ZERO 3W → Orange Pi Zero 3W (A733)

保留 kissqy 那套外部硬件与训练成果 (HD-1910 总线舵机, 总线 IMU, ONNX 步态策略, 标定流程), 
只换主控底座: Radxa ZERO 3W (RK3566)→ Orange Pi Zero 3W (全志 A733: 2×A76 + 6×A55, LPDDR5, Wi-Fi 6)。

**不做的事**: `duck-detect`——它绑定 RK3588 的 rknn 栈, A733 上跑不了。A733 自己的 NPU
 (Vivante VIP9000, ACUITY/NBG 工具链)以后要做视觉检测时可以走, 但那是新项目, 不随本次移植。
不复制上游代码。

## 为什么是这块板

| 候选 | 结论 |
| --- | --- |
| Radxa ZERO 3W (RK3566) | 原始设计目标, 但 `镜像 R1` 把内核/DTB/硬件绑定在一起, 换板就用不了; 且我们已经有更近的 A733 方案 |
| Orange Pi Zero 3 (H618) | 不行: 无 CSI, 40-pin 定义不同 |
| Orange Pi Zero 3W (A733) | 采用。40-pin 与 Radxa **物理布局**兼容, I2C/I2S 位置级兼容, 只有 UART 需要动 |

## 换板要动的四件事

1. **UART**: DXL 从 Radxa 的 8/10 (复用调试口)改到 **11/13 的 uart2**, console 留 8/10。
   HAT 侧改两根走线 (J4 焊盘 7/9 → 12/14), 内核侧加 overlay。见 [02-hat-porting.md](02-hat-porting.md)。
2. **镜像底座**: `镜像 R1` 不可用, 改用 **Armbian trixie vendor (Debian 13 + 6.6.98 内核)**, 
   自己叠 dtbo / 脚本 / 运行时产物。见 [03-software-stack.md](03-software-stack.md) §B。
3. **音频 codec**: 板载 TLV320AIC3104 在厂商内核里没编进去 (`# CONFIG_SND_SOC_TLV320AIC3X is not set`), 
   我们出一颗 `.ko` (`scripts/aic3x-module/`) 随镜像安装 (vermagic 必须带 `-vendor-sun60iw2`)。
4. **运行时**: 官方 `daemon-v0.17.9` 上补 Feetech 总线后端, 总线 IMU, 标定台架
    ([patches/](../patches/README.md)), 而不是沿用 kissqy 的老分叉。

## 阶段现状

| 阶段 | 状态 |
| --- | --- |
| 编译链 (Rust + aarch64 交叉编译) | ✅ `robotd` 9.6 MB / `robotctl` 7.7 MB, GLIBC 符号最高 2.39 |
| 设备树 overlay (uart2 / 音频) | ✅ 编译 + `fdtoverlay` 回归验证, 对镜像真实 dtb 验证通过 |
| HAT 移植 (引脚 + 供电) | ✅ REV B 已送厂 |
| aic3x codec 模块 | ✅ 上板原生编译 `snd-aic3x.ko`, vermagic 与目标内核逐字一致, 音频已出声 |
| A733 系统镜像 | ✅ 已组装出成品 (不入库, 按 [05-bringup-runbook.md](05-bringup-runbook.md) 第 5 步产出); 待真机验收 |
| 板侧依赖 (ONNX Runtime, GStreamer) | ⏳ 待板子到手 |
| 装配 / 标定 / 试走 | ⏳ 需实物 |

每一步怎么跑见 [05-bringup-runbook.md](05-bringup-runbook.md)。

## 风险清单

| 风险 | 缓解 |
| --- | --- |
| 厂商镜像缺 codec 驱动 | 已自带 `.ko`; 上板先查 `aplay -l`, 不行再查 `dmesg \| grep aic31` |
| A733 UART 500 kbps 半双工时序 | 方向切换在 HAT 硬件 (U7/U6 + MMBT3906), 内核侧只是普通串口; 已实测通过 (1 Mbps 在 24 MHz 固定时钟下会被取整成 750 kbps, 所以总线跑 500 kbps) |
| Studio 是照着 replica 的 fork 写的 | `busStatus`/`busCommand` 已补齐, `startupSubscribe` 按设计不做; 上板后逐页点, 差异记到 [03-software-stack.md](03-software-stack.md) |
| 供电 | HAT 只吃外部 5V (U11 端子), 舵机电池直接插 J13/J14; USB-C 与端子之间有理想二极管隔离, 可同时接 |
| 飞特 sync-read 的 IMU 应答顺序 | ID 200 必须排在 15 颗舵机**之后** (排首位会吃掉下一颗的末字节); 模块里有单测守着 |
