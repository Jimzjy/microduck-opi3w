# 脚本目录

复现这条移植链需要的全部脚本：交叉编译运行时、编内核模块、组装镜像、板侧 bring-up、台架冒烟，
加上改 EDA 工程用的两个工具。

| 文件 | 作用 |
| --- | --- |
| `eda-exec.ps1` | 把一段 JS 送进正在运行的 EasyEDA Pro 执行，返回 JSON。改原理图全靠它 |
| `eda-db-inspect.py` | 只读解析 `.eprj2`（SQLite 工程库），列工程结构与分支，用于快速核对工程内容 |
| `eda-db-content.py` | 从 `.eprj2` 里提取某类对象的明细 |
| `fetch-studio.ps1` | 按固定 commit 稀疏拉取 replica 的 `software/studio`，可选推到板子上。新版启动：`python3 -m studio serve --robotd unix:<sock> --listen host:port`，依赖 `python3-starlette` + `python3-uvicorn` |
| `setup-board-a733.sh` | A733 板侧 bring-up（在板子上跑）：uart2 overlay + ONNX Runtime + 音频 fail-soft（含 aic31xx 内核模块检查）+ 蓝牙手柄 + 板况报告。对照上游 `setup-board.sh`，去掉了全部 RK3566 专属步骤。用法见脚本头注释 |
| `apply-rootfs.sh` | 把 overlay dtbo + 板侧脚本 + firstboot 服务装进 Armbian 底图 img，可选 `--module <.ko>`（装进 /lib/modules 并 depmod）、`--payload <目录>`、`--bootloader <官方镜像.img>`（移植官方 boot0/u-boot 裸区，1GB 内存版必选，见 docs/05 §5）。支持 `--mount <挂载点>`（WSL 的 VHD 路线）。用法见脚本头注释 |
| `build-aic31xx-module.sh` | out-of-tree 交叉编译 `snd-soc-tlv320aic31xx.ko`（A733 音频 codec 驱动，vendor 内核没编）。记录了 headers 包全部手工补丁（fixdep、modpost、utsrelease 回写）。在 Linux（root）跑，WSL 亦可，用法见脚本头注释 |
| `aic31xx-build-aids/` | 上面脚本的配套留档：`arm64-tools-Makefile`（headers 缺的 kapi 生成器 Makefile）、`build-modpost-manual2.sh`（手工构建 kbuild modpost，含 devicetable-offsets.h 的 .s→.h 转换） |
| `build-runtime.sh` | 交叉编译运行时 `robotd`/`robotctl`（aarch64，源 = `microduck-runtime` 仓 `opi3w-feetech` 分支 = 官方 0.17.9 + 我们的补丁）并布进 `$MICRODUCK_IMG/payload/runtime-bin/`（默认仓库同级的 `img/`）。先跑受影响 crate 测试再出产物，`SKIP_TEST=1` 可跳。产物 GLIBC 符号最高要求 2.39（底图 trixie 的 2.41 满足）；onnxruntime 静态链入板上无需装库。**二进制不进 git** |
| `smoke-fake.sh` | 全链路台架冒烟测试（host x86_64，无需真机）：robotd `--fake` + onnxruntime + 测试 fixture 策略，用 robotctl 验 health/init/mode/monitor/quack fail-soft。前置：host 编译 robotd/robotctl + onnxruntime x64 ≥1.23 解到 `$ORT_DIR`（默认 /root/ort-x64）。详见脚本头注释 |
| `smoke-commissioning.sh` | 标定台架冒烟：`robotd --fake --commissioning` 起来、策略被关掉、控制环在跑、`health` 回话。前置只需 host 编译 robotd/robotctl（debug） |

## overlay 编译与验证（任意主机，需要 dtc）

