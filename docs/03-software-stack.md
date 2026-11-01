# 软件层: 固件 / Studio / 镜像 / 训练

一句话: **主控运行时用官方 0.17.9 + Feetech 后端的移植版 (自己交叉编译), Studio 从 replica 按需拉一个目录, 镜像我们自己按 A733 做, 训练沿用 kissqy 的发布包。**
四层互不拷贝, 版本都在 [00-upstreams.md](00-upstreams.md) 里钉死。

## 全景

```
主控 (Orange Pi Zero 3W / A733, Debian 13 用户态)
├── robotd  ── 50 Hz 控制环, JSON-RPC over /run/robotd.sock (root:robot)
└── robotctl── 命令行客户端
        ↑
   Microduck Studio (可选)── 网页中控, 127.0.0.1:8000, 经同一 socket 说话
```

官方全家桶里还有 `padd` (手柄)/ `btd` (蓝牙)/ `mediad` (摄像头/WebRTC)/ `configd` (系统配置)。
**本项目只编 `robotd` 与 `robotctl`**, 其余四个暂不部署——手柄, WebRTC 摄像头, 系统配置页这些能力
因此目前不可用; 需要时按同样的方法在 `microduck-runtime` 里编出来再加进 payload 即可。

## A. 板载运行时 (官方 0.17.9 + 我们的补丁)

**源**: `pollen-robotics/microduck` 的 `daemon-v0.17.9` tag + [patches/runtime-opi3w-feetech.patch](../patches/README.md)。
补丁里是三块: Feetech STS 总线后端 (`bus_feetech.rs` + `bus_select.rs`), 总线 IMU, 标定台架
 (`busStatus` / `busCommand` / `--commissioning`)。
**实测**: `cargo test` 554 通过 / 0 失败; aarch64 release 交叉编译出 `robotd` (9.6 MB)/ `robotctl` (7.7 MB)。

**`[bus] protocol`**: `dynamixel2` (默认, XL330 + IMU 板 200)或 `feetech-sts` (HD-1910, 
`[bus.feetech] p_scale=0.16` + 15 项 directions + `imu=true`)。

**总线 IMU (feetech-sts, `54e26b8`)**: IMU 板固件同时实现飞特寄存器表, 所以同一块板在飞特
总线上也答 ID 200——同一条 `sync_read` 里顺带读回来, **排在 15 颗舵机之后** (实测: 排前面会让
舵机应答早一个字节, 板子的校验和吃掉下一块首字节; 中间或末尾可靠)。块在 `56/15`, 前 12 字节
与 Dynamixel 的 `124/12` 完全同格式 (gyro i16×3 + SFLP 四元数 xyz fp16, w 由主控算), 所以复用
`SflpDecoder`, `imu_ready()` 在滤波收敛 25 帧后转真——这是策略接管的门槛。`[bus.feetech] imu=false`
时不读那一块, `imu_ready()` 保持 false (机器人没装 IMU 板也能起, 照实报告), 不会死等。
`set_imu_mount` 两个后端都生效 (mount 是机身属性), 摔倒检测/里程计/被拿起检测随之恢复。
待上板实测: ttyS2 上 ID 200 是否应答, `firmware/1.0.0` 板子的 sample 计数是否在走。

**交叉编译** (任意 Linux 主机, `scripts/build-runtime.sh`; 我们是在 Windows+WSL2 Debian 13 上跑的): 

```bash
bash scripts/build-runtime.sh          # 测试 → 编译 → ELF 校验 → 布进 $MICRODUCK_IMG/payload/runtime-bin/
SKIP_TEST=1 bash scripts/build-runtime.sh   # 跳过测试
```

工具链: rustup stable + `aarch64-unknown-linux-gnu` target + `gcc-aarch64-linux-gnu`。
产物 GLIBC 基线实测 **2.39** (底图 Armbian trixie 是 glibc 2.41, 满足——bookworm 2.36 会拒载); 
onnxruntime 由 ort crate 静态链入, 板上无需 libonnxruntime.so。

