#!/usr/bin/env python3
"""Turn the runtime's deploy/robotd.toml template into the payload config the
image ships to /etc/robot/robotd.toml on first boot.

Why this exists: deploy/robotd.toml documents every value as a commented-out
default (upstream's habit, so a board that never edits the file follows the
release).  Our hardware is not the default though -- HD-1910 servos on
/dev/ttyS2 speak Feetech STS, and the measured gain for them is P=5, i.e.
p_scale 0.025 (gain 200 * 0.025).  Shipping the template verbatim gave a board
with p_scale 0.16 (P=32, factory stiffness) or worse, which is the "why is it
still shaking" of 2026-11-07.

So: uncomment exactly the keys this robot needs, leave everything else as the
upstream template has it (commented = follow the release), and drop the policy
to off, because a freshly flashed duck has no calibration and must not walk on
default zeros.

Usage:
    python3 scripts/stage-payload-toml.py \
        --runtime ../microduck-runtime \
        --payload ../img/payload
"""
from __future__ import annotations

import argparse
import pathlib
import sys
import tomllib

# What this robot is: (key line in the template -> value line we want).
BUS_LINES = {
    'protocol = "dynamixel2"': 'protocol = "feetech-sts"',
}
FEETECH_LINES = {
    "# p_scale = 0.16": "p_scale = 0.025",
    "# imu = true": "imu = true",
    '# calibration = "/etc/robot/feetech-ft5/hd1910-calibration.toml"':
        'calibration = "/etc/robot/feetech-ft5/hd1910-calibration.toml"',
}
SECTIONS = ("[bus.feetech]",)


def patch(text: str) -> str:
    out: list[str] = []
    section = ""
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        # The feetech block is commented out in the template; open it here.
        if stripped == "# [bus.feetech]":
            out.append("[bus.feetech]\n")
            section = "[bus.feetech]"
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped
            out.append(line)
            continue

        if section == "[bus]":
            for want, repl in BUS_LINES.items():
                if stripped == "# " + want:
                    out.append(repl + "\n")
                    break
            else:
                out.append(line)
                continue
            continue

        if section == "[bus.feetech]":
            for want, repl in FEETECH_LINES.items():
                if stripped == want:
                    out.append(repl + "\n")
                    break
            else:
                # Keep directions and the explanatory comments as they are.
                out.append(line)
                continue
            continue

        if section == "[policy]" and stripped == "enabled = true":
            out.append("enabled = false\n")
            continue

        out.append(line)
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtime", default="../microduck-runtime")
    ap.add_argument("--payload", default="../img/payload")
    args = ap.parse_args()

    src = pathlib.Path(args.runtime) / "deploy" / "robotd.toml"
    dst = pathlib.Path(args.payload) / "runtime-bin" / "robotd.toml"
    text = patch(src.read_text(encoding="utf-8"))
    dst.write_text(text, encoding="utf-8")

    cfg = tomllib.loads(text)
    bus = cfg.get("bus", {})
    feetech = bus.get("feetech", {})
    checks = [
        ("bus.port", bus.get("port"), "/dev/ttyS2"),
        ("bus.protocol", bus.get("protocol"), "feetech-sts"),
        ("bus.feetech.p_scale", feetech.get("p_scale"), 0.025),
        ("bus.feetech.imu", feetech.get("imu"), True),
        ("bus.feetech.calibration", feetech.get("calibration"),
         "/etc/robot/feetech-ft5/hd1910-calibration.toml"),
        ("policy.enabled", cfg.get("policy", {}).get("enabled"), False),
    ]
    bad = [(k, got, want) for k, got, want in checks if got != want]
    for k, got, want in checks:
        print(f"  {k} = {got!r}" + ("" if got == want else f"  (want {want!r})"))
    if bad:
        print(f"staged {dst} but it does not say what this robot needs", file=sys.stderr)
        return 1
    print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
