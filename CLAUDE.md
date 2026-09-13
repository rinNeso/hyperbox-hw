# Context for agent sessions on hyperBox

Read this before diagnosing anything graphics-, display- or boot-related on this
machine. It exists because the obvious reading of the logs here is usually wrong.

## The trap

`amdgpu 0000:c4:00.0: device lost from bus!` has been produced by **two unrelated
root causes** on this machine. It means "PCIe config reads to the GPU now return
0xFFFFFFFF" — it does not tell you why. Downstream of it you will always also see
SMU `response:0xFFFFFFFF`, ring/fence timeouts, `flip_done timed out`, and kwin's
`Pageflip timed out! This is a bug in the amdgpu kernel driver`. **All of that is
noise.** kwin's message in particular is actively misleading — it blames the driver.

Distinguish by what comes *before* the bus loss:

| Prelude | Cause | Writeup |
|---|---|---|
| `snd_hda_intel ... Unable to change power state from D3hot to D0` + `CORB reset timeout` | PCIe runtime PM on the eGPU's HDA function | `incidents/2026-08-27-egpu-d3-bus-drop.md` |
| `org_kde_powerdevil: Initializing libddcutil` ~2s earlier | ddcutil 3.0.0 wedging amdgpu via DDC/CI probe | `incidents/2026-09-13-ddcutil-300-gpu-kill.md` |
| Neither | Something new. Do not assume it is the cable. | — |

## Before blaming the hardware

The eGPU sits on an OCuLink cable, which makes "it's the cable" an attractive and
usually wrong conclusion. It has been wrong at least once, and the cable was
replaced for nothing. Check these first:

- **Did the link train normally?**
  `journalctl -b -1 -k | grep 'available PCIe bandwidth'` → expect
  `63.012 Gb/s ... 16.0 GT/s PCIe x4 link at 0000:00:03.1`. Identical in healthy
  and failing boots means the physical link is fine.
- **How long was it healthy?** A marginal cable does not idle at a login greeter
  for 20 minutes, or game for 13 hours, and then fail on a software event.
- **What ran immediately before?** Correlate to the second, not the minute. Both
  incidents had a trigger within ~2s of the first fault.
- **There is no AER.** Firmware owns it (`_OSC: platform does not support
  [SHPCHotplug AER]`), so the kernel reports no PCIe correctable errors either
  way. Absence of AER evidence is not evidence of a healthy link — and not
  evidence of a bad one.

`bin/egpu-check.sh <boot>` automates the first pass.

## Load-bearing state that is easy to clobber

- **Kernel cmdline** lives in `/etc/default/limine`, applied by `limine-update`.
  If `amdgpu.runpm=0` or `pcie_port_pm=off` goes missing from `/proc/cmdline`,
  the 2026-08-27 failure comes back.
- **`/etc/udev/rules.d/20-audio-pm.rules` is a deliberate 0-byte file.** It masks
  a rule of the same name shipped by `cachyos-settings`. It is not an accident and
  must not be "cleaned up". If `cachyos-settings` ever ships audio PM under a
  different filename, the mask stops working.
- **`egpu-pin-pm.service`** re-pins the HDA function after `snd_hda_intel` resets
  `power/control` to `auto` post-bind. The udev rule alone is not sufficient —
  that was the whole point of the second fix pass.
- **`ddcutil` is held at 2.2.7** via `IgnorePkg` in `/etc/pacman.conf`. Do not
  lift that until 3.0.1+ is actually in the repos.

## Conventions

- Verify against the live system before asserting; this repo can drift. `./check.sh`
  reports drift.
- Changes here should be reflected on the machine and vice versa — if you fix
  something on the box, update the repo in the same session or it will be lost.
- Incident writeups are evidence-first: what the logs actually showed, then the
  conclusion. Keep that order; it is what makes them re-checkable later.
