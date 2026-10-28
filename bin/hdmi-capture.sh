#!/bin/bash
# Capture a third-monitor link failure on the eGPU's HDMI port.
#
# Background: a 2560x1600@120 generic-EDID panel on card0-HDMI-A-1 (the RX
# 9070's only HDMI) blanked and recovered on a ~15s cycle. The logs from that
# incident are gone -- cachyos-settings caps the journal at 50M, which holds
# about one day. This script writes its own file instead of trusting journald.
#
# A ~15s blank/recover cadence is a link that trains, fails a periodic status
# check, and retrains -- NOT the bus-drop signature in incidents/. If you see
# "device lost from bus" here, stop and read CLAUDE.md; that is a different bug.
#
# Usage:  sudo ./hdmi-capture.sh [connector]      (default card0-HDMI-A-1)
#         plug the monitor in, let it cycle 4-5 times, then Ctrl-C.

set -u
CONN="${1:-card0-HDMI-A-1}"
[ "$(id -u)" -eq 0 ] || { echo "run me with sudo"; exit 1; }
[ -e "/sys/class/drm/$CONN" ] || { echo "no such connector: $CONN"; exit 1; }

# Everything belongs to the invoking user, not root.
U="${SUDO_USER:-root}"
UHOME="$(getent passwd "$U" | cut -d: -f6)"
UID_N="$(id -u "$U")"
OUT="$UHOME/hdmi-capture-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"; chown "$U:$U" "$OUT"
echo "capturing to $OUT"

# kscreen-doctor is a session client -- it needs the user's bus, not root's.
kd() {
    sudo -u "$U" env \
        XDG_RUNTIME_DIR="/run/user/$UID_N" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_N/bus" \
        kscreen-doctor -o 2>&1
}

mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null

# 0x116 = DP | ATOMIC | KMS | DRIVER. Verbose; that is the point.
PREV_DEBUG=$(cat /sys/module/drm/parameters/debug)
echo 0x116 > /sys/module/drm/parameters/debug

cleanup() {
    trap - INT TERM
    echo "$PREV_DEBUG" > /sys/module/drm/parameters/debug
    kill "$DMESG_PID" "$UDEV_PID" 2>/dev/null
    sleep 1

    cat "/sys/class/drm/$CONN/status" > "$OUT/status.after" 2>/dev/null
    if [ -s "/sys/class/drm/$CONN/edid" ]; then
        cp "/sys/class/drm/$CONN/edid" "$OUT/edid.bin"
        edid-decode "$OUT/edid.bin" > "$OUT/edid.txt" 2>&1
        echo "  EDID captured -> edid.txt"
    else
        echo "  no EDID readable at exit (sink was disconnected)"
    fi
    for f in /sys/kernel/debug/dri/*/"${CONN#*-}"/*; do
        [ -f "$f" ] && { echo "--- $f"; cat "$f" 2>/dev/null; }
    done > "$OUT/debugfs.after" 2>/dev/null
    kd > "$OUT/kscreen.after"
    chown -R "$U:$U" "$OUT"

    python3 - "$OUT/kernel.log" <<'PY'
import re, sys, datetime
pat = re.compile(r'link training|link_training|\bFRL\b|hotplug|\bHPD\b|retrain|'
                 r'failed|link status|dc_link|atomic_commit|enable_stream|disable_stream',
                 re.I)
ts  = re.compile(r'^(\d{4}-\d\d-\d\dT[\d:.,]+)')
rows, prev = [], None
for line in open(sys.argv[1], errors='replace'):
    if not pat.search(line): continue
    m = ts.match(line)
    if not m: continue
    t = datetime.datetime.fromisoformat(m.group(1).replace(',', '.'))
    d = (t - prev).total_seconds() if prev else 0.0
    rows.append((d, line.strip()[:150])); prev = t
print("\n=== link events: gap, then message ===")
for d, l in rows[-45:]:
    print(f"  +{d:6.1f}s  {l}")
gaps = [d for d, _ in rows if 3 < d < 120]
if gaps:
    gaps.sort()
    print(f"\n  {len(gaps)} inter-event gaps, median {gaps[len(gaps)//2]:.1f}s"
          f"  (a tight cluster ~15s = periodic retrain)")
PY

    echo
    echo "=== bus-drop check (should be empty) ==="
    grep -aE 'device lost from bus|device inaccessible' "$OUT/kernel.log" || echo "  clean"
    echo
    echo "written: $OUT"
    exit 0
}
trap cleanup INT TERM

{ echo "connector: $CONN"; echo "kernel: $(uname -r)"; echo "cmdline: $(cat /proc/cmdline)"; } > "$OUT/context"
cat "/sys/class/drm/$CONN/status" > "$OUT/status.before" 2>/dev/null
kd > "$OUT/kscreen.before"

dmesg -w --time-format=iso > "$OUT/kernel.log" & DMESG_PID=$!
udevadm monitor --udev --property --subsystem-match=drm > "$OUT/udev.log" & UDEV_PID=$!

echo
echo "Plug the monitor into $CONN now."
echo "Let it blank and recover 4-5 times (~90s), then press Ctrl-C."
wait "$DMESG_PID"
