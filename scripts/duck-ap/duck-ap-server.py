#!/usr/bin/env python3
"""duck-ap-server: first-boot WiFi provisioning page.

Serves a single-purpose web app on the setup access point (http://192.168.4.1):
list nearby networks, pick one, enter the password. On submit it writes the
netplan WiFi config, applies it, and waits for wlan0 to associate. Success
writes the provisioning marker and tears the AP down via the service.

Board has no third-party Python packages, so this is stdlib-only. Test mode:

    python3 duck-ap-server.py --dry-run   # writes netplan candidate to /tmp,
                                          # never touches /etc/netplan, never
                                          # applies, always "succeeds"
"""
import http.server
import json
import os
import subprocess
import threading
import time
import urllib.parse

HOST = "192.168.4.1"
PORT = 80
NETPLAN = "/etc/netplan/30-wifis-dhcp.yaml"
MARKER = "/var/lib/robot/ap-provisioned"
WAIT_SECS = 60
DRY_RUN = "--dry-run" in os.sys.argv

PAGE = """<!doctype html><html lang=zh><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>microduck 首次设置</title>
<style>
body{font-family:system-ui,sans-serif;max-width:420px;margin:0 auto;padding:16px;color:#222}
h1{font-size:1.2rem} button{font-size:1rem;padding:8px 16px;margin:8px 0}
ul{list-style:none;padding:0} li{padding:6px;border-bottom:1px solid #ddd;cursor:pointer}
li:hover{background:#f4f4f4} input{width:100%;font-size:1rem;padding:8px;margin:4px 0}
#msg{margin-top:12px;white-space:pre-wrap}
.sig{color:#888;font-size:.8rem}
</style><body>
<h1>microduck 首次设置</h1>
<p>选择家里的 WiFi 并输入密码。配置成功后热点会自动关闭。</p>
<button onclick=scan()>扫描附近网络</button>
<ul id=list></ul>
<form onsubmit="return connect()">
<label>WiFi 名称 (SSID)</label><input id=ssid name=ssid autocomplete=off required>
<label>密码</label><input id=psk name=psk type=password minlength=8 required>
<button type=submit>连接</button>
</form>
<pre id=msg></pre>
<script>
function esc(s){let d=document.createElement("div");d.textContent=s;return d.innerHTML}
async function scan(){
  document.getElementById("msg").textContent="扫描中…";
  let r=await fetch("/api/scan"); let j=await r.json();
  document.getElementById("msg").textContent="";
  let ul=document.getElementById("list"); ul.innerHTML="";
  for(let n of j){
    let li=document.createElement("li");
    li.innerHTML=`${esc(n.ssid)} <span class=sig>${n.sig} dBm</span>`;
    li.onclick=()=>{document.getElementById("ssid").value=n.ssid;
                    document.getElementById("psk").focus()};
    ul.appendChild(li);
  }
  if(!j.length) document.getElementById("msg").textContent="没扫到网络，再点一次扫描";
}
async function connect(){
  let ssid=document.getElementById("ssid").value;
  let psk=document.getElementById("psk").value;
  document.getElementById("msg").textContent="正在连接 "+ssid+" … 请保持本页面打开（约一分钟）";
  let r=await fetch("/connect",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},
    body:new URLSearchParams({ssid,psk})});
  let j=await r.json();
  document.getElementById("msg").textContent=j.msg;
  return false;
}
</script></body></html>"""


def run(cmd, timeout=30):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def scan_networks():
    """Return [{ssid, sig}] via wpa_cli, falling back to iw."""
    nets = {}
    try:
        run(["wpa_cli", "-i", "wlan0", "scan"], timeout=15)
        out = run(["wpa_cli", "-i", "wlan0", "scan_results"], timeout=15).stdout
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) >= 5 and parts[0].count(":") == 5:  # a BSSID row
                ssid, sig = parts[4], parts[2]
                if ssid:
                    nets[ssid] = max(int(sig), nets.get(ssid, -999))
        if nets:
            return sorted(({"ssid": k, "sig": v} for k, v in nets.items()),
                          key=lambda n: -n["sig"])
        # wpa_ctrl socket not reachable: fall through to iw
    except Exception:
        out = run(["iw", "dev", "wlan0", "scan", "freq",
                   "2412-2484", "5180", "5200", "5220", "5240",
                   "5745", "5765", "5785", "5805", "5825"], timeout=25).stdout
        ssid = None
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("SSID:"):
                ssid = line[5:].strip()
            elif line.startswith("signal:") and ssid:
                try:
                    sig = int(float(line[7:].split(" ")[0]))
                except ValueError:
                    sig = -99
                if ssid:
                    nets[ssid] = max(sig, nets.get(ssid, -999))
                ssid = None
    return sorted(({"ssid": k, "sig": v} for k, v in nets.items()),
                  key=lambda n: -n["sig"])


