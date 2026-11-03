# 08 摄像头与 ToF

这两个外设都在上游 Microduck 的软件栈里: 摄像头走 `mediad` (WebRTC 视频), ToF 走 `tofd` (8x8 距离阵列)。本页写它们在 A733 + 本 HAT 上的适配方式。

物料:

| 项 | 器件 | 状态 |
|---|---|---|
| 摄像头 | IMX219 模组 (Raspberry Pi camera v2 兼容, 排线 CSI), 上游购物清单同款 160 度广角 | 未实测, 需板上验证 |
| ToF | VL53L5CX (VL53L5X V2) 模组, I2C 地址 0x29, 接 HAT 的 H1 排针 | 未实测, 需板上验证 |

## 摄像头

### 结论: 不需要 overlay

A733 的原厂设备树 (`sun60i-a733-orangepi-zero3w.dtb`) 已经把 IMX219 配好并使能:

- `sensor0_mname = "imx219"`, `status = "okay"`, I2C 地址 0x10, MCLK 1
- `csi@5820000` / `mipi@5810100` / `vinc@5830000` 全部 `okay`

摄像头走的是主控板自带的 CSI 相机座和专用 CCI 控制器, 与 HAT 的 40 排针和 I2C3 (codec/ToF 共用) 无关。内核模块 `imx219.ko` / `vin_v4l2.ko` 在镜像里都有 (vendor 内核 `kernel/bsp/drivers/vin/`)。

排线直接插主控板上的 FPC 座即可。首次验证 (板子在线后):

```
v4l2-ctl --list-devices
dmesg | grep -iE 'imx219|vin'
```

### mediad (视频流)

`mediad` 从 CSI 读流并经 WebRTC 推给浏览器, 依赖三层:

1. **GStreamer 运行时** (apt): `gstreamer1.0-plugins-bad` (webrtcbin), `gstreamer1.0-nice`。上游 `scripts/setup-gstreamer.sh` 负责安装, 版本基线见上游 `docs/project/media-bringup.md`。
2. **webrtcsink**: 属于 gst-plugins-rs, Debian 没有包, 要用 cargo-c 从源码构建, 装到 `/usr/local/lib/gstreamer-1.0` 并在 service 里加 `Environment=GST_PLUGIN_PATH=/usr/local/lib/gstreamer-1.0`。版本要 >= 0.14.5 (含 webrtcsink 死锁修复), 上游用 0.15.3。
3. **mediad 二进制**: 本仓不预编译分发, 交叉编译方法见 docs/05。

A733 侧的硬件编码器 (Radxa 路线用的 mpph264enc 是 RK 专属) 尚未验证; 全志 ve 硬件编码在 vendor 内核里有 bsp 驱动, GStreamer 插件是否存在要板上确认。没有硬件编码器时 webrtcsink 会退到软件 x264, 1GB 内存版可能吃紧。

安装顺序 (板子在线后):

```
sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-nice
# 构建 gst-plugins-rs 的 webrtcsink (见上游 setup-gstreamer.sh)
sudo /usr/local/bin/mediad --rotate 90
```

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
