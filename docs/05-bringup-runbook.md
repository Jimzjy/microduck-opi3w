# 从零复刻（bring-up runbook）

这份文档假设你手上只有这台电脑和一块新买的主控板：**从 GitHub clone 开始，到机器人能站起来、能被
Studio 标定**。每一步都给出命令和验证方法；没验证过的步骤不要往下走。

（如果只是想理解为什么这么设计，看 `01`–`04`。想照着做，就看这一页。）

## 0. 需要什么

**硬件**（型号与替代见 [DUCK-SHOPPING-LIST](../firmware/DUCK-SHOPPING-LIST.md) 与 [START-HERE](../firmware/START-HERE.txt)）

| 件 | 数量 | 说明 |
| --- | --- | --- |
| Orange Pi Zero 3W（2 GB） | 1 | 主控，A733（`sun60iw2`） |
| microSD 卡 | 1 | ≥16 GB，A1/A2 |
| microduck HAT（REV B） | 1 | `hardware/eda/HAT_REVA_SCH_OPI3W.eprj2`，已送厂 |
| HD-1910 舵机（飞特 STS 协议） | 15 | 腿部 12 + 头颈 3 |
| IMU 板（replica v2） | 1 | `hardware/eda/imu_to_dxl_1V0A.eprj2`，总线 ID 200 |
| 总线 Hub | 1 | `hardware/eda/wire_hub_1V0A.eprj2` |
| USB-TTL 串口线 | 1 | 3.3 V 电平，接 console（排针 8/10） |
| 5 V / 3 A 电源模块 | 1 | 同步整流（mini560 一类），供 HAT |
| ToF 测距模块 **VL53L5X V2** | 1 | 8×8 多区 ToF，I2C 地址 0x29（与 codec 共用 i2c3）。杜邦线接 HAT H1 排针（3V3/GND/SDA/SCL，见 `hat-layout.md` ①；禁止插 Qwiic 转接线，会反接电源） |
| 喇叭（**3525 腔体**） | 1 | **4 Ω / 3 W**，接 HAT J1 喇叭座（PAM8406D 功放输出） |
| 摄像头 **Radxa ROCK 5 IMX219** | 1 | CSI 排线接主控 CSI 座。注意：本仓只部署 robotd/robotctl，摄像头链路（mediad/WebRTC）未部署，见 docs/03 §B |
| 驻极体麦克风 **4015 封装** | 2 | 接 HAT J2（左）/ J9（右）。输出阻抗 2.2 kΩ、工作电压 1–10 V（HAT 偏置 5 V 在范围内）、最大电流 500 µA、最大输入声压 110 dB、灵敏度 56 dB、信噪比 40 dB |

**主机环境**：从取源码到交叉编译只需要一台 **Linux 主机**，发行版不限（命令按 Debian/Ubuntu 写，
其它发行版换等价包）。三种常见情况：

| 主机 | 能做到哪一步 | 说明 |
| --- | --- | --- |
| Linux（物理机 / 虚机 / 云主机） | **全部** | 标准路线，组装镜像走 loop 设备 |
| Windows + WSL2 | **全部** | 我们开发用的环境；差别只在组装镜像没有 loop 设备，走 §5 的 VHD 路线（文档里单独标出） |
| macOS | 除「组装镜像」外全部 | 编译与 smoke 没问题；组装镜像要写 ext4，第 5 步找任何一台 Linux（虚机/云主机均可）代跑。交叉编译链未在 macOS 验证过，链接器可用 cargo-zigbuild 等价替代 |

除标注「WSL」的步骤外，本文命令对三种环境是同一套。

**软件包**（Debian/Ubuntu 名）：`git`、`rustup`（稳定版，另加 target `aarch64-unknown-linux-gnu`）、
`gcc-aarch64-linux-gnu`、`device-tree-compiler`；`qemu-utils` 只有 Windows+WSL 的 VHD 路线需要。

## 1. 取源码

```bash
git clone --recurse-submodules <本仓 URL> microduck-opi3w
cd microduck-opi3w
git submodule status      # 应显示 eccc2fdbbf4c835e12abfa7ae6c93b1b1462fc51 firmware (heads/main)
```

子模块是 kissqy 的发布仓，我们只用它的**硬件基线 + 发布包（步态模型、安装脚本）**。它固定在上表那个
commit，`update` 之前先想清楚：模型格式跟着它走，换版本要重新验 `deployment-contract.json`。

我们的运行时（主控程序）不在本仓里，是一份补丁：见 [patches/README.md](../patches/README.md)。

## 2. 编设备树 overlay

`hardware/overlay/*.dtbo` 不入库（`dtc` 产物），clone 后自己编：

