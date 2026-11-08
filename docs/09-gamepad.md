# 09 · 蓝牙手柄 (padd)

目标是让鸭子自己读手柄：手柄和板子配对，板上 `padd` 守护进程把按键转成 intent 发给 `robotd`。
不经过电脑、不经过 UDP 手柄 (`netpadd`)。2026-11-08 用 Xbox One S 手柄实测通过。

## 1. 它由哪几块组成

| 组件 | 作用 | 我们的位置 |
| --- | --- | --- |
| BlueZ + `bluetooth.service` | 配对、连接、HID | 底图自带 5.82，芯片 `aic8800` |
| `padd` | 读 `/dev/input`，把按键/摇杆变成 `robotd` 的 intent | `/usr/local/bin/padd` + `scripts/padd.service` |
| `robotd` | 收 intent，真正驱动伺服 | `/usr/local/bin/robotd` |
| `configd` | Studio 手柄页与 `robotctl pad pair` 的后端 (可选) | **未装**：直连不需要它，Studio 的手柄页读不到状态 |

`padd` 不在系统镜像里 (镜像只带 `robotd`/`robotctl`/`mediad`/`tofd`)，要单独编、单独装。
装好之后它是开机服务，重启板子自动起来，手柄 trust 过就会自动回连。

## 2. 编 padd

```bash
# WSL / Debian，先有一次 scripts/cross-sysroot.sh 生成的 sysroot (含 libudev-dev)
bash scripts/build-padd.sh
# 产物: runtime/target/aarch64-unknown-linux-gnu/release/padd  (~5.6 MB)
```

依赖 `gilrs 0.11` → `libudev`，所以 sysroot 里必须有 `libudev.pc` 与 `libudev.so`；
链接时会警告 `libcap.so.2, needed by libudev.so, not found`，这是传递依赖、运行期由 systemd 自带满足，可以忽略。

## 3. 装 padd

```bash
bash scripts/deploy-padd.sh ~/.../release/padd scripts/padd.service
```

脚本做六件事，都是幂等的：

1. `robotd.service` 加 `Group=robot` —— `/run/robotd.sock` 是 `0660 root:robot`，`padd` 不加这个组连不上；
   这次运行不重启 robotd，先 `chgrp robot /run/robotd.sock` 顶上。
2. 建 `padd` 用户（`/usr/lib/sysusers.d/padd.conf` → `systemd-sysusers`）。
3. 装二进制与 unit，`daemon-reload`。
4. `/etc/robot/robotd.toml` 里 `[netpad] enabled = false` —— `padd --should-run` 读这个开关，
   为 `true` 时它主动退出，把手柄让给 `netpadd`。板上如果还留着 `/usr/local/bin/netpadd`，
   记得别同时把 `netpad` 打开。
5. `enable` + `restart padd`。
6. 备份：`robotd.service.bak-padd`、`robotd.toml.bak-padd`。

健康检查：

```bash
systemctl status padd --no-pager
journalctl -u padd -n 20 --no-pager -o cat
ls -l /run/padd/            # identity.json + pad.sock
```

起来时应看到 `pad connected — driving` 与 `socket=/run/robotd.sock hz=50`。

## 4. 配手柄（顺序很关键）

```bash
bash scripts/pair-gamepad.sh EC:83:50:7C:B5:EC B4:65:DC:91:6E:00   # <手柄MAC> <适配器MAC>
```

这个脚本把「发现 + 配对」放进**同一个 `bluetoothctl` 会话**：扫描出来的设备在 `scan off`
之后就不在缓存里了，单独 `connect` 会报 `Device ... not available`；而且连接前必须先停
discovery，否则 `Connect()` 会间歇失败。

顺序按手柄类型分：

- **BR/EDR（经典蓝牙）**：Xbox One S (`Modalias usb:v045Ep02FDd…`)、DualSense、无名 Pro Controller
  → `pair` → `trust` → `connect`。
- **LE**：Xbox Series 那一类 → `connect` → `trust`，先 `Pair()` 会 `AuthenticationCanceled`。

先 `connect` 的经典手柄会留下**假配对**：`Paired: yes` 但 `Bonded: no`，bond 文件里没有任何 key，
`/dev/input` 里永远不出现 `js0`，`bluetoothd` 日志是：

```
profiles/input/device.c:hidp_add_connection() Rejected connection from !bonded device /org/bluez/hci0/dev_XX
```

