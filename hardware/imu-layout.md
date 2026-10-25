# IMU 板（replica v2 `imu_to_dxl_1V0A`）：连接与要点

本仓采用的 IMU 板是 replica 自制 v2（`hardware/新版/imu_to_dxl_1V0A`），工程文件
`hardware/eda/imu_to_dxl_1V0A.eprj2`。它挂在 HD-1910 舵机总线上，作为 **DXL ID 200** 被主控读取，
板载 MCU 是 STM32G031F8P6，IMU 是 LSM6DSV16XTR（SPI1）。

> 为什么不用 kissqy 的 `imu_to_dxl_RevA`：我们 HAT 已去掉板载 IMU 芯片，需要一块独立的；v2 在
> 电源与保护上迭代过（PTC + TVS + 5.1V 钳位），且记录齐全。RevA 的差异见文末。

## 1. 连接器与**脚序（这是唯一要注意的地方）**

| 连接器 | 型号 | 1 | 2 | 3 | 备注 |
| --- | --- | --- | --- | --- | --- |
| J1 | CJT `A2007WR-3P`（弯脚） | **DXL_BUS（数据）** | **VDD_BUS（+5V）** | **GND** | 镜像序，和普通舵机线**相反** |
| J2 | JST `BM03B-ACHSS`（1.2 mm） | **GND** | **VDD_BUS** | **DXL_BUS（数据）** | 标准序；4/5 脚是机械固定脚，接 GND |
| J3 | `PZ254V-11-06P`（2.54 6P） | 见下 | | | SWD 调试口 |

**我们 HAT 的 J13/J14 是 `A2007WV-3P`，脚序 `1=GND / 2=SERVO_VPASS(+5V) / 3=DXL_DATA`**，与 IMU 板的 **J1 正好 1↔3 对调**。
所以：

- 一根按普通舵机线序压的 3P 线直接插 J1，会把 `+5V` 落在数据脚、`GND` 落在数据脚 —— **不能这么插**。
- 接 J1 必须做一根专用交叉线（1↔3），且**这根线绝不能插到 HAT 或舵机上**。
- 接 J2 用标准序线即可，但 ACH 1.2 mm 线束机械强度弱，鸭子走动时容易松。

**结论（当前方案）**：不改 IMU 板。等我们画 HUB 板时，在 HUB 上留一个 **IMU 专用 3P 口，按 IMU 的 J1 镜像序布线**
（HUB 由我们画，改 HUB 比改 IMU 板便宜），这样用一根普通 3P 线就能把 IMU 并到总线上。
如果以后想要「任何舵机线都能插 IMU」，再考虑把 J1 的 1/3 脚网络对调成标准序（一处改动）。

## 2. 电源树（网表实测）

```
J1-2 / J2-2  VDD_BUS (+5V, 舵机电池经 HUB 过来)
   │
   ├─ F1  MF-NSMF020X-2  200 mA 自恢复保险丝
   │     │
   │     └─ VDD_F ── D1  SMF12A (TVS, 对地) ── C6 10µF ── C8 100nF
   │                    └─ U4  HT7533-1  → 3V3 ── C7 10µF
   │
   └─ 数据脚不取电
```

3V3 供 MCU（U1）与 IMU（U2）；U3（SN74LVC2G241）也在 3V3 上。
舵机总线电压（6–12.6 V）**不进** IMU 板逻辑侧，只经 PTC + TVS + LDO。

## 3. 数据通路（半双工 → 全双工）

```
U3 SN74LVC2G241DCUR（双缓冲，OE 均为低有效）
  TX：PA2 (USART2_TX) → 1A → 1Y → R6 0Ω → DXL_BUS   （1OE# 由 PA1 控制）
  RX：DXL_BUS → 2A → 2Y → PA3 (USART2_RX)            （2OE 由 PB7 控制）
  D2 BZT52C5V1（5.1 V 齐纳）接 DXL_BUS 对地，做钳位
```

- **J1 是镜像序**，所以 DXL_BUS 就是数据脚；`R6 = 0Ω`（值为 0R，BOM 料号 `0603WAF0000T5E`/C21189，符号名还留着旧版 `0603WAF1500T5E` 的字样，不影响电气与 BOM）。
- 与 kissqy HAT 那套「1G126 + 1G125 + 3906 自动换向」不同：这里是 **MCU 主动控制两个 OE**，收发时序完全由固件决定。

## 4. MCU 引脚（v2 实测 + replica 固件一致）

| 引脚 | 用途 |
| --- | --- |
| PA0 | LSM6DSV16X **INT1** |
| PA1 | U3 **1OE#**（发送使能，低有效） |
| PA2 / PA3 | USART2 TX / RX（接缓冲器） |
| PA4 | IMU **CS** |
| PA5 / PA6 / PA7 | SPI1 SCK / MISO / MOSI |
| PB7 | U3 **2OE**（接收使能，低有效） |
| 15 脚（PB0/PB1/PB2/PA8） | IMU **INT2** |
| PF2-NRST / 19 脚（PA15/PA14 BOOT0） | 复位 / BOOT0（R2 10k 上拉、R3 100k 下拉） |

## 5. 我们要做的改动：**只改固件，不改电路**

烧 kissqy 的 FT6 固件（`control.43` 那套，DXL ID 200 协议）时，官方板与这块板的引脚定义不同，
必须改两处（另一处是编译环境）：

1. **PA0 不能再当 LED 输出**：这里 PA0 接 IMU 的 INT1，两个输出对打会互相拉扯。改成不驱动（或干脆空置）。
2. **PB7 必须拉低给 2OE**：不复位后悬空的话，接收缓冲可能整段关掉，表现为「主机完全收不到 IMU 回包」。
3. 顺带核对 **PA1（1OE#）极性**：低 = 发送、高 = 释放总线；与 kissqy 板的 TX_EN 逻辑相反，需按固件里的宏改。

固件源码与编译方式见 `docs/03-software-stack.md`；烧录走 J3 的 SWD（3V3 / SWDIO / GND / SWCLK / NRST）。
**J3 脚序**：1=3V3、2=SWDIO、3=GND、4=SWCLK、5=NRST、6=…（以工程为准，飞线前用万用表确认）。

## 6. 与 kissqy `imu_to_dxl_RevA` 的差异（不用它，但排障时会遇到旧资料）

| 项 | RevA（kissqy） | v2（replica，本仓采用） |
| --- | --- | --- |
| 总线连接器 | J1 `A2007WV-3P`，标准序 GND/VDD/DATA | J1 `A2007WR-3P` **镜像序** + J2 ACH 标准序 |
| 串阻 | R6 330Ω | R6 0Ω |
| 保护 | D1 PESD5V0S1BA（ESD） | F1 200 mA PTC + D1 SMF12A（TVS）+ D2 5.1V 齐纳 |
| 3V3 | TLV74233DBVR | HT7533-1 |
| 缓冲 | SN74LVC2G125DCUR | SN74LVC2G241DCUR（双通道，方向独立使能） |
| INT1 / INT2 | PA11/PA12 | PA0 / 15 脚 |
| 固件 | kissqy FT6（板子即按它设计） | replica 自制固件（协议兼容 DXL ID 200） |
