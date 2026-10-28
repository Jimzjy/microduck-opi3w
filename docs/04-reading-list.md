# replica 必读清单（工程实践主参考）

`fanhao375/microduck-replica` 是本仓的**硬件与工程实践主参考**：它留下的实机记录、防护设计与采购经验，
能直接省掉我们大量试错。（它的运行时源码没有公开，我们也不跑它的二进制——
运行时以自己的官方 0.17.9 基线 + [patches/](../patches/README.md) 为准。）

**只读不搬**：这些文档是 **CC BY-NC-SA 4.0**（非商业 + 相同方式共享）。整篇复制进本仓会让本仓文档
也被传染，所以这里只放「标题 + 一句话摘要 + 固定 commit 链接」。要细节就点链接，别复制正文。

固定版本：`35b435d7a6361c3480c2d0916ecf79c318710690`
链接前缀：`https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/`

## 0. 本仓自带的厂商文档

上游文档看链接即可，但**厂商原始资料**建议离线放着，断网也能核对：

| 位置 | 内容 |
| --- | --- |
| [hardware/datasheets/](../hardware/datasheets/README.md) | 飞特 HD-1910-C001 规格书（A/0）、Orange Pi Zero 3W 用户手册 v1.0、V1.2 原理图 / 位号图 / TOP+BOT DXF；带 SHA256 与「用来核对什么」 |

## 1. 上机前必读（电源、总线、IMU 的坑都在这几篇里）

| 文档 | 一句话摘要 | 为什么我们要读 |
| --- | --- | --- |
| [踩坑记录.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/踩坑记录.md) | 83.7 KB，按现象归类的问题与解法 | 装配/首启阶段八成的怪现象这里已经有答案 |
| [调试记录.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/调试记录.md) | 44.5 KB，按时间顺序的实测过程 | 看排查顺序比看结论更有用 |
| [HD1910-20261013-夜-掉电-舵机D与蹭地.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261013-夜-掉电-舵机D与蹭地.md) | 33.8 KB：舵机掉电、D 腿蹭地的定位过程 | 直接对应我们的 HUB 板供电与走线设计 |
| [HD1910-20261014-白天-仿真找原因与新版放开参数.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261014-白天-仿真找原因与新版放开参数.md) | 33.7 KB：仿真复现 + 放开参数后的结果 | 走路不稳先看这篇，别急着改硬件 |
| [HD1910-20261015-IMU乱跳根因与陀螺融合上机.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261015-IMU乱跳根因与陀螺融合上机.md) | 20.8 KB：总线 IMU 数据乱跳的根因与融合方案 | 我们用同一颗 IMU 板，这篇等于免费排障 |
| [HD1910-20261012-夜-IMU校准与首次迈步.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261012-夜-IMU校准与首次迈步.md) | 19.3 KB：校准流程与第一次迈步 | 首次上电照它的顺序走 |
| [HD1910-20261012-kissqy整套上机.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261012-kissqy整套上机.md) | 20.7 KB：整套 kissqy 方案跑通的过程 | 我们走的就是这条路线 |

## 2. 硬件与电控

| 文档 | 一句话摘要 | 为什么我们要读 |
| --- | --- | --- |
| [硬件方案逆向.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/硬件方案逆向.md) | 46.5 KB：整机电控逐块拆解与推断 | 弄清每块板为什么这样设计，再决定我们改什么 |
| [hardware-teardown.en.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/hardware-teardown.en.md) | 30.6 KB：英文版拆解笔记 | 引用公式与参数时看这版 |
| [硬件入门.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/硬件入门.md) | 19.5 KB：从零理解这套电控 | 装配/接线时的对照 |
| [硬件规格速查.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/硬件规格速查.md) | 18.5 KB：电压、电流、扭矩、接口速查 | 选电源、算余量时用 |
| [电控采购清单.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/电控采购清单.md) | 30.5 KB：逐项料号与替代 | 我们补 HUB 板物料时直接对照 |
| [执行器选型.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/执行器选型.md) | 26.3 KB：HD-1910 与其他舵机的取舍 | 换型号前先看代价 |
| [不打HAT.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/不打HAT.md) | 不装 HAT、直接飞线的方案 | 板子还没到时先用它点亮验证 |

## 3. 软件与版本

| 文档 | 一句话摘要 | 为什么我们要读 |
| --- | --- | --- |
| [软件来源与我们的改动.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/软件来源与我们的改动.md) | 它自述运行时来自哪、改了哪些补丁 | 判断「要不要跟它的补丁」的唯一依据 |
| [官方更新跟踪.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/官方更新跟踪.md) | 16.7 KB：官方 0.15.x 到后续版本的变更 | 我们跟的是官方主线（0.17.9 + 补丁），升级前看它有没有踩过这条线的坑 |
| [HD1910-20261023-总线IMU自动识别.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261023-总线IMU自动识别.md) | 总线 IMU 自动识别补丁的来历 | 万一我们要摘这个补丁 |
| [HD1910-20261013-官方更新与UDP手柄.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD1910-20261013-官方更新与UDP手柄.md) | 官方版本升级与 UDP 手柄补丁 | 手柄方案对照 |
| [PROGRESS.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/PROGRESS.md) | 18.1 KB：项目进度与阶段结论 | 看它做到哪一步，避免重复劳动 |
| [HD-1910训练前数据清单.md](https://github.com/fanhao375/microduck-replica/blob/35b435d7a6361c3480c2d0916ecf79c318710690/docs/HD-1910训练前数据清单.md) | 14.7 KB：训练前要采的数据 | 走到训练阶段前核对 |

## 4. 怎么用这份清单

- **装配前**：先扫第 1 节七篇的标题与结论段，把已知的坑标在装配单上。
- **排障时**：先搜 `踩坑记录.md` 与 `调试记录.md`，再动手改硬件。
- **改设计时**：第 2 节四篇是依据；我们的 HAT 改动理由写在
  [hardware/hat-layout.md](../hardware/hat-layout.md)，结论冲突时以本仓实测为准（板不同）。
