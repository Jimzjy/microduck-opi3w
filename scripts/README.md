# 脚本目录

（建设中，板子到手后填充）

计划：
- `setup-board-a733.sh` — A733 板侧依赖安装（ONNX Runtime 1.28 aarch64、GStreamer、
  舵机总线 UART 配置；对照 firmware/scripts/setup-board.sh 移植，去掉 rknn 部分）
- `build-firmware.sh` — WSL 交叉编译一键脚本（含 sysroot 构建）
