# Microduck 复刻：Orange Pi Zero 3W（A733）

把 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 这只开源四足鸭，复刻到
**Orange Pi Zero 3W（全志 A733）** 上：沿用飞特 HD-1910 总线舵机与总线 IMU，
HAT 以 kissqy 的 HAT（板名 HAT-V5，立创工程名 HAT_REVA_SCH，同一块板）为基础做接口移植
（供电外置、UART/I2S/I2C 重映射），把它用不到的部分删掉。

本仓**只放改动和移植文档**，上游代码一律不复制：固件走 git submodule 固定在某个 commit，
软件层（Studio / 镜像脚本 / 训练工程）按需拉取，见 [docs/00-upstreams.md](docs/00-upstreams.md)。

## 三条上游，各取什么

| 上游 | 它是什么 | 我们取哪部分 | 许可 |
| --- | --- | --- | --- |
| [pollen-robotics/microduck](https://github.com/pollen-robotics/microduck)、[microduck_rl](https://github.com/pollen-robotics/microduck_rl) | 官方运行时（Rust）、强化学习训练、MJCF + STL | **主控运行时基线**：官方 0.17.9 + 我们移植的 Feetech 后端（`opi3w-feetech` 分支）；3D 打印件 | 代码 Apache-2.0；3D 网格 CC BY-NC-SA |
| [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy) | HAT（板名 HAT-V5 / 工程 HAT_REVA_SCH）、HD-1910 运行时 fork、总线 IMU 板、发布包（步态模型等） | **HAT 硬件基线**（已按本仓精简）+ **发布包**（真步态 ONNX 模型、文档）；固件子模块仅作参考 | 见 `firmware/` 内 LICENSE；文档/资产沿用上游条款 |
| [fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) | 用官方 HAT 的复刻实践、板载网页中控 Studio、可烧录镜像构建脚本、自制 IMU v2 / wire_hub / POGO 板、大量实测文档 | **硬件与工程实践主参考**：自制 IMU v2 板（硬件+固件 firmware-1.0.0 都用它）、wire_hub/POGO 板、Studio、镜像脚本思路、踩坑记录（引用，不整搬） | 代码/Studio/镜像脚本 Apache-2.0；文档与 3D CC BY-NC-SA |

固件分工（2026-10-27 定稿）：**主控运行时 = 官方 0.17.9 + 我们移植的 Feetech 后端**
（源码 `microduck-runtime` 仓 `opi3w-feetech` 分支，466 测试过 + host 全链路冒烟通过，飞特总线上也读得到 IMU 板）；
**IMU 板固件 = replica 的 `firmware-1.0.0.hex`**（板就是 replica 的 v2，Feetech 协议、真机共线实测过）。
kissqy 子模块不再用于固件，只保留作 HAT 硬件基线和发布包来源。详见 [docs/03-software-stack.md](docs/03-software-stack.md)。

## 硬件

- **HAT**：`hardware/eda/HAT_REVA_SCH.eprj2`（EasyEDA Pro）。当前 **REV B**，67 个器件（含图纸框，实贴 66）、202 条导线、38 个网络；
  DRC **0 error / 3 warning**（「建议器件标准化」+「建议给悬空脚加 NC 标记」，不影响打样）。
  相对 kissqy 原图净省 20 颗贴片：拆掉板载 5V 降压与旧理想二极管、外接麦替代板载 MEMS、去掉 ToF Qwiic 座、
  删冗余阻容与已死的与门、删双路保险丝；另加了反接保护 Q2 与防 USB 倒灌的理想二极管 Q3/Q4。
- **供电**：外部 5V 由 U11 螺钉端子进入 → Q2（AO3401A）反接保护 → Q3/Q4 分立理想二极管（调试时 USB-C
  与外部 5V 可同时接，互不倒灌）→ `5V` 单一母线，D1（SMAJ5.0A TVS）钳位；
  HAT 不再吃舵机电池。舵机电池走独立的 HUB 板（`BATT_IN` 与 `SERVO_VPASS` 都不进 HAT）。
- **IMU 板**：replica 自制 v2（`hardware/eda/imu_to_dxl_1V0A.eprj2`，挂 DXL 总线 ID 200）。
  电路不改；要注意的是 **J1 是镜像序（1=数据/2=+5V/3=GND）**、J2 才是标准序，接线与固件改动见
  [hardware/imu-layout.md](hardware/imu-layout.md)。
- **主控**：Orange Pi Zero 3W 2GB。40-pin **物理布局**与 Radxa ZERO 3W 兼容；**I2C / I2S 位置级兼容，
  无需改 HAT 走线**；**UART 不同**——DXL 舵机串口从 Radxa 位置的排针 8/10（那边复用调试口）改到
  **11/13 的 uart2**（PB0/PB1，J4 焊盘 7/9→12/14 已在 REV B 改接），console 留在 8/10，
  依据 overlay 见 [hardware/overlay/uart2-dxl.dts](hardware/overlay/uart2-dxl.dts)。

细节：[hardware/hat-layout.md](hardware/hat-layout.md)（网表、BOM、每处改动的理由）、
[hardware/pinmap.md](hardware/pinmap.md)（信号 → A733 引脚与控制器）、
[hardware/imu-layout.md](hardware/imu-layout.md)、[docs/02-hat-porting.md](docs/02-hat-porting.md)。

## 目录

```
docs/
  00-upstreams.md      三个上游的关系、许可边界、我们各取什么（先读这个）
  01-port-plan.md      移植总计划与阶段状态
  02-hat-porting.md    HAT 移植方案与已执行的供电/引脚改动
  03-software-stack.md 软件层：固件 / Studio / 镜像 / 训练，谁在哪、怎么装
  04-reading-list.md   replica 必读清单（上机前 / 排障时 / 改设计时各看哪几篇）
hardware/
  eda/                 EasyEDA Pro 工程（HAT 原理图 + IMU 板）
  overlay/             A733 设备树 overlay（uart2-dxl.dts）
  hat-layout.md        HAT 网表、BOM、改动记录、DRC 状态
  pinmap.md            40-pin 重映射 + A733 控制器实证
  imu-layout.md        IMU 板连接
scripts/
  fetch-studio.ps1     按固定 commit 稀疏拉取 replica 的 Studio（可选推到板子）
  eda-exec.ps1         立创EDA Pro 桥（执行 JS）
  eda-db-*.py          .eprj2 内的库缓存工具
firmware/              git submodule：kissqy/Microduck-kissqy（固定 commit）
```

## 进度

| 项 | 状态 |
| --- | --- |
| 运行时移植（官方 0.17.9 + Feetech） | ✅ `opi3w-feetech` 分支，**554 测试通过**；host 端 `--fake` 全链路冒烟 5/5 绿 |
| 飞特总线 IMU（ID 200） | ✅ 代码+测试过（`54e26b8`）：块在 56/15，前 12 字节复用 SflpDecoder，读在 15 颗舵机之后；`imu_ready()` 收敛后转真，策略才接管。上板待验 |
| 标定链路（busStatus / busCommand / `--commissioning`） | ✅ `2b1e43c`：`robot.busStatus` 从快照拼装不碰串口、`robot.busCommand` 三动作（calibration-status / hold-home / verify-imu）、标定 TOML 双向写入（小助手写关节、robotd 只写 IMU mount）；`--fake` 台架冒烟 healthy。`robot.startupSubscribe` 不做（Studio 优雅降级） |
| aarch64 交叉编译 | ✅ `robotd`（9.3MB）/ `robotctl`（7.7MB）release 产物，GLIBC 符号最高 2.39（trixie 2.41 满足） |
| HAT 原理图移植与精简 | ✅ 网表/DRC 收敛，REV B 已送厂（见上） |
| 排针重映射 + overlay | ✅ `uart2-dxl.dts` 编译+fdtoverlay 应用验证；`audio-a733.dts` 对镜像真实 dtb 验证通过 |
| aic31xx codec 内核模块 | ✅ 交叉编译成功（vermagic 匹配 vendor 6.6.98），随镜像布防 |
| A733 系统镜像 | ✅ 成品 `img/microduck-opi3w-base.img`（Armbian trixie vendor 6.6.98 + dtbo + 脚本 + runtime payload，离线抽查通过；待真机验收） |
| 板侧依赖（ONNX Runtime、GStreamer） | ⏳ 待板子到手 |
| Studio 上板 | ✅ host 端实测可连 0.17.9（robot.state/init/pose/policies/health 通）；三个 v40 接口缺口里 `busStatus`/`busCommand` 已补齐、`startupSubscribe` 按设计不做（见 docs/03 C.1），板上待验 |
| 装配 / 标定 / 试走 | ⏳ 需实物（PCB/物料/OPi 在途） |

## 许可

- `firmware/` 是子模块，条款以该仓内 `LICENSE` / `LICENSES/` 与文件头为准（运行时源自 Pollen Robotics，Apache-2.0）。
- 按需拉取的 replica 内容不受本仓管辖：其代码 Apache-2.0，文档与 3D 资产 CC BY-NC-SA 4.0（**非商业**，需署名）。
  因此本仓文档只**引用**其结论与路径，不整篇搬运。
- 3D 打印件与机壳来自上游 MJCF/STL，同样受 CC BY-NC-SA 约束，不能商用。
- 本仓自有文档与脚本：暂未声明许可，默认保留全部权利；如需开源再定。
