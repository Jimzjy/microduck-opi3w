# 硬件目录

只收**改动**与移植文档: HAT 用 kissqy 衍生版 (我们自己精简过), IMU 板原样沿用 replica 的 v2。

## 内容

| 路径 | 内容 |
| --- | --- |
| `pinmap.md` | HAT-V5 信号 → A733 40-pin 重映射对照表 (含 DXL 走 11/13 的 uart2, I2S0 五脚) |
| `hat-layout.md` | HAT 逐区说明: 电源, 音频, DXL 总线, ToF, 排针; 以及每处改动的理由 |
| `imu-layout.md` | IMU 板: 连接器脚序, 电源, 数据通路, MCU 引脚, 固件来源 |
| `overlay/` | A733 设备树 overlay: `uart2-dxl.dts` (打开 uart2 PB0/PB1 → 排针 11/13), `audio-a733.dts` (aic31xx 声卡) |
| `eda/HAT_REVA_SCH_OPI3W.eprj2` | HAT 原理图工程 (EasyEDA Pro), REV B, 已送厂。**本仓唯一自有的 EDA 工程** |
| `datasheets/` | 厂商原始文档存档: 飞特 HD-1910-C001 规格书, Orange Pi Zero 3W 手册/原理图/位号图/DXF (含 SHA256 与用途说明, 见其 README) |

IMU 板 / POGO 电池连接板**不在本仓**: 原样沿用 replica 的设计, 未做任何修改, 工程文件用
[fanhao375/microduck-replica](https://github.com/fanhao375/microduck-replica) 仓里的
`hardware/新版/imu_to_dxl_1V0A / POGO_PIN_1V0A` (IMU 板的固件也在同仓库:
`hardware/新版/imu_to_dxl_1V0A/firmware-1.0.0/Build/imu_to_dxl.hex`, 烧录说明见
[imu-layout.md](imu-layout.md) §5)。POGO 板是电池的顶针接触连接板。
要改这两块板, clone replica 仓改它的工程。
**注意: replica 的 wire_hub (总线 HUB) 板有正负极短路缺陷 (打板前未过 DRC), 勿照它打板;
本项目不做 HUB, 电池直接插 HAT 的 J13/J14。**

## HAT 供电定案

`U11` 两脚螺钉端子接外部 5V → `Q2` (AO3401A) 反接保护 → `Q3/Q4` 分立理想二极管 (调试时 USB-C
与外部 5V 同时接不倒灌) → `5V` 单一母线 (SoC/偏置/功放共用) → `D1` SMAJ5.0A 钳位。buck, PTC,
旧理想二极管全部删除。舵机串不经 5V 母线: 电池直接接在 J13/J14 总线座上给舵机供电 (座脚序
1=数据 / 2=电池+ / 3=GND), 不需要独立的 HUB 板。

逐条改动与理由见 [hat-layout.md](hat-layout.md)。

## 注意

- EDA 工程的自动备份 (`*_backup/`), `.epro2` 与 `.bak` 不入库 (见根目录 `.gitignore`)。
- EDA 里改完记得 **Ctrl+S**; `.eprj2` 是二进制工程包, 直接提交即可。
- 上游参考 (在 `firmware/` 子模块内): `hardware/IMU-FIRMWARE.md` (IMU 烧录),
  `docs/ASSEMBLY-NOTES.md` (装配注意)。**例外**: `hardware/AMP2.0-VERSION.md` 里 HAT J13/J14 的
  脚序 (GND / BATT_IN / DXL_DATA) 是 kissqy 原版, 我们已改成 1=数据 / 2=V+ / 3=GND,
  以本仓 [imu-layout.md](imu-layout.md) 为准。
