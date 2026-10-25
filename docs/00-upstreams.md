# 上游来源、许可边界、我们取什么

本仓是「Microduck 复刻 + 主控换 A733」的移植仓，不是任何上游的 fork。所有上游代码都以
**固定 commit 的子模块**或**按需拉取**的方式引入，正文里只留结论与引用。

## 1. 三条上游

```
Pollen Robotics（官方）
├── microduck            板载运行时（Rust）：robotd / padd / mediad / configd / btd / robotctl
├── microduck_rl         强化学习训练 + MJCF 仿真模型 + 3D 打印件（STL）
└── elec_RPI_Robot_HAT   官方 HAT 板：KiCad 工程 + Gerber / BOM / 贴片坐标（Apache-2.0）

kissqy/Microduck-kissqy（HAT-V5 与 HD-1910 总线移植）
├── HAT-V5 原理图/PCB        ← 我们 HAT 的基线（EasyEDA Pro，已精简）
├── microduck-hd1910/       运行时 fork：飞特 HD-1910 总线、总线 IMU、R17/V167 发布流程
├── release-assets/         预编译包（Console / Training-Studio zip，约 100 MB）
└── docs/                   装配、IMU 固件、总线协议等

fanhao375/microduck-replica（官方 HAT 上的复刻实践）
├── software/studio/        Microduck Studio：板内网页中控（Python 3.13，端口 8000）
├── software/image/         「烧好就能用」镜像的构建脚本（绑定 Radxa R1 / rk35xx）
├── software/training/      mjlab 训练工程（HD-1910）
├── hardware/新版/          自制 IMU v2、wire_hub（舵机总线 HUB）、POGO 电池接口板
└── docs/                   踩坑记录、调试记录、软件来源说明（大量实测）
```

## 2. 各取什么，为什么

| 我们需要的东西 | 取自 | 理由 |
| --- | --- | --- |
| HAT 硬件基线 | kissqy | 只有 kissqy 公开了 HAT-V5 的 EasyEDA 工程；我们已在它上面做完供电/引脚移植与精简 |
| 板载运行时 | kissqy（子模块） | 它就是我们这套硬件（HD-1910 总线 + 总线 IMU）对应的工作版本，且已有 R17/V167 的编译与发布流程 |
| 网页中控 Studio | replica | 独立于主控，纯 Python + 本地依赖，直接可用；Apache-2.0，可放心调用 |
| 镜像构建思路 | replica（参考，不直接用） | 它的 `build-image.sh` 以 **Radxa R1 镜像**为底座、换成 rk35xx U-Boot 与 B1 DTB，对 A733 完全不适用；只借它的目录结构、清理步骤与首次开机脚本的写法 |
| 训练 / 模型 | kissqy release-assets | 训练工程（mjlab）与走路模型随仓发布，能直接用；replica 的训练工程是同一套的改版，没有必须切换的理由 |
| 3D 打印件 | 上游 microduck_rl / kissqy | 我们不改结构 |

### 明确不取的

- replica 的**预构建镜像**与 `software/image` 的产物：Radxa 专用，且模型是作者个人非商业许可，不适合作为我们的分发基础。
- replica 的**自制 IMU v2 硬件**：它改用 I²C IMU + 自动识别补丁；我们沿用 kissqy 的总线 IMU（DXL ID 200），换过去要动固件和线束，没有收益。
- replica 的 **wire_hub 板**：功能与我们要做的独立 HUB 板重合，但它是按官方 HAT 的座子排布，A733 侧要重画，等 HUB 板方案定了再决定是否借鉴。
- replica 的 `docs/*.md`：**CC BY-NC-SA 4.0，非商业 + 相同方式共享**。整篇搬进本仓会让本仓文档也被传染上 NC-SA，所以只做「一句话结论 + 链接」的引用，不复制正文。

## 3. 许可一览（照原文）

| 内容 | 许可 | 对我们的约束 |
| --- | --- | --- |
| Pollen `microduck`、`microduck_rl` 代码、`elec_RPI_Robot_HAT` | Apache-2.0 | 保留版权与 NOTICE，改动文件需说明 |
| 上游 3D 网格 / MJCF 几何（`microduck_rl`） | CC BY-NC-SA 4.0 | 非商业、署名、相同方式共享 |
| kissqy 仓内 `microduck-hd1910/` 代码 | Apache-2.0（仓内 `LICENSE`、`LICENSES/`） | 同上 |
| kissqy 的 `release-assets/` 二进制与模型 | 随上游条款（模型为社区训练产物） | 不自称原创，不商用转售 |
| replica 代码 / Studio / 镜像脚本 | Apache-2.0 | 保留版权声明 |
| replica 的 `*.md`、`docs/`、3D 网格、`assets/` | CC BY-NC-SA 4.0 | 只引用，不搬运 |
| replica 镜像内的走路/动作模型 | 作者个人非商业许可 | 不随任何收费产品分发 |
| 本仓自有文档与脚本 | 未声明（保留全部权利） | 需要时再定 |

## 4. 固定下来的上游版本

| 上游 | 引用方式 | 版本 |
| --- | --- | --- |
| kissqy/Microduck-kissqy | git submodule `firmware/` | `eccc2fdbbf4c835e12abfa7ae6c93b1b1462fc51`（main） |
| fanhao375/microduck-replica | 按需稀疏拉取（`scripts/fetch-studio.ps1`） | `35b435d7a6361c3480c2d0916ecf79c318710690` |

**升级规则**：先在本仓文档里改这里的 commit，再更新子模块/重新拉取；不要在未记录版本的情况下改。
子模块里 100 MB 的 `release-assets/` 预编译包可以用 sparse-checkout 剔掉（只影响本地工作区，不影响 GitHub 体积）：

```bash
git -C firmware sparse-checkout init --cone
git -C firmware sparse-checkout set --no-cone '/microduck-hd1910/**' '/!release-assets/**'
```

## 5. 常见疑问

**问：为什么不直接 fork replica，在它上面改 A733？**
答：replica 的镜像层、文档、CAD 全是 Radxa + 官方 HAT 假设，改造成本高于收益；而它可复用的只有 Studio，
按需拉取一个目录就够，不必背上 240 MB 与 NC-SA 文档。

**问：kissqy 的固件会不会被 replica 的新版补丁拉开差距？**
答：replica 的补丁集中在 I²C IMU 自动识别、UDP 手柄、总线错误恢复。前两项我们不用；第三项如果实测遇到
总线断连需要恢复，再单独从 fanhao 的 fork 摘那一个补丁（Apache-2.0 允许），不必整体切换。
