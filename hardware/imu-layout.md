# IMU-TO-DLX RevA 原理图：布局与要点（自工程预览图离线解析）

工程：hardware/eda/imu_to_dxl_RevA_V1.eprj2（2026-09-04 建，2026-10-15 更新；原理图 only，**有意未生成 PCB**）。标题栏：Schematic1 / Board1 / P1 / A4。

布局同样松散（kissqy 分区标题与实际器件有错位、重复标签多），按图归组：

## ① 左下：Dynamixel TTL 总线
- J1：DXL_BUS / CJT A2007WV 3P（AMP 2.0 系）——GND / DXL_VDD / DXL_DATA

## ② 左中：电源（DXL_VDD → 3V3）
- R1 0Ω：DXL_VDD → LDO_IN；C1/C2 4.7µF 25V（LDO_IN 侧）
- U3 TLV74233DBVR 3.3V LDO；C3 4.7µF 25V（3V3 侧）
- 去耦：C5 100nF（MCU）、C6 1µF（MCU）、C7 100nF（VDD_IO）、C8 100nF（VDD）、C9 1µF（IMU 本地）、C10 100nF（buffer）

## ③ 中央：MCU
- U1 **STM32G031F8P6**（TSSOP20）
- SWD：J2 SWD 1×5（3V3/SWDIO/GND/SWCLK/NRST）；R3 100k BOOT0 下拉；R2 10k NRST 上拉
- 调试灯：R7 1k → D2 DEBUG LED
- 引脚分配：PA11/PA12 → IMU_INT1；PA2 → DXL_TX；PA3 → DXL_RX；PA5–PA7 → IMU SPI（MOSI/MISO/SCK）；PA4 → IMU_CS

## ④ 右上：IMU
- U2 **LSM6DSV16XTR**（主 SPI）：SDO/SA0、SDX/AIIO1、SCX/AIIO2、CS、INT1/INT2、OCS_Aux1/Aux2（aux 通道未接器件）、Vdd_IO/Vdd 3V3；R4 10k IMU_CS 上拉

## ⑤ 右中：DXL 半双工缓冲
- U4 SN74LVC2G125DCUR：1OE = DXL_TX_EN（R5 10k 上拉到 3V3 = 缺省禁发）；DXL_TX → 1A；2Y → DXL_RX
- R6 330Ω 串联：DXL_TX_RAW → **DXL_DATA**
- D1 PESD5V0S1BA：DXL_DATA 对地 ESD 双向保护

## 注意
- 与 HAT 的方向切换（74LVC1G126/125 + 3906）不同：IMU 板用 **SN74LVC2G125 + TX_EN 软件控制**，烧 FT6 固件时 TX_EN 极性/时序要对
- 图中多处区块标题重复/与器件错位（"SWD + STARTUP STRAPS" 出现 4 次、"IMU — LSM6DSV16X PRIMARY SPI" 3 次），是排版乱，非电路重复
