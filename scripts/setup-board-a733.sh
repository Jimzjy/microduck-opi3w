#!/usr/bin/env bash
#
# setup-board-a733.sh — Orange Pi Zero 3W（A733 / sun60iw2）板级 bring-up。
#
# 这是 firmware/microduck-hd1910/firmware/scripts/setup-board.sh（Radxa Zero 3W 版）的
# A733 移植版。同一套机器人软件（robotd/padd/btd/mediad/configd，由官方 install.sh 或
# updaterd 安装）需要板子具备：舵机总线串口、ONNX Runtime（走策略）、蓝牙手柄、音频。
# 那份脚本里所有 RK3566 专属的东西（vendor-rk35xx 内核、aic3x DKMS、rockchip/overlay、
# camera overlay 镜像）在这里都不适用，逐段换成 A733 的做法。
#
# 与上游的关键差异（为什么不能直接复用）：
#   1. 舵机串口：A733 走 uart2（PB0/PB1 → 排针 11/13），console 留在 uart0（排针 8/10）。
#      上游把 console 和总线挤在同一个 UART 上需要「解放串口」；这里不用，但保留防御性
#      检查——如果哪个 getty 占了 ttyS2，mask 掉。
#   2. overlay：uart2-dxl.dtbo 用 target-path 写法（不依赖基础 dtb 的 __symbols__），
#      装进 /boot/overlay-user/ 并写 user_overlays=；上游是装进 vendor 内核的 rockchip
#      overlay 目录并写 overlays=，目录和键都不一样。
#   3. 音频：codec 是 AIC3x 家族，要 snd-aic3x（不是 aic31xx）。实测 Armbian trixie
#      vendor 6.6.98 的 sun60iw2 内核 # CONFIG_SND_SOC_TLV320AIC3X is not set
#      （CONFIG_SND_SOC_AC101=y 是板载声卡的），驱动源码在厂商内核树
#      sound/soc/codecs/tlv320aic3x.c 里，但要 out-of-tree 编成 snd-aic3x.ko
#      （源码与步骤见 scripts/aic3x-module/）。音频 overlay 本身已定稿并对镜像真实
#      dtb 验证过（twi0+codec+i2s0 节点、phandle fixup 全对）。本脚本对该层 fail-soft：
#      装 alsa-utils/i2c-tools，发现邻目录有 audio-a733.dtbo 就装，并装 mixer 开机服务；
#      内核模块缺失只警告不阻塞——没音频的板子照常走路。
#   4. ToF：上游的 udev 规则匹配 RK3566 的 fe5c0000.i2c；A733 上 HAT 的 I2C 挂在哪个 twi
#      控制器要上板实测才能定。给 DUCK_I2C_KERNELS 环境变量留了口子，没设就警告。
#   5. 蓝牙：OPi Zero 3W 用 aic8800sd，和上游同样的收发芯片 → 完整保留 UserspaceHID=false、
#      --weird-ble、--pause-btd-on-pair 三个机制（marker 路径与 robotctl 的约定一致）。
#
# 用法（板子上，root）：
#   sudo ./setup-board-a733.sh                    # 全部
#   sudo ./setup-board-a733.sh --skip-onnx        # 已有 ONNX Runtime 时
#   sudo ./setup-board-a733.sh --weird-ble        # 手柄连不上 bond 时再加
#   sudo ./setup-board-a733.sh --status           # 只打印现状，不改任何东西
#
# 设计原则与上游相同：幂等、每步 fail-soft、能跑的部分绝不因为一段失败而停下；
# 结束时打印 needs_reboot 与板况报告。

set -u

# ── 常量 ─────────────────────────────────────────────────────────────────────
ONNX_VERSION="${ONNX_VERSION:-1.28.0}"
MOTOR_PORT="${MOTOR_PORT:-/dev/ttyS2}"
ENV_TXT=/boot/armbianEnv.txt
OVERLAY_USER_DIR=/boot/overlay-user
UART2_OVERLAY_NAME=uart2-dxl
AUDIO_OVERLAY_NAME=audio-a733
BT_CONF=/etc/bluetooth/main.conf
BT_INPUT_CONF=/etc/bluetooth/input.conf
WEIRD_BLE_MARKER=/var/lib/robot/weird-ble
# 上游 pollen 仓库（aic3104-init.sh 等音频资产仍从那里取，与 Radxa 板共用）
UPSTREAM_RAW="${UPSTREAM_RAW:-https://raw.githubusercontent.com/pollen-robotics/microduck/main}"

