# 10 · 站立与行走：策略 + 舵机增益

这只鸭子最终是怎么站住、走起来的。**先读第 3 节**——三个和 HD-1910 有关的寄存器事实，是我们花了一整天才
试出来的；不知道它们，后面所有参数都会被误读成「调不动」。

## 1. 现在能做什么（实测数字）

策略用 kissqy 发布包里的两个网络（`kq_walk.onnx` 走 / `kq_sitstand.onnx` 坐起），跑在我们的运行时上：

| 场景 | 结果 |
| --- | --- |
| 站立（零命令，walk 模型） | 连续 14.6 s，看门狗未触发；腿电流均值 4217 mA、纹波 267 mA、峰值 4998 mA；陀螺仪均值 0.01 / 最大 0.17 rad/s；目标步长 0.0058 rad/拍；跟踪误差 ≤ 0.15 rad |
| 直走 `vx = 0.2 m/s` | 6 s 走 0.454 m（0.072 m/s）；10 s 走 0.735 m（0.074 m/s）；全程躯干重力 z ≈ −1.00 |
| 步态是不是真的 | 左膝目标 −0.49…+0.58、右膝 +0.02…+0.81 rad，左右相关系数 0.34，踝 ±0.15 rad 交替——是迈步，不是原地抖 |
| 手柄 | Xbox One S 经 `padd` 驱动同上（[docs/09](09-gamepad.md)） |

速度低于命令值（0.074 vs 0.2 m/s）有两个已知原因：策略本身没走到满速，以及我们每拍的记录里包含了起步/收尾
的慢速段。要更接近上限，发 `|vx|` 到 0.3–0.4 试。

## 2. 怎么跑一次

板上就位（模型、标定、`[policy]` 配置见 [04](04-quickstart.md) §5 / [05](05-bringup-runbook.md) §6），然后：

```bash
# 1) 上扭矩，走到 home 姿态（坐着的鸭子会先坐到座位再起身，约 2 s）
robotctl robot init

# 2) 交给策略。日志里 policy 从 held 变成 walk
robotctl robot enable

# 3) 发速度意图。robot.move 是 deadman：500 ms 内不刷新就归零，所以要循环发
python3 scripts/walk-drive.py 0.2 0 0 10      # vx=0.2, vy=0, vyaw=0, 10 秒
```

`scripts/walk-drive.py` 直接用 `/run/robotd.sock` 发 `robot.move` notification（连续意图用无 id 的
notification，见 `duck-ipc-proto/src/lib.rs`），不依赖手柄、也不依赖 `netpadd`。

看状态用 `robotctl monitor`：`policy`（held/walk/sit/limp…）、`safety.gravity`（竖直时 z ≈ −1）、
`safety.fallen`、`joints`/`targets`（跟踪误差）、`currents_ma`、`odom.position`/`odom.yaw`。

## 3. 三个硬件事实（不知道就会白调一天）

### 3.1 HD-1910 真正的 P/D 在寄存器 50/51，不是 21/22

| 寄存器 | 是什么 | 出厂值 |
| --- | --- | --- |
| 21 / 22 / 23 | STS 表的 P / D / I。HD-1910 **能写、能读回，但不影响位置环** | 影子 |
| **50 / 51 / 52** | **位置环真正的 P / D / I** | **32 / 40 / 0** |
| 40 | 扭矩使能 | 0 |
| 42 | 目标位置 | — |
| 46 / 47 | 目标速度 | 0 |
| 48 / 49 | 转矩限制 | 1000 |
| 55 | 锁（EEPROM 写保护） | 出厂是关着的（锁定） |

证据：逐字节扫寄存器 + 单变量实测。只写 21 时关节刚度完全没有变化（用户的原话是「你真的把电机的刚性
调下来了吗？为什么在我看来根本没有区别」），写 50=5 后陀螺仪 rms 从 0.43 掉到 0.02 rad/s、电流纹波从
1896 掉到 335 mA。

`set_gain` 现在**两张表都写**：21 保留（兼容 STS 系列），50/51 必写。都是 RAM 写（55 保持锁着），
所以断电回 32/40，上力时重新写——这也是为什么冷启动的第一秒关节是「硬」的，`robotctl robot init`
之后才软下来。

### 3.2 速度寄存器的一格是 50 步/秒，不是 1

`read_speed_unit` 原来把 fine 档当成 1 步/秒每格，读出来的速度只有真值的 **1/50**（鸭子自由倒下时位置差分算
0.209 rad/s、寄存器报 0.0046 rad/s，比值 0.02，相关系数 0.87）。策略的关节速度通道等于没有，阻尼失效，
表现就是 4–7 Hz 的小幅自激——**这时候怎么调 P、D、低通、限速都只是改幅度**。

kissqy 的固件把这个常量写死成 50（`SPEED_RAD_S_PER_COUNT = 50 * TAU / 4096`），我们照他的口径改。

