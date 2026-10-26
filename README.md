# Microduck 复刻：Orange Pi Zero 3W（A733）

把 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 这只开源四足鸭，复刻到
**Orange Pi Zero 3W（全志 A733）** 上：沿用飞特 HD-1910 总线舵机与总线 IMU，
HAT 以 kissqy 的 HAT-V5 为基础做接口移植（供电外置、UART/I2S/I2C 重映射），把它用不到的部分删掉。

本仓**只放改动和移植文档**，上游代码一律不复制：固件走 git submodule 固定在某个 commit，
软件层（Studio / 镜像脚本 / 训练工程）按需拉取，见 [docs/00-upstreams.md](docs/00-upstreams.md)。

## 三条上游，各取什么

| 上游 | 它是什么 | 我们取哪部分 | 许可 |
| --- | --- | --- | --- |
| [pollen-robotics/microduck](https://github.com/pollen-robotics/microduck)、[microduck_rl](https://github.com/pollen-robotics/microduck_rl) | 官方运行时（Rust）、强化学习训练、MJCF + STL | 运行时（经 kissqy fork 间接引入）、3D 打印件 | 代码 Apache-2.0；3D 网格 CC BY-NC-SA |
| [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy) | HAT-V5 原理图、HD-1910 运行时 fork、总线 IMU 板、发布包 | **HAT 硬件基线**（已按本仓精简）+ **固件子模块** | 见 `firmware/` 内 LICENSE；文档/资产沿用上游条款 |
| [fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) | 用官方 HAT 的复刻实践、板载网页中控 Studio、可烧录镜像构建脚本、自制 IMU v2 / wire_hub / POGO 板、大量实测文档 | **硬件与工程实践主参考**：自制 IMU v2 板、Studio、镜像脚本思路、踩坑与调试记录（引用，不整搬） | 代码/Studio/镜像脚本 Apache-2.0；文档与 3D CC BY-NC-SA |

为什么固件仍然用 kissqy 而不是 replica：replica 的运行时是 kissqy 的 fork，额外补丁主要服务于**它自制的 I²C IMU 板**
和 UDP 手柄；我们用的是 kissqy 的**总线 IMU（DXL ID 200）**，那套补丁对我们没有收益。详见
[docs/03-software-stack.md](docs/03-software-stack.md)。

## 硬件

- **HAT**：`hardware/eda/HAT_REVA_SCH.eprj2`（EasyEDA Pro）。当前 **REV B**，63 个器件（含图纸框，实贴 62）、192 条导线、35 个网络；
  DRC **0 error / 3 warning**（「建议器件标准化」+「建议给悬空脚加 NC 标记」，不影响打样）。
  相对 kissqy 原图净省 24 颗贴片：拆掉板载 5V 降压与理想二极管、外接麦替代板载 MEMS、去掉 ToF Qwiic 座、删冗余阻容与已死的与门、删双路保险丝。
- **供电**：外部 5V 由 U11 螺钉端子进入 → Q2（AO3401A）反接保护 → `5V` 单一母线，D1（SMAJ5.0A TVS）钳位；
  HAT 不再吃舵机电池。舵机电池走独立的 HUB 板（`BATT_IN` 与 `SERVO_VPASS` 都不进 HAT）。
- **IMU 板**：replica 自制 v2（`hardware/eda/imu_to_dxl_1V0A.eprj2`，挂 DXL 总线 ID 200）。
  电路不改；要注意的是 **J1 是镜像序（1=数据/2=+5V/3=GND）**、J2 才是标准序，接线与固件改动见
  [hardware/imu-layout.md](hardware/imu-layout.md)。
- **主控**：Orange Pi Zero 3W 2GB；40-pin 与 Radxa ZERO 3W **位置级兼容**，四类信号（I2C / I2S / UART / SPI）无需改 HAT 走线。

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
| 固件 aarch64 交叉编译 | ✅ 已在本机 WSL 编出 `robotd/robotctl/padd/btd/mediad/configd/sounds`（glibc 2.30 依赖，≥2.31 系统可直接跑） |
| HAT 原理图移植与精简 | ✅ 网表/DRC 收敛（见上） |
| 排针重映射 + overlay | ✅ 引脚与控制器已实证；`uart2-dxl.dts` 已写好 |
| A733 系统镜像 | ⏳ 待选官方镜像/自建，验收：串口、SSH、40-pin UART/I2S、codec 驱动 |
| 板侧依赖（ONNX Runtime、GStreamer） | ⏳ 待板子到手 |
| Studio 上板 | ⏳ 脚本已备（`scripts/fetch-studio.ps1`），等系统 |
| 装配 / 标定 / 试走 | ⏳ 需实物 |

## 许可

- `firmware/` 是子模块，条款以该仓内 `LICENSE` / `LICENSES/` 与文件头为准（运行时源自 Pollen Robotics，Apache-2.0）。
- 按需拉取的 replica 内容不受本仓管辖：其代码 Apache-2.0，文档与 3D 资产 CC BY-NC-SA 4.0（**非商业**，需署名）。
  因此本仓文档只**引用**其结论与路径，不整篇搬运。
- 3D 打印件与机壳来自上游 MJCF/STL，同样受 CC BY-NC-SA 约束，不能商用。
- 本仓自有文档与脚本：暂未声明许可，默认保留全部权利；如需开源再定。