**安装布局** (台架手工安装, 不走官方 updaterd 签名链): 

| 项 | 位置 | 怎么进去 |
| --- | --- | --- |
| robotd / robotctl | `/usr/local/bin/` | payload `runtime-bin/` → 板上首开 setup 脚本安装 |
| robotd.service | `/etc/systemd/system/` (enabled) | 同上, setup 脚本生成 |
| robotd.toml | `/etc/robot/robotd.toml` (已存在不覆盖) | payload 里的 `deploy/robotd.toml` 默认版 |

> 舵机串口是 `/dev/ttyS2` (PB0/PB1 = 排针 11/13), 由 `uart2-dxl.dts` 打开; 半双工方向由 HAT 上的
> U6/U7/Q1 硬件自动切换, 内核侧就是普通 500 kbps 串口, 不需要 RS485 ioctl。

## B. Microduck Studio (从 replica 按需拉取)

**是什么**: 装在鸭子上, 浏览器打开的网页中控 (`http://<鸭子 IP>:8000/`)。能看状态, 一键卸力, 站立/走路, 
标定舵机, 校准 IMU 方向, 把标定写进主程序。

**为什么可以直接用**: 它是纯 Python (3.13)+ 仓库内钉死版本的 `deps/` (starlette/uvicorn/wsproto/pyserial 等), 
不依赖 RK 硬件; 它与主程序之间只走 `/run/robotd.sock` 的 JSON-RPC。

**接口对得上多少 (2026-10-27 已在 host 实测——Studio 直连我们的 robotd --fake)**: 

- **能连上, 页面能开**: Studio (replica 35b435d, 按接口 v40 写)连 robotd 0.17.9 (接口 v44)成功, 
  `robot.state` 实时流, `robot.init`, `robot.pose`, `robot.policies`, `robot.health` 都通; 
  HTTP 200, 无密码模式正常。Python 3.13.5 + 内置 deps 一次跑通, 无需装任何包。
