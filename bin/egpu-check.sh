#!/bin/bash
# Did the eGPU fall off the PCIe bus? Run AFTER a crash reboot.
#
# Background: an RX 9070 on OCuLink (M.2 adapter) dropped off the bus 3x on
# 2026-08-27. Every time the first failure was a D3hot->D0 resume on the GPU's
# HDA function (c4:00.1), ~1-2s before amdgpu noticed. Mitigation = keep the
# whole chain in D0 (amdgpu.runpm=0, snd_hda_intel.power_save=0 /
# power_save_controller=N, pcie_port_pm=off, plus udev pinning).
#
# Usage: ./egpu-check.sh [boot_index]     (default -1 = the boot that died)

B="${1:--1}"
echo "=== boot $B ==="
journalctl --list-boots 2>/dev/null | awk -v b="$B" '$1==b'

n=$(journalctl -b "$B" -k --no-pager 2>/dev/null \
      | grep -cE 'device inaccessible|lost from bus')
echo
echo "crash signatures: $n"
echo

if [ "$n" -eq 0 ]; then
    echo "HELD. No bus-drop in that boot."
    echo "If it still crashed, the cause is something new -- grab the trace:"
    echo "  journalctl -b $B -k | grep -iE 'amdgpu|drm' | tail -60"
else
    echo "SAME FAILURE got through despite the D0 pinning."
    echo "=> Treat as physical. Next steps, in order:"
    echo "   1. Reseat BOTH OCuLink ends and the M.2 adapter."
    echo "   2. Check the dock's PSU / power delivery."
    echo "   3. Add pcie_aspm=off to /etc/default/limine, then: sudo limine-update"
    echo
    echo "--- onset ---"
    journalctl -b "$B" -k --no-pager -o short-precise 2>/dev/null \
      | grep -E 'Unable to change power state|CORB reset|lost from bus' | head -5
fi

echo
echo "--- current pinning (this boot) ---"
printf "%-16s %-8s %-10s %s\n" DEVICE D3COLD CONTROL STATUS
for d in 0000:00:03.1 0000:c2:00.0 0000:c3:00.0 0000:c4:00.0 0000:c4:00.1; do
    [ -e "/sys/bus/pci/devices/$d" ] || continue
    printf "%-16s %-8s %-10s %s\n" "$d" \
      "$(cat /sys/bus/pci/devices/$d/d3cold_allowed 2>/dev/null)" \
      "$(cat /sys/bus/pci/devices/$d/power/control 2>/dev/null)" \
      "$(cat /sys/bus/pci/devices/$d/power/runtime_status 2>/dev/null)"
done
