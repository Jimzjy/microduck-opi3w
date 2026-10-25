# HAT 移植方案（HAT-V5 → OPi Zero 3W）

原则：**功能电路不重新设计，只改与主控的接口层**。

## 供电改动（已定方案：降压外置）

原 HAT-V5 由板载 AP63205WU（5V 2A 降压）给主控供电。移植时**拆除板载降压**，
改用外置 DCDC 模块产生 5V 后接入 HAT：

```
电池 NP-F550 (7.3V/满8.4V)
 ├─→ 舵机总线（BATT_IN 直通，不改）──── 舵机 ×15 + IMU 板
 └─→ 外置 5V DCDC 模块 ──→ HAT 5V 轨 ──→ OPi Zero 3W 5V 脚 / 音频 codec / 功放
```

要求：
- 模块 ≥ 3A 同步整流（主控峰值 + PAM8406D 功放 + 摄像头），纹波要低（喂音频）
- 模块到 HAT 走线短粗（≥24AWG），HAT 5V 入口保留 C1/C3 4.7µF 去耦与 TVS D1
- 舵机总线的 1000µF/16V 缓冲电容（ASSEMBLY-NOTES.md:27）是电池进电口的，与本 5V 轨无关，保留

净成本与板载方案基本持平；换来的是焊接简化与散热外移。

## 不改的部分

- 音频 codec TLV320AIC3104（U2）+ PAM8406D 功放（U1，5W 双声道 D 类）：芯片与周边电路原样
- 总线/保护：LM5050 ORing、PESD5V0S1BA、BZT52C5V1、J13/J14 总线座（AMP2.0 版脚序 GND/BATT_IN/DXL_DATA）
- IMU 板：整体不在此板，挂总线 ID 200，与主控无关，原样沿用

## 排针重映射对照表

已产出：hardware/pinmap.md（Zero 3W 40-pin → HAT 信号 + A733 官方原理图对照，结论：四类信号位置级全兼容，无需改 HAT 走线；剩余为 sun55i overlay 软件工作）。

A733 侧待补：I2S 控制器引脚、I2C 控制器引脚、1 Mbps 半双工 UART 引脚、5V/GND。
画板/下单前必须逐根核对。
