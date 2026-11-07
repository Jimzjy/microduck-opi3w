# 快速开始: 烧卡 → 烧 IMU → 装机 → 标定

想从源码自己构建看 [05](05-bringup-runbook.md)。

```
① 烧镜像到 SD 卡
② 烧 IMU 板的固件        5 分钟   (只做一次)
③ 设 15 颗舵机的 ID 与波特率
④ 装机接线
⑤ 首次开机 + 五项验收
⑥ 标定
```

## 1. 烧镜像

发行镜像放在 GitHub Releases: `microduck-opi3w-<日期>.img.xz` 与同名 `.sha256`。

```bash
sha256sum -c microduck-opi3w-<日期>.img.xz.sha256
xz -d microduck-opi3w-<日期>.img.xz
```

用 Etcher / Rufus 把 `.img` 写到 SD 卡 (≥16 GB)。也可以 `dd`:

```bash
sudo dd if=microduck-opi3w-<日期>.img of=/dev/sdX bs=4M conv=fsync status=progress
```

镜像里已经带官方 bootloader, **1 GB 内存版的主控板可以直接用** (Armbian 原版 bootloader 在 1 GB 板上
会 `DRAM Pstate 1 training fail` 卡在 U-Boot 之前, 已在这个镜像里换掉)。

镜像与 HAT 的硬件版本绑定: HAT 改过引脚就必须用同版本镜像, 版本对应关系见 release 说明。

> 还没发布对应版本的镜像时: 按 [05](05-bringup-runbook.md) 自己构建一次 (需要 Linux 或 WSL2 + Rust 交叉编译工具链),
> 或开 issue 询问。

## 2. 烧 IMU 板 (只做一次)

固件在: `hardware/imu-firmware/Build-gcc/imu_to_dxl.hex`:

验证: 板子的串口 (115200 8N1) 发 `s`, 首行应为

```
imu_to_dxl 1.0.0-500k | STM32G031F8 | FT-SCS ID=200 500000 8N1
```

发 `n`: `ready=1 id=0x70 err=0`, 计数每秒涨约 113。
为什么不是上游那份 hex: 我们这条总线跑 500 kbps, 上游 hex 写死 1 Mbps, 见 [07](07-imu-firmware.md)。

## 3. 舵机 ID 与波特率 (装机前做)
15 颗舵机的 ID 是固定的, 参考上游的项目

波特率档位设置 `1` = 500 kbps

## 4. 装机接线

| 接法 | 说明 |
| --- | --- |
| 舵机电池 → HAT `J13` / `J14` | 15 颗舵机与 IMU 板都吃这条电池电压 (脚序 1=DATA, 2=+, 3=GND) |
| 5 V 模块 → HAT `U11` 端子 | **只给 HAT 板自己供电** (主控 / codec / 功放), 不经过舵机电流 |
| IMU 板 | 挂在总线末端, **必须排在 15 颗舵机之后** (排首位会吃掉下一块的末字节) |
| 麦克风 | 两颗 4015 驻极体, 插 `J2` (左) 与 `J9` (右) |
| 喇叭 | `J1`, 4 Ω 3 W |

细节与每处改动的理由见 [02-hat-porting.md](02-hat-porting.md) 与 [hardware/hat-layout.md](../hardware/hat-layout.md)。

## 5. 首次开机 + 验收

插卡上电。调试通道按优先级: ① 串联网线/WiFi 的 SSH; ② **OTG Type-C 虚拟网卡** — 电脑侧设
`10.55.0.2/24`, 然后 `ssh root@10.55.0.1` (装上 HAT 后串口被盖住, 这条是救命通道);
③ 串口 (排针 8/10, 115200) 与 HDMI。

镜像不含 WiFi 凭据, 第一次进去自己连。

首开由 `microduck-firstboot` 跑 `setup-board-a733.sh` (装 dtbo, 落 payload, 装 robotd/robotctl,
写默认配置并 enable)。看日志:

```bash
journalctl -u microduck-firstboot -b
```

五项验收, 全过再往下:

```bash
robotctl --robot-socket /run/robotd.sock health    # robot healthy, loop 50 Hz, bus ok
robotctl --robot-socket /run/robotd.sock status    # 15 颗关节 + IMU
robotctl --robot-socket /run/robotd.sock monitor   # imu.ready 约 25 帧后转 true
aplay -l | grep -i aic3104                         # card 1: aic3104hat
amixer -c 1 cget numid=11                          # 118 = 0.00 dB
```

麦克风自检 (喇叭会响, 认的是自己发出的 750 Hz):

```bash
python3 scripts/mic-selftest.py --vol 90 --amp 12000
# 期望: 750 Hz ratio 25.74 / 1500 Hz ratio 32.68 -> MICROPHONE PICKS UP SOUND
```

## 6. 标定

标定要在 commissioning 模式下做 (不跑策略, 只守姿态):

```bash
sudo systemctl stop robotd
sudo robotd --commissioning
robotctl --robot-socket /run/robotd.sock status   # bus.mode 应为 "commissioning"
```

然后按 Studio 的标定页走: 粗校 (hold-home, 报每关节误差) → 修零位/方向 → 写回标定文件 →
verify-imu (摆正, 20 s 内低头 15–30°)。流程细节见 [05 §8](05-bringup-runbook.md)。

## 7. 出问题先看这里

| 现象 | 原因 |
| --- | --- |
| `aplay -l` 里没有 card 1 | aic3x 模块没装或 vermagic 不对: `dmesg \| grep -i aic3` |
| 有 card 1 但没声音 | `amixer -c 1 cget numid=11` 是 6 (即 -56 dB), 跑 `scripts/aic3104-mixer.sh` |
| `ping 200` 没有应答 | IMU 固件没烧 / 波特率不是 500 kbps / IMU 没排在舵机之后 |
| robotd 日志刷 `read version block on 21: Operation timed out` | 21 号舵机没接; 15 颗接齐后自己会过 |
| dmesg 每秒一条 `uart2, baud 500000 beyond rance` | 总线还没一次走通时的重试日志, 接齐舵机后消失 |
| 上电时喇叭"啪"一声 | 功放与 codec 上电顺序造成的直流瞬态, 无害 |

更多排障见 [05](05-bringup-runbook.md) 与 [06](06-audio-aic3104.md)。
