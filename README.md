# Microduck 复刻：Orange Pi Zero 3W（A733）

把 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 这只开源四足鸭，复刻到
**Orange Pi Zero 3W（全志 A733）** 上：沿用飞特 HD-1910 总线舵机与总线 IMU，
HAT 以 kissqy 的 HAT（板名 HAT-V5，立创工程名 HAT_REVA_SCH，同一块板）为基础做接口移植
（供电外置、UART/I2S/I2C 重映射），把它用不到的部分删掉。

本仓**只放改动和移植文档**，上游代码一律不复制：kissqy 发布仓走 git submodule（固定在
`eccc2fdb`），官方运行时用一份补丁打在 `daemon-v0.17.9` 上（[patches/](patches/README.md)），
Studio 与训练工程按需拉取，见 [docs/00-upstreams.md](docs/00-upstreams.md)。

**想直接动手**：看 [docs/05-bringup-runbook.md](docs/05-bringup-runbook.md)（clone → 编译 → 镜像 → 烧卡 → 验收 → 标定）。
其余文档是设计与背景。

## 三条上游，各取什么

| 上游 | 它是什么 | 我们取哪部分 | 许可 |
| --- | --- | --- | --- |
| [pollen-robotics/microduck](https://github.com/pollen-robotics/microduck)、[microduck_rl](https://github.com/pollen-robotics/microduck_rl) | 官方运行时（Rust）、强化学习训练、MJCF + STL | **主控运行时基线**：官方 `daemon-v0.17.9` + 我们的补丁（Feetech 后端、总线 IMU、标定台架）；3D 打印件 | 代码 Apache-2.0；3D 网格 CC BY-NC-SA |
| [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy) | HAT（板名 HAT-V5 / 工程 HAT_REVA_SCH）、HD-1910 运行时 fork、总线 IMU 板、发布包（步态模型等） | **HAT 硬件基线**（已按本仓精简）+ **发布包**（真步态 ONNX 模型、安装脚本、文档） | 见 `firmware/` 内 LICENSE；文档/资产沿用上游条款 |
| [fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) | 用官方 HAT 的复刻实践、板载网页中控 Studio、可烧录镜像构建脚本、自制 IMU v2 / wire_hub / POGO 板、大量实测文档 | **硬件与工程实践主参考**：自制 IMU v2 板（硬件+固件 `firmware-1.0.0` 都用它）、wire_hub/POGO 板、Studio（固定 commit）、镜像脚本思路、踩坑记录（引用，不整搬） | 代码/Studio/镜像脚本 Apache-2.0；文档与 3D CC BY-NC-SA |

固件分工：**主控运行时 = 官方 0.17.9 + 我们的补丁**（`patches/runtime-opi3w-feetech.patch`，
554 测试通过 + host 端 `--fake` 全链路冒烟，飞特总线上也读得到 IMU 板）；**IMU 板固件 = replica 的
`firmware-1.0.0`**（板就是 replica 的 v2，贴片与固件同源）。kissqy 子模块不用于固件，只作 HAT 硬件
基线与发布包来源。详见 [docs/03-software-stack.md](docs/03-software-stack.md)。

## 硬件

- **HAT**：`hardware/eda/HAT_REVA_SCH.eprj2`（EasyEDA Pro），当前 **REV B**，已送厂。
  相对 kissqy 原图删掉了：板载 5V 降压、旧理想二极管、板载 MEMS 麦（改双外接麦）、ToF 的 Qwiic 座、
  若干冗余阻容、双路保险丝；另加了反接保护 Q2 与防 USB 倒灌的理想二极管 Q3/Q4。
  逐处理由见 [hardware/hat-layout.md](hardware/hat-layout.md)。
- **供电**：外部 5V 由 U11 螺钉端子进入 → Q2（AO3401A）反接保护 → Q3/Q4 分立理想二极管（调试时 USB-C
  与外部 5V 可同时接，互不倒灌）→ `5V` 单一母线，D1（SMAJ5.0A TVS）钳位；HAT 不吃舵机电池。
  舵机电池走独立的 HUB 板（`BATT_IN` 与 `SERVO_VPASS` 都不进 HAT）。
- **IMU 板**：replica 自制 v2（`hardware/eda/imu_to_dxl_1V0A.eprj2`，总线 ID 200）。
  现在的三处总线座（IMU J1、HAT J13/J14、HUB 各口）**脚序已统一为 1=数据 / 2=V+ / 3=GND**，
  一根普通 3P 线直插即可（别用 Dynamixel 序的成品线）；细节与 1 脚朝向的检查见
  [hardware/imu-layout.md](hardware/imu-layout.md)。
- **主控**：Orange Pi Zero 3W 2GB。40-pin **物理布局**与 Radxa ZERO 3W 兼容；**I2C / I2S 位置级兼容，
  无需改 HAT 走线**；**UART 不同**——DXL 舵机串口从 Radxa 位置的排针 8/10（那边复用调试口）改到
  **11/13 的 uart2**（PB0/PB1，J4 焊盘 7/9→12/14 已在 REV B 改接），console 留在 8/10，
  依据 overlay 见 [hardware/overlay/uart2-dxl.dts](hardware/overlay/uart2-dxl.dts)。

细节：[hardware/pinmap.md](hardware/pinmap.md)（信号 → A733 引脚与控制器）、
[docs/02-hat-porting.md](docs/02-hat-porting.md)。

## 目录

```
docs/
  00-upstreams.md      三个上游的关系、许可边界、我们各取什么（先读这个）
  01-port-plan.md      移植要点：换板要动哪四件事、阶段状态、风险
  02-hat-porting.md    HAT 移植方案与已执行的供电/引脚改动
  03-software-stack.md 软件层：运行时 / Studio / 镜像 / 训练，谁在哪、怎么装
  04-reading-list.md   replica 必读清单（上机前 / 排障时 / 改设计时各看哪几篇）
  05-bringup-runbook.md 从零复刻：clone → 编译 → 镜像 → 烧卡 → 验收 → 标定
patches/
  runtime-opi3w-feetech.patch  我们运行时分支的完整差分（打在上游 daemon-v0.17.9 上）
  README.md                    基线与结果树哈希、apply 步骤、内容清单
hardware/
  eda/                 EasyEDA Pro 工程（HAT / IMU 板 / HUB / POGO）
  overlay/             A733 设备树 overlay（uart2-dxl.dts、audio-a733.dts）
  hat-layout.md        HAT 网表、BOM、每处改动的理由
  pinmap.md            40-pin 重映射 + A733 控制器实证
  imu-layout.md        IMU 板连接器、电源、数据通路、固件
scripts/               构建与部署（见 scripts/README.md）
firmware/              git submodule：kissqy/Microduck-kissqy @ eccc2fdb
```

## 进度

| 项 | 状态 |
| --- | --- |
| 运行时移植（官方 0.17.9 + 补丁） | ✅ **554 测试通过**；host 端 `--fake` 全链路冒烟 5/5 绿；补丁已验证可精确重建该分支 |
| 飞特总线 IMU（ID 200） | ✅ 代码+测试过：块在 56/15，前 12 字节复用 SflpDecoder，读在 15 颗舵机之后；`imu_ready()` 收敛后转真，策略才接管。上板待验 |
| 标定链路（busStatus / busCommand / `--commissioning`） | ✅ `robot.busStatus` 从快照拼装不碰串口、`robot.busCommand` 三动作（calibration-status / hold-home / verify-imu）、标定 TOML 双写入方（小助手写关节、robotd 只写 IMU mount）；`--fake` 台架冒烟 healthy。`robot.startupSubscribe` 不做（Studio 优雅降级） |
| aarch64 交叉编译 | ✅ `robotd` 9.6 MB / `robotctl` 7.7 MB，GLIBC 符号最高 2.39（trixie 2.41 满足） |
| HAT 原理图移植与精简 | ✅ REV B 已送厂 |
| 排针重映射 + overlay | ✅ `uart2-dxl.dts` 编译+fdtoverlay 应用验证；`audio-a733.dts` 对镜像真实 dtb 验证通过 |
| aic31xx codec 内核模块 | ✅ 交叉编译成功（vermagic 与 vendor 6.6.98 逐字一致），随镜像布防 |
| A733 系统镜像 | ✅ 成品 `microduck-opi3w-base.img` 已组装（Armbian trixie vendor 6.6.98 + dtbo + 脚本 + runtime payload）；镜像本身不入库，按 [docs/05](docs/05-bringup-runbook.md) 第 5 步自己产出。待真机验收 |
| 板侧依赖（ONNX Runtime、GStreamer） | ⏳ 待板子到手 |
| Studio 上板 | ✅ host 端实测可连 0.17.9（robot.state/init/pose/policies/health 通）；`busStatus`/`busCommand` 已补齐、`startupSubscribe` 按设计不做（见 docs/03 C.1），板上待验 |
| 装配 / 标定 / 试走 | ⏳ 需实物（PCB/物料/OPi 在途） |

## 许可

- `firmware/` 是子模块，条款以该仓内 `LICENSE` / `LICENSES/` 与文件头为准（运行时源自 Pollen Robotics，Apache-2.0）。
- 按需拉取的 replica 内容不受本仓管辖：其代码 Apache-2.0，文档与 3D 资产 CC BY-NC-SA 4.0（**非商业**，需署名）。
  因此本仓文档只**引用**其结论与路径，不整篇搬运。
- `patches/` 是官方 Apache-2.0 代码上的差分，随官方条款。
- 3D 打印件与机壳来自上游 MJCF/STL，同样受 CC BY-NC-SA 约束，不能商用。
- 本仓自有文档与脚本：暂未声明许可，默认保留全部权利；如需开源再定。
