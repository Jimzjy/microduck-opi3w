# 运行时补丁 (`opi3w-feetech`)

`runtime-opi3w-feetech.patch` 是我们主控运行时分支的**完整差分**: 把它打在官方的
`daemon-v0.17.9` 上, 就得到我们正在跑的那个运行时, 一位不差。

**为什么要存这份补丁**: 那个分支目前只在我们自己的机器上 (没推到任何远端)。这台机器没了, 
移植成果就没了。补丁放在本仓里, clone 下来就能重建。

## 版本

| 项 | 值 |
| --- | --- |
| 基线 | `pollen-robotics/microduck` tag `daemon-v0.17.9` = `96b89d8613f06722c1d64ce75ab0d7124fed9d8f` |
| 打完补丁后 | 15 个 crate 的树与我们分支 `opi3w-feetech` HEAD `3c74775` **完全一致** (`git write-tree` = `41403c05b8dbe610ca596145353db4bbb828536d`) |
| 规模 | 16 个文件, `+3856 / −25` (含 4 个新文件) |

## 用法

```bash
git clone https://github.com/pollen-robotics/microduck.git
cd microduck
git checkout daemon-v0.17.9
git apply /path/to/microduck-opi3w/patches/runtime-opi3w-feetech.patch
git switch -c opi3w-feetech

cargo test -p duck-ipc-proto -p robotd-params -p duck-control -p robotd   # 554 通过 / 0 失败
```

然后用本仓的 [scripts/build-runtime.sh](../scripts/build-runtime.sh) 交叉编译出
`robotd` / `robotctl` (那脚本默认从旁边的 `microduck-runtime` 目录取源码, 改一下路径或先把仓放在同名目录即可)。

## 补丁里有什么

| 文件 | 内容 |
| --- | --- |
| `duck-control/src/bus_feetech.rs` (新) | 飞特 STS 总线后端: 寄存器同步读写, `p_scale` 换算, 逐颗电压/温度, 总线 IMU (ID 200, 块 `56/15`, 前 12 字节复用 `SflpDecoder`) |
| `duck-control/src/bus_select.rs` (新) | `BusProtocol` 按配置在 Dynamixel 2.0 与 Feetech STS 之间选一个 |
| `duck-control/src/{bus,io,lib,model,sim}.rs` | `SlowSensors.joint_volts`, `cached_slow`, 标定零位/方向/限位, `sim` 补 `joint_volts`; **总线 500 kbps** (`BAUD_RATE = 500_000` + `FEETECH_BAUD_REGISTER = 1`, 见下) |
| `duck-ipc-proto/src/lib.rs` | `robot.busStatus` / `robot.busCommand` 的调用与响应类型 (`BusStatus`, `BusCommandParams`, `BusCalibration` …) |
| `robotd-params/src/calibration.rs` (新) | 标定文件 `hd1910-calibration.toml` 的解析 / 校验 / 回写 |
| `robotd-params/src/{lib,registry}.rs` | `[bus.feetech]` 配置项 (含 `calibration` 路径) |
| `robotd/src/commissioning.rs` (新) | 标定台架状态机: hold-home 的目标流插值 + 实测误差, verify-imu 的摆正/低头判定 |
| `robotd/src/main.rs` | 总线后端选择, 标定装载, `busStatus` 快照拼装, `busCommand` 异步派发, `--commissioning` 模式 |
| `docs/design/robotd-design.md` | §3.6 标定台架的机制说明 |
| `deploy/robotd.toml` | `[bus.feetech]` 的注释与默认值 |

## 总线为什么是 500 kbps

A733 的 uart2 时钟来自固定的 24 MHz, vendor 的 uart-ng 驱动没有小数分频, 1 Mbps 会被取整成
750 kbps, 总线上一颗舵机都不应答 (而且 dmesg 每秒刷 `baud 500000 beyond rance` 这类提示)。
500 kbps 能整除 (`24 MHz / 16 / 3`), 也是飞特的标准档位。

**舵机侧要同步**: EEPROM 寄存器 6 (`baudrate`) 设成 `1` (500 kbps), 出厂默认是 `0` (1 Mbps)。
`check_registers` 启动时会把不一致的舵机自动改成 `1`。

## 以后怎么维护

- 分支继续往前走时, **同时**更新这份补丁 (`git diff daemon-v0.17.9..HEAD --output=…`)与本文件的树哈希, 
  否则补丁会悄悄落后于真机在跑的东西。
- 更好的做法是把 `opi3w-feetech` 推到一个远端仓 (自己 fork 官方仓即可), 补丁作为离线备份保留。
  两者不冲突: 远端是主路径, 补丁是断网/丢号时的兜底。
