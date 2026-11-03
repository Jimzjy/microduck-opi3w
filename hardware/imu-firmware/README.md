# imu_to_dxl 固件 1.0.0（FT-SCS）

> 这一版是从 0.1.0（Dynamixel 2.0）另起改成飞特协议的，跟旁边 [`../firmware/`](../firmware/) 的 0.2.0 是两套独立实现：15 字节块、型号 0x4D44 一样，诊断区不一样（这一版在 90..185，0.2.0 在 124..247）。在 Microduck 上用，主程序要是 fork 4734cbb 起（复刻镜像 20261021b 起），它会把这块板排在舵机后面。两版怎么选见 [`../README.md`](../README.md)。

Microduck 用 **STM32G031F8P6 + LSM6DSV16X** IMU 板的固件。硬件基线
`fanhao375/microduck-replica` @ `a1f4979c`（含 J4/J5、RX_EN）。

固件说 **飞特 FT-SCS 协议**（已从 Dynamixel 2.0 迁移）：IMU 板固定 **ID=200、500 kbps、8N1**
（本仓改动：`Core/Inc/board_config.h` 的 `BOARD_BUS_BAUD` 1000000→500000、
`Core/Inc/protocol.h` 的 `PROTO_BAUD_CODE` 0→1；与舵机 reg6=1、主控 `BAUD_RATE=500_000` 三端一致，原因见 [`../../docs/07-imu-firmware.md`](../../docs/07-imu-firmware.md)），
与飞特 SCS/STS 舵机共用同一根单线半双工总线，一条 SYNC READ 同时读取 IMU 与全部舵机。
数据内容对齐 GitHub `pollen-robotics/microduck` 的 duck-control 契约
（陀螺仪 i16×3 + SFLP fp16 四元数 x/y/z，w 主机恢复，50Hz）。

数据流：LSM6DSV16X → SPI1 → STM32 → USART2 + 外部缓冲 → 单线半双工总线 → 主控。
裸机、无 RTOS、无动态内存、无 HAL；ID/波特率固定为 500 kbps，不写 Option Bytes / Flash 配置。

## 快速开始

```bash
# 1) 构建固件（需 arm-none-eabi-gcc；仓库已预置构建好的 hex，可跳过）
make          # 产物 Build-gcc/imu_to_dxl.hex

# 2) 烧录（务必用 OpenOCD）
openocd -f interface/cmsis-dap.cfg \
  -f target/stm32g0x.cfg -c 'adapter speed 4000' \
  -c 'program Build-gcc/imu_to_dxl.hex verify reset exit'

# 3) 上位机工具（--port 接半双工总线适配器，Linux 下常为 /dev/ttyUSB0）
python -m pip install -r Tools/requirements.txt
python Tools/servo_tool.py scan --port /dev/ttyUSB0       # 扫描 IMU(200)+舵机
python Tools/bus_monitor.py --port /dev/ttyUSB0 --no-demo # IMU+舵机联合监控（不转动）
python Tools/imu_monitor.py --port /dev/ttyUSB0 --plot    # IMU 50Hz 曲线
python Tools/imu_probe.py --port /dev/ttyUSB0 --seconds 30 # 只读验收（退出码 0 = 通过）
```

**唯一硬性总线规则**：主机 SYNC READ 的 ID 列表中，200 必须排在舵机之后（末位/中位），
禁止首位，也可单独成组。详见 [使用说明](docs/使用说明.md) 第 6 节。

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/使用说明.md](docs/使用说明.md) | 接线（J1/J2/J4/J5/J3）、环境、构建烧录、四个 Python 工具完整用法、首次上板流程、排障表、无硬件测试 |
| [docs/实现原理.md](docs/实现原理.md) | FT-SCS 帧机与校验、寄存器/诊断映射、SYNC READ 排位防撞状态机、半双工 DE 时序、50Hz 时间预算、IMU 采样链与主机契约 |
| [VALIDATION.md](VALIDATION.md) | 主机测试与实机验收记录 |
| [DEPENDENCIES.md](DEPENDENCIES.md) | 第三方源码/工具链版本与许可 |

## 目录结构

```
Core/Inc, Core/Src   固件源码（board / imu / protocol / control_table / main）
Drivers/             固定版本 CMSIS 与 ST LSM6DSV16X 驱动（含许可证）
Tools/               4 个 Python 工具（servo_tool / bus_monitor / imu_monitor / imu_probe）
docs/                使用说明、实现原理
gcc/                 GCC 启动文件与链接脚本（本仓的交叉编译入口，见 Makefile）
Build-gcc/           构建产物（make 产出；含预置的 imu_to_dxl.hex）
```

> 上游原版还有 Keil（MDK-ARM）、无硬件测试（Tests）等目录，本仓未收录；构建用 `make`（arm-none-eabi-gcc）替代 Keil。

## 关键事实速查

- 帧：`FF FF ID LEN INST P... CK`；`LEN=参数数+2`，总长 `4+LEN`；校验 `~(ID+LEN+INST+ΣP)&0xFF`。
- 指令：PING(0x01) / READ(0x02) / WRITE(0x03) / SYNC READ(0x82) / SYNC WRITE(0x83)；
  广播 PING 静默；无返回延迟。
- 快速块地址 56（与舵机状态块同址）：56..61 gyro i16×3（±500dps，17.5mdps/LSB）、
  62..67 qx/qy/qz fp16；68..73 加速度；75 flags；76 WHO_AM_I=0x70；
  84 user_marker 可读写；90..185 诊断块 24×u32；写 240=0xA5 重初始化 IMU。
- 采样：IMU 120Hz（FIFO+SFLP），主机 50Hz；未就绪时 gyro/quat 返回全零，
  主机必须结合 ready/采样计数/年龄做失效处理。
- 本机端口：半双工总线 **500 kbps**；DAP-Link 日志 115200（需 DTR/RTS 拉高）。

## 资料

- [本板硬件](https://github.com/fanhao375/microduck-replica/tree/a1f4979c425bd9228622be89f2bfa4d1de7fbde3/hardware/imu_to_dxl)
- [STM32G031 数据手册](https://www.st.com/resource/en/datasheet/stm32g031f8.pdf)
- [LSM6DSV16X 数据手册](https://www.st.com/resource/en/datasheet/lsm6dsv16x.pdf)
- [上游主控接口 duck-control](https://github.com/pollen-robotics/microduck/blob/5984efb770855432b03dafd3d879e9929981e45b/duck-control/src/bus.rs)
- [飞特 FT-SCS 协议](https://www.feetechrc.com/)

新写代码按 MIT 许可提供；第三方文件保留各自版权与许可（见 Drivers 目录）。
