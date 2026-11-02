# IMU 板 (replica v2 `imu_to_dxl_1V0A`)

这块板挂在 HD-1910 舵机总线上, 作为 **DXL ID 200** 被主控读取。板载 MCU 是 STM32G031F8P6, 
IMU 是 LSM6DSV16XTR (SPI1)。电路是 replica 的 v2 原样, 但**固件由本仓维护**(总线跑 500 kbps,
上游那份 hex 写死在 1 Mbps)。

- 工程文件: `hardware/eda/imu_to_dxl_1V0A/` (EasyEDA Pro 工程 + 原理图 PDF, 取自 replica @ `35b435d`, 已快照进本仓)
- 固件: `hardware/imu-firmware/` (源码 + GCC 构建 + 预置 hex), 说明见 [docs/07-imu-firmware.md](../docs/07-imu-firmware.md)
- 电路不改; 固件只改波特率档位与台架自检命令, 引脚定义与下表一致

## 1. 连接器与脚序

| 连接器 | 型号 | 1 | 2 | 3 | 说明 |
| --- | --- | --- | --- | --- | --- |
| J1 | CJT `A2007WR-3P` (弯脚) | **DXL_BUS (数据)** | **VDD_BUS (+5V)** | **GND** | 总线口 |
| J2 | JST `BM03B-ACHSS` (1.2 mm) | **GND** | **VDD_BUS** | **DXL_BUS (数据)** | 与 J1 同信号, 脚序不同; 本项目不用, 焊盘保留不贴 |
| J3 | `PZ254V-11-06P` (2.54 6P) | 3V3 | SWDIO | GND | 第 4 脚 SWCLK, 第 5 脚 NRST, 第 6 脚未用; 唯一的烧录口。**这组针序是照工程记录的, 飞线前用万用表对一次** |

**脚序已经统一, 一根普通 3P 线可以直接插**: 本仓用到的总线座现在都是
`1=数据 / 2=V+ / 3=GND` —— IMU 板的 J1, HAT 的 J13/J14, 和 HD-1910 原配线
 (两端同序 1↔1, 2↔2, 3↔3)完全一致。舵机线插舵机, 插 HAT, 插 IMU 都通用, 不需要做交叉线。

两条仍然要注意的: 

- **不要用 Dynamixel 序的成品线** (那种是 `1=GND / 2=V+ / 3=DATA`)。插上去等于把电供到数据脚, 把地供到 V+。
- **1 脚朝向要量一次**: A2007 的直插座 (HAT `A2007WV`)与弯插座 (IMU/HUB `A2007WR`)在 PCB 上 1 脚可能朝相反方向。
  打样后, 通电前用通断档确认: 插头信号脚 ↔ 板子的数据脚应导通; 若通到 GND, 说明座子 1 脚在另一头。

## 2. 电源

```
J1-2 / J2-2  VDD_BUS (+5V, 来自 HAT J13/J14 上的舵机电池)
   │
   ├─ F1  MF-NSMF020X-2  200 mA 自恢复保险丝
   │     │
   │     └─ VDD_F ── D1  SMF12A (TVS, 对地) ── C6 10µF ── C8 100nF
   │                    └─ U4  HT7533-1 → 3V3 ── C7 10µF
   │
   └─ 数据脚不取电
```

3V3 供 MCU (U1)与 IMU (U2); U3 (SN74LVC2G241)也在 3V3 上。总线电压 (6–12.6 V)不进逻辑侧, 
只经 PTC + TVS + LDO。

## 3. 数据通路 (半双工 → 全双工)

```
U3 SN74LVC2G241DCUR (双缓冲, OE 均低有效)
  TX: PA2 (USART2_TX) → 1A → 1Y → R6 0Ω → DXL_BUS    (1OE# 由 PA1 控制)
  RX: DXL_BUS → 2A → 2Y → PA3 (USART2_RX)             (2OE 由 PB7 控制)
  D2 BZT52C5V1 (5.1 V 齐纳)接 DXL_BUS 对地, 做钳位
```

与 kissqy HAT 那套"1G126 + 1G125 + 3906 自动换向"不同: 这里由 MCU 主动控制两个 OE, 收发时序全在固件里。

> `R6` 的 Value 是 `0R`, 料号 `0603WAF0000T5E` (C21189); 符号名里还留着旧版 `0603WAF1500T5E` 的字样, 
> 不影响电气与 BOM——读值请看 Value / 料号字段, 不要看符号名。

