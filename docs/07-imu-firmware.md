# IMU 板与固件

IMU 是挂在舵机总线上的 **DXL ID 200** 设备 (STM32G031F8P6 + LSM6DSV16X), 一块板、一份固件、一根总线线。
这块板是 replica 的 v2 设计, 但**固件由本仓维护**——因为本项目把总线改成了 500 kbps。

## 1. 板子: 工程文件在本仓

| 项 | 位置 |
| --- | --- |
| EasyEDA Pro 工程 | [`hardware/eda/imu_to_dxl_1V0A/imu_to_dxl_1V0A.eprj2`](../hardware/eda/imu_to_dxl_1V0A/imu_to_dxl_1V0A.eprj2) |
| 原理图 PDF | [`hardware/eda/imu_to_dxl_1V0A/imu_to_dxl_1V0A-原理图.pdf`](../hardware/eda/imu_to_dxl_1V0A/imu_to_dxl_1V0A-原理图.pdf) |
| 来源 | `fanhao375/microduck-replica` @ `35b435d7a6361c3480c2d0916ecf79c318710690`, 路径 `hardware/新版/imu_to_dxl_1V0A` |

**为什么把上游的工程文件复制进来**: 我们改了固件, 固件与板子的引脚表是一对一绑定的。如果哪天 replica
把这块板改了 (换 MCU、挪 INT1/CS、加器件), 照我们文档去 clone replica 的人拿到的就是另一块板, 我们的
固件反而用不了。工程放在本仓, 复刻者一定拿到我们验证过的那一版, 上游怎么演进都不影响。

接插件脚序、电源、数据通路、MCU 引脚表见 [hardware/imu-layout.md](../hardware/imu-layout.md)。

## 2. 固件: 本仓自带 (500 kbps)

| 项 | 位置 |
| --- | --- |
| 源码 (含预编译 hex) | [`hardware/imu-firmware/`](../hardware/imu-firmware/) |
| 预置产物 | `hardware/imu-firmware/Build-gcc/imu_to_dxl.hex` (51,353 B) |
| 基线 | replica `hardware/imu_to_dxl/firmware-1.0.0` (MIT) |
| 相对基线的改动 | 3 个文件: 波特率、波特率编码、台架自检命令; 细节见该目录 `README-opi3w.md` |

**为什么必须自己编**: A733 的 uart2 时钟固定 24 MHz, vendor 的 uart-ng 驱动没有小数分频。
1 Mbps 算出来是 `24e6/16/1e6 = 1.5`, 取整成 2 → 实际 750 kbps, 总线上没有任何一颗设备应答;
500 kbps 整除 (`24e6/16/3`)。改总线就得改两端的档位, 而 replica 那份 hex 的档位写死在 1 Mbps。

三个档位必须一致, 缺一个就不通:

| 端 | 设定 | 在哪 |
| --- | --- | --- |
| 舵机 | EEPROM 寄存器 6 = `1` (500 kbps) | 用飞特 FD 软件改, 每颗都改 |
| IMU 板 | `PROTO_BAUD_CODE = 1`, `BOARD_BUS_BAUD = 500000` | 本仓 `hardware/imu-firmware/Core/Inc/` |
| 主控 | `BAUD_RATE = 500_000`, `FEETECH_BAUD_REGISTER = 1` | 运行时补丁 `patches/runtime-opi3w-feetech.patch` |

主控在启动时会逐个读舵机与 IMU 的寄存器 6 做校验, 对不上就在日志里报 `baud ... expected 1`。

烧录与验证步骤见 `hardware/imu-firmware/README-opi3w.md` (SWD 接 J3, `openocd program ...`)。
验证的三条: 串口 `s` 显示 `1.0.0-500k ... 500000 8N1`; `n` 显示 `ready=1 id=0x70`;
主控 `read_id_0_8` 的第 7 字节 (寄存器 6) 是 `0x01`。

## 3. 供电: IMU 板从总线取电, 5V DC-DC 只给 HAT

```
电池 (6–8.4 V) ──→ HAT J13/J14 (2 脚只直通) ──→ 舵机 ×15 + IMU 板 (J1-2 VDD_BUS)
                                              IMU 板内部: F1 PTC → D1 TVS → HT7533-1 → 3V3

5V DC-DC (UBEC) ──→ HAT U11 ──→ Q2/Q3/Q4 ──→ 5V 母线 ──→ OPi Zero 3W / codec / 麦克风偏置 / 功放
```

**5V DC-DC 只给 HAT 板供电**: 舵机和 IMU 板吃的是电池电压, 不经过 5V 母线。所以 DC-DC 只需要按
"主控 + codec + 功放" 估电流 (3A 同步整流够用), 不用按 15 颗舵机的堵转电流选; 反过来, 拔掉舵机电池
时 IMU 板也会一起断电, 这是正常的。

## 4. 排障

| 现象 | 先查 |
| --- | --- |
| 主控完全收不到 IMU 回包 | 板子有没有上电 (J1-2 有没有电池电压); 固件是不是 500 kbps 版 (`s` 的首行) |
| 同上, 且总线是 1 Mbps | 固件与舵机档位不一致, 三个档位表逐项对 |
| `ping 200` 没应答但舵机能通 | J1 的 1/2/3 脚序 (本项目统一 `数据/V+/GND`, 不要用 Dynamixel 序的成品线) |
| `ready=0 err=3` | IMU 芯片 SPI 不通, 多半是 LGA 焊接 (见 [imu-layout.md](../hardware/imu-layout.md)) |
