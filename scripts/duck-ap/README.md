# duck-ap: 首次开机自动开热点配网

板子第一次开机（或 WiFi 配置坏掉后）没有可用 WiFi 时, 自动开一个配置热点:
手机连上后在网页里选家里 WiFi 输密码, 配置成功后热点自动关闭, 以后开机
直接连家里路由器, 不再开热点。

## 使用

正常情况不需要任何操作: 上电 → 等约 1 分钟 → 手机 WiFi 里出现
`microduck-XXXX` (XXXX 是板子 MAC 后四位, 密码 `12345678`) → 连接后打开
`http://192.168.4.1` → 扫描 → 选家里 WiFi → 输密码 → 完成。

已配置过 WiFi 的板子永远不会再开热点; 想重新进配置模式, 删掉标记文件并
重启 (或删掉 `/etc/netplan/30-wifis-dhcp.yaml` 里的网络):

```bash
sudo rm /var/lib/robot/ap-provisioned
sudo reboot
```

## 组成

| 文件 | 装到 | 作用 |
|---|---|---|
| `duck-setup-ap.sh` | `/usr/local/bin/` | 判定状态机: 已配好 WiFi 就退出; 45 秒内拿不到地址就开热点 |
| `duck-ap-server.py` | `/usr/local/bin/` | 配置页 (Python 标准库, 零依赖, 端口 80) |
| `duck-setup-ap.service` | `/etc/systemd/system/` | 开机服务, enabled |

安装 (板上执行, 或由 `setup-board-a733.sh` 完成):

```bash
sudo install -m 755 duck-setup-ap.sh /usr/local/bin/
sudo install -m 755 duck-ap-server.py /usr/local/bin/
sudo install -m 644 duck-setup-ap.service /etc/systemd/system/
sudo systemctl enable duck-setup-ap
```

依赖: `hostapd` 与 `dnsmasq` (镜像里需预装, 台架上 `apt install hostapd dnsmasq`)。

## 实现要点 (AIC8800 实测结论)

- **信道必须用 149** (5 GHz, 5745 MHz)。低段 5 GHz 信道 (36 等) 对 AP 是 DFS
  信道, hostapd 直接拒绝: `Primary frequency not allowed` (flags 含 RADAR)。
- AP 跑在独立虚拟接口 `wlan0ap` 上, 与 `wlan0` 的 STA 连接可并发, 开热点
  不影响 SSH。
- 配置写入 netplan (`/etc/netplan/30-wifis-dhcp.yaml`, 渲染器 systemd-networkd),
  `netplan apply` 后轮询 `wlan0` 拿到地址才算成功; 60 秒连不上就回滚旧配置,
  热点保持开着让用户重试。
- 成功标记 `/var/lib/robot/ap-provisioned`; 标记在, 服务每次开机秒退。
- 页面固定 AP 密码 `12345678` — 热点只在未配置状态短暂存在, 且设备还没接入
  任何网络, 临时性大于保密性; 配置成功后热点即关闭。

## 测试

- 已配置状态下重启: 服务应在几秒内退出 (`journalctl -u duck-setup-ap` 看
  "marker present" 或 "has an address")。
- 干跑配置页 (不碰 netplan):

```bash
sudo python3 /usr/local/bin/duck-ap-server.py --dry-run
# 手机/浏览器连上热点后访问 http://192.168.4.1, 提交后看 /tmp/duck-ap-netplan-test.yaml
```

- 完整首开流程: 删标记 + 删 netplan wifi 段 → 重启 → 手机完成配置。
