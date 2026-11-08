# 08 摄像头与 ToF

这两个外设都在上游 Microduck 的软件栈里: 摄像头走 `mediad` (WebRTC 视频), ToF 走 `tofd` (8x8 距离阵列)。本页写它们在 A733 + 本 HAT 上的适配方式。

物料:

| 项 | 器件 | 状态 |
|---|---|---|
| 摄像头 | IMX219 模组 (Raspberry Pi camera v2 兼容, 排线 CSI), 上游购物清单同款 160 度广角 | ✅ 端到端实测通: RG10 抓帧 + `mediad` 720p WebRTC 出流, 控制台可见实时画面 |
| ToF | VL53L5CX (VL53L5X V2) 模组, I2C 地址 0x29, 接 HAT 的 H1 排针 | 未实测, 需板上验证 |

## 摄像头

### 结论: 驱动不用改, 板级补两样东西

A733 的原厂设备树 (`sun60i-a733-orangepi-zero3w.dtb`) 已经把 IMX219 配好并使能:

- `sensor0_mname = "imx219"`, `status = "okay"`, I2C 地址 0x10, MCLK 1
- `csi@5820000` / `mipi@5810100` / `vinc@5830000` 全部 `okay`

摄像头走的是主控板自带的 CSI 相机座和专用 CCI 控制器, 与 HAT 的 40 排针和 I2C3 (codec/ToF 共用) 无关。内核模块 `imx219.ko` / `vin_v4l2.ko` 在镜像里都有 (vendor 内核 `kernel/bsp/drivers/vin/`)。

**出图只需要两件事**, 都跟驱动源码无关:

1. **BLDO2 (VCC_3V3_CSI) 常开** — `hardware/overlay/csi-rail.dts` (已编好 dtbo)。
   板级 DTS 里没有任何 consumer 引用这颗 LDO, 开机约 30 秒的 unused-regulator
   sweep 会把它关掉。症状是「传感器 I2C 应答、格式能读, 但一帧不进来、中断恒 0」。
   Armbian 有一份等价补丁 (`0008-orangepizero3w-keep-csi-camera-rail-always-on.patch`,
   只给 `reg_bldo2` 加 `regulator-always-on`), 我们跑的内核没带, 所以用 overlay 补。
2. **`vin_v4l2` 开机自动加载** — `modules-load.d/vin_v4l2.conf`。厂商不给它写
   `modules-load` 也没有 udev 规则, 不写这一行开机根本没有 `/dev/video*`。

另外**抓帧必须带 `VIDIOC_S_INPUT`** (见下), 这不是配置问题, 是这颗驱动的调用约定。

### 抓帧: 必须先 S_INPUT

`vin_v4l2` 把「打开 pipeline」放在 `VIDIOC_S_INPUT` 里而不是 `open()`:

```
vin_open()          只置 VIN_LPM/VIN_BUSY
vidioc_s_input()    → __vin_sensor_setup_link() + __vin_pipeline_open(prepare=true)
                    → 传感器 s_power (开 MCLK、上电) + ISP/scaler init
vidioc_streamon()   → __vin_pipeline_s_stream → 传感器 s_stream
```

不调 S_INPUT 时 `S_FMT` 也能返回 0 (probe 阶段 prepare 过一遍), `STREAMON` 也
不报错, 但传感器 `s_stream` 从不被调用、MCLK 一直是关的 —— 所以「设备在、
格式能设、就是没图」。ftrace 对照过两种走法: 没有 S_INPUT 时整条链路上只有
`__vin_sensor_setup_link` / `__vin_pipeline_s_stream`, 传感器侧的 `sensor_power`
和 `sensor_s_stream` 一次都没进。

```
# 一条命令搞定 (每次 v4l2-ctl 都是新 open, S_INPUT 必须和抓帧同一个进程)
v4l2-ctl -d /dev/video0 --set-input=0 \
    --set-fmt-video=width=1920,height=1080,pixelformat=RG10 \
    --stream-mmap=4 --stream-count=1 --stream-to=/tmp/snap.raw
```

脚本版: `scripts/camera-snapshot.sh`。抓到的是原始 Bayer (RG10 = 16-bit 小端、
低 10 位、高度按 8 行对齐到 1088), 在 PC 上用 `scripts/cam-raw2png.py` 转 PNG。
实测 1920x1080 单帧 4,177,920 B, 3 帧 12,533,760 B, 画面正常 (偏暗偏绿是没有
ISP 调色, 不是坏)。

![实测抓帧](images/camera-snap.png)

本板实拍样张 (桌面/深色物体/木纹), 由上面那条命令抓的 raw 直接转出来, 没有经过
任何 ISP 处理。

`timeout` 一定要加: 驱动在失败路径上会卡在 DQBUF 里不返回; 被 timeout 杀掉之后
下一次 STREAMON 会报 `video0 has already stream on`, 只有
`modprobe -r vin_v4l2; modprobe -r imx219; modprobe -r vin_io; modprobe vin_v4l2`
能清掉这个状态。