needs_reboot=0

say()  { printf '%s\n' "$*"; }
warn() { say "warning: $*"; }
die()  { say "error: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "needs root:  sudo $0 $*"

# ── 参数 ─────────────────────────────────────────────────────────────────────
SKIP_ONNX=0; WEIRD_BLE=0; PAUSE_BTD=0; STATUS_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-onnx)        SKIP_ONNX=1 ;;
        --weird-ble)        WEIRD_BLE=1 ;;
        --pause-btd-on-pair) PAUSE_BTD=1 ;;
        --status)           STATUS_ONLY=1 ;;
        *) die "unknown argument: $1 (--skip-onnx, --weird-ble, --pause-btd-on-pair, --status)" ;;
    esac
    shift
done

script_dir="$(cd "$(dirname "$0")" && pwd)"

# ── 1. 舵机总线：uart2 overlay ───────────────────────────────────────────────
# A733 的 uart2（PB0/PB1 → 排针 11/13）。半双工方向由 HAT 上 U7/U6/Q1 硬件自动切换，
# 内核侧就是普通串口，overlay 只负责 status = "okay"。
ensure_user_overlay_word() {
    # user_overlays 是独立于 overlays= 的键（Armbian 从 /boot/overlay-user/ 里找）。
    if [ ! -f "$ENV_TXT" ]; then
        warn "no ${ENV_TXT}; not an Armbian image?
  Load the ${1} overlay by whatever means this image provides, then re-run.
  Everything else here will still be done."
        return 0
    fi
    if grep -Eq "^user_overlays=" "$ENV_TXT"; then
        grep -E '^user_overlays=' "$ENV_TXT" | grep -qw "$1" || {
            sed -i "s/^user_overlays=\(.*\)$/user_overlays=\1 $1/" "$ENV_TXT"
            needs_reboot=1
        }
    else
        echo "user_overlays=$1" >> "$ENV_TXT"
        needs_reboot=1
    fi
}

install_uart2_overlay() {
    say "motor bus: installing ${UART2_OVERLAY_NAME} overlay"

    command -v fdtput >/dev/null 2>&1 || apt-get install -y -qq device-tree-compiler >/dev/null 2>&1 || true

    src_dts="${script_dir}/../hardware/overlay/${UART2_OVERLAY_NAME}.dts"
    src_dtbo="${script_dir}/../hardware/overlay/${UART2_OVERLAY_NAME}.dtbo"
    [ -f "$src_dtbo" ] || src_dtbo=""

    local built=""
    if [ -n "$src_dtbo" ]; then
        built="$src_dtbo"
    elif [ -f "$src_dts" ] && command -v dtc >/dev/null 2>&1; then
        built="$(mktemp)"; built="${built}.dtbo"
        if dtc -@ -I dts -O dtb -o "$built" "$src_dts" 2>/dev/null; then
            say "compiled ${src_dts} with dtc"
        else
            warn "dtc could not compile ${src_dts}"
            built=""
        fi
    else
        warn "no ${src_dtbo} and (no ${src_dts} or no dtc) — overlay not installed
  The motor bus will not appear until this overlay is on the board."
    fi

    if [ -n "$built" ]; then
        mkdir -p "$OVERLAY_USER_DIR"
        dst="${OVERLAY_USER_DIR}/${UART2_OVERLAY_NAME}.dtbo"
        if [ ! -f "$dst" ] || ! cmp -s "$built" "$dst"; then
            cp "$built" "$dst"
            needs_reboot=1
        fi
        ensure_user_overlay_word "$UART2_OVERLAY_NAME"
    fi

    # 防御：任何占据 ttyS2 的 getty 都会吃掉舵机回包（上游 free_motor_port 的教训）。
    # A733 的 console 在 ttyS0（8/10），正常情况下这里无事可做。
    if systemctl is-enabled serial-getty@ttyS2.service >/dev/null 2>&1; then
        say "masking serial-getty@ttyS2 (it would eat servo replies)"
        systemctl mask serial-getty@ttyS2.service >/dev/null 2>&1 || true
    fi
}

