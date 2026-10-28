# 上游来源、许可边界、我们取什么

本仓是「Microduck 复刻 + 主控换 A733」的移植仓，不是任何上游的 fork。所有上游代码都以
**固定 commit 的子模块**、**一份差分补丁**或**按需拉取**的方式引入，正文里只留结论与引用。

## 1. 三条上游

```
Pollen Robotics（官方）
├── microduck            板载运行时（Rust）：robotd / padd / mediad / configd / btd / robotctl
├── microduck_rl         强化学习训练 + MJCF 仿真模型 + 3D 打印件（STL）
└── elec_RPI_Robot_HAT   官方 HAT 板：KiCad 工程 + Gerber / BOM / 贴片坐标（Apache-2.0）

kissqy/Microduck-kissqy（HAT-V5 与 HD-1910 总线移植）
├── hardware/               HAT-V5 原理图/PCB ← 我们 HAT 的基线（EasyEDA Pro，已精简）
├── microduck-hd1910/       他自己的运行时 fork（飞特 HD-1910 总线）—— 我们不跑它，只用他的发布包
├── release-assets/         预编译包（Console / Training-Studio zip，约 100 MB）
└── docs/                   装配、IMU 固件、总线协议等

fanhao375/microduck-replica（官方 HAT 上的复刻实践）—— 本仓的「硬件与工程实践主参考」
├── hardware/新版/          自制 IMU v2（已采用）、wire_hub（舵机总线 HUB）、POGO 电池接口板
├── software/studio/        Microduck Studio：板内网页中控（Python 3.13，端口 8000）
├── software/image/         「烧好就能用」镜像的构建脚本（绑定 Radxa R1 / rk35xx）
├── software/training/      mjlab 训练工程（HD-1910）
└── docs/ + 根目录 *.md     按日期的实机调试记录、踩坑记录、硬件逆向、采购清单
                            必读清单见 docs/04-reading-list.md（只引用，不搬运）
```

**运行时以上游官方 0.17.9
为基线（我们打补丁），硬件与排障经验跟 replica，发布包（步态模型）跟 kissqy**。

## 2. 各取什么，为什么

| 我们需要的东西 | 取自 | 理由 |
| --- | --- | --- |
| HAT 硬件基线 | kissqy | 只有 kissqy 公开了 HAT-V5 的 EasyEDA 工程；我们已在它上面做完供电/引脚移植与精简 |
| 主控运行时 | 官方 `daemon-v0.17.9` + 我们的补丁 | 官方版本是唯一仍在维护、有接口版本号与发布节奏的基线；Feetech 后端、总线 IMU、标定台架由我们补（[patches/](../patches/README.md)） |
| 网页中控 Studio | replica | 独立于主控，纯 Python + 本地依赖；它按 fork 的接口版本写，与 0.17.9 的差异已摸清（见 docs/03 §C） |
| IMU 板 | replica `hardware/新版/imu_to_dxl_1V0A` | 我们 HAT 上已无 IMU 芯片；这块板挂总线 ID 200，电气与协议已核对通过（见 [hardware/imu-layout.md](../hardware/imu-layout.md)） |
| IMU 板固件 | replica `firmware-1.0.0` | 板与固件同源，不用改一行源码 |
| 镜像构建思路 | replica（参考，不直接用） | 它的 `build-image.sh` 以 **Radxa R1 镜像**为底座、换成 rk35xx U-Boot 与 B1 DTB，对 A733 完全不适用；只借它的目录结构、清理步骤与首次开机脚本的写法 |
| 训练 / 模型 | kissqy release-assets | 训练工程（mjlab）与走路模型随仓发布，能直接用；replica 的训练工程是同一套的改版，没有必须切换的理由 |
| 硬件防护与连接器经验 | replica（引用结论） | 它的 v2 板已经踩过 TVS / PTC / 连接器序的坑，我们照结论做，不重复实验 |
| 排障与工程记录 | replica `docs/`、`踩坑记录.md`、`调试记录.md` | 上机前读一遍能省掉大量试错；清单见 `docs/04-reading-list.md` |
| 3D 打印件 | replica | 我们不改结构 |

