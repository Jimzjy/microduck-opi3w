# Microduck 复刻: Orange Pi Zero 3W (A733)

把 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 这只开源四足鸭复刻到
**Orange Pi Zero 3W (全志 A733)** 上: 沿用飞特 HD-1910 总线舵机与总线 IMU。
本仓只放改动与移植文档; 上游代码以子模块、差分补丁或小体量快照 (IMU 板工程 + 固件) 引入, 不整仓复制。

## 你需要准备什么

| # | 物料 | 说明 |
| --- | --- | --- |
| 1 | Orange Pi Zero 3W 主控板 | 本项目按 1GB 版实测。发行镜像已换好官方 bootloader (1GB 版可直接用); 自己构建见 docs/05 §5 |
| 2 | HAT 扩展板 | 工程 `hardware/eda/HAT_REVA_SCH_OPI3W.eprj2` (EasyEDA Pro), BOM 见 [hardware/hat-layout.md](hardware/hat-layout.md) |
| 3 | IMU 板 | 工程 [hardware/eda/imu_to_dxl_1V0A](hardware/eda/imu_to_dxl_1V0A/) (取自 replica, 已存本仓), 烧本仓固件 [hardware/imu-firmware](hardware/imu-firmware/), 见 [docs/07](docs/07-imu-firmware.md) |
| 4 | 5V DC-DC 模块 | 3A 同步整流 (mini560 类, 不要用 2A 的 LM2596), **只给 HAT 板供电**; 舵机与 IMU 板吃舵机电池, 不经过它 |
| 5 | 15x HD-1910 舵机 | 飞特 STS 总线; ID 与波特率设置见 docs/04 §3, 标定见 §6 |
| 6 | microSD 卡 | 卡 >= 16GB; 调试另备 mini HDMI 线或 USB-TTL 串口线 |
| 7 | ST-LINK V2 / V3 | 用于烧 IMU 板固件 |

