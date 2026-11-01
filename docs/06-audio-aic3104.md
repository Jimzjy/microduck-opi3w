# 音频: TLV320AIC3104 + PAM8406

HAT 上的音频是一颗 AIC3104 codec 加一颗 PAM8406 D 类功放, 走 A733 的 I2S0, I2C 用 twi0。
这一页写清楚接法, 驱动与设备树要点, mixer 该设成什么, 以及几个会让人误判成「硬件坏了」的坑。

## 1. 硬件通路

codec U2 = TLV320AIC3104IRHBR (HVQFN-32, LCSC C181753), I2C 地址 `0x18`, I2S 侧做从机。

| codec 引脚 | 信号 | 排针 | SoC |
| --- | --- | --- | --- |
| U2-1 MCLK | `I2S0_MCLK` | 7 | PB4 |
| U2-2 BCLK | `I2S0_BCLK` | 12 | PB5 |
| U2-3 WCLK | `I2S0_LRCK` | 35 | PB6 |
| U2-4 DIN (codec 收) | `I2S0_DOUT` | 40 | PB7 |
| U2-5 DOUT (codec 发) | `I2S0_DIN` | 38 | PB8 |
| U2-8 SCL / U2-9 SDA | `twi0` | — | PB2 / PB3 |

注意 J4 焊盘号与排针号整体错一位 (奇数焊盘 = 排针号 + 1, 偶数焊盘 = 排针号 − 1), 所以原理图上
`I2S0_DIN` 落在 J4-37 = 排针 38, 是正确接法。

**麦克风输入** (两颗 2 线驻极体, 双麦单声道):

```
J2(左) 偏置脚 ── R22 10k ── 5V, C44 470pF 去耦
       信号脚 ── C41 1µF ── U2-10 (MIC1LP)
J9(右) 偏置脚 ── R23 10k ── 5V, C45 470pF 去耦
       信号脚 ── C40 1µF ── U2-12 (MIC1RP)
```

组装时**胶囊与外壳相通的那一脚接 GND**, 另一脚接偏置脚。装上后偏置脚应在 2–3 V; 一直是 5 V
说明胶囊没导通 (接反或坏件)。

**输出** (单声道): `U2-29 RIGHT_LOP` → C2 → R2 10k → PAM8406 `INR` → 喇叭 (3525, 4Ω 3W)。
左声道整条已在 HAT 上删除。

## 2. 驱动

厂商内核**没有**编 `CONFIG_SND_SOC_TLV320AIC3X`, 要 out-of-tree 出 `snd-aic3x.ko`, 源码与步骤见
[aic3x-module/README.md](../scripts/aic3x-module/README.md)。

**不要用 `snd-soc-tlv320aic31xx`**: 那是 AIC3100/3110 家族, Page 0 寄存器语义不同, 装上后 codec 能
绑定、能读寄存器, 但 DAC 永远不会上电, 喇叭一点声音都没有。

Overlay 见 [hardware/overlay/audio-a733.dts](../hardware/overlay/audio-a733.dts), 四个要点:

- `compatible = "ti,tlv320aic3104"`, 节点挂在 twi0 下 (`clock-frequency = <400000>`, 地址 `0x18`)
- AVDD/DVDD/IOVDD/DRVDD 四路 `*-supply` 用 `regulator-fixed` 顶上 (不接 regulator 框架时不给会绑定失败)
- `soundcard-mach,slot-num = <2>` —— **必须是 2**。底图默认 4, ASoC core 会生成 4 bit 的 slot mask,
  而 aic3x 只接受两个相邻 bit, 结果是 `set_tdm_slot` 返回 `-EINVAL`, 声卡注册失败
- `soundcard-mach,codec { sound-dai = <&aic3104>; }` 把空的 codec 子节点接到 codec

装上后应有 `card 1: aic3104hat`:

```bash
aplay -l | grep -i aic3104
ls /sys/bus/i2c/drivers/tlv320aic3x/      # 0-0018
```

## 3. mixer

默认值不能直接用, 所以有一个开机服务把所有必要控件设一遍:
[aic3104-mixer.sh](../scripts/aic3104-mixer.sh) + [aic3104-mixer.service](../scripts/aic3104-mixer.service)。
`setup-board-a733.sh` 会装它们并 `enable`; 手工安装就是把两个文件拷到
`/usr/local/bin/aic3104-mixer.sh` 和 `/etc/systemd/system/aic3104-mixer.service`,
`systemctl enable --now aic3104-mixer`。