# ── 2. ONNX Runtime（robotd 走策略要加载的推理库）───────────────────────────
# 与上游同源：aarch64 官方包解到 /usr/local/lib。版本可用环境变量 ONNX_VERSION 覆盖。
# 注意：ort 2.0.0-rc.11 起硬性要求 onnxruntime 动态库 >= 1.23.x（上游注释实证），
# 换固件版本时对着 firmware 的 Cargo.toml 核对。
configure_onnx() {
    [ "$SKIP_ONNX" = 1 ] && { say "onnx: skipped (--skip-onnx)"; return 0; }
    if ls /usr/local/lib/libonnxruntime.so* >/dev/null 2>&1; then
        say "onnx: already present in /usr/local/lib"
        return 0
    fi
    say "onnx: installing ONNX Runtime aarch64 ${ONNX_VERSION}"
    tmp=$(mktemp -d)
    url="https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-linux-aarch64-${ONNX_VERSION}.tgz"
    if curl -fsSL "$url" -o "$tmp/ort.tgz" \
        && tar -xzf "$tmp/ort.tgz" -C "$tmp" \
        && cp -a "$tmp"/onnxruntime-linux-aarch64-"${ONNX_VERSION}"/lib/. /usr/local/lib/; then
        ldconfig
        needs_reboot=0   # 库是动态链接时查找的，不需要重启
        say "onnx: installed to /usr/local/lib"
    else
        warn "could not download/install ONNX Runtime ${ONNX_VERSION}
  robotd 的策略加载会失败。手动装：
    curl -fsSL ${url} | tar -xz -C /tmp
    sudo cp -a /tmp/onnxruntime-linux-aarch64-${ONNX_VERSION}/lib/. /usr/local/lib/ && sudo ldconfig"
    fi
    rm -rf "$tmp"
}

# ── 3. 音频：TLV320AIC3104（fail-soft，与上游同一原则）───────────────────────
# 驱动是 snd-aic3x（AIC3x 家族，不是 aic31xx），vendor 内核没编，out-of-tree 构建见
# scripts/aic3x-module/README.md；缺模块只警告。
# mixer 用本仓的 aic3104-mixer.sh + aic3104-mixer.service，不取上游那份 aic3104-init.sh：
# 它按 Radxa 板的默认值写，DAC→Line 这一级会停在 6（= -56 dB），喇叭几乎听不见。
configure_audio() {
    say "audio: TLV320AIC3104 bring-up (fail-soft)"
    if ! modinfo snd-aic3x >/dev/null 2>&1 \
        && ! find "/lib/modules/$(uname -r)" -name 'snd-aic3x*' 2>/dev/null | grep -q .; then
        warn "kernel module snd-aic3x not found (Armbian vendor kernel has
  CONFIG_SND_SOC_TLV320AIC3X unset) — codec will not bind even with the overlay.
  Build it on the board: see scripts/aic3x-module/README.md."
    fi
    audio_pkgs="alsa-utils i2c-tools"
    missing=""
    for pkg in $audio_pkgs; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
    done
    if [ -n "$missing" ]; then
        apt-get update -qq || true
        # shellcheck disable=SC2086
        apt-get install -y -qq $missing || warn "apt failed — audio will not work on this board"
    fi

    src_audio="${script_dir}/../hardware/overlay/${AUDIO_OVERLAY_NAME}.dtbo"
    if [ -f "$src_audio" ]; then
        mkdir -p "$OVERLAY_USER_DIR"
        dst="${OVERLAY_USER_DIR}/${AUDIO_OVERLAY_NAME}.dtbo"
        if [ ! -f "$dst" ] || ! cmp -s "$src_audio" "$dst"; then
            cp "$src_audio" "$dst"
            needs_reboot=1
        fi
        ensure_user_overlay_word "$AUDIO_OVERLAY_NAME"
    else
        warn "no ${src_audio} — codec overlay not installed, no sound card yet
  (the codec driver also needs an out-of-tree module; see scripts/aic3x-module/.
  Walking works without it.)"
    fi

    # mixer：本仓维护的那份，开机 oneshot 设一遍（capture 路由 + DAC→Line 增益 + 喇叭音量）。
    local src_mix="${script_dir}/aic3104-mixer.sh"
    local src_unit="${script_dir}/aic3104-mixer.service"
    if [ -f "$src_mix" ] && [ -f "$src_unit" ]; then
        if [ ! -f /usr/local/bin/aic3104-mixer.sh ] \
            || ! cmp -s "$src_mix" /usr/local/bin/aic3104-mixer.sh; then
            install -m 755 "$src_mix" /usr/local/bin/aic3104-mixer.sh
            say "installed /usr/local/bin/aic3104-mixer.sh"
        fi
        if [ ! -f /etc/systemd/system/aic3104-mixer.service ] \
            || ! cmp -s "$src_unit" /etc/systemd/system/aic3104-mixer.service; then
            install -m 644 "$src_unit" /etc/systemd/system/aic3104-mixer.service
            systemctl daemon-reload
        fi
        systemctl is-enabled --quiet aic3104-mixer.service 2>/dev/null \
            || systemctl enable aic3104-mixer.service >/dev/null 2>&1 || true
        systemctl restart aic3104-mixer.service >/dev/null 2>&1 \
            || warn "aic3104-mixer.service did not start (no sound card yet? reboot needed)"
    else
        warn "scripts/aic3104-mixer.sh or .service missing — mixer stays at power-on levels"
    fi
}

