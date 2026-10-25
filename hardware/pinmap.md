# Zero 3W 40-pin → HAT 信号对照（来自 kissqy HAT RevA 原理图实测导出）

来源：HAT_REVA_SCH.eprj2 原理图导线网络 + firmware overlay 注释交叉验证。

## 已确认的信号（kissqy 实机验证过）

| 功能 | Zero 3W 排针脚 | 网络（原理图名） | SoC 控制器 / overlay |
|---|---|---|---|
| 3V3 | 1 | 3V3 | — |
| 5V | 2、4 | 5V | 外部 5V 经 HAT U11 螺钉端子上板（板载 DC-DC 已拆） |
| I2C（codec 0x18 / ToF H1） | 3、5 | GPIO02_I2C_SDA / GPIO03_I2C_SCL | i2c3 m0（`i2c3-pihat.dts`，400kHz，禁 fusb302） |
| DXL 半双工 UART | 8（TX）、10（RX） | GPIO14_UART_TX / GPIO15_UART_RX | uart2 m0（`REQUIRED_OVERLAY=uart2-m0`，1Mbaud；与 SoC 调试口复用） |
| I2S 音频 | 12、35、38、40 | GPIO18_PCM_CLK / GPIO19_PCM_FS / GPIO20_PCM_DIN / GPIO21_PCM_DOUT | i2s3_2ch（`aic3104-i2c3.dts`，MCLK 来自板上 Y1 12MHz 晶振，非排针） |
| GND | 6、9、13、14、20、25、30、34、39 等未接信号脚 | GND | — |

## J4 排母（FH-00339 / C2685112）贴装错位规则

原理图标注：**ZERO 奇数脚 n → J4 焊盘 n+1；偶数脚 n → J4 焊盘 n−1**（J4 焊盘号与排针号整体错一位，PCB 布线时注意）。

## 未使用的排针脚

7、11、15、16、18、21、22、23、24、26、27、28、29、31、32、33、36（原理图无连线）。移植到 A733 时这些脚可自由复用。

---

## A733 40-pin 对照（Orange Pi Zero 3W v1.2 官方原理图实测，已定稿）

来源：**香橙派官方原理图** `OPI ZERO 3W V1_2_原理图.pdf` 第 18 页 EXT I/O（CONN ZX20，PH0220-100TF-SM-H9，用户提供的桌面资料），放大逐脚核对；官网 Pin Definition 图有错标（如 38/40 均标 PB7、UART 标在 6/8），以原理图为准。
电源限制：3.3V 轨 MAX 0.5A（VCC_3V3_EXT）；5V 轨输入 2A / 输出 MAX 0.5A。

### A733 全 40 脚（原理图 V1.2）

| 排针脚 | SoC 引脚 | 原理图功能 | | 排针脚 | SoC 引脚 | 原理图功能 |
|---|---|---|---|---|---|---|
| 1 | — | 3.3V Power | | 2 | — | 5V Power |
| 3 | PB3 | I2C_SDA（I2C0）= EXT_TWI0_SDA | | 4 | — | 5V Power |
| 5 | PB2 | I2C_SCK（I2C0）= EXT_TWI0_SCK | | 6 | — | GND |
| 7 | PB4 | GPCLK（PWM0-0）= I2S0-MCLK | | 8 | — | UART_TX = CPU-TX（调试口） |
| 9 | — | GND | | 10 | — | UART_RX = CPU-RX（调试口） |
| 11 | PB0 | GPIO | | 12 | PB5 | **PWM/PCM_CLK = I2S0-BCLK**（S-PWM0-0） |
| 13 | PB1 | GPIO | | 14 | PL2 | S-PWM0-0 / SCPU-TX（arisc 域） |
| 15 | PE11 | GPIO | | 16 | PL3 | S-PWM0-1/IR / SCPU-RX（arisc 域） |
| 17 | — | 3.3V Power | | 18 | — | GND |
| 19 | PE2 | SPI_MOSI（SPI3） | | 20 | PD0 | GPIO |
| 21 | PE3 | SPI_MISO（SPI3） | | 22 | PE0 | SPI_CS0（SPI3_CS0） |
| 23 | PE1 | SPI_SCLK（SPI3） | | 24 | PE4 | SPI_CS1（SPI3_CS1） |
| 25 | — | GND | | 26 | PL4 | S-TWI2-SCK（arisc 域） |
| 27 | PL5 | I2C_SDA（S-TWI2，arisc 域） | | 28 | — | I2C_SCL（S-TWI2） |
| 29 | PE12 | GPIO | | 30 | — | GND |
| 31 | PE13 | GPIO | | 32 | PD1 | PWM（PWM0-1） |
| 33 | PD3 | PWM（PWM0-3） | | 34 | — | GND |
| 35 | PB6 | **PCM_FS = I2S0-LRCK** | | 36 | PD2 | GPIO（PWM0-2） |
| 37 | PD4 | GPIO（PWM0-4，I2S0-LRCK 网络） | | 38 | PB8 | **PCM_DIN = I2S0-DIN0** |
| 39 | — | GND | | 40 | PB7 | **PCM_DOUT = I2S0-DOUT0** |

### HAT 所需信号 → A733 映射（结论：位置级完全兼容）

| HAT 信号 | Zero 3W(RK3566) 现脚 | A733 脚 | 结论 |
|---|---|---|---|
| I2C（codec 0x18 + ToF） | 3/5 | 3/5 = TWI0（PB3/PB2） | 同位置；overlay 换 twi0，S-TWI2 在 PL/arisc 域默认不使能则无冲突 |
| DXL 1M UART | 8/10（uart2 m0，复用调试口） | 8/10 = UART（CPU 调试口） | 同位置、同玩法：照抄 kissqy setup-board.sh 思路，禁 console、UART 让给 DXL，1Mbaud |
| I2S BCLK/FS/DIN/DOUT | 12/35/38/40 | 12/35/38/40（I2S0，PB5/PB6/PB8/PB7） | 四线位置完全相同 |
| codec MCLK 12MHz | 板上 Y1 12MHz 晶振（HAT 自带，非排针） | 同上，不需要主控 MCLK | 无影响；A733 的 7 脚 I2S0-MCLK 留空即可 |
| 3V3 / 5V | 1、2/4 | 1、2/4 | 注意 A733 5V 输出上限 0.5A、3V3 0.5A——外置 DCDC 供电方案不受影响 |

### 结论（替代此前基于官网引脚图的悲观判断）

- **HAT 四类信号（I2C / UART / I2S / 电源）与 A733 位置级全部兼容，无需改任何一根 HAT 走线**；官网引脚图的「8/10 无 UART、无 I2S」是错标/简标，以原理图为准。
- 剩余工作全部在**软件侧**：A733（sun55i）内核 overlay——twi0 使能（codec 0x18 + ToF）、UART0 去 console + 1Mbaud、I2S0 + codec 驱动（aic3104 dt 节点移植）、按需 pwm。
- 排针 14/16/26/27/28（PL2/PL3/PL4/PL5）挂 arisc/常开域，做 GPIO 备用前先确认主核可控。

### 残留待办

- [ ] 用户手册核对：I2S0/twi0/uart0 的 sun55i pinctrl 节点名，用于写 overlay（手册 PDF 已在桌面资料）
- [ ] 板到手后 gpioinfo 实测 altfunc 与本表比对
