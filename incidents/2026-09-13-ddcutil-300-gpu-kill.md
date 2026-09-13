# 2026-09-13 — ddcutil 3.0.0 takes the GPU off the bus at login

**Symptom:** three consecutive boots failed to reach a usable desktop. Display died
seconds after login; each time the machine was hard power-cycled.

**Cause:** `ddcutil` 3.0.0, not hardware. Upstream regression
[rockowitz/ddcutil#629](https://github.com/rockowitz/ddcutil/issues/629), fixed in 3.0.1.

**Resolution:** downgraded to 2.2.7-1.1 and pinned via `IgnorePkg`.

> The OCuLink cable was replaced during this incident and **that was not the fix.**
> The evidence below is what ruled it out. Worth reading before replacing hardware
> on this machine again.

## Chain of events

```
org_kde_powerdevil: Initializing libddcutil. ddcutil version: 3.0.0
org_kde_powerdevil: (i2c_ioctl_reader1) EREMOTEIO(-121), device=/dev/i2c-7
  +1.2s  amdgpu: Fence fallback timer expired on ring gfx_0.0.0
  +2.2s  amdgpu: device lost from bus!
  +10.4s kwin_wayland: Pageflip timed out!          <- screen dies here
         plasma-powerdevil.service: start timed out -> SIGKILL
```

PowerDevil loads libddcutil at session start. 3.0.0's x37 DDC/CI probe against the
AMDGPU DM AUX buses retry-storms and wedges amdgpu; the GPU then leaves the PCIe bus.
The PowerDevil service start timeout is the part that presents as "can't log in".

## Why it was not the cable

**1. Every failure fired ~2s after libddcutil initialised.**

| boot | libddcutil init | `device lost from bus` | Δ |
|---|---|---|---|
| -3 | 10:42:37.34 | 10:42:39.31 | 1.95s |
| -2 | 11:04:09.49 | 11:04:11.53 | 2.04s |
| -1 | 11:07:38.16 | 11:07:40.33 | 2.20s |

**2. Zero amdgpu faults before that init, in all three boots.** 0 before / 23, 25
and 43 after. A clean split at the software boundary.

**3. One failing boot sat at the login greeter for 20 minutes**, compositing both
displays without a single error, and died 2 seconds after login. A marginal cable
does not idle perfectly for 20 minutes and then fail on a software event, three
times, with the same latency.

**4. The session that predated the upgrade ran ~13h on the same cable**, including
Counter-Strike 2 and FFXIV, with zero GPU errors. `ddcutil` was upgraded
2.2.7 → 3.0.0 at 19:09 the previous evening; that session's PowerDevil already had
the old library mapped in memory. It was also the only boot in the window that
ended with a clean shutdown rather than a power cut.

**5. The PCIe link trained identically in failing and working boots:**
`63.012 Gb/s ... 16.0 GT/s PCIe x4 link at 0000:00:03.1`. No degradation, no
retraining, no link-down.

**6. OCuLink carries PCIe only.** It is physically unrelated to the DisplayPort AUX
channel that DDC/CI runs on. Swapping it cannot change whether a monitor ACKs i2c
address 0x37.

## Why the post-swap boot survived

Luck, not the cable. That boot logged `X37 detection succeeded on try 2` — the probe
answered early and never entered the retry storm. In the failing boots i2c-7 never
answered and ddcutil kept hammering it. The machine was still fully exposed after
the cable swap; only the downgrade actually closed it.

## Guardrail added

`pacman/` in this repo — a PreTransaction hook that blocks `ddcutil` (and other
known-hostile packages) before the transaction runs. It sits at the pacman layer
deliberately, so it fires for `pacman -Syu`, `yay`, and the cachy-update tray alike.