# ── 4. ToF：I2C 总线的稳定名 ────────────────────────────────────────────────
# A733 上 HAT 的 I2C 落在哪个控制器（→ /dev/i2c-N 几号）要上板看
# /sys/bus/i2c/devices/ 才知道。已知后设 DUCK_I2C_KERNELS=<控制器 kobj 名>（如
# 2502000.i2c 那种 dt 别名）重跑本脚本，即可得到 /dev/i2c-pihat。
configure_tof() {
    rule=/etc/udev/rules.d/99-robot-i2c-pihat.rules
    if [ -n "${DUCK_I2C_KERNELS:-}" ]; then
        content="SUBSYSTEM==\"i2c-dev\", KERNELS==\"${DUCK_I2C_KERNELS}\", SYMLINK+=\"i2c-pihat\""
        if [ -f "$rule" ] && [ "$(cat "$rule")" = "$content" ]; then
            say "tof: /dev/i2c-pihat rule already in place"
            return 0
        fi
        printf '%s\n' "$content" > "$rule"
        chmod 644 "$rule"
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
        say "tof: /dev/i2c-pihat -> ${DUCK_I2C_KERNELS}"
    else
        [ -f "$rule" ] || warn "tof: DUCK_I2C_KERNELS not set — /dev/i2c-pihat rule skipped
  上板后跑  ls /sys/bus/i2c/devices/  找到 codec/ToF 挂的控制器名（如 2502400.i2c），
  再 DUCK_I2C_KERNELS=<名字> sudo $0 重跑即可。tofd 默认回退 /dev/i2c-3，也能先用。"
    fi
}