```bash
sudo apt-get install device-tree-compiler
cd hardware/overlay
dtc -@ -I dts -O dtb -o /tmp/uart2-dxl.dtbo uart2-dxl.dts
# 回归验证（不需要真实板子/内核）：
dtc -q -I dts -O dtb -o /tmp/stub.dtb uart2-dxl-applytest.dts
fdtoverlay -i /tmp/stub.dtb -o /tmp/applied.dtb /tmp/uart2-dxl.dtbo
fdtdump /tmp/applied.dtb | grep -A4 'uart@2502000'   # status 应为 "okay"
```

overlay 用 target-path 写法，**不依赖基础 dtb 的 `__symbols__`**（厂商 BSP 的 dtb 不带符号也能用）。

## 镜像组装（底图 Armbian trixie vendor）

```bash
sudo scripts/apply-rootfs.sh <base.img>            # 底图见 docs/05 第 5 步
```

WSL2 没有 loop 设备也能跑——走 `--mount` 模式：img 用 `qemu-img convert -O vpc` 转 VHD，
`wsl --mount --vhd xx.vhd --partition 1` 挂进 WSL，然后
`sudo scripts/apply-rootfs.sh --mount /mnt/wsl/<挂载点> --module ../img/aic31xx-module/snd-soc-tlv320aic31xx.ko --payload ../img/payload`，
改完 `wsl --unmount` + `qemu-img convert -O raw` 转回 img 烧卡。
两条路线（Linux loop / WSL2 + VHD）产出的镜像都包含：dtbo + `user_overlays` + setup 脚本 +
firstboot 服务 + aic31xx.ko + depmod + `robotd`/`robotctl`/`robotd.toml` payload。

镜像里的运行时是**手工安装**（不走官方 updaterd 签名链）：payload 里若有
`runtime-bin/robotd`，板上首开 `setup-board-a733.sh` 会装 `/usr/local/bin/robotd`、
`robotctl`，写 `/etc/robot/robotd.toml`（已存在不覆盖）并 enable `robotd.service`。
换运行时 = 重跑 `build-runtime.sh` + `apply-rootfs.sh --payload` 再刷一次（或板上直接覆盖二进制重跑 setup）。

镜像分区/内核信息与验收清单见 [../docs/03-software-stack.md](../docs/03-software-stack.md) C 节。
已知缺口：Armbian vendor 6.6.98 内核没编 `SND_SOC_TLV320AIC31XX`，音频要响需 out-of-tree
编 `snd-soc-tlv320aic31xx.ko`。

## aic31xx 模块

```bash
sudo bash scripts/build-aic31xx-module.sh \
    <linux-headers-vendor-sun60iw2_*.deb> <厂商树 tlv320aic31xx 源码目录>
```

产物 vermagic 必须逐字为 `6.6.98-vendor-sun60iw2 SMP preempt mod_unload aarch64`（脚本末尾自检）；
依赖（REGMAP_I2C/I2C/SND_SOC/SND_SOC_I2C_AND_SPI）全部 =y 内置，模块无硬依赖。
三个坑（脚本里都有对应处理）：①`modules_prepare` 死循环在 resolve_btfids，不跑完，只补 fixdep；
②modpost 要手工构建（headers 缺）；③prepare 会把 utsrelease 重写成 `6.6.98` 丢 `-vendor-sun60iw2`
后缀导致板上拒载，编译前强制写回。

镜像安装：`sudo scripts/apply-rootfs.sh <img> --module snd-soc-tlv320aic31xx.ko`
（自动放 `/lib/modules/<kver>/kernel/sound/soc/codecs/` 并 depmod）。

## 板子到手后

没有待写的脚本了——构建、镜像、bring-up、冒烟都已就位。上板要做的只是按
[../docs/05-bringup-runbook.md](../docs/05-bringup-runbook.md) 走一遍验收，把结果写回文档。

## EDA 桥怎么用

前提：EasyEDA Pro 开着、工程已打开、已装「API 网关」扩展（监听 49620 端口）。

```powershell
# 1) 写一段 JS 到临时文件（脚本里用 eda.* API，最后 return 一个可序列化对象）
# 2) 执行
scripts/eda-exec.ps1 -CodeFile .\task.js -OutFile .\out.json
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
