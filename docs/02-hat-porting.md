# HAT 移植方案（HAT-V5 → OPi Zero 3W）

原则：**功能电路不重新设计，只改与主控的接口层**。

## 供电改动（已定方案：降压外置，原理图已执行）

原 HAT-V5 由板载 AP63205WU（5V 2A 降压）给主控供电。移植时**拆除板载降压**，
改用外置 5V 电源经 HAT 上的 **U11 2P 螺钉端子**接入：

```
电池 (7.3V/满8.4V) ──→ 舵机 HUB 板 ──→ 舵机 ×12 + IMU 板
                      └ 信号/GND 经 J13/J14（SERVO_VPASS 2 脚只直通，HAT 不取电池）

外部 5V（UBEC/电源 ≥3A）──→ U11-1 ──→ F1 (PTC 1.5A) ──→ 5V 轨 ──→ OPi Zero 3W 5V 脚 / codec / 功放
                            U11-2 ──→ GND            └ D1 (SMAJ5.0A TVS) ──→ GND
```

原理图实际改动（2026-10-25）：
- 删除 U9(AP63205)、L4(6.8µH)、C20(自举 100nF)、Q2(SI2312)、U10(LM5050-1)、R8(100R)、C39(100nF)
- C21 22µF 保留在 5V 轨作输入储能（C22 已删，两颗冗余）
- **D1 由 BAT54SW 改为 PTC + TVS**：F1 = mSMD150-16V（1.5A 保持 / 3A 跳闸 / 16V，F1812，C70122）串在 5V_VIN→5V；
  D1 = SMAJ5.0A（5V 单向 TVS，SMA，C143135）接 5V↔GND。原 BAT54SW 中间脚悬空，实际不导通，等于没装
- **删除 C15，取消 BATT_IN 网络**：J13-2/J14-2 改为 SERVO_VPASS 直通，HAT 完全不吃舵机电池
- **去耦精简（同一轮）**：删 C4/C6（功放 PVDD 上重复 1µF）、C29/C31（codec 3V3 重复 1µF）、
  C42/C43（5V 上重复 1µF，且原本没接到偏置节点）、C37（3V3 重复 10µF）；
  改为在麦克风偏置节点各加一颗 470pF：C44 = MIC_EXT_L_BIAS↔GND、C45 = MIC_EXT_R_BIAS↔GND（0603，C1620）
  原则：每个电源脚 1 颗 100nF 贴脚、每个电源域 1 颗 1µF、PVDD 只留贴脚 10µF

注意事项：
- **电池不再给主控供电**，板子必须由 U11 上的外部 5V 供电；如需电池供电，需自备 5V UBEC 接到 U11
- PTC 是慢断保护：真反接时靠 PTC 限流 + TVS 钳位，长期反接仍会烧 PTC，接线前务必看清 U11 极性
- USB-C 与端子同时供电是硬并联，不要同时接
- 电源模块要求：≥3A、低纹波（喂音频），到 HAT 走线短粗（≥24AWG）

## 不改的部分

- 音频 codec TLV320AIC3104（U2）+ PAM8406D 功放（U1，5W 双声道 D 类）：芯片与周边电路原样
- 总线/保护：PESD5V0S1BA、BZT52C5V1、D1 SMAJ5.0A、J13/J14 总线座（AMP2.0 版脚序 GND / 舵机 V+ / DXL_DATA，HAT 侧 2 脚只直通不取电）
- 麦克风：板载 MK1 已删除，仅保留 J2/J9 外接麦（R22/R23 10k 从 5V 偏置，偏置节点各一颗 470pF 到地）
- IMU 板：整体不在此板，挂总线 ID 200，与主控无关，原样沿用

## 排针重映射对照表

已产出：hardware/pinmap.md（Zero 3W 40-pin → HAT 信号 + A733 官方原理图对照，结论：四类信号位置级全兼容，无需改 HAT 走线；剩余为 sun60iw2 overlay 软件工作）。

A733 侧已核实到引脚与控制器（详见 pinmap.md 末节「I2S / UART 在 A733 上能否配出来」）：
- I2S0：PB5/PB6/PB8/PB7（= 排针 12/35/38/40），控制器 `i2s0_plat` 的 pinctrl 已配好，只差 `status = "okay"`；`i2s0_mach` 的 codec 子节点为空，供外挂 TLV320AIC3104 填 `sound-dai`。
- I2C：TWI0（PB3/PB2 = 排针 3/5），厂商 dts 里 `status = "disabled"`，overlay 打开即可。
- DXL UART：**定案改走 11/13 的 uart2（PB0/PB1）**，console（uart0 / ttyS0）留在 8/10 不动。HAT 侧已随之改线：J4-7/9（排针 8/10）断开，J4-12/14（排针 11/13）接 `UART2_TX` / `UART2_RX`；网络名已按 HAT 功能统一（不再是 SoC 信号名）；overlay 见 `hardware/overlay/uart2-dxl.dts`。
- 平台代号是 **sun60iw2**（不是 sun55i）。
