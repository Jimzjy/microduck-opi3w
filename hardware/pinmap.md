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

## A733 40-pin 对照（待办）

- [ ] I2C3 M0 → A733 对应控制器/引脚
- [ ] UART（1M）→ A733 对应 UART/引脚
- [ ] I2S3 → A733 对应 I2S 控制器/引脚
- [ ] 待 A733 手册核实后补全右列