```bash
sudo apt install device-tree-compiler
dtc -@ -I dts -O dtb -o hardware/overlay/uart2-dxl.dtbo hardware/overlay/uart2-dxl.dts
dtc -@ -I dts -O dtb -o hardware/overlay/audio-a733.dtbo hardware/overlay/audio-a733.dts
```

验证：`dtc -I dtb -O dts hardware/overlay/uart2-dxl.dtbo | head` 能看到 `uart2` 与 `pinctrl` 节点。

## 3. 编运行时（robotd / robotctl）

```bash
rustup target add aarch64-unknown-linux-gnu
sudo apt install gcc-aarch64-linux-gnu
bash scripts/build-runtime.sh          # 先跑测试，再交叉编译，产物落到 $MICRODUCK_IMG/payload/runtime-bin/
```

编译产物**不进 git**：脚本默认放到仓库**同级**的 `img/`（`MICRODUCK_IMG` 可改；镜像底图、`.ko`、
payload 都放那儿）。运行时源码同样取同级目录 `microduck-runtime/`（`MICRODUCK_RUNTIME` 可改）。
第一次建那个目录时：

```bash
git clone https://github.com/pollen-robotics/microduck.git microduck-runtime
cd microduck-runtime && git checkout daemon-v0.17.9
git apply ../microduck-opi3w/patches/runtime-opi3w-feetech.patch
git switch -c opi3w-feetech
```

验证：`file ../img/payload/runtime-bin/robotd` 应报 `ELF 64-bit LSB pie executable, ARM aarch64`。

## 4. 编 aic31xx 音频模块

板载 codec 在内核里没编进去（`# CONFIG_SND_SOC_TLV320AIC31XX is not set`），要自己出一个 `.ko`。
脚本是「人工流程的脚本化」，要两个输入：Armbian 的 headers 包、厂商树的驱动源码。

```bash
# 1) headers 包（apt.armbian.com 的 linux-headers-vendor-sun60iw2_*_arm64.deb）
# 2) 驱动源码：orangepi-xunlong/linux-orangepi 分支 orange-pi-6.6-sun60iw2 里的
#    sound/soc/codecs/tlv320aic31xx.c + tlv320aic31xx.h（记下 commit）
bash scripts/build-aic31xx-module.sh <linux-headers-*.deb> <驱动源码目录> ../img/aic31xx-module
```

**唯一要盯的是 vermagic**：必须是 `6.6.98-vendor-sun60iw2 SMP preempt mod_unload aarch64`，
少了 `-vendor-sun60iw2` 后缀上板会拒载（`modules_prepare` 会把 release 重写成 `6.6.98`，脚本已强制写回并自检）。

## 5. 组装镜像

底图：`Armbian_26.8.1_Orangepizero3w_trixie_vendor_6.6.98_minimal.img.xz`
（`dl.armbian.com/orangepizero3w/archive/`），解压得到 `.img`。

**1GB 内存版必须换 bootloader**：Armbian 的 boot0 DRAM 参数表不含 1GB 容量，
上电串口会打 `DRAM Pstate 1 training fail, fail result is 0xff` → `Failed preparing
the second boot`，死在进 U-Boot 之前（2GB 及以上不受影响）。解法：烧一次官方镜像
（Orange Pi 下载页的 Debian/Ubuntu，全容量自适应）确认能起，然后把官方 `.img` 传给
`--bootloader`——脚本把官方镜像的 bootloader 裸区（扇区 16 到分区 1 之前，boot0+U-Boot）
整段移植进底图，根文件系统不动。官方镜像与底图分区布局不同会直接拒绝执行。

在**带 `/dev/loop` 的 Linux** 上：

```bash
sudo scripts/apply-rootfs.sh Armbian_26.8.1_....img \
     --module ../img/aic31xx-module/snd-soc-tlv320aic31xx.ko \
     --payload ../img/payload \
     --bootloader /path/to/Orangepizero3w_1.0.2_debian_trixie_server_linux6.6.98.img
```

在 WSL2 上（没有 loop 设备）走 VHD 路线：

```powershell
qemu-img convert -O vpc Armbian_26.8.1_....img build.vhd
wsl --mount --vhd $PWD\build.vhd --partition 1
# 挂载点形如 /mnt/wsl/<路径压平>/；第一次报「磁盘已在使用」就先 wsl --unmount
wsl -d Debian -u root -- bash -c 'cd /mnt/c/.../microduck-opi3w && scripts/apply-rootfs.sh --mount /mnt/wsl/<挂载点> --module ../img/aic31xx-module/snd-soc-tlv320aic31xx.ko --payload ../img/payload'
wsl --unmount $PWD\build.vhd
qemu-img convert -f vpc -O raw build.vhd microduck-opi3w-base.img
```