### 3.3 速度要延后一拍再进观测

训练合同是 `delay_min_lag = 1`（策略看到的是上一拍的关节速度）。我们把 reported 速度缓存一拍再喂进 obs；
不延后实测更糟（腿电流 4742 → 5952 mA、偏航 rms 0.32 → 0.42）。

## 4. 最终参数

`/etc/robot/robotd.toml` 里只留**偏离默认值**的项（其余按官方注释的默认值走）：

| 项 | 值 | 为什么 |
| --- | --- | --- |
| `[bus] protocol` | `"feetech-sts"` | HD-1910 走飞特 STS 协议 |
| `[bus.feetech] p_scale` | `0.025` | `gain 200 × 0.025 = P 5`，kissqy 真机在用的一档 |
| `[bus.feetech] directions` | `[1 ×15]` | 兜底；实际由标定文件的 `direction = -1` 覆盖 |
| `[policy] walk` / `sitstand` | `kq_walk.onnx` / `kq_sitstand.onnx` | kissqy 的发布包，61 输入 / 14 输出，加载时校验 |
| `[policy] action_scale` | `1.0` | 他 `deployment-execution.json` 的实测值（ONNX 元数据写 1.0，训练默认另算） |

**没有**设的（都是默认）：`head_lowpass = 0.5`、`legs_lowpass = 0.7`（训练值，默认就是它们）、
`velocity_source = reported`（默认）、`max_target_speed`（不设＝不限速）、`gyro_lowpass_hz`（不设）、
`gain = 200`、`hz = 50`。D 由代码固定写 0。

## 5. 试过、确认没用的（省你时间）

| 试的 | 结果 |
| --- | --- |
| 限速 `max_target_speed = 0.8` | 走路时 **105/105 帧**都撞上限（未削顶的平均步长是上限的 4.2 倍），目标变成斜坡，鸭子 1.6 s 前扑。站着不撞上限，所以看不出害处。**走路必须不设** |
| 限速 0.5 / 0.35 / 0.25 | 只是把抖变小、变慢；0.25 时 12 s 后慢慢歪倒。限速是临时补丁，不是解 |
| 舵机 D = 20 | 更差（俯仰角速度 0.224 vs 0.198 rad/s，纹波 1673 vs 1511）→ D = 0 |
| 腿低通 0.4 | 抖动无变化（目标步长 0.0146 vs 0.0144） |
| P = 32 vs P = 5 | 修 50/51 之前两者没区别（因为写的是影子寄存器）；修好后 P=5 就是最终值 |
| 陀螺仪低通 8 Hz | 不需要；真正的自激源是 50/51 没写 |
| 差分速度（difference） | 幅值对但量化噪声大，比 reported 抖（俯仰 rms 0.250 vs 0.198） |

另外两条不是参数、但会骗人：

- **`hold-home` 是标定台架**，会在保持窗口内把目标钉成 home（`main.rs` 的 `bench_tick`）——用它「扶着站」
  测出来的稳定是假的，测策略别用。
- **调试线会扯鸭子**：直走 10 s 里偏航漂 1.85 rad 那次，最后判定是线被拉住了。测轨迹先给线留余量。

## 6. 标定前提

标定文件 `/etc/robot/feetech-ft5/hd1910-calibration.toml` 决定零位、方向和 IMU 安装四元数，
`robotd` 启动时会打 `calibration file loaded ... calibrated=true` 和 `directions from_calibration=true`。

**注意**：我们现在的 15 个关节全是 `zero_raw = 2048`、`direction = -1`，即「行程中点 = 零位」，这不是真标定
（kissqy 每颗舵机的 `zero_raw` 各不相同）。鸭子能站能走，但姿态不是按它的机械零位对的；真标定走
[04](04-quickstart.md) §6 的 Studio 流程。

## 7. 排错

| 现象 | 看哪里 |
| --- | --- |
| 关节很硬、一动就嗡嗡抖 | 50/51 是不是 32/40？`robotctl robot init` 之后再读一遍；断电后会回出厂值 |
| 抖得像报警器（4–7 Hz） | 速度通道是不是又被缩小 50 倍？日志应有 `servo speed unit phase=52 steps_per_count=50.0` |
| 目标每拍都在跳 0.1 rad 以上，关节跟不上 | 看 `targets` vs `joints` 的差；先确认没有设 `max_target_speed` |
| 一 enable 就前扑 | `safety.gravity` 在 enable 时是否 ≈ −1（没竖直就上电）；`policy` 标签是不是 walk 而不是 sit |
| 走两步就停 | `robot.move` 是 deadman，500 ms 没刷新就归零——循环要 ≥ 2 Hz |
| 站住但一直在原地蹭 | 先看 50/51 和速度单位；再看地垫/脚底是不是滑 |

