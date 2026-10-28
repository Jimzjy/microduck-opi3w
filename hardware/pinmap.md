# Zero 3W 40-pin → HAT 信号对照（REV B 定稿）

来源：`HAT_REVA_SCH_OPI3W.eprj2` 的导线网络 + 厂商 device tree 交叉验证。

## 已确认的信号（kissqy 实机验证过）

| 功能 | Zero 3W 排针脚 | 网络（原理图名） | SoC 控制器 / overlay |
|---|---|---|---|
| 3V3 | 1 | 3V3 | — |
| 5V | 2、4 | 5V | 外部 5V 经 HAT U11 螺钉端子上板（板载 DC-DC 已拆） |
| I2C（codec 0x18 / ToF H1） | 3、5 | `I2C_SDA` / `I2C_SCL` | i2c3 m0（`i2c3-pihat.dts`，400kHz，禁 fusb302） |
| DXL 半双工 UART | 11（TX）、13（RX） | `UART2_TX` / `UART2_RX` | uart2（PB0/PB1，见 `hardware/overlay/uart2-dxl.dts`，1Mbaud） |
| I2S 音频 | 12、35、38、40 | `I2S0_BCLK` / `I2S0_LRCK` / `I2S0_DIN` / `I2S0_DOUT` | i2s0 四线（MCLK 来自板上 Y1 12MHz 晶振，非排针） |
| GND | 6、9、14、18、20、25、30、34、39 | GND | — |

## J4 排母（FH-00339 / C2685112）贴装错位规则

原理图标注：**ZERO 奇数脚 n → J4 焊盘 n+1；偶数脚 n → J4 焊盘 n−1**（J4 焊盘号与排针号整体错一位，PCB 布线时注意）。

## 未使用的排针脚

**7**、15、16、18、21、22、23、24、26、27、28、29、31、32、33、36（HAT 原理图无连线）。
（7 在 A733 上是 I2S0-MCLK，HAT 的 MCLK 由板上 Y1 12 MHz 晶振提供，所以不需要它。）
移植到 A733 时这些脚可自由复用；11/13 已用于 DXL，8/10 留给 console。

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

### HAT 所需信号 → A733 映射（I2C / I2S 位置级兼容；UART 需改两根线）

| HAT 信号 | Zero 3W(RK3566) 现脚 | A733 脚 | 结论 |
|---|---|---|---|
| I2C（codec 0x18 + ToF） | 3/5 | 3/5 = TWI0（PB3/PB2） | 同位置；overlay 换 twi0，S-TWI2 在 PL/arisc 域默认不使能则无冲突 |
| DXL 1M UART | 8（TX）/10（RX）（uart2 m0，复用调试口） | **11（PB0 = UART2_TX）/ 13（PB1 = UART2_RX）** | **定案走 11/13**（用户 2026-10-25 决定）：console 留在 8/10 的 uart0/ttyS0，DXL 走 uart2，两者互不干扰 |
| I2S BCLK/FS/DIN/DOUT | 12/35/38/40 | 12/35/38/40（I2S0，PB5/PB6/PB8/PB7） | 四线位置完全相同 |
| codec MCLK 12MHz | 板上 Y1 12MHz 晶振（HAT 自带，非排针） | 同上，不需要主控 MCLK | 无影响；A733 的 7 脚 I2S0-MCLK 留空即可 |
| 3V3 / 5V | 1、2/4 | 1、2/4 | 注意 A733 5V 输出上限 0.5A、3V3 0.5A——外置 DCDC 供电方案不受影响 |

### 结论

- DXL 走 **11/13 的 uart2**，console 留在 8/10。HAT 侧因此改了两处走线：J4 上「排针 8」「排针 10」两个
  焊盘与 `UART2_TX` / `UART2_RX` 断开，改接「排针 11」（J4-12）与「排针 13」（J4-14）。原因：8/10 是
  **焊死在 J4 排母上**的，只跳线不切断等于让 console（uart0）和 DXL（uart2）两个 UART 顶在同一个网上。
- 8/10 在 HAT 上因此空出来，正好接 USB-TTL 看 console。
- 半双工方向切换全在 HAT 硬件（U7/U6 + MMBT3906），不占 GPIO，也不需要内核 RS485。
- **不走「DXL 复用 8/10 的 uart0」**（评估过，放弃）：uart0 就是调试口，要 mask `serial-getty@ttyS0`
  丢掉 console；固件口从 `/dev/ttyS2` 变成 `/dev/ttyS0`；uart0 FIFO 只有 64 B（uart2 是 256 B），
  1 Mbps 无 DMA 的余量只能靠实测。代价大于改两根线。