| 控件 | 值 | 为什么 |
| --- | --- | --- |
| `PGA Capture Switch` | `on,on` | 上电是静音的, 不解除则录音只有噪声底 |
| `PGA Capture Volume` | `40` (+20 dB) | 4015 胶囊输出只有 mV 级 |
| `Left/Right PGA Mixer Line1L/Line1R/Mic2L` | `on` | 两颗麦都混进两个声道 (双麦单声道) |
| `Right PGA Mixer Line1L` | **必须 `on`** | 关掉它整条采集会退化成数字乱码 (DAPM 依赖) |
| `Line Mixer DACL1/DACR1` `Line DAC` `HP DAC` `HPCOM DAC` | `100%` | **上电是 6, 即 -56 dB**, 不改就是「喇叭几乎没声音」 |
| `* PGA Bypass` | `off` | 模拟旁路不进混音器, 免噪声与回授 |
| `Line` | `9` + `on` | 线路输出这一级 |
| `PCM` | `60` (-33.5 dB) | 功放很响且喇叭离耳朵近, 默认压住; 范围 0–127, 127 = 0 dB |

这些控件名都能用, 但 `amixer sset 'PGA Capture Switch' on` 会报 "Unable to find simple control",
`numid` 写法一定可用 (`amixer -c aic3104hat cget numid=43`)。

## 4. 验收

```bash
# 声卡与增益
aplay -l | grep -i aic3104
amixer -c aic3104hat cget numid=11        # 期望 118 [100%] [0.00dB] [on]

# 放音 (先小音量)
aplay -D hw:1,0 -f S16_LE -r 48000 -c 2 some.wav

# 录音自检 (一条命令, 不需要人对着麦说话)
python3 scripts/mic-selftest.py --vol 90 --amp 12000
```

自检会播一条不中断的音调流、同时录音, 用窄带 Goertzel 判麦克风有没有拾到。期望:

```
750 Hz   silence 1.548 -> tone 39.855   ratio 25.74
1500 Hz  silence 2.233 -> tone 72.963   ratio 32.68
RESULT: MICROPHONE PICKS UP SOUND
```

判据是 `ratio > 3` 且音调段幅值 `> 20`。`NO PICKUP` 时先查第 3 节的 `numid=11` 有没有到 118。

## 5. 会误判成硬件故障的坑

| 现象 | 真正原因 |
| --- | --- |
| 喇叭「能听到一点点, 像杂音」 | DAC→Line Mixer 增益停在 6 = -56 dB |
| 改 PGA 增益/静音, 录音电平一点不变 | AGC 默认开着, 它接管增益, PGA 被绕过 (链是 PGA→AGC→ADC) |
| 关掉 AGC 后录音变精确 0 | AGC 一关, ADC 约 1–2 s 后自己掉电; 重开流即恢复, 所以不能靠关 AGC 做线性增益扫描 |
| 放音一结束, 录音立刻变精确 0 且不恢复 | 功放/codec 的 DAPM 一起拆了; 声学自测必须用**一条不中断**的播放流 (静音→音调→静音写进同一个 raw) |
| 开流前写 codec 寄存器的实验全无效果 | 驱动开流时会重写 `0x13`/`0x16`; **寄存器实验必须在流内写并当场回读** |
| 换 24k/16k/8k 采样率后数据完全变形 | 这些采样率下 codec 没被正确重配; 固定用 48 kHz |
| `pkill -f "arecord ..."` 之后 SSH 断了 | 模式匹配把远程 shell 也杀了, 用 `pkill -x arecord` |

第 5 节这些坑里, 「录音全零」和「拾不到声音」曾经把排查带向 U2 第 5 脚焊接、C40/C41 耦合电容、
麦座极性等硬件方向。三条实测可以一次性排除:

1. **SoC 读的就是 codec**: 流内把 `0x13/0x16` 的 bit2 清掉 (ADC 掉电) → 录音精确归零, 写回立刻恢复;
   把接口模式从 I2S 改成右对齐/DSP/左对齐 → 数据跟着变。悬空线不会这样配合。
2. **麦克风那一路是接通的**: 把左 ADC 分别接到麦克风脚 (U2-10)、板内接地的 Mic2L (U2-14)、
   悬空的 Mic2R (U2-16), 三档电平明显不同 (约 530 / 几十 / 230), 说明耦合电容与引脚都在通路上。
3. **确实是喇叭太小声**: 增益修好后同一套自检从 `ratio 1.58` 变成 `25.7`。

## 6. 上电啪一声

浪涌来自功放输入电容充电 + codec 的 DAC 比功放晚上电, PAM8406 的常见现象, 与麦克风通路无关。
