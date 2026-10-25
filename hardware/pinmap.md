# Zero 3W 40-pin → HAT 信号对照（来自 kissqy HAT RevA 原理图实测导出）

来源：HAT_REVA_SCH.eprj2 原理图导线网络 + firmware overlay 注释交叉验证。

## 已确认的信号（kissqy 实机验证过）

| 功能 | Zero 3W 排针脚 | 网络（原理图名） | SoC 控制器 / overlay |
|---|---|---|---|
| 3V3 | 1 | 3V3 | — |
| 5V | 2、4 | 5V | —（经 AP63205/LM5050 电源域） |
| I2C（codec 0x18 / ToF J5） | 3、5 | GPIO02_I2C_SDA / GPIO03_I2C_SCL | i2c3 m0（`i2c3-pihat.dts`，400kHz，禁 fusb302） |
| DXL 半双工 UART | 8（TX）、10（RX） | GPIO14_UART_TX / GPIO15_UART_RX | uart2 m0（`REQUIRED_OVERLAY=uart2-m0`，1Mbaud；与 SoC 调试口复用） |
| I2S 音频 | 12、35、38、40 | GPIO18_PCM_CLK / GPIO19_PCM_FS / GPIO20_PCM_DIN / GPIO21_PCM_DOUT | i2s3_2ch（`aic3104-i2c3.dts`，MCLK 12MHz 固定时钟） |
| GND | 6、9、13、14、20、25、30、34、39 等未接信号脚 | GND | — |

## J4 排母（FH-00339 / C2685112）贴装错位规则

原理图标注：**ZERO 奇数脚 n → J4 焊盘 n+1；偶数脚 n → J4 焊盘 n−1**（J4 焊盘号与排针号整体错一位，PCB 布线时注意）。

## 未使用的排针脚

7、11、15、16、18、21、22、23、24、26、27、28、29、31、32、33、36（原理图无连线）。移植到 A733 时这些脚可自由复用。

## A733 40-pin 对照（Orange Pi Zero 3W v1.2，官方引脚图实测）

来源：[香橙派官网 Zero 3W 页面](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-Zero-3W.html) 的 Pin Definition 图（img/zero3w/details/24.webp），逐脚抄录。

### A733 全 40 脚（官方引脚图）

| 排针脚 | A733 引脚 | 功能 | | 排针脚 | A733 引脚 | 功能 |
|---|---|---|---|---|---|---|
| 1 | — | 3.3V | | 2 | — | 5V |
| 3 | PB3 | TWI0_SDA | | 4 | — | GND |
| 5 | PB2 | TWI0_SCK | | 6 | PB9 | UART0_TX |
| 7 | PB4 | PWM0_0 | | 8 | PB10 | UART0_RX |
| 9 | — | GND | | 10 | PB5 | —（无标注） |
| 11 | PB0 | UART2_TX | | 12 | GND | — |
| 13 | PB1 | UART2_RX | | 14 | PL2 | UART7_TX |
| 15 | PE11 | —（无标注） | | 16 | PL3 | UART7_RX |
| 17 | — | 3.3V | | 18 | GND | — |
| 19 | PE3 | TWI2_SDA / SPI3_MOSI | | 20 | PD0 | —（无标注） |
| 21 | PE3* | TWI3_SCK / SPI3_MISO | | 22 | PE0 | SPI3_CS0 / UART6_TX |
| 23 | PE1 | UART6_RX / TWI2_SCK / SPI3_CLK | | 24 | PE4 | SPI3_CS1 / TWI3_SDA |
| 25 | — | GND | | 26 | PL4 | —（无标注） |
| 27 | PL5 | —（无标注） | | 28 | GND | — |
| 29 | PE12 | —（无标注） | | 30 | PD1 | PWM0_1 |
| 31 | PE13 | —（无标注） | | 32 | GND | — |
| 33 | PD3 | PWM0_3 | | 34 | PD2 | PWM0_2 |
| 35 | PB6 | PWM0_8 | | 36 | PB8 | TWI1_SDA |
| 37 | PD4 | PWM0_4 | | 38 | PB7 | TWI1_SCL |
| 39 | — | GND | | 40 | PB7? | PWM0_9（官方图 38/40 均标 PB7，其一应为图误） |

\* 21 与 38/40 的脚-功能配对以官方图为直观抄录，图上个别线段贴标位置有歧义（TWI3_SCK 究竟挂 21 还是 19 行、TWI1_SCL 是 38 还是 40），**以 A733 datasheet / 官方手册为最终依据**。

### HAT 所需信号 → A733 映射

| HAT 信号 | Zero 3W(RK3566) 现脚 | A733 候选 | 结论/风险 |
|---|---|---|---|
| I2C（codec 0x18 + ToF） | 3/5 | 3/5 = TWI0（PB3/PB2） | ✅ 同位置可用，i2c3 overlay 换成 twi0 |
| DXL 1M UART | 8/10 | 6/8 = UART0（PB9 TX/PB10 RX） | ⚠️ **A733 的 8/10 无 UART**，必须换位置。UART0 在 6/8 是首选；UART7（14/16）在 PL 库（常暖域/arisc 管理），风险高不推荐 |
| I2S（4 线） | 12/35/38/40 | **40-pin 上无 I2S 标注** | ❌ 待核：候选是 SPI3 四脚（19/21/22/23，PE0-4）的 PCM 复用功能。**线上查不到 A733 I2S 复用确证**，需 A733 datasheet 或板子到手 `gpioinfo` 看 altfunc |
| MCLK 12MHz | 专用固定时钟 | 无 PWM-clock 直映射 | ⚠️ A733 40-pin 未暴露专用 MCLK；候选：PWM 引脚配 pwm-clock 出 12MHz，或 codec 内 PLL 由 BCLK 生成 MCLK（AIC3104 有 PLL，需核对手册） |

### 结论

- I2C ✅ 同位兼容；DXL ⚠️ 要从 8/10 挪到 6/8（一根跳线/改 HAT 走线）；I2S 与 MCLK 是**两个未决硬点**，决定 HAT 是否能原样贴到 A733。
- 未决前不要打 HAT A733 适配板。下一步：拿到 A733 datasheet（全志官网/Linux sun55i 内核 pinctrl dtsi）核 SPI3 四脚的 PCM 复用。