- 若将来直接拿 kissqy 原版 PCB 插 A733：他把排针 32（J4-31）接地，A733 该脚是 PD1/PWM，需确认 PD1
  上电态不为高；我们这版留空。
- 排针 14/16/26/27/28（PL2/PL3/PL4/PL5）挂 arisc/常开域，做 GPIO 备用前先确认主核可控。
- 软件侧还差：twi0 使能（codec 0x18 + ToF）、uart2 使能（`hardware/overlay/uart2-dxl.dts`）、
  I2S0 + aic31xx 驱动、按需 pwm。

### I2S / UART 在 A733 上能否配出来（厂商内核 BSP 实证，2026-10-25）

来源：`orangepi-xunlong/linux-orangepi` 分支 `orange-pi-6.6-sun60iw2` 的 `arch/arm64/boot/dts/allwinner/sun60i-a733-orangepi-zero3w.dts` + `sun60iw2p1.dtsi`（已下载本地核对）。

**I2S：可配，pin 级已钉死**
- 板级 dts 的 i2s0 pin 组：`i2s0_pins_a` = **PB4**（i2s0_mclk）、`i2s0_pins_b` = **PB5**（bclk）、`i2s0_pins_c` = **PB6**（lrck）、`i2s0_pins_d` = **PB8**（din0）、`i2s0_pins_e` = **PB7**（dout0）——与排针 7 / 12 / 35 / 38 / 40 完全对上。
- 控制器 `i2s0_plat@2532000`（`allwinner,sunxi-snd-plat-i2s`）带 tx/rx DMA 与 PLL_AUDIO 时钟，`pinctrl-0` 已把这 5 个 pin 组全挂上，只差 `status = "okay"`。
- machine 节点 `i2s0_mach`（`allwinner,sunxi-snd-mach`）里的 `soundcard-mach,codec { };` 是**空节点**，
  就是留给外挂 codec 填 `sound-dai` 的。
- codec 驱动 `sound/soc/codecs/tlv320aic31xx.c` 在厂商内核树内存在。overlay 三件套即：i2c 上挂 codec 节点、`&i2s0_plat` 置 okay、`&i2s0_mach` 的 codec 子节点指向它。
- 仍需上板确认：镜像内核有没编 `CONFIG_SND_SOC_TLV320AIC31XX` 与 sunxi sound mach（`zcat /proc/config.gz | grep -i aic31`）。

**UART：可配，两条路都在**
- 9 个 uart 控制器统一 `allwinner,uart-v100`（uart0@0x2500000 … uart8@0x7081000），都能 overlay 挂 pin 组开启，1 Mbps + DMA 无碍。
- uart2 的 pin 组是 `pins = "PB0","PB1"`，即排针 **11/13**（本项目已把 DXL 接在这里）。
- 排针 8/10 是「CPU-TX / CPU-RX 调试口」，即 console 用的 uart0 / ttyS0。
- ∴ 走 8/10 = 复用 debug UART，要禁 console/getty（kissqy 同款）；**本板已定案改走 11/13 的 uart2**（`hardware/overlay/uart2-dxl.dts`，只写一行 `status = "okay"`，pinctrl 板级 dts 里已有），console 留在 8/10。
- **TX/RX 顺序**：`uart2_pins_active` 里 `pins = "PB0","PB1"`，按 sunxi 惯例（uart1 的 PG6/PG7… 同样先 TX 后 RX）**PB0 = TX → 排针 11、PB1 = RX → 排针 13**。厂商侧旁证：u-boot 的 A733 pinctrl patch 里 `uart0` 默认复用就是 `PB9, PB10`（先 TX 后 RX）。仍列为待实测项，若反了只需对调两根线。
- 仍需上板确认：厂商 dts 的 `uart0_pins_active` 是 `pins = "", ""`（空），Linux 侧 pin 名要查手册 GPIO 复用表，或 `cat /sys/kernel/debug/pinctrl/*/pinmux-pins` 直接读（走 uart2 的话此项只影响 console，与 DXL 无关）。

### 残留待办

- [ ] uart2 的 PB0/PB1 谁是 TX 实测确认（反了对调排针 11/13 两根线即可）
- [x] HAT REV B：J4 焊盘 7/9（排针 8/10）断开 UART 网，焊盘 12/14（排针 11/13）接 `UART2_TX` / `UART2_RX`（2026-10-25 已在原理图完成，网表实测通过）
- [ ] 板到手后 gpioinfo / pinmux-pins 实测 altfunc 与本表比对