# ── 5. 蓝牙手柄（aic8800sd，与上游同芯片 → 同三机制）────────────────────────
configure_bluetooth() {
    # UserspaceHID=false：经典蓝牙手柄的报告走内核 hidp。BlueZ 5.82 默认 true 时，
    # 无名 Switch 克隆手柄的 IMU 流会把 bluetoothd 打到 15% CPU（上游 2026-09-09 实测）。
    if [ -f "$BT_INPUT_CONF" ]; then
        grep -Eq '^[[:space:]]*UserspaceHID[[:space:]]*=[[:space:]]*false' "$BT_INPUT_CONF" \
            || { sed -i -E 's|^[[:space:]]*#?[[:space:]]*UserspaceHID[[:space:]]*=.*|UserspaceHID=false|' "$BT_INPUT_CONF"; needs_reboot=1; }
    else
        mkdir -p "$(dirname "$BT_INPUT_CONF")" 2>/dev/null || true
        printf '[General]\nUserspaceHID=false\n' > "$BT_INPUT_CONF" 2>/dev/null && needs_reboot=1
    fi

    if [ "$WEIRD_BLE" = 0 ] && [ "$PAUSE_BTD" = 0 ]; then
        say "bluetooth: no --weird-ble / --pause-btd-on-pair given (a pad that will not bond wants one)"
        return 0
    fi
    if [ ! -f "$BT_CONF" ]; then
        warn "no ${BT_CONF}; skipping the gamepad Bluetooth settings"
        return 0
    fi
    if [ "$WEIRD_BLE" = 1 ]; then
        if grep -Eq '^[[:space:]]*Privacy[[:space:]]*=[[:space:]]*device' "$BT_CONF"; then
            say "bluetooth Privacy already device"
        else
            if grep -Eq '^[[:space:]]*#?[[:space:]]*Privacy[[:space:]]*=' "$BT_CONF"; then
                sed -i -E 's|^[[:space:]]*#?[[:space:]]*Privacy[[:space:]]*=.*|Privacy = device|' "$BT_CONF"
            elif grep -q '^\[General\]' "$BT_CONF"; then
                sed -i '/^\[General\]/a Privacy = device' "$BT_CONF"
            else
                printf '\n[General]\nPrivacy = device\n' >> "$BT_CONF"
            fi
            needs_reboot=1
        fi
    fi
    # marker：robotctl 读它决定配对时暂停 btd。两个 flag 都写它。
    if [ ! -f "$WEIRD_BLE_MARKER" ]; then
        mkdir -p "$(dirname "$WEIRD_BLE_MARKER")"
        printf '# This board needs btd paused while a gamepad bonds (aic8800). See\n# firmware setup-board.sh --weird-ble docs; delete to undo.\n' > "$WEIRD_BLE_MARKER"
        chmod 644 "$WEIRD_BLE_MARKER"
        say "wrote ${WEIRD_BLE_MARKER} so robotctl pauses btd while a pad bonds"
    fi
}

# ── 6. robotd 二进制（payload 里有就装；没有则跳过）─────────────────────────
# apply-rootfs.sh --payload 把交叉编译产物放在 /opt/robot/payload/runtime-bin/：
#   robotd, robotctl（aarch64，静态链 onnxruntime，GLIBC≥2.39 → trixie 满足）
#   robotd.toml（默认配置，装到 /etc/robot/robotd.toml，已存在则不覆盖）
# 注意：这是台架/dev 用的手工安装，不走官方 updaterd 签名发布链。
configure_runtime_binaries() {
    src=/opt/robot/payload/runtime-bin
    [ -x "$src/robotd" ] || { say "runtime: no payload binary at ${src}/robotd — skip
  （板上没有 robotd。装法：把交叉编译的 robotd/robotctl 放进 ${src}/ 后重跑本脚本，
   或按上游 docs/robot/install-dev.md 走官方 provision 流程）"
        return 0; }
    groupadd -rf robot 2>/dev/null || true
    install -m 755 "$src/robotd" /usr/local/bin/robotd
    if [ -f "$src/robotctl" ]; then
        install -m 755 "$src/robotctl" /usr/local/bin/robotctl
    fi
    if [ -f "$src/robotd.toml" ] && [ ! -f /etc/robot/robotd.toml ]; then
        mkdir -p /etc/robot
        install -m 644 "$src/robotd.toml" /etc/robot/robotd.toml
        say "runtime: wrote /etc/robot/robotd.toml (defaults; edit [bus] before real hardware)"
    fi
    cat > /etc/systemd/system/robotd.service <<'UNIT'
[Unit]
Description=MicroDuck robot daemon (dev image, hand-installed)
After=network.target

[Service]
ExecStart=/usr/local/bin/robotd
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload 2>/dev/null || true
    systemctl is-enabled --quiet robotd.service 2>/dev/null \
        || systemctl enable robotd.service >/dev/null 2>&1 || true
    say "runtime: installed robotd/robotctl to /usr/local/bin, robotd.service enabled"
}