### 别走的弯路 (都试过, 无效)

- 改 `bsp/drivers/vin` 让 `vin_md_prepare_pipeline()` 认 disabled 链路, 重编
  `vin_v4l2.ko` 上板 (能编过、S_FMT 从 EINVAL 变成 0, 但仍然没帧 —— 因为
  真正缺的是 S_INPUT 带的 power/stream)。**结论: 驱动保持原厂, 别维护私编模块。**
- 用 `media-ctl` 手动把 `imx219:0→sunxi_mipi.0`、`sunxi_csi.0→sunxi_tdm_rx.0`
  两条链路置 ENABLED: 能让格式协商往前走一步, 但 `media_entity_setup_link`
  不会走驱动的上电路径, 仍然没帧。
- `dynamic debug` (`module vin_v4l2 +p`): 这版内核的 vin 打日志走自己的
  `vin_log_mask` (`/sys/.../5830000.vinc/vin_log_mask`), 不是 pr_debug。
- 从用户态读 imx219 寄存器: CCI 驱动独占 `/dev/i2c-11`, `I2C_SLAVE` 报 EBUSY。

### mediad (视频流)

`mediad` 从 CSI 读流并经 WebRTC 推给浏览器, 依赖三层:

1. **GStreamer 运行时** (apt): tools + plugins-base/good/bad/ugly + `gstreamer1.0-nice`, 外加 `v4l-utils`。一条命令: `scripts/setup-gstreamer.sh --mirror`(国内网络)或 `scripts/setup-gstreamer.sh`。
2. **webrtcsink**: 属于 gst-plugins-rs, Debian **任何 suite 都没有**。不用在板子上编 Rust —— 上游已经从 0.15.3 编好 A733 可用的 `microduck-gst-plugins-v3-aarch64.tar.gz`(release v3), `setup-gstreamer.sh` 会带 sha256 校验装 `libgstrswebrtc.so` + `libgstrsrtp.so` 到 `$(pkg-config --variable=pluginsdir gstreamer-1.0)`。板子上没有 cargo, 这条路也不该走。
3. **mediad 二进制**: 本仓不预编译分发, 交叉编译方法见 docs/05 (`runtime/scripts/cross-sysroot.sh` + `cargo build -p mediad --target aarch64-unknown-linux-gnu`)。

**A733 的采集不走 `v4l2src`**, 本仓已给 mediad 加了一条原始采集支路(`pipeline.rs` 的 `raw_bayer_source()`): 三个原因, 都是实测的 ——

- `v4l2src` 把 `VIDIOC_ENUM_FMT` 映射成 `GstVideoFormat`, 这张表里没有 Bayer, 所以它面对一个只出 Bayer 的设备直接 `has no supported format`;
- `v4l2src` 不发 `VIDIOC_S_INPUT`, 而 A733 的 vin 把整条链路的 prepare 放在 S_INPUT 里;
- 驱动列的 ISP 格式(NV16/422P/RGB3…)能协商、能出帧, 但内容是没调过的原始数据或黑帧(实测 NV16 解出来 luma 均值 36, 图里什么都没有; RGB3 是一片暗紫), 只有 RG10 是真的画面。

所以 mediad 在 `v4l2-ctl --list-formats` 里看到 Bayer fourcc 时, 自己起一条 `v4l2-ctl --set-input=0 --set-fmt-video=...RG10 --stream-mmap --stream-to=<fifo>`, 按帧读进 `appsrc`, 后面接 `bayer2rgb ! videocrop ! videoscale ! videoconvert` 变成管线要求的 UYVY。高度按 8 行对齐(1080 → 1088)由 `videocrop` 裁掉。

两个容易踩的点, 都是实测出来的:

- **抓帧必须走 FIFO, 不能用 `--stream-to=-`**。`v4l2-ctl` 会把 `Video input set to 0 (sunxi-vin: Camera, ok)` 打到 **stdout**(`--silent` 也压不住), 于是整条视频流前面多了 45 字节, 每一帧都提前 45 字节被读走, 出来的图是一片纯白(均值 233)。
- **按档位抓, 不要按传感器原生 1080p 抓**。VIN 的 scaler 真的能缩 raw, 而线宽就是帧率: 1080p raw 只有 13.6 fps, 原生 720p 26 fps, 而 debayer + convert 单独跑是 61 fps —— 瓶颈在抓帧带宽。

**亮度靠私有 ioctl, 标准 V4L2 控件在这颗驱动上是空转的**: 对 `/dev/video0` 和 `/dev/v4l-subdev0` 写 `exposure=19200,gain=409600`, `--get-ctrl` 能读回写入值, 但画面与默认逐字节相同。真正生效的是 `VIDIOC_VIN_SENSOR_EXP_GAIN`(`_IOWR('V', 192+61, 32)` = `0xc02056fd`), 参数是内核头 `bsp/include/media/sunxi_camera_v2.h` 里的 **8 个 int**(`exp_val` 是 行数<<4, `gain_val` 是 16/倍, 驱动夹在 [16,159] 即 9.94x)。`mediad` 的 `sensorctl.rs` 走的正是这条路, 所以 **自动曝光现在是开着的、也是有效的**, 不需要 `--no-auto-exposure`。

