#!/usr/bin/env python3
# mic-selftest.py -- one command microphone self test for the microduck HAT.
#
# Plays one continuous stream (silence -> 750 Hz -> silence) through the speaker and
# records through the codec at the same time, then looks for the tone with a
# narrow band Goertzel. A single playback stream is required: the amp teardown
# silences the capture, so the tone has to live inside one aplay run.
#
#   python3 mic-selftest.py            # tone at PCM 120, 8 s
#   python3 mic-selftest.py --vol 127  # louder
#
import argparse, math, os, struct, subprocess, sys, threading, time, fcntl, ctypes

CARD_I2C = "/dev/i2c-0"
ADDR = 0x18
I2C_RDWR = 0x0707
RATE = 48000
CH = 2

# ---------------------------------------------------------------- codec access
class _msg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16), ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16), ("buf", ctypes.c_char_p)]
class _rdwr(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(_msg)), ("nmsgs", ctypes.c_uint32)]

_fd = None
def _open():
    global _fd
    if _fd is None:
        _fd = open(CARD_I2C, "r+b", buffering=0)
def rd(reg):
    _open()
    rb = ctypes.create_string_buffer(1)
    wb = ctypes.create_string_buffer(bytes([reg & 0xFF]))
    m1 = _msg(ADDR, 0, 1, ctypes.cast(wb, ctypes.c_char_p))
    m2 = _msg(ADDR, 1, 1, ctypes.cast(rb, ctypes.c_char_p))
    arr = (_msg * 2)(m1, m2)
    d = _rdwr(arr, 2)
    fcntl.ioctl(_fd.fileno(), I2C_RDWR, d)
    return rb.raw[0] & 0xFF
def wr(reg, val):
    _open()
    b = ctypes.create_string_buffer(bytes([reg & 0xFF, val & 0xFF]))
    m = _msg(ADDR, 0, 2, ctypes.cast(b, ctypes.c_char_p))
    d = _rdwr(ctypes.pointer(m), 1)
    fcntl.ioctl(_fd.fileno(), I2C_RDWR, d)