# ── 7. 板况报告（--status 也走这里）─────────────────────────────────────────
report() {
    say "board status"

    if [ -e "$MOTOR_PORT" ]; then
        printf '  %-22s %s\n' "motor bus" "$MOTOR_PORT present"
    elif [ "$needs_reboot" = 1 ]; then
        printf '  %-22s %s\n' "motor bus" "$MOTOR_PORT absent — enabled, pending reboot"
    else
        printf '  %-22s %s\n' "motor bus" "$MOTOR_PORT ABSENT"
        warn "${MOTOR_PORT} missing and no overlay change pending. Check:
  ls /boot/overlay-user/ ; grep user_overlays ${ENV_TXT} ; dmesg | grep -iE 'ttyS|uart2'
  pinmux: cat /sys/kernel/debug/pinctrl/*/pinmux-pins | grep -i PB0"
    fi

    holder=""
    if command -v fuser >/dev/null 2>&1 && [ -e "$MOTOR_PORT" ]; then
        holder="$(fuser "$MOTOR_PORT" 2>/dev/null | tr -d ' ')"
    fi
    if [ -n "$holder" ]; then
        printf '  %-22s %s\n' "motor bus owner" "IN USE by pid ${holder}"
        warn "something else has ${MOTOR_PORT} open. A reader on this port consumes servo
  replies and every motor will look absent. Identify:  sudo fuser -v ${MOTOR_PORT}"
    else
        printf '  %-22s %s\n' "motor bus owner" "free"
    fi

    console_tty="$(sed -n 's/.*[[:space:]]console=\([^,[:space:]]*\).*/\1/p' /proc/cmdline | head -1)"
    if [ -n "$console_tty" ]; then
        if [ "/dev/${console_tty}" = "$MOTOR_PORT" ]; then
            printf '  %-22s %s\n' "console" "${console_tty} (= motor bus — WRONG for this wiring)"
        else
            printf '  %-22s %s\n' "console" "${console_tty} (header pins 8/10 — bus stays free)"
        fi
    else
        printf '  %-22s %s\n' "console" "none on serial (HDMI/network only)"
    fi

    onnx_lib=""
    for f in /usr/local/lib/libonnxruntime.so*; do
        [ -e "$f" ] || continue
        onnx_lib="$f"
        break
    done
    if [ -n "$onnx_lib" ]; then
        printf '  %-22s %s\n' "onnx runtime" "$(basename "$onnx_lib")"
    else
        printf '  %-22s %s\n' "onnx runtime" "MISSING (robotd policies will not load)"
    fi

    if command -v aplay >/dev/null 2>&1 && aplay -l 2>/dev/null | grep -qi 'aic\|aic31'; then
        printf '  %-22s %s\n' "audio card" "aic310x present"
    else
        printf '  %-22s %s\n' "audio card" "none (fails soft — robot walks without it)"
    fi

    if [ -f "$WEIRD_BLE_MARKER" ]; then
        printf '  %-22s %s\n' "btd on pairing" "paused — the marker is set"
    else
        printf '  %-22s %s\n' "btd on pairing" "not paused — a pad that will not bond wants --pause-btd-on-pair"
    fi

    pads=""
    for node in /dev/input/js*; do
        [ -e "$node" ] || continue
        pads="${pads}${node} "
    done
    printf '  %-22s %s\n' "gamepad" "${pads:-none connected}"
}

if [ "$STATUS_ONLY" = 1 ]; then
    report
    exit 0
fi

# ── 执行 ────────────────────────────────────────────────────────────────────
install_uart2_overlay
configure_onnx
configure_audio
configure_tof
configure_bluetooth
configure_runtime_binaries

say ""
report

if [ "$needs_reboot" = 1 ]; then
    say ""
    say "changes pending a reboot. After it:"
    say "  1. $0 --status                  # /dev/ttyS2 应出现且 owner=free"
    say "  2. stty -F ${MOTOR_PORT} 1000000 raw -echo -crtscts"
    say "  3. 接上 HAT 后用 robotctl 或手动 sync_read ping 一只舵机"
else
    say ""
    say "no reboot needed."
fi
