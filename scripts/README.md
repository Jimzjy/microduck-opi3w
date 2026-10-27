# 脚本目录

本仓的两个「工具」脚本 + 板子到手后要写的部署脚本。

## 已有

| 文件 | 作用 |
| --- | --- |
| `eda-exec.ps1` | 把一段 JS 送进正在运行的 EasyEDA Pro 执行，返回 JSON。改原理图全靠它 |
| `eda-db-inspect.py` | 只读解析 `.eprj2`（zip 里的 JSON），列文件/结构，用于快速核对工程内容 |
| `eda-db-content.py` | 从 `.eprj2` 里提取某类对象（器件、网络、导线）的明细 |
| `fetch-studio.ps1` | 按固定 commit 稀疏拉取 replica 的 `software/studio`，可选推到板子上 |
| `setup-board-a733.sh` | A733 板侧 bring-up（在板子上跑）：uart2 overlay + ONNX Runtime + 音频 fail-soft（含 aic31xx 内核模块检查）+ 蓝牙手柄 + 板况报告。对照上游 `setup-board.sh`，去掉了全部 RK3566 专属步骤。用法见脚本头注释 |
| `apply-rootfs.sh` | 把 overlay dtbo + 板侧脚本 + firstboot 服务装进 Armbian 底图 img，可选 `--module <.ko>`（装进 /lib/modules 并 depmod）、`--payload <目录>`。在**带 /dev/loop 的 Linux**上跑（WSL2 不行）。用法见脚本头注释 |
| `build-aic31xx-module.sh` | out-of-tree 交叉编译 `snd-soc-tlv320aic31xx.ko`（A733 音频 codec 驱动，vendor 内核没编）。记录了 headers 包全部手工补丁（fixdep、modpost、utsrelease 回写）。在 WSL Debian（root）跑，用法见脚本头注释 |
| `aic31xx-build-aids/` | 上面脚本的配套留档：`arm64-tools-Makefile`（headers 缺的 kapi 生成器 Makefile）、`build-modpost-manual2.sh`（手工构建 kbuild modpost，含 devicetable-offsets.h 的 .s→.h 转换） |

## overlay 编译与验证（WSL，需要 dtc）

```bash
sudo apt-get install device-tree-compiler
cd hardware/overlay
dtc -@ -I dts -O dtb -o /tmp/uart2-dxl.dtbo uart2-dxl.dts
# 回归验证（不需要真实板子/内核）：
dtc -q -I dts -O dtb -o /tmp/stub.dtb uart2-dxl-applytest.dts
fdtoverlay -i /tmp/stub.dtb -o /tmp/applied.dtb /tmp/uart2-dxl.dtbo
fdtdump /tmp/applied.dtb | grep -A4 'uart@2502000'   # status 应为 "okay"
```

2026-10-27 实测：dtc 1.7.2 编译通过、fdtoverlay 应用后 status disabled→okay。
overlay 用 target-path 写法，**不依赖基础 dtb 的 `__symbols__`**（厂商 BSP 的 dtb 不带符号也能用）。

## 镜像组装（底图 Armbian trixie vendor）

```bash
sudo scripts/apply-rootfs.sh Armbian_26.8.1_Orangepizero3w_trixie_vendor_6.6.98_minimal.img
```

镜像分区/内核实测数据与验收清单见 [../docs/03-software-stack.md](../docs/03-software-stack.md) C 节。
已知缺口：Armbian vendor 6.6.98 内核没编 `SND_SOC_TLV320AIC31XX`，音频要响需 out-of-tree
编 `snd-soc-tlv320aic31xx.ko`。

## aic31xx 模块（2026-10-27 已编出 ✅）

```bash
wsl -d Debian -u root -- bash scripts/build-aic31xx-module.sh \
    <linux-headers-vendor-sun60iw2_*.deb> <厂商树 tlv320aic31xx 源码目录>
```

产物 vermagic 实测 `6.6.98-vendor-sun60iw2 SMP preempt mod_unload aarch64`，与目标内核一致；
依赖（REGMAP_I2C/I2C/SND_SOC/SND_SOC_I2C_AND_SPI）全部 =y 内置，模块无硬依赖。
三个坑（脚本里都有对应处理）：①`modules_prepare` 死循环在 resolve_btfids，不跑完，只补 fixdep；
②modpost 要手工构建（headers 缺）；③prepare 会把 utsrelease 重写成 `6.6.98` 丢 `-vendor-sun60iw2`
后缀导致板上拒载，编译前强制写回。

镜像安装：`sudo scripts/apply-rootfs.sh <img> --module snd-soc-tlv320aic31xx.ko`
（自动放 `/lib/modules/<kver>/kernel/sound/soc/codecs/` 并 depmod）。

## 计划（板子到手后）

- `build-firmware.sh` — WSL 里一键构建 sysroot + 交叉编译（见 [../docs/03-software-stack.md](../docs/03-software-stack.md) A 节）

## EDA 桥怎么用

前提：EasyEDA Pro 开着、工程已打开、已装「API 网关」扩展（监听 49620 端口）。

```powershell
# 1) 写一段 JS 到临时文件（脚本里用 eda.* API，最后 return 一个可序列化对象）
# 2) 执行
C:/Users/JC/AppData/Local/Temp/eda-exec.ps1 -CodeFile .\task.js -OutFile .\out.json
```

要点（都是实测踩出来的）：

- 请求体是 `{code}`，POST 到 `http://localhost:49620/execute`，返回 `{ok, result, error}`。
- 拿原理图页要按 uuid 找：HAT 页 `43797fd6711e6142`；`eda.dmt_Project.getCurrentProjectInfo()` 里能列全。
- **器件封装引用必须是完整三项**（libraryUuid + uuid + name）。只用 `{libraryUuid,uuid}` 放置的器件，
  `getState_Footprint()` 里只有 uuid，DRC 会报「元件的引脚与焊盘未对应（引脚没有对应焊盘：1、2）」。
  正确做法是用 `eda.lib_Device.search()` 取完整条目重建；`modify()` 改不了封装。
- 写器件属性（`updateState` 之类）会连带清空位号/名称并触发自动重排位号 —— 改完必须逐个读回核对。
- DRC 明细拿不到 API：`eda.sch_Drc.check(strict, userInterface, verbose)` 只回聚合计数。
  明细要从界面 DOM 刮：`p.log.error` / `p.log.warn`，再按 `[data-log-find-id="<primId>"]`
  或 `"<primId>-e<pin>"` 定位到元件/引脚。重跑前 `eda.sys_Log.clear()`。
- **改完在 EDA 里按 Ctrl+S**：所有改动都在内存里，不存盘等于没改。