# ---------------------------------------------------------------- mixer setup
def amix(*a):
    return subprocess.run(["amixer", "-c", "1"] + list(a),
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def capture_setup():
    """Put the codec back into the configuration that is known to capture."""
    amix("cset", "numid=34", "on,on")        # AGC on (off silences the ADC)
    amix("cset", "numid=43", "on,on")        # PGA capture switch (unmute)
    amix("cset", "numid=42", "40,40")        # PGA capture volume
    amix("cset", "numid=53", "differential")
    amix("cset", "numid=54", "differential")
    amix("cset", "numid=47", "on")
    amix("cset", "numid=48", "on")
    for n in (57, 58, 59):
        amix("cset", "numid=%d" % n, "on")
    amix("cset", "numid=60", "off")

def playback_setup(vol):
    # The DAC -> line mixer gains default to value 6, which is -56 dB on a
    # -59.0 dB .. +0.5 dB scale. That alone explains a "barely audible" speaker.
    for n in (11, 13, 15, 17, 19, 21, 23, 25, 27):
        amix("cset", "numid=%d" % n, "100%")
    # Kill the analog PGA bypass path into the line mixer (feedback / noise).
    for n in (65, 67, 69, 71, 73, 75, 77, 79, 81, 83):
        amix("cset", "numid=%d" % n, "off")
    amix("cset", "numid=28", "9,9")          # line playback volume
    amix("cset", "numid=29", "on,on")        # line playback switch
    amix("sset", "PCM", str(vol))

def playback_teardown():
    amix("cset", "numid=29", "off,off")
    amix("sset", "PCM", "60")

# ---------------------------------------------------------------- audio pieces
def frames(seconds):
    return int(seconds * RATE)

def silent(seconds):
    return b"\x00" * (frames(seconds) * CH * 2)

def tone(seconds, hz, amp):
    n = frames(seconds)
    out = bytearray(n * CH * 2)
    w = 2 * math.pi * hz / RATE
    for i in range(n):
        v = int(amp * math.sin(w * i))
        struct.pack_into("<hh", out, i * 4, v, v)
    return bytes(out)

# ---------------------------------------------------------------- goertzel
def goertzel(samples, hz, rate=RATE):
    n = len(samples)
    if n == 0:
        return 0.0
    k = 2.0 * math.cos(2.0 * math.pi * hz / rate)
    s0 = s1 = s2 = 0.0
    for x in samples:
        s0 = x + k * s1 - s2
        s2 = s1
        s1 = s0
    p = s1 * s1 + s2 * s2 - k * s1 * s2
    return math.sqrt(max(p, 0.0)) / n

def rms(v):
    if not v:
        return 0.0
    return math.sqrt(sum(x * x for x in v) / len(v))

# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vol", type=int, default=120)
    ap.add_argument("--amp", type=int, default=22000)
    ap.add_argument("--hz", type=float, default=750.0)
    ap.add_argument("--tone-sec", type=float, default=8.0)
    args = ap.parse_args()

    print("=== mic selftest ===")
    print("codec regs before: 0f=%02x 10=%02x 13=%02x 16=%02x 1a=%02x" %
          (rd(0x0F), rd(0x10), rd(0x13), rd(0x16), rd(0x1A)))

    capture_setup()
    playback_setup(args.vol)
    time.sleep(0.4)
    print("mixer: AGC=%s PGA=%s LINE1L=%s" % (
        subprocess.run(["amixer", "-c", "1", "cget", "numid=34"],
                       capture_output=True, text=True).stdout.strip().splitlines()[-1].strip(),
        subprocess.run(["amixer", "-c", "1", "cget", "numid=43"],
                       capture_output=True, text=True).stdout.strip().splitlines()[-1].strip(),
        "on"))

    # one uninterrupted playback stream: 3 s silence, tone, 3 s silence
    buf = silent(3.0) + tone(args.tone_sec, args.hz, args.amp) + silent(3.0)
    open("/tmp/selftest_tone.raw", "wb").write(buf)
    total = 6.0 + args.tone_sec
    print("playing %.1f s stream (%.0f Hz for %.1f s, PCM %d, amp %d)" %
          (total, args.hz, args.tone_sec, args.vol, args.amp))
    print(">>> you should hear a steady tone starting now", flush=True)

    ap_ = subprocess.Popen(["aplay", "-D", "hw:1,0", "-f", "S16_LE", "-r", str(RATE),
                            "-c", str(CH), "-t", "raw", "-q", "/tmp/selftest_tone.raw"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.25)

    chunks = []
    stop = False
    def reader(p):
        while not stop:
            c = p.stdout.read(4096)
            if not c:
                break
            chunks.append((time.time(), c))

    cap = subprocess.Popen(["arecord", "-D", "hw:1,0", "-f", "S16_LE", "-r", str(RATE),
                            "-c", str(CH), "-t", "raw", "-q", "-"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
    th = threading.Thread(target=reader, args=(cap,), daemon=True)
    th.start()
    time.sleep(total - 0.5)
    stop = True
    try:
        cap.terminate()
    except Exception:
        pass
    th.join(timeout=3)
    try:
        ap_.wait(timeout=3)
    except Exception:
        ap_.kill()
    playback_teardown()

    data = b"".join(c for _, c in chunks)
    dur = len(data) / (RATE * CH * 2)
    print("captured %.2f s" % dur)
    if dur < args.tone_sec + 1.0:
        print("RESULT: capture too short -- the stream did not run")
        return 2

    # decode left channel
    n = len(data) // 2
    v = struct.unpack("<%dh" % n, data[:n * 2])
    left = v[0::2]

    def seg(a, b):
        i0 = int(a * RATE)
        i1 = int(b * RATE)
        return left[i0:i1]

    sil = seg(0.4, 2.6)
    tonew = seg(3.2, 3.2 + args.tone_sec - 0.6)
    tail = seg(3.0 + args.tone_sec + 0.4, dur - 0.2)

    print("\nper second:")
    for s in range(int(dur)):
        w = left[s * RATE:(s + 1) * RATE]
        if w:
            print("  t=%02d  rms=%7.1f" % (s, rms(w)))

    print("\nnarrow band, left channel:")
    freqs = [args.hz - 20, args.hz - 10, args.hz, args.hz + 10, args.hz + 20, 600.0, 1500.0]
    print("  %-8s %10s %10s %8s" % ("Hz", "silence", "tone", "ratio"))
    verdict_freq = None
    for f in freqs:
        a = goertzel(sil, f)
        b = goertzel(tonew, f)
        r = b / a if a > 1e-9 else float("inf")
        print("  %-8.0f %10.3f %10.3f %8.2f" % (f, a, b, r))
        if f == args.hz:
            verdict_freq = (a, b, r)

    a, b, r = verdict_freq
    print("\nrms  silence=%.1f  tone=%.1f  tail=%.1f" % (rms(sil), rms(tonew), rms(tail)))
    print("\nRESULT:")
    if r > 3.0 and b > 20:
        print("  MICROPHONE PICKS UP SOUND  (%.0f Hz ratio %.1f)" % (args.hz, r))
    elif r > 1.8:
        print("  WEAK RESPONSE at %.0f Hz (ratio %.1f) -- borderline" % (args.hz, r))
    else:
        print("  NO PICKUP at %.0f Hz (ratio %.1f)" % (args.hz, r))

    print("\nregs after: 0f=%02x 10=%02x 13=%02x 16=%02x 1a=%02x" %
          (rd(0x0F), rd(0x10), rd(0x13), rd(0x16), rd(0x1A)))
    return 0

if __name__ == "__main__":
    sys.exit(main())
