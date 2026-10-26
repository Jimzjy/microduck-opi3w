# 硬件目录

只收**改动**与移植文档：HAT 用 kissqy 衍生版（我们自己精简过），IMU 板原样沿用。

## 内容

| 路径 | 内容 |
| --- | --- |
| `pinmap.md` | HAT-V5 信号 → A733 40-pin 重映射对照表（含 DXL 走 11/13 的 uart2、I2S0 五脚） |
| `hat-layout.md` | HAT 逐区说明：电源、音频、DXL 总线、ToF、排针；含每轮删除/修改记录与「当前状态」 |
| `imu-layout.md` | IMU 板接口（DXL ID 200、TWI1、供电） |
| `overlay/uart2-dxl.dts` | 打开 uart2（PB0/PB1 → 排针 11/13）的设备树 overlay |
| `eda/HAT_REVA_SCH.eprj2` | HAT 原理图工程（EasyEDA Pro），REV B |
| `eda/imu_to_dxl_RevA_V1.eprj2` | IMU 板原理图工程（来自 kissqy，未改） |
| `datasheets/` | 厂商原始文档存档：飞特 HD-1910-C001 规格书、Orange Pi Zero 3W 手册/原理图/位号图/DXF（含 SHA256 与用途说明，见其 README） |

## HAT 现状（截至本轮）

63 器件（含图纸框，实贴 62）/ 192 导线 / 35 网络；DRC **0 error / 3 warning**（器件标准化建议、
悬空脚加 NC 建议，都不影响打样）。相对 kissqy 原版净省 24 颗贴片（另加了反接保护 Q2 + 下拉 R36）。

供电已定案：`U11` 两脚螺钉端子接外部 5V → `Q2`（AO3401A）反接保护 → `5V` 单一母线
（SoC/偏置/功放共用）→ `D1` SMAJ5.0A 钳位；原双路 2A PTC（F1/F2）已删（2026-10-26）；
buck、理想二极管、BATT_IN 全部删除，电池另走独立 HUB 板。

## 注意

- EDA 工程的自动备份（`*_backup/`）与 `.bak` 已移到仓外
  `C:/Users/JC/.dsh/bot/workspace/microduck-opi3w-backup-eda/`，不随仓库分发。
- EDA 里改完记得 **Ctrl+S**；`.eprj2` 是二进制工程包，直接提交即可。
- 上游参考（在 `firmware/` 子模块内）：`hardware/AMP2.0-VERSION.md`（J13/J14 脚序）、
  `hardware/IMU-FIRMWARE.md`（IMU 烧录）、`docs/ASSEMBLY-NOTES.md`（装配注意）。
