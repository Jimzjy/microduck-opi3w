# microduck-opi3w

用 Orange Pi Zero 3W（全志 A733）替代 Radxa ZERO 3W（RK3566），复刻 kissqy 的 HD1910 机器鸭实机。

> **来源声明 / 致谢**
> - 固件代码全部来自 [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy/)（本仓库以 git submodule 引用，不做任何复制修改）
> - kissqy 项目基于 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 0.15.1
> - 本仓库只包含**移植层**：移植文档、硬件改动方案、A733 系统配置。固件能力归上游两个项目

## 为什么可行（已实测验证）

- 固件本身**不绑死 RK3566**：kissqy 固件已在 x86 WSL 上用 cargo-zigbuild 交叉编译通过（`cargo board --bins`，产出 robotd 等 8 个 aarch64 二进制，最高只要求 GLIBC 2.30）。绑死 RK3566 的是「系统镜像 + 板侧 .so」，这正是本仓库要解决的部分
- 强化学习策略不受影响：策略是 ONNX 模型，robotd 通过 ONNX Runtime（通用 aarch64 库）CPU 推理，换 SoC 无关
- IMU 板（STM32G031 + LSM6DSV16X）挂在舵机总线上、与主控无关，**原样沿用，不改动**

## 已知的功能取舍

| 功能 | A733 上的状态 |
| --- | --- |
| 运动策略（RL ONNX） | ✅ 保留，CPU 推理 |
| 语音 / 遥控 / 标定 | ✅ 保留（需为 A733 配音频设备树） |
| duck-detect 目标检测 | ⚠️ 原实现 dlopen Rockchip rknn 运行时，A733 没有；计划改接 A733 的 VIP9000 NPU（见 docs/05） |
| 摄像头 | ⚠️ IMX219 CSI 链路按 A733 重新配置 |

## 仓库结构

```
docs/            移植文档（计划、硬件改动、系统镜像、NPU 调研）
hardware/        HAT 移植对照表与改动清单
scripts/         A733 板侧配置脚本（建设中）
firmware/        kissqy 固件（git submodule，只读引用）
```

## 克隆

```bash
git clone --recursive https://github.com/<你的用户名>/microduck-opi3w.git
```

## 进度

- [x] kissqy 仓库通读、复刻目标对齐
- [x] WSL 交叉编译链验证（Rust 1.99.0 / cargo-zigbuild 0.23.4 / Zig 0.15.1）
- [x] `cargo board --bins` 全量编译通过（含 sysroot）
- [ ] Orange Pi Zero 3W 系统镜像选型与验证（待板子到手）
- [ ] HAT 排针重映射对照表
- [ ] 板侧依赖脚本（ONNX Runtime 1.28、GStreamer）
- [ ] duck-detect 的 A733 NPU 后端
