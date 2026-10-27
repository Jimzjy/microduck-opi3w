# 软件层：固件 / Studio / 镜像 / 训练

一句话：**固件用 kissqy 的子模块（自己编 aarch64），Studio 从 replica 按需拉一个目录，镜像我们自己按 A733 做，训练沿用 kissqy 的发布包。**
四层互不拷贝，版本都在 [00-upstreams.md](00-upstreams.md) 里钉死。

## 全景

```
主控（Orange Pi Zero 3W / A733，Debian 13 用户态）
├── robotd  ── 50 Hz 控制环，JSON-RPC over /run/robotd.sock（root:robot）
├── padd    ── 手柄/IMU 板接入        ┐
├── btd     ── 蓝牙中枢               ├─ firmware 子模块编出来的二进制
├── mediad  ── 摄像头/音频/WebRTC     │  装到 /opt/robot/daemon，配置 /etc/robot
├── configd ── 系统配置（网络等）     │
└── robotctl── 命令行                 ┘
        ↑
   Microduck Studio（可选）── 网页中控，127.0.0.1:8000，经同一 socket 说话
```

## A. 板载运行时（`firmware/` 子模块）

**位置**：`firmware/microduck-hd1910/firmware/`（Cargo workspace）。Rust 工具链固定在其 `rust-toolchain.toml`（1.99.0）。

**交叉编译**（WSL Debian 13，已验证）：

```bash
cd firmware/microduck-hd1910/firmware
DUCK_DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian \
DUCK_SYSROOT=$HOME/duck-aarch64-sysroot \
sh scripts/cross-sysroot.sh
eval "$(sh scripts/cross-sysroot.sh 2>/dev/null | grep ^export)"
cargo board --bins     # robotd/robotctl/padd/btd/mediad/configd/sounds/pet-detect
```

产物最高依赖 GLIBC 2.30，凡是 glibc ≥ 2.31 的 aarch64 系统都能直接跑（A733 的 Debian 13 是 2.41）。

**安装布局**（照 `scripts/install.sh`）：

| 项 | 位置 |
| --- | --- |
| 二进制 | `/opt/robot/daemon/current/bin/`（`install.sh` 用软链切版本） |
| 配置 | `/etc/robot/robotd.toml`、`/etc/robot/feetech-ft5/hd1910-calibration.toml` |
| 单元 | `/etc/systemd/system/{robotd,padd,btd,mediad,configd}.service` |
| socket | `/run/robotd.sock`（`User=root`、`Group=robot`，组内可读是 Studio 的前提） |

**A733 上必须改的部分**

- `scripts/setup-gstreamer.sh` / `setup-rkaiq.sh` / `setup-npu.sh`：**RK 专属**（rkaiq 是 Rockchip ISP，NPU 走 rknn），A733 上跳过；
  GStreamer 用 apt 装 1.26 即可，ONNX Runtime 用 aarch64 通用 `.so`。
- `scripts/install.sh` 的头注释假设「Armbian 26.2.x on Radxa Zero 3」；用户名、硬件型号断言要改，逻辑本身可复用。
- 舵机串口：kissqy 用 `/dev/ttyS2`（PB0/PB1 = 排针 11/13），由 `hardware/overlay/uart2-dxl.dts` 打开；
  半双工方向由 HAT 上的 U6/U7/Q1 硬件自动切换，所以内核侧就是一个普通 1 Mbps 串口，**不需要 RS485 ioctl**。
- `robotd.toml` 里若写死 RK 的传感器/音频设备名，按 A733 的 `arecord -l`、`/sys/class/...` 改。

## B. Microduck Studio（从 replica 按需拉取）

**是什么**：装在鸭子上、浏览器打开的网页中控（`http://<鸭子 IP>:8000/`）。能看状态、一键卸力、站立/走路、
配对蓝牙手柄、标定舵机、校准 IMU 方向、把标定写进主程序、首次开机检查、连 WiFi。

**为什么可以直接用**：它是纯 Python（3.13）+ 仓库内钉死版本的 `deps/`（starlette/uvicorn/wsproto/pyserial 等），
不依赖 RK 硬件；它与主程序之间只走 `/run/robotd.sock` 的 JSON-RPC。

**接口对得上多少**：方法名基本齐（Studio 调用的 `robot.state/busStatus/busCommand/loadPolicy/policies/do/setMode/...`
在 kissqy 的 robotd 里都有），但**字段与语义没实测**——Studio 是照着 replica 的 fork 写的，页面个别项可能显示不出来或报错。
上板后逐页点一遍，缺什么补什么，是本项的主要工作量。

**装法**（脚本 `scripts/fetch-studio.ps1` 负责拉，这里是人做的部分）：