喇叭, 麦克风等其余外设的型号与采购见 kissqy 发布包: [DUCK-SHOPPING-LIST](https://github.com/kissqy/Microduck-kissqy) (子模块 `firmware/` 内同款文件)。

后续扩展:

| 物料 | 说明 |
| --- | --- |
| ToF 测距模块 | VL53L5X V2 (I2C, 接 HAT H1 4P 排针); 用于拾取检测 |
| CSI 摄像头 | IMX219 (Radxa ROCK 5 摄像头同款, 22P RPI 序 FPC, 两个 CAM 座任插); 抓帧与 WebRTC 出流均已实测通过, 见 docs/08 |

3D 打印件与机壳: 不在本仓, 从 [官方 microduck](https://github.com/pollen-robotics/microduck) (MJCF/STL)
  或 [kissqy 发布包](https://github.com/kissqy/Microduck-kissqy) 取。

## 怎么开始

有两条路, 按你手上有什么选:

**A. 只想把鸭子装起来 (最常见)** — 用发行镜像, 全程不用编译:

1. 烧镜像到 SD 卡
2. 烧 IMU 板的固件 (`hardware/imu-firmware/Build-gcc/imu_to_dxl.hex`, 一行 openocd)
3. 设 15 颗舵机的 ID 与波特率 (装机前)
4. 装机接线 → 首次开机 → 五项验收 → 标定

完整步骤: [docs/04-quickstart.md](docs/04-quickstart.md)。

**B. 要改代码 / 自己出镜像** — 从 clone 开始编 overlay、运行时、内核模块、镜像:
[docs/05-bringup-runbook.md](docs/05-bringup-runbook.md)。

其余文档是设计与背景, 复刻遇到问题时再读。

## 三条上游

| 上游 | 它是什么 | 我们取哪部分 | 许可 |
| --- | --- | --- | --- |
| [pollen-robotics/microduck](https://github.com/pollen-robotics/microduck), [microduck_rl](https://github.com/pollen-robotics/microduck_rl) | 官方运行时 (Rust), 强化学习训练, MJCF + STL | 主控运行时基线: 官方 `daemon-v0.17.9` + 我们的补丁 (Feetech 后端, 总线 IMU, 标定台架); 3D 打印件 | 代码 Apache-2.0; 3D 网格 CC BY-NC-SA |
| [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy) | HD-1910 运行时 fork, 总线 IMU 板, 发布包 (步态模型等) | HAT 硬件基线 (已按本仓精简) + 发布包 (真步态 ONNX 模型, 安装脚本, 文档) | 见 `firmware/` 内 LICENSE; 文档/资产沿用上游条款 |
| [fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) | 板载网页中控 Studio, 自制 IMU v2 / wire_hub / POGO 板, 大量实测文档 | 硬件与工程实践主参考: IMU v2 板 (工程与固件均已在 35b435d 快照进本仓, 固件由我们改到 500 kbps), Studio (固定 commit), 镜像脚本思路, 踩坑记录 | 代码/Studio/镜像脚本 Apache-2.0; 文档与 3D CC BY-NC-SA |

固件分工: **主控运行时 = 官方 0.17.9 + 我们的补丁** (`patches/runtime-opi3w-feetech.patch`);
**IMU 板固件 = 本仓维护的 500 kbps 版** (基线是 replica `firmware-1.0.0`, 只改了波特率档位与台架自检命令;
源码与 hex 都在 [hardware/imu-firmware](hardware/imu-firmware/), 为什么不直接用上游 hex 见 [docs/07](docs/07-imu-firmware.md))。
kissqy 子模块作为 HAT 硬件基线与发布包来源。
详见 [docs/03-software-stack.md](docs/03-software-stack.md)。

## 目录

```
docs/
  00-upstreams.md       三个上游的关系, 许可边界, 我们各取什么 (先读这个)
  01-port-plan.md       移植要点: 换板要动哪五件事, 阶段状态, 风险
  02-hat-porting.md     HAT 移植方案与已执行的供电/引脚改动
  03-software-stack.md  软件层: 运行时 / Studio / 镜像 / 训练, 谁在哪, 怎么装
  04-quickstart.md      快速开始: 烧卡 -> 烧 IMU -> 舵机设置 -> 装机 -> 验收 -> 标定
  05-bringup-runbook.md 从源码构建 (开发者): clone -> 编译 -> 镜像 -> 烧卡 -> 验收 -> 标定
  06-audio-aic3104.md   音频: codec 接线, 驱动/overlay 要点, mixer, 自检与踩坑
  07-imu-firmware.md    IMU 板与固件: 为什么自己维护, 三端波特率档位, 供电与排障
  08-camera-tof.md      摄像头与 ToF: CSI 抓帧要 S_INPUT, csi-rail overlay, mediad/tofd 依赖与启用
  09-gamepad.md         蓝牙手柄: 编/装 padd, 配对顺序 (BR/EDR vs LE), 键位, 与 Studio 急停验收的口径差异
runtime/               运行时源码 submodule (Jimzjy/microduck-runtime, 分支 opi3w-feetech), clone 时加 --recurse-submodules
patches/
  runtime-opi3w-feetech.patch   运行时差分快照 (基线 daemon-v0.17.9 -> 3c74775; 最新代码看 runtime/ submodule)
  README.md                     基线与结果树哈希, apply 步骤, 内容清单
hardware/
  eda/                  EasyEDA Pro 工程: HAT REV B + IMU v2 (取自 replica, 已快照进本仓); HUB/POGO 板用 replica 仓的工程
  imu-firmware/         IMU 板固件源码 + GCC 构建 + 预置 hex (500 kbps 版)
  overlay/              A733 设备树 overlay (uart2-dxl.dts, audio-a733.dts, csi-rail.dts)
  hat-layout.md         HAT 网表, BOM, 每处改动的理由
  pinmap.md             40-pin 重映射 + A733 控制器实证
  imu-layout.md         IMU 板连接器, 电源, 数据通路, 固件
  cad/                  整机 3D 模型 (microduck-FT.3mf)
scripts/                构建与部署 (见 scripts/README.md)
firmware/               git submodule: kissqy/Microduck-kissqy @ eccc2fdb
```

## 项目状态

| 项 | 状态 |
| --- | --- |
| 运行时移植 (官方 0.17.9 + 补丁) | ✅ 554 测试通过; host 端 `--fake` 全链路冒烟 5/5 绿; 补丁已验证可精确重建该分支 |
| 飞特总线 IMU (ID 200) | ✅ 上板实测: `ping 200` 回 `ffffc8020035`, 陀螺数据实时变化 |
| IMU 板固件 (500 kbps, 本仓维护) | ✅ 上板实测 `1.0.0-500k`, 寄存器 6 回 `0x01`; GCC 工具链可重建同尺寸 hex |
| 标定链路 (busStatus / busCommand / `--commissioning`) | ✅ 完成; 台架冒烟 healthy; `startupSubscribe` 不做 (Studio 优雅降级) |
| aarch64 交叉编译 | ✅ `robotd` 9.6 MB / `robotctl` 7.7 MB, GLIBC 2.39 (底图 2.41 满足) |
| HAT 原理图 | ✅ REV B 已送厂 |
| 排针重映射 + overlay | ✅ 编译与应用验证通过 |
| aic3x codec 内核模块 | ✅ 上板原生编译 `snd-aic3x.ko`, vermagic 与 vendor 内核一致 |
| CSI 摄像头 (IMX219) | ✅ 端到端实测通过: 1920x1080 RG10 抓帧 (单帧 4,177,920 B) + `mediad` 以 720p 经 WebRTC 出流, 浏览器控制台 http://<板>:8080/ 可见实时画面; 自动曝光走私有 ioctl `VIDIOC_VIN_SENSOR_EXP_GAIN`, 开灯房间稳定在均值 ~80 / 23 fps。板级需 `csi-rail` overlay + `vin_v4l2` 自启 + GStreamer/webrtcsink ([docs/08](docs/08-camera-tof.md)) |
| ToF 测距 (VL53L5CX) | ✅ 上板实测通过: 15 Hz 持续测距, `/run/tofd/tof.sock` 出 8x8 距离阵; I2C 走 udev 别名 `/dev/i2c-pihat`, `tofd` 装好后**默认不 enable** (没插传感器时会重启循环) ([docs/08](docs/08-camera-tof.md)) |
| 音频 (喇叭 + 麦克风) | ✅ 出声与录音实测通过, mixer 由开机服务持久化 ([docs/06](docs/06-audio-aic3104.md)) |
| A733 系统镜像 | ✅ 组装流程闭环 (含 1GB bootloader 修复), **真机首启验收通过**: robotd 开机自启, health 正常回话 |
| 站立与行走 | ✅ 实测: `robot init` 后躯干倾角 2.4–3.6°, 策略接管后 `scripts/pad-walk.py` 前进实测 19 cm |
| 蓝牙手柄 (padd) | ✅ 上板实测通过: Xbox One S (BR/EDR, `EC:83:50:7C:B5:EC`) `Bonded/Trusted/Connected` 全 yes, `/dev/input/js0` 出现, `padd` 读键并把 Start/A/B/摇杆转给 `robotd`。按官方映射 Select 短按无动作、按住 2 s 才 `robot.rest`, 所以鸭子身上**没有一键急停** (用网页卸力) ([docs/09](docs/09-gamepad.md)) |

## 许可

- `firmware/` 是子模块, 条款以该仓内 `LICENSE` / `LICENSES/` 与文件头为准 (运行时源自 Pollen Robotics, Apache-2.0)。
- 按需拉取的 replica 内容不受本仓管辖: 其代码 Apache-2.0, 文档与 3D 资产 CC BY-NC-SA 4.0 (**非商业**, 需署名)。
  因此本仓文档只引用其结论与路径, 不整篇搬运。
- `patches/` 是官方 Apache-2.0 代码上的差分, 随官方条款。
- `hardware/imu-firmware/` 是 replica `firmware-1.0.0` (MIT) 的快照 + 我们的改动, 保留原 `LICENSE`;
  `hardware/eda/imu_to_dxl_1V0A/` 是同一上游 commit 的工程文件原样快照, 只为保证复刻可重现, 版权归原作者。
- 3D 打印件与机壳来自上游 MJCF/STL, 同样受 CC BY-NC-SA 约束, 不能商用。
- 本仓自有文档与脚本: 暂未声明许可, 默认保留全部权利; 如需开源再定。
