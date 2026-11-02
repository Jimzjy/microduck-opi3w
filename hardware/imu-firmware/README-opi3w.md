# IMU 板固件 (本仓自带, 500 kbps 版)

这块板的固件**由本仓维护**, 不再直接烧 replica 的 `firmware-1.0.0` hex: 本项目的总线跑 500 kbps
(A733 的 uart2 出不了 1 Mbps, 见下), 而 replica 那一版的波特率写死在 1 Mbps。

- 基线: `fanhao375/microduck-replica` @ `35b435d7a6361c3480c2d0916ecf79c318710690`,
  路径 `hardware/imu_to_dxl/firmware-1.0.0` (MIT, 见同目录 `LICENSE`)
- 本目录 = 那份源码 + 三处改动 + 一套 GCC 构建 (上游只有 Keil 工程)
- 预置产物: `Build-gcc/imu_to_dxl.hex` (51,353 B; `text 18,136 / data 92 / bss 5,452`)

## 相对 replica 1.0.0 改了什么

只改三个文件, 其余逐字节相同:

| 文件 | 改动 |
| --- | --- |
| `Core/Inc/board_config.h` | `BOARD_BUS_BAUD` 1000000 → **500000**; 新增 `BOARD_BUS_BAUD_STR "500000"`; `BOARD_FIRMWARE_STRING` → `"imu_to_dxl 1.0.0-500k"` |
| `Core/Inc/protocol.h` | `PROTO_BAUD_CODE` 0 → **1** (飞特编码: 0 = 1 Mbps, 1 = 500 kbps)。主控启动时按寄存器 6 校验波特率, 不改成 1 会被判为配置不符 |
| `Core/Src/main.c` | 只加台架自检命令 (`p` 引脚, `s` SPI, `i` IMU, `b` 位翻转, `n` 探针, `x` SDO 上拉, `y` INT 输出, `w` SPI 压测)。数据通路, 协议, 控制表一行没动 |

**为什么不是 1 Mbps**: A733 的 uart2 时钟来自固定的 24 MHz, vendor 的 uart-ng 驱动没有小数分频。
`24e6 / 16 / 1e6 = 1.5`, 取整成 2 → 实际 750 kbps, 总线上没有一颗设备应答。500 kbps 是整除
(`24e6 / 16 / 3`), 而且舵机侧改个 EEPROM 字节就能跟 (寄存器 6 = `1`)。

所以这块板与舵机、与主控三方的档位必须一起看: **舵机 EEPROM 寄存器 6 = 1, IMU 固件的
`PROTO_BAUD_CODE = 1`, 主控运行时 `BAUD_RATE = 500_000 + FEETECH_BAUD_REGISTER = 1`**。

## 构建

需要 `arm-none-eabi-gcc` (Debian/Ubuntu: `apt install gcc-arm-none-eabi`), 不需要 Keil。

```bash
cd hardware/imu-firmware
make                # 产物在 Build-gcc/: imu_to_dxl.hex / .bin / .elf / .map
make clean
```

改过 `Core/Inc/*.h` 之后要 `make clean && make` —— Makefile 没有头文件依赖跟踪。

## 烧录

SWD 接板上的 J3 (`3V3 / SWDIO / GND / SWCLK / NRST`), 任一 CMSIS-DAP / ST-Link 探针:

```bash
openocd -f interface/cmsis-dap.cfg -f target/stm32g0x.cfg \
        -c 'adapter speed 4000' \
        -c 'program Build-gcc/imu_to_dxl.hex verify reset exit'
```

## 验证

1. 串口 (115200 8N1) 上 `s`: 应打印 `imu_to_dxl 1.0.0-500k | STM32G031F8 | FT-SCS ID=200 500000 8N1`
2. `n`: `ready=1 id=0x70 err=0`, `n` 每秒涨约 113
3. 主控侧 `read_id_0_8` 读回来第 7 个字节 (寄存器 6) 应是 `0x01`; `ping 200` 回 `ffffc8020035`

## 与上游同步

replica 若再改这块板或这份固件, **不要直接覆盖本目录**: 先比 `git log` 与其 `firmware-1.0.0`
的差异, 把我们这三处改动重新贴上去, 再 `make` 并跑一遍上面三条验证。板子的 EDA 工程同样已在
本仓 (`../eda/imu_to_dxl_1V0A/`), 不依赖上游在线可用。