这条 raw 路径上没有 ISP, 因此没有数字增益; 亮度的天花板就是「快门行数 × 模拟增益」。实测(开灯的房间): 1200 行 × 9.9x 只有 luma 61, 而驱动是拿快门当帧长用的, 所以把上限提到 2400 行可以到 luma 79.6 —— 代价是 23 fps(1200 行时约 30 fps)。

```
sudo apt install v4l-utils
sudo scripts/setup-gstreamer.sh            # GStreamer + webrtcsink
```

### 按需启动 (默认就是这样)

`mediad` 只解码 + WebRTC 就要占满一个核 (实测 61%), 平时没有理由让它常开。所以
**`mediad` 本身 `disable`, 开机不启动**, 由 `camera-launcher` 在有人打开控制台时拉起:

```
浏览器 → :8080 camera-launcher ──(TCP 转发)──→ :8081 mediad 控制台
                                        mediad 另听 :8443 做 WebRTC 信令
```

- 打开 `http://<板子IP>:8080/` 时启动器先 `systemctl start mediad`, 等 8081 可连
  再把请求转过去, 页面和视频体验不变 (视频仍然直连 8443, 不经过转发)。
- 没有任何人看时 (没有转发连接、也没有外部到 8443 的 ESTABLISHED 连接) 静默
  10 分钟就 `systemctl stop mediad`, CPU 回到 0。
- **判断「有人在看」必须看 8443, 不能看 8080**: 浏览器把页面资源取完就关掉 8081
  的连接, 之后视频才走 8443。另外 `mediad` 自己会和自己的 8443 建一条 loopback
  连接, 统计时要排掉 `127.0.0.1` 的对端, 否则永远不空闲。
- 想临时抓帧/用 `robotctl frame` 时, 手动 `systemctl start mediad` 即可 (同样会在
  空闲 10 分钟后被停):

```
systemctl start mediad        # robotctl frame 需要它
systemctl status camera-launcher
journalctl -u camera-launcher -f
```

安装方法见 `scripts/setup-board-a733.sh`; 手工部署就是三件事: 把
`scripts/camera-launcher.py` 放进 `/usr/local/bin/`, 装 `camera-launcher.service`,
并给 `mediad.service` 的 `ExecStart` 追加 `--web-port 8081` (再 `systemctl disable mediad`)。

A733 侧的硬件编码器 (Radxa 路线用的 mpph264enc 是 RK 专属) 尚未验证; 没有硬件编码器时 webrtcsink 会退到软件 H.264 (`openh264enc`), 1GB 内存版可能吃紧 —— 所以默认先用 720p 档位。

警告: **没接摄像头时不要 enable mediad 服务** — 它找不到采集设备会反复崩溃重启 (replica 板上烧过主板)。先手动跑通, 再写 service。

## ToF

### 接线

ToF 接 HAT 的 H1 排针 (1x4P 2.54, 见 hardware/README.md): 1=3V3, 2=GND, 3=SCL, 4=SDA, 与 codec 同在 I2C3。**只能杜邦线按编号接, 不能插 Qwiic 转接线 (脚序不同会反接电源)。**

### tofd

`tofd` 通过 `/run/tofd/tof.sock` 的 `tof.stream` 提供 8x8 距离阵。适配点:

- I2C 总线: 优先找 `/dev/i2c-pihat`, 回退 `/dev/i2c-3`。`/dev/i2c-pihat` 符号链接由 `scripts/setup-board-a733.sh` 的 udev 规则创建 (需要 `DUCK_I2C_KERNELS` 环境变量, 板上 `ls /sys/bus/i2c/devices/i2c-3/..` 确认后传入)。
- IMU: `tofd` 原生支持头部 BMI088, 我们不用 (IMU 在舵机总线上), 所以用 `--no-imu` 关闭。
- 二进制: 交叉编译产物 `target/aarch64-unknown-linux-gnu/release/tofd`。`setup-board-a733.sh` 会从 payload 安装并写好 service, 但**默认不启用** — 传感器没接时启用它只会得到重启循环。接好后:

```
systemctl enable --now tofd
# 验证 (另一个终端):
journalctl -u tofd -f
```

运行时不需要 overlay 之外的任何东西: I2C3 由音频 overlay 已经使能。

## 与 robotd 的关系

`mediad` 和 `tofd` 是独立 daemon, robotd 不直接依赖它们。上游 runtime 的 `route.rs` 在本 Feetech 分支已适配新增的总线状态调用 (只读放行, 写总线动作拒绝), 所以本仓补丁里的 mediad 与 robotd 是配套版本, 不要混用上游原版 mediad。
