#!/usr/bin/env python3
"""Drive the duck through netpadd with a synthetic UDP gamepad.

netpadd listens on 127.0.0.1:4210 (see /etc/robot/robotd.toml [netpad]) and
turns DKPD datagrams into robotd intents. There is no physical gamepad on the
board, so this script is how the robot is driven from a shell.

What the pipeline taught us, and what this script therefore does:

  * Keep frames flowing the whole time. A silence longer than robotd's pad
    timeout (1 s) counts as the pad leaving (the duck sits down), and the next
    datagram opens a new connection whose button states count as already held.
    So a sender thread streams neutral frames at 30 Hz for the whole run, even
    while the main thread is busy asking robotd for the robot state.
  * Do not rely on Start. Start is a toggle: from the held pose it starts the
    standing policy, but while a policy is already running (walk/sit) the same
    press *disables* it. Instead this script calls `robotctl robot init` when
    the policy is idle, which lands in the same place without the ambiguity.
  * A stick push while the policy is idle only logs the intent and moves
    nothing — the robot must be standing *with the policy driving* first, so
    the script waits for that before it pushes the stick.

Examples:
    pad-walk.py --forward 2 --speed 0.1              # ~20 cm forward
    pad-walk.py --forward 1.5 --speed 0.1 --yaw 0.2 # walk an arc
    pad-walk.py --stand-only                        # just stand and hold
    pad-walk.py --start --forward 2                 # manual Start tap instead
"""

import argparse
import json
import random
import socket
import struct
import subprocess
import threading
import time

DUCK = ("127.0.0.1", 4210)
START = 1 << 6          # pad button bit for Start, see udp-pad.md
FULL = 16384            # stick full deflection
RATE_HZ = 30
VX_MAX = 0.4            # m/s at full stick (robotd pad mapping)
ROBOTCTL = "/usr/local/bin/robotctl"
POLICY_RUNNING = {"walk", "stand"}


def state():
    """One robot.state sample, or {} if robotd is not answering."""
    try:
        out = subprocess.run(
            "timeout 6 %s monitor --json --hz 2 | head -1" % ROBOTCTL,
            shell=True, capture_output=True, text=True, timeout=20,
        )
        line = out.stdout.splitlines()[0]
        return json.loads(line).get("params", {})
    except Exception:
        return {}


class Pad:
    """Background 30 Hz sender; change .stick / .buttons at any time."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.seq = random.getrandbits(32)
        self.stick = (0, 0, 0, 0)     # lx, ly, rx, ry
        self.buttons = 0
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=2)

    def _run(self):
        period = 1.0 / RATE_HZ
        while not self._stop.is_set():
            self.seq = (self.seq + 1) % 2**32
            t_ms = int(time.monotonic() * 1000) % 2**32
            lx, ly, rx, ry = (max(-FULL, min(FULL, int(round(v)))) for v in self.stick)
            packet = b"DKPD" + struct.pack(
                "<BBII6hH", 1, 0, self.seq, t_ms, lx, ly, rx, ry, 0, 0, self.buttons,
            )
            try:
                self.sock.sendto(packet, DUCK)
            except OSError:
                pass
            time.sleep(period)


def main():
    ap = argparse.ArgumentParser(description="Drive the duck over netpadd.")
    ap.add_argument("--forward", type=float, default=0.0,
                    help="seconds of forward motion (default 0: no motion)")
    ap.add_argument("--speed", type=float, default=0.1,
                    help="forward speed in m/s (default 0.1, pad max 0.4)")
    ap.add_argument("--yaw", type=float, default=0.0,
                    help="turn command, +-1.0 full stick (sign: try both)")
    ap.add_argument("--stand-only", action="store_true",
                    help="only make sure the policy is driving; do not move")
    ap.add_argument("--start", action="store_true",
                    help="tap Start before waiting (toggle; usually unnecessary)")
    ap.add_argument("--wait", type=float, default=8.0,
                    help="max seconds to wait for the policy to take over (default 8)")
    ap.add_argument("--tail", type=float, default=1.0,
                    help="neutral frames after the motion (default 1.0)")
    args = ap.parse_args()

    pad = Pad()
    pad.start()
    time.sleep(0.5)                    # release anything left from before

    if args.start:
        pad.buttons = START
        time.sleep(0.15)
        pad.buttons = 0
        print("Start tapped")

    st = state()
    policy = st.get("policy")
    print("policy: %s" % policy)
    if policy == "sit":
        # 坐着时 init 不会起来（the robot is sitting — holding the seat），
        # robotd 自己的起身动作是一次 sit_toggle 技能。
        subprocess.run([ROBOTCTL, "robot", "do", "sit_toggle", "--json"],
                       capture_output=True)
        deadline = time.time() + args.wait
        while time.time() < deadline:
            time.sleep(0.7)
            policy = state().get("policy")
            if policy in POLICY_RUNNING:
                break
        print("policy: %s" % policy)
        time.sleep(2.0)                # the rise itself takes a couple of seconds
    elif policy not in POLICY_RUNNING:
        # 待机（held）：上扭矩到 home，然后把机器人交给策略。enable 没有
        # Start 那种开关歧义（Start 在策略跑着的时候按下去是关策略）。
        subprocess.run([ROBOTCTL, "robot", "init", "--json"], capture_output=True)
        time.sleep(0.5)
        subprocess.run([ROBOTCTL, "robot", "enable", "--json"], capture_output=True)
        deadline = time.time() + args.wait
        while time.time() < deadline:
            time.sleep(0.7)
            policy = state().get("policy")
            if policy in POLICY_RUNNING:
                break
        print("policy: %s" % policy)
        time.sleep(1.0)                # let the ramp finish

    if args.forward > 0:
        ly = FULL * max(0.0, min(1.0, args.speed / VX_MAX))
        lx = FULL * max(-1.0, min(1.0, args.yaw))
        print("forward %.1fs at %.2f m/s" % (args.forward, args.speed))
        pad.stick = (lx, ly, 0, 0)
        time.sleep(args.forward)
        pad.stick = (0, 0, 0, 0)

    time.sleep(args.tail)
    pad.stop()
    print("done (the duck sits when the pad goes away)")


if __name__ == "__main__":
    main()