验证（不依赖挂载态，直接查产物）：

```bash
debugfs -R "cat /boot/armbianEnv.txt" ../img/microduck-opi3w-base.img | grep user_overlays   # uart2-dxl audio-a733
debugfs -R "stat /usr/local/bin/robotd" ../img/microduck-opi3w-base.img | head               # 存在且有大小
```

## 6. 烧卡与首开

用 Etcher / Rufus 把 `microduck-opi3w-base.img` 写到 SD 卡 → 插板 → 接串口（8/10）→ 上电。

**调试通道（按优先级）**：① WiFi SSH（正常情况用它）；② **OTG Type-C 虚拟网卡**——镜像已内置
`usb-gadget` 服务，OTG 口插电脑会出一个 RNDIS 网卡，电脑侧手动设 IP `10.55.0.2/24`，
然后 `ssh root@10.55.0.1`。装上 HAT 后串口被盖住，这条就是救命通道；③ 串口（8/10）与
HDMI 用于系统起不来的场景。

首开由 `firstboot` 服务跑 `setup-board-a733.sh`，它会：装 dtbo 并写 `user_overlays`、落
`/opt/robot/payload/`、把 `robotd`/`robotctl` 装到 `/usr/local/bin`、写默认 `/etc/robot/robotd.toml`
（已存在则不覆盖）、`systemctl enable robotd`。日志：

```bash
journalctl -u microduck-firstboot -b
```

## 7. 验收（按顺序，全过再往下）

```bash
# ① 总线和 robotd
robotctl --robot-socket /run/robotd.sock health      # 期望 "robot healthy"，loop 50 Hz，bus ok
robotctl --robot-socket /run/robotd.sock status      # 15 颗关节 + IMU
# ② 串口设备树
dmesg | grep -i ttyS2                                # 存在且被 robotd 打开（lsof /dev/ttyS2）
# ③ 总线 IMU（ID 200 必须在舵机之后应答）
robotctl --robot-socket /run/robotd.sock monitor     # imu.ready 在约 25 帧后转 true
# ④ 音频
aplay -l | grep -i aic31xx
```

三项常见失败：

- `ttyS2` 没起来 → overlay 没生效，查 `/boot/armbianEnv.txt` 的 `user_overlays`
- IMU 一直 `ready=false` → ID 200 没应答，或 `[bus.feetech] imu` 没打开；先确认 ID 200 排在 15 颗舵机**之后**
- `aplay -l` 空 → `.ko` vermagic 不对（`dmesg | grep -i aic31`）

## 8. 标定

Studio 的标定流程要求在 **commissioning 模式**下做：让 robotd 不跑策略、只守姿态。

```bash
sudo systemctl stop robotd
sudo robotd --commissioning          # 前台跑，Ctrl-C 退出
robotctl --robot-socket /run/robotd.sock status   # bus.mode 应为 "commissioning"
```

长期用标定模式就把参数写进 systemd：`sudo systemctl edit robotd` 加一行
`ExecStart=`（覆盖原值）再跟 `/usr/local/bin/robotd --commissioning`。

然后按 Studio 页面走：粗校（hold-home 到 HOME，报每关节误差）→ 修零位/方向 → 写回标定文件 →
verify-imu（摆正 → 20 s 内前低头 15–30°）。

标定文件 `/etc/robot/feetech-ft5/hd1910-calibration.toml` 有两个写入方，谁写谁的部分是固定的：
Studio 侧小助手写关节部分，robotd 只写 IMU 那两行。细节见
[docs/03 §C.1](03-software-stack.md)。

## 9. 之后改东西

| 想改 | 做什么 |
| --- | --- |
| 运行时（robotd/robotctl） | 改 `microduck-runtime` → `build-runtime.sh` → 板上覆盖二进制并重启 robotd（不用重刷） |
| 设备树 / 引脚 | 改 `hardware/overlay/*.dts` → 重编 → `apply-rootfs.sh` 重刷，或板上直接换 `.dtbo` + 重写 `user_overlays` |
| 硬件 | 改 `hardware/eda/*.eprj2`（EasyEDA Pro）→ 打样 → 同步改 `pinmap.md` 与 `docs/02` |
| 模型（步态） | 从子模块的 `firmware/microduck-hd1910/firmware/packaging/models/` 取，装进 `/opt/robot/policies/current/` |

**每次改完，把结论写回对应文档。** 文档是下一个人（或三个月后的你）唯一的入口。