## 4. MCU 引脚 (与 replica 固件一致)

| 引脚 | 用途 |
| --- | --- |
| PA0 | LSM6DSV16X **INT1** |
| PA1 | U3 **1OE#** (发送使能, 低有效) |
| PA2 / PA3 | USART2 TX / RX (接缓冲器) |
| PA4 | IMU **CS** |
| PA5 / PA6 / PA7 | SPI1 SCK / MISO / MOSI |
| PB7 | U3 **2OE** (接收使能, 低有效) |
| 15 脚 (PB0/PB1/PB2/PA8) | IMU **INT2** |
| PF2-NRST / 19 脚 (PA15/PA14 BOOT0) | 复位 / BOOT0 (R2 10k 上拉, R3 100k 下拉) |

## 5. 固件: 烧本仓的 `1.0.0-500k`

- 源码与 hex: [`hardware/imu-firmware/`](imu-firmware/) —— `Build-gcc/imu_to_dxl.hex` (51,353 B)
- 基线: replica `hardware/imu_to_dxl/firmware-1.0.0` (MIT); 相对它只改了三个文件:
  `board_config.h` (`BOARD_BUS_BAUD` → 500000, 版本串 → `imu_to_dxl 1.0.0-500k`)、
  `protocol.h` (`PROTO_BAUD_CODE` → 1)、`main.c` (只加台架自检命令)
- 构建: `cd hardware/imu-firmware && make` (需要 `arm-none-eabi-gcc`, 不需要 Keil); 预置 hex 可直接烧
- 烧录: ST-Link (或任意 SWD 探针)接 J3 —— 3V3 / SWDIO / GND / SWCLK / NRST

**为什么不用 replica 原版 hex**: 它的波特率写死 1 Mbps, 而 A733 的 uart2 时钟固定 24 MHz、驱动无小数
分频, 1 Mbps 会被取整成 750 kbps, 总线上没有一颗设备应答。500 kbps 整除。三端档位必须一起改:
舵机 EEPROM 寄存器 6 = `1`、IMU `PROTO_BAUD_CODE = 1`、主控 `BAUD_RATE = 500_000`。

**不要烧 kissqy 的 FT6 版本** (`control.43` 那套): 它是照 kissqy 自己的 `imu_to_dxl_RevA` 写的, 
引脚定义不同——PA0 在那块板上是 LED 输出, PB7 是普通输出。烧到这块板上, PA0 会和 IMU 的 INT1 对打, 
PB7 不给 2OE 会让接收缓冲关掉, 表现为"主机完全收不到 IMU 回包"。协议 (DXL ID 200)两边兼容, 
但**引脚表不兼容**, 认板不认协议。

上电验证: 总线 500 kbps 8N1, 发 ID 200 的 READ 应答应有回音; 主控侧看到的就是
`robotctl --robot-socket /run/robotd.sock status` 里的 IMU ready。串口 (115200 8N1) 上 `s` 应显示
`imu_to_dxl 1.0.0-500k | STM32G031F8 | FT-SCS ID=200 500000 8N1`, `n` 应显示 `ready=1 id=0x70`。

## 6. 与 kissqy `imu_to_dxl_RevA` 的差异 (排障时会遇到旧资料)

| 项 | RevA (kissqy, 本项目不用) | v2 (replica, 本项目采用) |
| --- | --- | --- |
| 总线连接器 | J1 `A2007WV-3P`, Dynamixel 序 GND/VDD/DATA | J1 `A2007WR-3P` (数据/V+/GND)+ J2 ACH |
| 串阻 | R6 330Ω | R6 0Ω |
| 保护 | D1 PESD5V0S1BA (ESD) | F1 200 mA PTC + D1 SMF12A (TVS)+ D2 5.1V 齐纳 |
| 3V3 | TLV74233DBVR | HT7533-1 |
| 缓冲 | SN74LVC2G125DCUR | SN74LVC2G241DCUR (双通道, 方向独立使能) |
| INT1 / INT2 | PA11 / PA12 | PA0 / 15 脚 |
| 固件 | kissqy FT6 (板子按它设计) | 本仓 `1.0.0-500k` (基线 replica 1.0.0, DXL ID 200 协议兼容) |
