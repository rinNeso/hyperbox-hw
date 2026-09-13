# hyperbox-hw

Hardware-specific configuration, guardrails and incident history for **hyperBox**.

This is a restore point. If the OS gets nuked and reinstalled, this repo is what
turns a fresh install back into a working machine — not the dotfiles, not the
package list, but the small pile of non-obvious settings that took real debugging
to find and that nothing on the system will tell you again.

Everything here is distro-agnostic in *knowledge* even where it is Arch-specific
in *mechanism*. The kernel parameters and udev rules are facts about the hardware;
the pacman hook is one implementation of a guardrail that would need porting.

## The machine

| | |
|---|---|
| Chassis | Framework Desktop |
| CPU / APU | AMD Ryzen AI MAX+ 395 (Strix Halo), Radeon 8060S iGPU |
| dGPU | Radeon RX 9070 XT (Navi 48) — **external, over OCuLink** |
| eGPU link | M.2 → OCuLink adapter in root port `0000:00:03.1`, PCIe Gen4 x4 (~63 Gb/s) |
| Displays | 2× DisplayPort, both on the 9070 XT (`card0-DP-2`, `card0-DP-3`) |
| OS | CachyOS, KDE Plasma on Wayland |

### PCI topology of the eGPU chain

```
0000:00:03.1   root port (M.2 → OCuLink adapter)
└── c2:00.0    Navi upstream switch port    [1002:1478]
    └── c3:00.0  downstream switch port     [1002:1479]
        ├── c4:00.0  RX 9070 XT             [1002:7550]
        └── c4:00.1  its HDMI audio func    [1002:ab40]
```

That HDA function at `c4:00.1` is not incidental — it is the device that took the
whole GPU off the bus in the 2026-08-27 incident. Any power-management change that
touches it is a hazard.

## What's here

| Path | What it is |
|---|---|
| `kernel/cmdline.md` | Boot parameters that keep the eGPU alive, and why each one is there |
| `udev/` | Rules pinning the eGPU chain out of runtime PM, plus the audio-PM mask |
| `systemd/`, `bin/egpu-pin-pm` | Re-pins the HDA function after `snd_hda_intel` resets it |
| `bin/egpu-check.sh` | Post-crash triage: did the GPU fall off the bus, and was it this bug? |
| `pacman/` | Hardware watchlist: blocks or warns on upgrades known to break this machine |
| `desktop/` | Forces the update tray into kitty |
| `incidents/` | Full writeups of both GPU failures, with the evidence that identified them |

## Restore order on a clean install

1. **Kernel parameters first** — `kernel/cmdline.md`. Without these the eGPU can
   drop off the bus before you finish setting anything else up.
2. **udev + the pin service** — `./install.sh` handles both.
3. **Pacman guardrail** — also `./install.sh`. Re-pin `ddcutil` if 3.0.1 still
   isn't in the repos (see `incidents/2026-09-13-ddcutil-300-gpu-kill.md`).
4. **Verify** — `./check.sh`, then reboot and run `bin/egpu-check.sh 0`.

```sh
sudo ./install.sh      # idempotent; safe to re-run
./check.sh             # diffs live system against this repo
```

## Read the incidents before changing anything here

Both GPU failures in `incidents/` produced the *same* kernel line —
`amdgpu 0000:c4:00.0: device lost from bus!` — from completely different causes.
One was PCIe power management, one was a userspace library probing an i2c bus.
That line alone tells you nothing about which problem you have. The writeups
explain how to tell them apart, which matters because the wrong diagnosis sends
you chasing hardware that is fine.