### 明确不取的

- replica 的**预构建镜像**与 `software/image` 的产物：Radxa 专用，且模型是作者个人非商业许可，不适合作为我们的分发基础。
- replica 的**运行时**（含它镜像里那个 0.15.1 的 robotd）：源码未公开（`local_only`），且内核版本落后于 0.17.9。
- replica 的 `docs/*.md`：**CC BY-NC-SA 4.0，非商业 + 相同方式共享**。整篇搬进本仓会让本仓文档也被传染上 NC-SA，所以只做「一句话结论 + 链接」的引用，不复制正文。

## 3. 许可一览（照原文）

| 内容 | 许可 | 对我们的约束 |
| --- | --- | --- |
| Pollen `microduck`、`microduck_rl` 代码、`elec_RPI_Robot_HAT` | Apache-2.0 | 保留版权与 NOTICE，改动文件需说明 |
| 上游 3D 网格 / MJCF 几何（`microduck_rl`） | CC BY-NC-SA 4.0 | 非商业、署名、相同方式共享 |
| kissqy 仓内代码与 `LICENSE` / `LICENSES/` | Apache-2.0 | 同上 |
| kissqy 的 `release-assets/` 二进制与模型 | 随上游条款（模型为社区训练产物） | 不自称原创，不商用转售 |
| replica 代码 / Studio / 镜像脚本 | Apache-2.0 | 保留版权声明 |
| replica 的 `*.md`、`docs/`、3D 网格、`assets/` | CC BY-NC-SA 4.0 | 只引用，不搬运 |
| replica 镜像内的走路/动作模型 | 作者个人非商业许可 | 不随任何收费产品分发 |
| 本仓 `patches/` | 派生自 Apache-2.0 代码 | 随官方条款，保留版权声明 |
| 本仓自有文档与脚本 | 未声明（保留全部权利） | 需要时再定 |

## 4. 固定下来的上游版本

| 上游 | 引用方式 | 版本 |
| --- | --- | --- |
| kissqy/Microduck-kissqy | git submodule `firmware/` | `eccc2fdbbf4c835e12abfa7ae6c93b1b1462fc51`（main） |
| pollen-robotics/microduck | 差分补丁 `patches/runtime-opi3w-feetech.patch` | 基线 tag `daemon-v0.17.9` = `96b89d8613f06722c1d64ce75ab0d7124fed9d8f`；打完后树 = `0e6e6b4725e9b63e37390b15bf6317e0dcf72333` |
| fanhao375/microduck-replica | 按需稀疏拉取（`scripts/fetch-studio.ps1`） | `35b435d7a6361c3480c2d0916ecf79c318710690` |

**升级规则**：先在本仓文档里改这里的 commit/哈希，再更新子模块或重新生成补丁；不要在未记录版本的
情况下改。子模块里 100 MB 的 `release-assets/` 预编译包可以用 sparse-checkout 剔掉（只影响本地
工作区，不影响 GitHub 体积）：

```bash
git -C firmware sparse-checkout init --cone
git -C firmware sparse-checkout set --no-cone '/microduck-hd1910/**' '/!release-assets/**'
```

## 5. 常见疑问

**问：为什么已经把它当成主参考了，还是不直接 fork replica？**
答：**参考**和 **fork** 是两件事。它的价值在记录与结论，按 commit 链接读就行；但它的镜像层、CAD、
Studio 全是 Radxa + 官方 HAT 的假设，fork 等于把这些假设连同 240 MB 资产和 NC-SA 文档一起绑进我们仓。
我们要的是「拿它的结论，走 A733 + 自画 HAT 的路」，所以只引用、按需拉取。

**问：为什么不直接跑 kissqy 的 HD-1910 运行时？**
答：他那个 fork 与官方主线分叉已久，版本号（R17/V167）是他自己的编号，和官方接口版本对不上；它
还绑着他的发布与更新流程。而 Feetech 后端本身只有几百行，在官方 `daemon-v0.17.9` 上补回去、跟住
上游的接口演进，比在一个老分叉上追上游便宜——这就是我们现在的做法。
