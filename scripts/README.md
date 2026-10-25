# 脚本目录

本仓的两个「工具」脚本 + 板子到手后要写的部署脚本。

## 已有

| 文件 | 作用 |
| --- | --- |
| `eda-exec.ps1` | 把一段 JS 送进正在运行的 EasyEDA Pro 执行，返回 JSON。改原理图全靠它 |
| `eda-db-inspect.py` | 只读解析 `.eprj2`（zip 里的 JSON），列文件/结构，用于快速核对工程内容 |
| `eda-db-content.py` | 从 `.eprj2` 里提取某类对象（器件、网络、导线）的明细 |
| `fetch-studio.ps1` | 按固定 commit 稀疏拉取 replica 的 `software/studio`，可选推到板子上 |

## 计划（板子到手后）

- `build-firmware.sh` — WSL 里一键构建 sysroot + 交叉编译（见 [../docs/03-software-stack.md](../docs/03-software-stack.md) A 节）
- `setup-board-a733.sh` — A733 板侧依赖安装（ONNX Runtime aarch64、GStreamer、uart2 overlay），
  对照 `firmware/microduck-hd1910/firmware/scripts/setup-board.sh` 移植，**去掉 rknn/rkaiq 部分**

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