```bash
# 0. 先在本机拉下来（约 16 秒、400 文件 / 11.3 MB，落在 vendor/microduck-replica/software/studio，已被 .gitignore 忽略）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fetch-studio.ps1
#    也可以加 -PushTo <user>@<板子IP> 一步推过去；-NoProxy 直连、-Retries N 改重试次数

# 1. 整个 software/studio 拷到板子，放在运行用户的 home 下
scp -r vendor/microduck-replica/software/studio <user>@<板子IP>:/home/<user>/studio-dev

# 2. 用运行用户启一次，确认能起来（-I 是必须的：只认 deps/ 里的版本）
cd ~/studio-dev && python3 -I run.py --listen 0.0.0.0:8000

# 3. 装 root 小助手（舵机总线交接、写标定、配手柄、SSH 开关都靠它）
sudo sh deploy/install.sh <user>

# 4. 开机自启：先改 service 里的 User/Group/WorkingDirectory（原文写死 radxa），再装
sudo install -m 644 deploy/microduck-studio.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now microduck-studio
```

**它默认假设的镜像级配置**（手动装 Studio 时不会自动有，缺了只是对应卡片不显示）：

| 依赖 | 提供者 | 缺失后果 |
| --- | --- | --- |
| `/run/microduck/net.json` | 镜像里的 `microduck-netcheck` | 「连 WiFi」卡片不出现 |
| NetworkManager 连接 `Microduck-Hotspot` | 镜像 overlay | 开不了热点 |
| `configd` 以 `--allow-user <用户>` 运行 | 镜像/logind 配置 | 网页改不了网络 |
| mDNS（`duck-xxxx.local`） | 镜像 | 只能用 IP 访问 |

**安全边界**：`deploy/install.sh` 只往 sudoers 放**一条**规则——允许该用户免密执行 `/usr/local/sbin/microduck-helper`；
这个 helper 只认固定动词（`bus-take` / `bus-give-back` / `calib-commit` / `pad-pair` / `wifi-hotspot-up` / `ssh-password` …），
参数逐个校验，不执行网页传来的命令。密码只走 stdin，不进命令行与日志。

## C. 系统镜像（我们自己做，不搬 replica 的）

replica 的 `software/image/build-image.sh` 以 **Radxa R1 镜像**为底，换 Radxa U-Boot + B1 DTB，再把从调好的鸭子上拉的 payload 装进去。
对 A733 是**整条链不适用**：内核、DTB、U-Boot、overlay 全不同。我们只借它的目录结构：
`build-image.sh`（拉底图 → 应用 rootfs 改动 → 生成可烧录 img）、`apply-rootfs.sh`（装二进制/配置/服务）、
`capture-payload.sh`（从调好的板子上只读抓 payload）。

我们的目标是：

1. 底图：Orange Pi 官方 / Armbian 的 A733 镜像（Debian 13 用户态），要求 40-pin 可用、glibc ≥ 2.31。
2. 叠加：`hardware/overlay/uart2-dxl.dts`（uart2，✅ 已编译+fdtoverlay 回归验证，dtc 1.7.2，
   target-path 写法不依赖基础 dtb 符号表；验证夹具 `uart2-dxl-applytest.dts`）、
   i2s0 + TLV320AIC3104 的 codec 节点、TWI0（排针 3/5）。
3. 板侧 bring-up：`scripts/setup-board-a733.sh`（上游 `setup-board.sh` 的 A733 移植：
   overlay 安装到 /boot/overlay-user + user_overlays、ONNX Runtime、音频 fail-soft、
   蓝牙 UserspaceHID/--weird-ble/--pause-btd-on-pair、板况报告）。镜像里放它，
   首次开机调用，或手工 `sudo ./setup-board-a733.sh`。
4. 装包：`firmware` 编出的二进制 + `robotd.toml` + 出厂标定模板 + Studio。
5. 首次开机脚本：起名、认 IMU、连不上 WiFi 就开热点、删掉出厂标定模式标记。

验收清单：串口 console 可用（排针 8/10）→ 板侧网络可用 → `/dev/ttyS2` 出现并能 1 Mbps 通信 →
`arecord -l` 看到 codec → `robotd` 起来后 `robotctl status` 有 15 个关节 → Studio 页面能开。

## D. 训练与模型（不并入，按需引用）

- **走路/动作模型**：kissqy 的 `firmware/release-assets/Microduck-Training-Studio-R1.5.27.zip` 与
  `Microduck-Console-R17-V167.zip`，以及 `microduck-hd1910/packaging/models/`（部署时 `install-files.py` 装到 `/opt/robot/daemon/current/models/`）。
- **训练工程**：上游 `pollen-robotics/microduck_rl`（MJCF + Isaac/mjlab）。replica 的 `software/training/` 是同一套的改版，
  差异没有大到必须切换，等真要重训再对比。
- **不装 rknn**：kissqy 的 `duck-detect` 走 RK3588 NPU，A733 用不上；固件里对应 crate 不编进板侧集合即可
  （`cargo board --bins` 已经不含它）。

## 待办

- [ ] 板子到手后：按 A 节装运行时，改掉 RK 专属脚本与用户名
- [ ] Studio 上板逐页验证，记录与 kissqy fork 的字段差异
- [ ] 镜像：底图选定后写 `scripts/apply-rootfs.sh`（或在板上直接跑 install.sh 再固化）
- [ ] 把 `robotd.toml` 里 RK 设备名换成 A733 实际设备