- 当时报的三个方法缺口 (`robot.busStatus` / `robot.busCommand` / `robot.startupSubscribe`)里, 
  前两个已在运行时补齐, 第三个按设计不做——细节与取舍见 [§C.1](#c1-标定台架bc2026-10-27)。
- 手柄, 蓝牙, 连 WiFi, 首次开机检查这几张卡片依赖我们**没有部署**的守护进程与镜像件
   (`padd`/`btd`/`configd`/`microduck-netcheck`), 所以现在点它们不会生效; 运动, 状态, 标定相关页面不受影响。

**为什么先不部署这四个**: ①台架阶段用不到——运动/状态/标定全走 robotd, Studio 已覆盖; 
②它们各拖一串板侧依赖 (`mediad` 要 GStreamer + WebRTC 栈, `btd` 要蓝牙 HID 的 udev/守护件, 
`configd` 按官方镜像的 NetworkManager 约定工作), 没在 A733 上验证过的东西先塞进去, 
坏的是"烧卡即起"的基线; ③加回来不贵——同一个运行时仓, `build-runtime.sh` 的 `-p` 列表
加上对应 crate, payload 补齐镜像件即可, 等手柄/摄像头真要用了再上。
- 上板后逐页点一遍, 把实际能用的页面记在这里。

**装法** (脚本 `scripts/fetch-studio.ps1` 负责拉, 这里是人做的部分): 

```bash
# 0. 先在本机拉下来 (约 16 秒, 400 文件 / 11.3 MB, 落在 vendor/microduck-replica/software/studio, 已被 .gitignore 忽略)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fetch-studio.ps1
#    也可以加 -PushTo <user>@<板子IP> 一步推过去; -NoProxy 直连, -Retries N 改重试次数

# 1. 整个 software/studio 拷到板子, 放在运行用户的 home 下
scp -r vendor/microduck-replica/software/studio <user>@<板子IP>:/home/<user>/studio-dev

# 2. 用运行用户启一次, 确认能起来 (-I 是必须的: 只认 deps/ 里的版本)
cd ~/studio-dev && python3 -I run.py --listen 0.0.0.0:8000

# 3. 装 root 小助手 (舵机总线交接, 写标定, 配手柄, SSH 开关都靠它)
sudo sh deploy/install.sh <user>

# 4. 开机自启: 先改 service 里的 User/Group/WorkingDirectory (原文写死 radxa), 再装
sudo install -m 644 deploy/microduck-studio.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now microduck-studio
```

**它默认假设的镜像级配置** (手动装 Studio 时不会自动有, 缺了只是对应卡片不显示): 

| 依赖 | 提供者 | 缺失后果 |
| --- | --- | --- |
| `/run/microduck/net.json` | 镜像里的 `microduck-netcheck` | "连 WiFi"卡片不出现 |
| NetworkManager 连接 `Microduck-Hotspot` | 镜像 overlay | 开不了热点 |
| `configd` 以 `--allow-user <用户>` 运行 | 镜像/logind 配置 | 网页改不了网络 |
| mDNS (`duck-xxxx.local`) | 镜像 | 只能用 IP 访问 |

**安全边界**: `deploy/install.sh` 只往 sudoers 放**一条**规则——允许该用户免密执行 `/usr/local/sbin/microduck-helper`; 
这个 helper 只认固定动词 (`bus-take` / `bus-give-back` / `calib-commit` / `pad-pair` / `wifi-hotspot-up` / `ssh-password` …), 
参数逐个校验, 不执行网页传来的命令。密码只走 stdin, 不进命令行与日志。

## C. 系统镜像 (我们自己做, 不搬 replica 的)

replica 的 `software/image/build-image.sh` 以 **Radxa R1 镜像**为底, 换 Radxa U-Boot + B1 DTB, 再把从调好的鸭子上拉的 payload 装进去。
对 A733 是**整条链不适用**: 内核, DTB, U-Boot, overlay 全不同。我们只借它的目录结构: 
`apply-rootfs.sh` (应用 rootfs 改动到已有 img)+ `setup-board-a733.sh` (板侧 bring-up)+ `capture-payload.sh` (从调好的板子上只读抓 payload)。

**底图已定: Armbian trixie vendor** (`Armbian_26.8.1_Orangepizero3w_trixie_vendor_6.6.98_minimal.img.xz`, 
dl.armbian.com/orangepizero3w/archive/, Debian 13 + vendor 6.6.98 内核, glibc 2.41 满足我们的 2.39 基线)。
镜像实测 (对下载的 img 直接读的结论, 非转述): 

- 分区: 单 ext4 p1, 起点扇区 65536 (32 MiB); 前面裸区是 Allwinner boot0/u-boot。rootfs UUID `932dec6a-307e-4174-8694-c4a1ef18eef4`。
- `/boot/armbianEnv.txt`: `fdtfile=allwinner/sun60i-a733-orangepi-zero3w.dtb`, `overlay_prefix=sun60i-a733`, **没有 `user_overlays` 行 (追加即可)**。
- 内核 config: `CONFIG_SND_SOC_AC101=y` (板载声卡); **`# CONFIG_SND_SOC_TLV320AIC3X is not set`**——AIC3x 驱动
  (`sound/soc/codecs/tlv320aic3x.c`) 在厂商树里存在但没编进内核。**已 out-of-tree 解决 ✅**: 源码放
  `scripts/aic3x-module/`, 上板原生编译成 `snd-aic3x.ko`, vermagic `6.6.98-vendor-sun60iw2` 与目标内核一致,
  无硬依赖 (REGMAP_I2C/I2C/SND_SOC 全部 =y 内置)。**不要用 aic31xx**: 那是 AIC3100/3110 家族, Page 0
  寄存器语义不同, 装上后 DAC 永远不会上电。
- WiFi/BT: `CONFIG_AIC8800_WLAN_SUPPORT=m`, `CONFIG_AIC8800_BTLPM_SUPPORT=m` (与蓝牙三机制的假设一致)。

1. ~~底图选定~~ ✅ Armbian trixie vendor 6.6.98 (上面)。
2. 叠加 overlay (✅ 全部编译并对镜像真实 dtb 用 `fdtoverlay` 应用验证过): 
   - `uart2-dxl.dtbo`: uart2 status disabled→okay (target-path `/soc@3000000/uart@2502000`, 不依赖符号表)。
   - `audio-a733.dtbo`: twi0→okay + 新增 `tlv320aic3104@18`; i2s0_plat→okay; i2s0_mach name→`aic3104-hat`
     且 codec `sound-dai` phandle 被 `__local_fixups__` 正确 fixup (实测 636→新节点, cpu 317→i2s0_plat 原值不动)。
3. 板侧 bring-up: `scripts/setup-board-a733.sh` (上游 `setup-board.sh` 的 A733 移植: 
   overlay 安装到 /boot/overlay-user + user_overlays, ONNX Runtime, 音频 fail-soft (含 aic3x 模块缺失检查), 
   蓝牙 UserspaceHID/--weird-ble/--pause-btd-on-pair, 板况报告)。镜像里放它, 
   首次开机调用, 或手工 `sudo ./setup-board-a733.sh`。
4. 装包: 运行时二进制 (`build-runtime.sh` → `img/payload/runtime-bin/{robotd,robotctl,robotd.toml}`)+ aic3x `.ko`; Studio 和标定模板等上板后再说。
5. 首次开机脚本: 装 payload 里的 robotd 到 `/usr/local/bin` 并 enable 服务, 认串口, 板况报告。

**用法** (在带 loop 设备的 Linux 上, WSL2 没有 /dev/loop 跑不了): 
`sudo scripts/apply-rootfs.sh <base.img> [--module <.ko>] [--payload <dir>]` ——脚本自己 `sfdisk` 读分区偏移 (不写死 65536), losetup 挂载, 
装两个 dtbo 到 `/boot/overlay-user/`, `armbianEnv.txt` 幂等写 `user_overlays=uart2-dxl audio-a733`, 
放 `setup-board-a733.sh` 并生成 `microduck-firstboot.service` (首次开机 oneshot); `--module` 装
内核模块 (如 aic3x 的 .ko, 自动落 /lib/modules/<kver>/ 并 depmod); `--payload` 可选装额外产物。
标准命令: 

```bash
sudo scripts/apply-rootfs.sh <base.img> \
     --module ../img/aic3x-module/snd-aic3x.ko --payload ../img/payload
```

产物里应有: dtbo + `user_overlays` + setup 脚本 + firstboot 服务 + snd-aic3x.ko + depmod 索引 +
`robotd`/`robotctl`/`robotd.toml` payload。WSL2 下走 VHD 路线 (qemu-img → `wsl --mount --vhd` →
`apply-rootfs.sh --mount` → 转回), 命令见 [05-bringup-runbook.md](05-bringup-runbook.md)。

验收清单: 串口 console 可用 (排针 8/10)→ 板侧网络可用 → `/dev/ttyS2` 出现并能 500 kbps 通信 →
`arecord -l` 看到 codec (前置: aic3x 内核模块装好)→ `robotd` 起来后 `robotctl status` 有 15 个关节 → Studio 页面能开。

**上板前的无真机冒烟**: `scripts/smoke-fake.sh` (host `--fake` + onnxruntime + fixture 策略 +
robotctl 全链路)。2026-10-27 实测 5/5 通过: health → `robot healthy`, 50Hz 控制环 0 missed, 
`policy loaded mode=walk`, `robot init`/`monitor` 正常, quack 无音频时 fail-soft。
fixture (lstm.onnx)只验证加载链, 真步态模型仍来自 D 节发布包。

### C.1 标定台架 (B/C, 2026-10-27)

Studio 的标定页要三个 0.17.9 里没有的方法, 两个已补, 一个按设计不做 (运行时 `2b1e43c`): 

| 方法 | 状态 | 说明 |
|---|---|---|
| `robot.busStatus` | ✅ 已实现 | 从控制环已发布的快照拼装, **不碰串口** (Studio 10 Hz 轮询不能和控制环抢总线); 不知道的量回 `null` 不回 0 |
| `robot.busCommand` | ✅ 已实现 | `calibration-status` / `hold-home` / `verify-imu` 三个动作, 走异步 dispatch + oneshot, `hold-home` 20 s, `verify-imu` 30 s 超时 |
| `robot.startupSubscribe` | ❌ 不做 | Studio 见方法缺失即记"不支持"继续; bring-up 状态在 `robot.state` 里已有 |

台架模式是同一个二进制的开关: `robotd --commissioning` (策略关闭, `busStatus.mode` 报
`commissioning`, 允许握手/校零)。Studio 的粗校守卫要求 `phase=="holding"` +
`torque_state=="all_enabled"` + `hold.max_error_deg<=5`, 这三项都来自 `hold-home` 的真实收敛。

标定文件 `bus.feetech.calibration` (默认 `/etc/robot/feetech-ft5/hd1910-calibration.toml`)
有两方写入, 各管一段: 

- **Studio 的 root 小助手** (`microduck-helper`): 关节 `zero_raw` / `direction` / `min_rad` /
  `max_rad` / `calibrated`, 以及 `motion_enabled`
- **robotd**: 只写 `imu_mount_quat` 与 `imu_mount_verified` 两个字段, 且只有 `verify-imu` 成功时写

robotd 在开总线时读它, 重试时重读 (小助手可能在等舵机供电时正在写), 载入后以内存为准; 
读失败只 warn 不拒启动——标定坏掉的鸭子仍然得能站起来重新标。

板侧验收 (板子到手后照着走): 

```bash
systemctl stop robotd
sudo robotd --commissioning          # 或改 drop-in 让 service 带这个参数
# Studio: 连板子 → 标定页 → 摆正 → 校零 → hold-home (应报 ≤5° 误差)→ 低头 15–30° 验 IMU
sudo cat /etc/robot/feetech-ft5/hd1910-calibration.toml   # 看 imu_mount_verified = true
systemctl start robotd                # 回到运动模式
```


## D. 训练与模型 (不并入, 按需引用)

- **走路/动作模型**: kissqy 的 `firmware/release-assets/Microduck-Training-Studio-R1.5.27.zip` 与
  `Microduck-Console-R17-V167.zip`, 以及 `microduck-hd1910/firmware/packaging/models/` (内容寻址的哈希目录, 
  部署时由同目录的 `install-files.py` 按 `install-files.json` 装到 `/opt/robot/daemon/current/models/`)。
- **训练工程**: 上游 `pollen-robotics/microduck_rl` (MJCF + Isaac/mjlab)。replica 的 `software/training/` 是同一套的改版, 
  差异没有大到必须切换, 等真要重训再对比。
- **不装 rknn**: kissqy 的 `duck-detect` 走 RK3588 NPU (rknn), 代码绑死了那家的运行时, A733 用不上。
  A733 的 NPU 是 Vivante VIP9000 (ACUITY/NBG 工具链), 以后要做视觉检测按那条路另起, 不随本次移植。
  我们只编 `robotd`/`robotctl`, 本来也含不进它。

## 待办

- [ ] 板子到手后: 按 [05-bringup-runbook.md](05-bringup-runbook.md) 跑一遍, 把结果写回这里
- [ ] Studio 上板逐页验证, 记录哪些卡片可用
- [ ] 把 `robotd.toml` 里 RK 设备名换成 A733 实际设备
- [ ] 按需补 `padd` / `btd` / `mediad` / `configd` (手柄, 蓝牙, WebRTC 目前没有)
