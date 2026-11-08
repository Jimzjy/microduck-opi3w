#!/usr/bin/env python3
"""On-demand camera: keep mediad stopped until someone opens the console.

mediad serves the console itself, so a stopped mediad means nothing listens on the console's
port and the URL cannot be opened. This sits in front of it on 8080, starts mediad when the
first request arrives (mediad listens on 8081 instead), relays the TCP stream, and stops
mediad again once nobody has watched for CAMERA_IDLE_SECONDS.

The "is anyone watching" test cannot be "is a relay open": the browser loads the page over
8081 and then closes those connections, while the video keeps flowing over the WebRTC
signalling connection on 8443. So idle means no relay open AND no established TCP connection
to 8443, read from /proc/net/tcp{,6}.
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
# Do not stop a mediad that has only just started: the page may still be loading, and the
# WebRTC connection that proves someone is watching does not exist for the first second.
MIN_UPTIME_SECONDS = 45

lock = threading.Lock()
start_lock = threading.Lock()
active = 0
last_activity = time.time()
mediad_started_at = 0.0


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
    except Exception as exc:  # systemd missing, timeout, ...
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
    """Both listeners must be up: the page itself needs 8081, but its script opens the
    signalling WebSocket as soon as it has parsed, which is earlier than 8443 appears
    (~150 ms vs ~280 ms after start on this board). Serving the page one tick too early is
    exactly the "cannot reach signalling port 8443" the console shows."""
    return tcp_open(MEDIAD_WEB_PORT) and tcp_open(SIGNAL_PORT)


def ensure_mediad():
    """Start mediad if it is not serving, and wait until both of its ports answer."""
    global mediad_started_at
    if mediad_ready():
        return True
    with start_lock:
        if mediad_ready():
            return True
        log("console requested, starting mediad")
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


def viewer_connected():
    """True if a remote peer holds an established connection to the WebRTC signalling port.

    mediad keeps a loopback connection to its own 8443 open (fd pair 127.0.0.1 <-> 127.0.0.1),
    so loopback peers must not count as viewers or mediad would never go idle.
    """
    loopback = {
        "0100007F",  # 127.0.0.1
        "00000000000000000000000001000000",  # ::1
    }
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as fh:
                lines = fh.read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 4 or fields[3] != "01":  # 01 = ESTABLISHED
                continue
            try:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                peer = fields[2].rsplit(":", 1)[0]
            except (IndexError, ValueError):
                continue
            if local_port == SIGNAL_PORT and peer not in loopback:
                return True
    return False


def pipe(src, dst):
    """Copy one direction, half-closing dst on EOF so the other side sees the end too."""
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


def handle(conn, peer):
    global active, last_activity
    with lock:
        active += 1
        last_activity = time.time()
    upstream = None
    try:
        if not ensure_mediad():
            return
        try:
            upstream = socket.create_connection(("127.0.0.1", MEDIAD_WEB_PORT), timeout=10)
        except OSError as exc:
            log(f"cannot reach mediad for {peer}: {exc}")
            return
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


def stopper():
    idle_since = None
    while True:
        time.sleep(10)
        with lock:
            open_relays = active
        if open_relays or viewer_connected() or not mediad_active():
            idle_since = None
            continue
        if mediad_started_at and time.time() - mediad_started_at < MIN_UPTIME_SECONDS:
            idle_since = None
            continue
        with lock:
            quiet_for = time.time() - last_activity
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
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", LISTEN_PORT))
    server.listen(32)
    log(f"camera launcher on :{LISTEN_PORT} -> mediad :{MEDIAD_WEB_PORT}, idle stop {IDLE_SECONDS}s")
    while True:
        conn, peer = server.accept()
        threading.Thread(target=handle, args=(conn, peer), daemon=True).start()


if __name__ == "__main__":
    main()
