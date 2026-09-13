# 2026-08-27 — eGPU falls off the PCIe bus on a failed D3 resume

**Symptom:** hard lock, three times in one day. Display dead, machine unresponsive,
only a power cycle recovered it.

**Cause:** PCIe runtime power management on the eGPU chain. A failed D3hot→D0 resume
took the device off the bus; amdgpu then could not reset a device that was no longer
there (`GPU reset ret = -19`, ENODEV).

**Resolution:** pin the whole chain in D0 — kernel parameters + udev rules + a
systemd oneshot. Mitigated, but the underlying link marginality was never proven
either way.

## Signature

The failure always started on the GPU's **HDMI audio function** (`c4:00.1`), 1–2
seconds before amdgpu noticed anything:

```
snd_hda_intel 0000:c4:00.1: Unable to change power state from D3hot to D0, device inaccessible
snd_hda_intel 0000:c4:00.1: CORB reset timeout#2, CORBRP = 65535
  -> amdgpu 0000:c4:00.0: device lost from bus!
  -> amdgpu 0000:c4:00.0: GPU reset ret = -19
```

That HDA prelude is what distinguishes this incident from the
[2026-09-13 ddcutil failure](2026-09-13-ddcutil-300-gpu-kill.md), which produces the
same `device lost from bus` line with no `snd_hda_intel` involvement at all.

The gfx/sdma ring timeouts and kwin's `Pageflip timed out! This is a bug in the
amdgpu kernel driver` are downstream noise. kwin's message is wrong about the cause.

## Why it happened

`power_save=10` — from `/usr/lib/udev/rules.d/20-audio-pm.rules`, shipped by
`cachyos-settings` — suspended the audio function after 10 seconds of silence. The
whole chain also had `d3cold_allowed=1` and `power/control=auto`, so the OCuLink
link was retraining constantly. Every wake was a dice roll.

Workload was irrelevant: idle desktop, FFXIV, and a bare terminal all produced the
same trace. This was a power-state resume failing over OCuLink, not a load transient.

## Mitigation

1. **Kernel parameters** — see `kernel/cmdline.md`.
2. **`udev/81-egpu-no-runtime-pm.rules`** — pins `power/control=on` and
   `d3cold_allowed=0` on the GPU, its HDA function, both switch ports, and the M.2
   root port.
3. **`systemd/egpu-pin-pm.service` + `bin/egpu-pin-pm`** — the udev rule alone is
   **not sufficient**: `snd_hda_intel` calls `pm_runtime_allow()` after its bind
   uevent is processed, resetting `c4:00.1` back to `auto`. This oneshot runs after
   the driver settles and re-pins it. `udev/82-egpu-pin-pm-trigger.rules` re-triggers
   it on hotplug.
4. **`20-audio-pm.rules` masked** by a 0-byte file in `/etc/udev/rules.d/`.

Verify with `bin/egpu-check.sh` — all five devices should report
`d3cold_allowed=0`, `power/control=on`.

## Status

Suppressed, not root-caused. The mitigation removes the *trigger*; whether the link
itself is marginal was never established, and the platform reports no AER support
(`_OSC: platform does not support [SHPCHotplug AER]`), so there is no PCIe error
reporting to settle it.

If this exact signature — **with** the `snd_hda_intel` D3 prelude — recurs despite
the pinning, treat it as physical: reseat both OCuLink ends and the M.2 adapter,
check the dock PSU, then try `pcie_aspm=off`.

Do **not** apply that advice to a bare `device lost from bus` with no HDA prelude.
That mistake is exactly what led to an unnecessary cable replacement on 2026-09-13.
