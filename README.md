# Microduck 复刻: Orange Pi Zero 3W (A733)

把 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 这只开源四足鸭复刻到
**Orange Pi Zero 3W (全志 A733)** 上: 沿用飞特 HD-1910 总线舵机与总线 IMU。
本仓只放改动与移植文档, 上游代码不复制。

## 你需要准备什么

| # | 物料 | 说明 |
| --- | --- | --- |
| 1 | Orange Pi Zero 3W 主控板 | 本项目按 1GB 版实测 (需换官方 bootloader, 见 docs/05 第 5 步); 2GB 及以上不受影响 |
| 2 | HAT 扩展板 | 工程 `hardware/eda/HAT_REVA_SCH_OPI3W.eprj2` (EasyEDA Pro), BOM 见 [hardware/hat-layout.md](hardware/hat-layout.md) |
| 3 | IMU 板 | 用 [microduck-replica](https://github.com/fanhao375/microduck-replica) 的 `hardware/新版/imu_to_dxl_1V0A` 工程打板, 烧其 `firmware-1.0.0`, 见 [hardware/imu-layout.md](hardware/imu-layout.md) §5 |
| 4 | 5V DC-DC 模块 | 3A 同步整流 (mini560 类, 不要用 2A 的 LM2596), 同时给 HAT 和 IMU 板供电 |
| 5 | 15x HD-1910 舵机 | 飞特 STS 总线; ID 分配与标定见 docs/05 第 8 步 |
| 6 | microSD 卡 | 卡 >= 16GB; 调试另备 mini HDMI 线或 USB-TTL 串口线 |

喇叭, 麦克风等其余外设的型号与采购见 kissqy 发布包: [DUCK-SHOPPING-LIST](https://github.com/kissqy/Microduck-kissqy) (子模块 `firmware/` 内同款文件)。

后续扩展 (现阶段不必备, 我们也尚未实测):

| 物料 | 说明 |
| --- | --- |
| ToF 测距模块 | VL53L5X V2 (I2C, 接 HAT H1 4P 排针); 用于拾取检测 |
| CSI 摄像头 | IMX219 (Radxa ROCK 5 摄像头同款, 22P RPI 序 FPC, 两个 CAM 座任插); 视频链依赖未部署的 mediad, 见 docs/03 §B |

3D 打印件与机壳: 不在本仓, 从 [官方 microduck](https://github.com/pollen-robotics/microduck) (MJCF/STL)
  或 [kissqy 发布包](https://github.com/kissqy/Microduck-kissqy) 取。

想直接动手: [docs/05-bringup-runbook.md](docs/05-bringup-runbook.md)
(clone → 编译 → 镜像 → 烧卡 → 验收 → 标定)。其余文档是设计与背景, 复刻遇到问题时再读。

## 三条上游

| 上游 | 它是什么 | 我们取哪部分 | 许可 |
| --- | --- | --- | --- |
| [pollen-robotics/microduck](https://github.com/pollen-robotics/microduck), [microduck_rl](https://github.com/pollen-robotics/microduck_rl) | 官方运行时 (Rust), 强化学习训练, MJCF + STL | 主控运行时基线: 官方 `daemon-v0.17.9` + 我们的补丁 (Feetech 后端, 总线 IMU, 标定台架); 3D 打印件 | 代码 Apache-2.0; 3D 网格 CC BY-NC-SA |
| [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy) | HD-1910 运行时 fork, 总线 IMU 板, 发布包 (步态模型等) | HAT 硬件基线 (已按本仓精简) + 发布包 (真步态 ONNX 模型, 安装脚本, 文档) | 见 `firmware/` 内 LICENSE; 文档/资产沿用上游条款 |
| [fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) | 板载网页中控 Studio, 自制 IMU v2 / wire_hub / POGO 板, 大量实测文档 | 硬件与工程实践主参考: IMU v2 板 (硬件 + 固件 `firmware-1.0.0` 都用它), Studio (固定 commit), 镜像脚本思路, 踩坑记录 | 代码/Studio/镜像脚本 Apache-2.0; 文档与 3D CC BY-NC-SA |

固件分工: **主控运行时 = 官方 0.17.9 + 我们的补丁** (`patches/runtime-opi3w-feetech.patch`);
**IMU 板固件 = replica 的 `firmware-1.0.0`** (板就是 replica 的 v2, 贴片与固件同源)。
kissqy 子模块作为 HAT 硬件基线与发布包来源。
详见 [docs/03-software-stack.md](docs/03-software-stack.md)。

## 目录

```
docs/
  00-upstreams.md       三个上游的关系, 许可边界, 我们各取什么 (先读这个)
  01-port-plan.md       移植要点: 换板要动哪四件事, 阶段状态, 风险
  02-hat-porting.md     HAT 移植方案与已执行的供电/引脚改动
  03-software-stack.md  软件层: 运行时 / Studio / 镜像 / 训练, 谁在哪, 怎么装
  05-bringup-runbook.md 从零复刻: clone -> 编译 -> 镜像 -> 烧卡 -> 验收 -> 标定
  06-audio-aic3104.md   音频: codec 接线, 驱动/overlay 要点, mixer, 自检与踩坑
patches/
  runtime-opi3w-feetech.patch   我们运行时分支的完整差分 (打在上游 daemon-v0.17.9 上)
  README.md                     基线与结果树哈希, apply 步骤, 内容清单
hardware/
  eda/                  EasyEDA Pro 工程 (HAT REV B; IMU/HUB/POGO 板用 replica 仓的工程)
  overlay/              A733 设备树 overlay (uart2-dxl.dts, audio-a733.dts)
  hat-layout.md         HAT 网表, BOM, 每处改动的理由
  pinmap.md             40-pin 重映射 + A733 控制器实证
  imu-layout.md         IMU 板连接器, 电源, 数据通路, 固件
scripts/                构建与部署 (见 scripts/README.md)
firmware/               git submodule: kissqy/Microduck-kissqy @ eccc2fdb
```

## 项目状态

| 项 | 状态 |
| --- | --- |
| 运行时移植 (官方 0.17.9 + 补丁) | ✅ 554 测试通过; host 端 `--fake` 全链路冒烟 5/5 绿; 补丁已验证可精确重建该分支 |
| 飞特总线 IMU (ID 200) | ✅ 上板实测: `ping 200` 回 `ffffc8020035`, 陀螺数据实时变化 |
| 标定链路 (busStatus / busCommand / `--commissioning`) | ✅ 完成; 台架冒烟 healthy; `startupSubscribe` 不做 (Studio 优雅降级) |
| aarch64 交叉编译 | ✅ `robotd` 9.6 MB / `robotctl` 7.7 MB, GLIBC 2.39 (底图 2.41 满足) |
| HAT 原理图 | ✅ REV B 已送厂 |
| 排针重映射 + overlay | ✅ 编译与应用验证通过 |
| aic3x codec 内核模块 | ✅ 上板原生编译 `snd-aic3x.ko`, vermagic 与 vendor 内核一致 |
| 音频 (喇叭 + 麦克风) | ✅ 出声与录音实测通过, mixer 由开机服务持久化 ([docs/06](docs/06-audio-aic3104.md)) |
| A733 系统镜像 | ✅ 组装流程闭环 (含 1GB bootloader 修复), **真机首启验收通过**: robotd 开机自启, health 正常回话 |
| 板侧依赖 (ONNX Runtime, GStreamer) / 装配 / 标定 / 试走 | ⏳ 等实物装配与标定 |

## 许可

- `firmware/` 是子模块, 条款以该仓内 `LICENSE` / `LICENSES/` 与文件头为准 (运行时源自 Pollen Robotics, Apache-2.0)。
- 按需拉取的 replica 内容不受本仓管辖: 其代码 Apache-2.0, 文档与 3D 资产 CC BY-NC-SA 4.0 (**非商业**, 需署名)。
  因此本仓文档只引用其结论与路径, 不整篇搬运。
- `patches/` 是官方 Apache-2.0 代码上的差分, 随官方条款。
- 3D 打印件与机壳来自上游 MJCF/STL, 同样受 CC BY-NC-SA 约束, 不能商用。
- 本仓自有文档与脚本: 暂未声明许可, 默认保留全部权利; 如需开源再定。
