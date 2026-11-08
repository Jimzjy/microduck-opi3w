#!/usr/bin/env python3
"""On-demand camera: keep mediad stopped until somebody actually opens the console or
connects to its signalling port.

Two lids, both on ports that are always up:

  8080  console   → relay to mediad's 8081 (mediad serves the page there)
  8443  signalling → relay to mediad's 8443, but mediad is bound to 127.0.0.1 only, so
                     the LAN address on 8443 belongs to this process instead

The second one is what makes a stale tab work: the console's script opens
`ws://<hostname>:8443` the moment it has parsed, so if mediad has been idle-stopped the
WebSocket connects to *us*, we start mediad, and only then forward. Without it the page
sits there with a dead "cannot reach signalling port 8443" until it is reloaded.

The page's own signalling port comes from mediad (it substitutes its --port into the HTML),
so mediad must keep --port 8443 while binding loopback; nothing else is rewritten.

Idle means: no console relay and no signalling relay for CAMERA_IDLE_SECONDS. The relay
lifetime equals the browser's WebSocket session, which is exactly "somebody is watching".
"""

import os
import socket
import subprocess
import threading
import time

LISTEN_PORT = int(os.environ.get("CAMERA_LISTEN_PORT", "8080"))
MEDIAD_WEB_PORT = int(os.environ.get("CAMERA_MEDIAD_WEB_PORT", "8081"))
SIGNAL_PORT = int(os.environ.get("CAMERA_SIGNAL_PORT", "8443"))
IDLE_SECONDS = int(os.environ.get("CAMERA_IDLE_SECONDS", "600"))
MIN_UPTIME_SECONDS = 45

lock = threading.Lock()
start_lock = threading.Lock()
active = 0
last_activity = time.time()
mediad_started_at = 0.0
signal_sock = None
signal_host = None


def log(msg):
    print(msg, flush=True)


def tcp_open(port, host="127.0.0.1", timeout=0.3):
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except OSError:
        return False


def systemctl(*args):
    try:
        subprocess.run(["systemctl", *args], check=False, timeout=40)
    except Exception as exc:
        log(f"systemctl {' '.join(args)} failed: {exc}")


def mediad_active():
    try:
        out = subprocess.run(
            ["systemctl", "is-active", "mediad"], capture_output=True, text=True, timeout=10
        )
        return out.stdout.strip() == "active"
    except Exception:
        return False


def mediad_ready():
    """The page needs 8081; its script needs 8443 as soon as it has parsed, and that port
    comes up a little later. Serving the page in between is the "cannot reach signalling
    port 8443" the console reports."""
    return tcp_open(MEDIAD_WEB_PORT) and tcp_open(SIGNAL_PORT)


def ensure_mediad():
    global mediad_started_at
    if mediad_ready():
        return True
    with start_lock:
        if mediad_ready():
            return True
        log("wake requested, starting mediad")
        systemctl("start", "mediad")
        mediad_started_at = time.time()
        deadline = time.time() + 30
        while time.time() < deadline:
            if mediad_ready():
                log("mediad is up (console + signalling)")
                return True
            time.sleep(0.1)
    log("mediad did not come up within 30 s")
    return False


def lan_ip():
    """Primary IPv4 of the interface that reaches the outside; no packet is sent."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.0.2.1", 9))
        ip = s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()
    return None if ip.startswith("127.") else ip


def listen(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((host, port))
    s.listen(32)
    s.settimeout(5)
    return s


def bind_signalling():
    """Bind 8443 on the LAN address; retried until an address exists."""
    global signal_sock, signal_host
    while True:
        ip = lan_ip()
        if ip:
            try:
                signal_sock = listen(ip, SIGNAL_PORT)
                signal_host = ip
                log(f"signalling lid on {ip}:{SIGNAL_PORT} -> mediad 127.0.0.1:{SIGNAL_PORT}")
                return
            except OSError as exc:
                log(f"cannot bind {ip}:{SIGNAL_PORT}: {exc}")
        time.sleep(5)


def pipe(src, dst):
    global last_activity
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
            with lock:
                last_activity = time.time()
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def relay(conn, peer, upstream_port, tag):
    global active, last_activity
    with lock:
        active += 1
        last_activity = time.time()
    upstream = None
    try:
        if not ensure_mediad():
            return
        try:
            upstream = socket.create_connection(("127.0.0.1", upstream_port), timeout=10)
            upstream.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError as exc:
            log(f"{tag}: cannot reach mediad for {peer}: {exc}")
            return
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        t1 = threading.Thread(target=pipe, args=(conn, upstream), daemon=True)
        t2 = threading.Thread(target=pipe, args=(upstream, conn), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    finally:
        with lock:
            active -= 1
            last_activity = time.time()
        for sock in (conn, upstream):
            if sock is None:
                continue
            try:
                sock.close()
            except OSError:
                pass


def accept_loop(sock, upstream_port, tag):
    while True:
        try:
            conn, peer = sock.accept()
        except socket.timeout:
            continue
        except OSError:
            time.sleep(1)
            continue
        threading.Thread(target=relay, args=(conn, peer, upstream_port, tag), daemon=True).start()


def signal_loop():
    """Accept signalling connections and rebind if the LAN address changes."""
    global signal_sock, signal_host
    while True:
        try:
            conn, peer = signal_sock.accept()
        except socket.timeout:
            if lan_ip() != signal_host:
                log(f"LAN address changed (was {signal_host}), rebinding signalling lid")
                try:
                    signal_sock.close()
                except OSError:
                    pass
                bind_signalling()
            continue
        except OSError:
            time.sleep(1)
            continue
        threading.Thread(
            target=relay, args=(conn, peer, SIGNAL_PORT, "signalling"), daemon=True
        ).start()


def stopper():
    idle_since = None
    while True:
        time.sleep(10)
        with lock:
            open_relays = active
            quiet_for = time.time() - last_activity
        if open_relays or not mediad_active():
            idle_since = None
            continue
        if mediad_started_at and time.time() - mediad_started_at < MIN_UPTIME_SECONDS:
            idle_since = None
            continue
        if quiet_for < MIN_UPTIME_SECONDS:
            idle_since = None
            continue
        if idle_since is None:
            idle_since = time.time()
        elif time.time() - idle_since >= IDLE_SECONDS:
            log(f"nobody has watched for {IDLE_SECONDS}s, stopping mediad")
            systemctl("stop", "mediad")
            idle_since = None


def main():
    threading.Thread(target=stopper, daemon=True).start()
    console = listen("0.0.0.0", LISTEN_PORT)
    log(f"console lid on :{LISTEN_PORT} -> mediad :{MEDIAD_WEB_PORT}, idle stop {IDLE_SECONDS}s")
    threading.Thread(target=accept_loop, args=(console, MEDIAD_WEB_PORT, "console"), daemon=True).start()
    bind_signalling()
    signal_loop()


if __name__ == "__main__":
    main()