def netplan_yaml(ssid, psk):
    ssid_q = json.dumps(ssid)          # json escaping == yaml double-quoted
    psk_q = json.dumps(psk)
    return (
        "# Written by duck-ap-server (first-boot WiFi provisioning)\n"
        "network:\n"
        "  wifis:\n"
        "    wlan0:\n"
        "      dhcp4: yes\n"
        "      dhcp6: yes\n"
        "      access-points:\n"
        f"        {ssid_q}:\n"
        f"         password: {psk_q}\n"
    )


def wifi_has_address():
    out = run(["ip", "-4", "addr", "show", "wlan0"], timeout=10).stdout
    return " inet " in out


def apply_credentials(ssid, psk):
    """Write netplan, apply, wait for association. Returns (ok, message)."""
    if not ssid or not (8 <= len(psk) <= 63):
        return False, "WiFi 名称不能为空, 密码需要 8-63 个字符"

    backup = None
    if os.path.exists(NETPLAN):
        with open(NETPLAN, "rb") as f:
            backup = f.read()

    if DRY_RUN:
        with open("/tmp/duck-ap-netplan-test.yaml", "w") as f:
            f.write(netplan_yaml(ssid, psk))
        return True, "DRY-RUN OK: candidate written to /tmp/duck-ap-netplan-test.yaml"

    with open(NETPLAN, "w") as f:
        f.write(netplan_yaml(ssid, psk))
    os.chmod(NETPLAN, 0o600)

    ap_err = run(["netplan", "apply"], timeout=60)
    if ap_err.returncode != 0:
        if backup is not None:
            with open(NETPLAN, "wb") as f:
                f.write(backup)
            run(["netplan", "apply"], timeout=60)
        return False, "netplan apply 失败: " + ap_err.stderr.strip()[:300]

    deadline = time.time() + WAIT_SECS
    while time.time() < deadline:
        if wifi_has_address():
            os.makedirs(os.path.dirname(MARKER), exist_ok=True)
            with open(MARKER, "w") as f:
                f.write("provisioned\n")
            return True, "连接成功! 热点将在几秒后关闭, 请重新连接你家路由器分配的网络。"
        time.sleep(3)

    # did not associate: restore the previous config so nothing is half-broken
    if backup is not None:
        with open(NETPLAN, "wb") as f:
            f.write(backup)
        run(["netplan", "apply"], timeout=60)
    return False, ("等待 %d 秒没能连上, 密码可能不对或信号太弱。"
                   "已恢复之前的状态, 请检查后重试。" % WAIT_SECS)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quiet; systemd journal keeps stderr
        pass

    def _send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            self._send(200, "text/html; charset=utf-8", PAGE.encode())
        elif path == "/api/scan":
            try:
                nets = scan_networks()
            except Exception as e:
                nets = []
                self._send(200, "application/json",
                           json.dumps({"error": str(e)}).encode())
                return
            self._send(200, "application/json", json.dumps(nets).encode())
        else:
            self._send(404, "text/plain", b"not found")

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path != "/connect":
            self._send(404, "text/plain", b"not found")
            return
        length = int(self.headers.get("Content-Length", 0))
        form = urllib.parse.parse_qs(self.rfile.read(length).decode())
        ssid = (form.get("ssid") or [""])[0].strip()
        psk = (form.get("psk") or [""])[0]
        ok, msg = apply_credentials(ssid, psk)
        self._send(200, "application/json",
                   json.dumps({"ok": ok, "msg": msg}, ensure_ascii=False).encode())
        if ok and not DRY_RUN:
            # let the response flush, then stop the AP service (teardown runs
            # in the service's ExecStop path / post-exit cleanup)
            threading.Timer(2.0,
                            lambda: subprocess.Popen(
                                ["systemctl", "stop", "duck-setup-ap"])).start()


if __name__ == "__main__":
    srv = http.server.ThreadingHTTPServer((HOST, PORT), Handler)
    print("duck-ap-server: serving on http://%s" % HOST, flush=True)
    srv.serve_forever()