补救：`bluetoothctl remove <MAC>`，让手柄重新进配对模式，再跑一遍脚本。

`trust` 是必须的：不 trust，重启后没人批准，手柄不会自动连回来。

## 5. 实测记录（2026-11-08）

- 板载蓝牙可用：`hci0` = `B4:65:DC:91:6E:00`，BlueZ 5.82，`aic8800-bluetooth.service` running。
- 配对成功后：`Paired/Bonded/Trusted/Connected` 全 yes，`/var/lib/bluetooth/…/<MAC>/info` 338 B（含 key），
  `/dev/input/` 出现 `event2 event3 js0`。
- `padd` 日志：`pad connected — driving`、`socket=/run/robotd.sock hz=50`；按 Start 后 `robotd` 的
  `robot.init: torque on, ramping to the home pose`。
- gilrs 有一条无害警告：`SDL-mapping ... Xbox One Controller: Unknown button b16`（某个按钮索引超出内置表）。

## 6. 键位（官方 runtime 的映射）

| 按键 | 动作 |
| --- | --- |
| Start 短按 | 站起 / 切换策略（`robot.enable` 的 toggle） |
| Start 按住 1.5 s | 回 HOME 姿态 |
| A | 坐 / 起 |
| B | 地面拾取 |
| RT / LT | 张嘴（扳机模拟量） |
| D-pad 上 / 右 / 左 / 下 | 头部上抬 / 头部+转身 / 平移 / 身体+头 |
| 左摇杆 | 走（`vx` ±0.4，`vy` ±0.3） |
| 右摇杆 | 转（`vyaw` ±1.0） |
| **Select 短按** | **什么都不做**（只写一行日志 `Select tapped — hold it 2 s to rest…`） |
| **Select 按住 2 s 后松开** | `robot.rest`：先坐下、进 rest 姿态，再关扭矩并重启 15 颗舵机 |
| **Select 按住 4 s** | `robot.shutdown`：关机 |

映射在 `runtime/pad-map/src/mapper.rs:357-389`：注释第一句就是 "Select: nothing on a tap."

## 7. 和 replica Studio 的「测急停」对不上

Studio 手柄页有一张急停验收卡（`microduck-replica/software/studio/web/pad.js` 的 `TEST_STEPS`），
它要求「**短按**一下 Select」，然后读回扭矩应为关。这个口径来自 replica 自己的文档
(`software/image/烧录和第一次使用.md`：「Select 短按 → 马上卸力（急停）」)，replica 的 padd 在
松开 Select 时直接发 `robot.relax`。

官方 runtime 的 padd 不是这样：短按无动作，2 s 才 `rest`。两者都自洽，只是不是同一套。
**我们在 A733 上保留官方映射**（2026-11-08 用户决定），所以：

- Studio 那张卡会一直报 `× 松开 Select 6 秒了，回读扭矩还没关` —— 这是口径差异，不是故障；
- 鸭子身上**没有一键急停**。要立即卸力用网页右上角的「卸力」按钮，或按住 Select 2 s
  （但它会先坐下、要几秒钟，不能当急停用）。

如果哪天真要补，改动只有一处：`mapper.rs:378` 的 `HoldAction::Tap` 分支里加
`out.push(Out::Request(proto::Call::RobotRelax))` —— `robotd` 的 `RobotRelax` 是"永不拒绝、
立刻卸力"（`robotd/src/main.rs:6496-6501`），重编 padd 约 40 秒。

## 8. 排错

| 现象 | 原因 / 处理 |
| --- | --- |
| `padd` 起来后立刻退出 | `[netpad] enabled = true`；改成 false 再 `systemctl restart padd` |
| `Failed to connect: org.bluez.Error.Failed` / socket 权限 | `robotd.service` 缺 `Group=robot`，或没 `chgrp robot /run/robotd.sock` |
| 配对显示成功但 `/dev/input` 没有 `js0` | 假配对（`Bonded: no`），按第 4 节 remove 后重配 |
| `Device ... not available` | 扫描与连接不在同一个 bluetoothctl 会话 |
| 重启后手柄不回来 | 没 `trust`；`bluetoothctl info <MAC>` 看 `Trusted` |
| 日志 `Unknown button b16` | gilrs 内置映射表没有这个按钮，无害 |
| Studio 手柄页读不到手柄 | 没装 `configd`（直连不需要它）；Studio 只有 `padd` 旁路能看按键 |
