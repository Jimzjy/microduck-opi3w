# 外部文档存档（datasheets）

这里只放**厂商/上游提供的原始文档**，作为设计核对的依据。我们自己的结论、推算和取舍一律写在 `docs/` 与 `hardware/*.md`，不写进这个目录。

## 清单

| 文件 | 内容 | 大小 | 原始文件名 |
|---|---|---|---|
| `Feetech_HD-1910-C001_spec_A0.pdf` | 深圳飞特 **HD-1910-C001** 产品规格书（EDITION A/0）：HD1910M，6V，12kg·cm，TTL 串口，360°，磁编码双轴，金属齿，AMP 端子 | 4.66 MB | `icoss199515806373041e7b5856c2a5.pdf`（WPS 导出，2026-09-07） |
| `OrangePi_Zero3W_A733_user-manual_v1.0.pdf` | Orange Pi Zero 3W（A733）用户手册 v1.0：接口定义、40Pin 排针、系统与镜像、串口/I2C/I2S 使用说明 | 15.9 MB | `OrangePi_Zero3W_A733_用户手册_v1.0.pdf` |
| `OrangePi_Zero3W_V1.2_schematic.pdf` | Zero 3W V1.2 原理图（官方）：排针每脚接到 SoC 的具体球号、电源树 | 1.08 MB | `OPI ZERO 3W V1_2_原理图.pdf` |
| `OrangePi_Zero3W_V1.2_placement.pdf` | Zero 3W V1.2 位号图（官方）：板面元件定位 | 0.29 MB | `OPi_ZERO_3W_V1_2-位号图.pdf` |
| `OrangePi_Zero3W_V1.2_TOP.dxf` | 板子顶面机械图（板框、开孔、连接器位置） | 0.45 MB | `OPi ZERO 3W V1_2_TOP.dxf` |
| `OrangePi_Zero3W_V1.2_BOT.dxf` | 板子底面机械图 | 1.45 MB | `OPi ZERO 3W V1_2_BOT.dxf` |

SHA256（用于确认拿到的是同一份）：

```
aafd3b6a03f4902f74164bf49091d88c01418b12ddf7d5f8118cbc763f03f9a9  Feetech_HD-1910-C001_spec_A0.pdf
37700b90b522238bfe5b9cdb67b891512f2f2d9387d4e9dbcf4a1aa6e6c360fe  OrangePi_Zero3W_A733_user-manual_v1.0.pdf
4e0e92afbb1cca97a9c8593b8f2679178d9738f242ea431ed3650e893fe28ed0  OrangePi_Zero3W_V1.2_schematic.pdf
3b85fb61ab9ad949519fa3392b8bc73a9e846d50de14ca02dcbebc2e0736532c  OrangePi_Zero3W_V1.2_placement.pdf
fa18db454d5d6298c944e02f342441afd7a2a60bf636147234f8c3cfcb13ef26  OrangePi_Zero3W_V1.2_TOP.dxf
8086e504d24f4799b191336247cf4015760115485e58d8620816f6e700186cdd  OrangePi_Zero3W_V1.2_BOT.dxf
```

## 这些文档在项目里被用来核对什么

- **HD-1910 规格书**：确认舵机电气与机械规格（6V、12kg·cm、TTL 半双工、AMP 端子针脚 1=Signal / 2=Vcc / 3=GND），是 HAT 把 J13/J14 改成飞特线序、以及总线电平/限流设计的依据；也用来判断电池电压范围与堵转电流。
- **Zero 3W 用户手册**：排针功能、镜像与串口 console 用法、I2C/I2S/UART 的启用方式；和 `hardware/pinmap.md`、`docs/01-port-plan.md` 相互印证。
- **Zero 3W V1.2 原理图**：确定每个物理排针脚最终落到 SoC 的哪一路（3V3/5V 从 PMIC 来、GND 分布、40Pin 与 SoC 球号对应），是 overlay（`hardware/overlay/uart2-dxl.dts`）引脚选择的最终依据。
- **位号图 / DXF**：机械核对——板框尺寸、开孔位置、40Pin 排母相对板边的偏移，用来判断 HAT 装到 Pi 上后 J4 的焊盘位置对不对、外壳开孔够不够。

## 注意

1. **版权归各自厂商**（深圳飞特模型有限公司；Orange Pi / 深圳市讯龙）。本仓库只是个人自用存档，方便离线核对；若要公开分发本仓库，请自行确认这些文档的再分发许可，或改成链接到官方下载页。
2. 规格书是 WPS 导出的**矢量绘制页**，页内文字不是可检索文本（`pdftotext` 之类的工具取不到文字）。需要查某一页时，把页面渲染成图片看即可。
3. 文档版本已在文件名里标死（`A0`、`v1.0`、`V1.2`）。厂商若出新版，**新增文件而不是覆盖**，这样历史结论还能对上当时依据的版本。
