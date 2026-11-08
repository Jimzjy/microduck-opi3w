#!/usr/bin/env python3
"""Drive the duck with robot.move notifications, for a fixed time.

Usage: walk-drive.py [VX] [VY] [VYAW] [SECONDS] [RATE_HZ]
        defaults: 0.2  0.0  0.0    6.0      20

Runs on the board (unix socket /run/robotd.sock); the robot must be standing with a policy
driving first (`robotctl robot init` then `robotctl robot enable`). Continuous intents are
JSON-RPC notifications (no id) — that is what the runtime expects for robot.move, and it is
a deadman: the last one expires 500 ms later, so the loop has to keep sending. Zeros are sent
at the end rather than relying on the timeout alone.
"""

import json
import socket
import sys
import time

vx = float(sys.argv[1]) if len(sys.argv) > 1 else 0.2
vy = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
vyaw = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
secs = float(sys.argv[4]) if len(sys.argv) > 4 else 6.0
rate = float(sys.argv[5]) if len(sys.argv) > 5 else 20.0

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(8)
s.connect("/run/robotd.sock")
f = s.makefile("rwb")

f.write((json.dumps({"jsonrpc": "2.0", "id": 1, "method": "hello",
                     "params": {"api_version": 2}}) + "\n").encode())
f.flush()
print("hello:", f.readline().decode().strip())


def notify(method, params):
    f.write((json.dumps({"jsonrpc": "2.0", "method": method, "params": params}) + "\n").encode())
    f.flush()


period = 1.0 / rate
n = 0
end = time.time() + secs
while time.time() < end:
    notify("robot.move", {"vx": vx, "vy": vy, "vyaw": vyaw})
    n += 1
    time.sleep(period)
print("drive sent", n, "x vx=%.3f" % vx)

# Let the deadman expire rather than leaving a stale twist behind.
for _ in range(12):
    notify("robot.move", {"vx": 0.0, "vy": 0.0, "vyaw": 0.0})
    time.sleep(period)
print("zeros sent")
