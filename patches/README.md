# 运行时补丁 (`opi3w-feetech`)

`runtime-opi3w-feetech.patch` 是我们主控运行时分支的**完整差分**: 把它打在官方的
`daemon-v0.17.9` 上, 就得到我们正在跑的那个运行时, 一位不差 (下面有树哈希对账)。

**为什么要存这份补丁**: 那个分支已推到 `Jimzjy/microduck-runtime` 的 `opi3w-feetech` 分支,
并作为 submodule 挂在本仓 `runtime/`——**优先用 submodule, 它永远是最新真相**。补丁是同一份代码的
离线形态: 远端丢号、断网、或者想在一个干净 clone 上复现时用它。

## 版本

| 项 | 值 |
| --- | --- |
| 基线 | `pollen-robotics/microduck` tag `daemon-v0.17.9` = `96b89d8613f06722c1d64ce75ab0d7124fed9d8f` |
| 打完补丁后 | 与我们分支 `opi3w-feetech` HEAD `4d375ba` **完全一致** (`git write-tree` = `a1d4105fa12fc54d8c09b20ef539632a17e1f4d5`, 2026-11-08 实测 `TREE MATCH`) |
| 规模 | 29 个文件, `+5646 / −387` (含 6 个新文件) |

## 用法

```bash
git clone https://github.com/pollen-robotics/microduck.git
cd microduck
git checkout daemon-v0.17.9
git apply /path/to/microduck-opi3w/patches/runtime-opi3w-feetech.patch
git switch -c opi3w-feetech
git add -A && git write-tree      # 应为 a1d4105...

cargo test -p duck-ipc-proto -p robotd-params -p duck-control -p robotd
```

然后用本仓的 [scripts/build-runtime.sh](../scripts/build-runtime.sh) 交叉编译出
`robotd` / `robotctl` (那脚本默认从旁边的 `microduck-runtime` 目录取源码, 改一下路径或先把仓放在同名目录即可)。

## 补丁里有什么

| 文件 | 内容 |
| --- | --- |
| `duck-control/src/bus_feetech.rs` (新) | 飞特 STS 总线后端: 寄存器同步读写, `p_scale` 换算, **HD-1910 真增益寄存器 50/51**, 速度寄存器单位 50 step/s, 逐颗电压/温度, 总线 IMU (ID 200, 块 `56/15`, 前 12 字节复用 `SflpDecoder`, 排在 15 颗舵机之后) |
| `duck-control/src/bus_select.rs` (新) | `BusProtocol` 按配置在 Dynamixel 2.0 与 Feetech STS 之间选一个 |
| `duck-control/src/{bus,io,lib,model,sim,safety,imu}.rs` | `SlowSensors.joint_volts`, `cached_slow`, 标定零位/方向/限位, `sim` 补 `joint_volts`; **总线 500 kbps** (`BAUD_RATE = 500_000` + `FEETECH_BAUD_REGISTER = 1`, 见下) |
| `duck-ipc-proto/src/lib.rs` | `robot.busStatus` / `robot.busCommand` 的调用与响应类型 (`BusStatus`, `BusCommandParams`, `BusCalibration` …) |
| `robotd-params/src/calibration.rs` (新) | 标定文件 `hd1910-calibration.toml` 的解析 / 校验 / 回写 (含 `imu_mount_quat`) |
| `robotd-params/src/{lib,registry,edit}.rs` | `[bus.feetech]`、`[control] velocity_source`、`[policy] max_target_speed / gyro_lowpass_hz` 等配置项 |
| `robotd/src/commissioning.rs` (新) | 标定台架状态机: hold-home 的目标流插值 + 实测误差, verify-imu 的摆正/低头判定 |
| `robotd/src/dump.rs` (新) | 每拍 obs/action 落盘 (`--dump`), 离线对齐策略看到了什么 |
| `robotd/src/{main,control}.rs` | 总线后端选择, 标定装载, `busStatus` 快照拼装, `busCommand` 异步派发, `--commissioning` 模式; 速度来源 (reported / 差分) 与延后一拍, 可选的目标限速 |
| `mediad/src/{exposure,sensorctl,pipeline,route,sensor,main,lib}.rs` | A733 摄像头: 曝光走私有 ioctl `VIDIOC_VIN_SENSOR_EXP_GAIN`, 原始 Bayer 抓帧, 抓帧降到档位分辨率 |
| `robotctl/src/monitor.rs`, `updater/src/ipc.rs` | 监控输出与 updater 接口跟进 |
| `docs/design/robotd-design.md` | §3.6 标定台架的机制说明 |
| `deploy/robotd.toml` | `[bus.feetech]` 与几个可选旋钮的注释、默认值, 以及我们实测的取舍 |

## 三条与舵机有关的实测结论

复刻时最容易踩的三个坑, 都写进了代码注释, 这里给出处:

1. **HD-1910 真正的 P/D 在寄存器 50/51**, 出厂 32/40。STS 表的 21/22/23 能写、能读回, 但**不影响位置环**
   ——只写 21 会得到「刚度完全没变」的结果。`set_gain` 现在两张表都写, D 固定 0 (写 20 实测更差)。
   都是 RAM 写 (锁寄存器 55 保持关闭), 断电恢复出厂 32/40, 上力时重写。
2. **速度寄存器的单位是 50 步/秒每格**, 不是 1。按 1 读会给策略一个**小 50 倍**的关节速度, 阻尼通道等于
   没有, 表现为 4–7 Hz 小幅自激。`read_speed_unit` 按 phase 位选 50.0。
3. **速度要延后一拍再进观测** (训练合同 `delay_min_lag = 1`)；`velocity_source` 默认 `reported`
   (舵机自己平滑过的速度), 差分是备选, 实测更抖。

## 总线为什么是 500 kbps

A733 的 uart2 时钟来自固定的 24 MHz, vendor 的 uart-ng 驱动没有小数分频, 1 Mbps 会被取整成
750 kbps, 总线上一颗舵机都不应答 (而且 dmesg 每秒刷 `baud 500000 beyond rance` 这类提示)。
500 kbps 能整除 (`24 MHz / 16 / 3`), 也是飞特的标准档位。

**舵机侧要同步**: EEPROM 寄存器 6 (`baudrate`) 设成 `1` (500 kbps), 出厂默认是 `0` (1 Mbps)。
`check_registers` 启动时会把不一致的舵机自动改成 `1`。

## 以后怎么维护

- 分支每往前走一步, **同一次提交里**重新生成补丁 (`git diff daemon-v0.17.9..HEAD --output=…`)、
  更新本文件的 HEAD 与树哈希, 否则补丁会悄悄落后于真机在跑的东西。
- 生成后按上面「用法」里的 `git write-tree` 对一次哈希, 这是唯一能证明补丁没漏东西的办法。
