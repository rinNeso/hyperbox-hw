# Kernel command line

Set in `/etc/default/limine`, applied with `sudo limine-update`. Verify with
`cat /proc/cmdline` after any bootloader or kernel change.

## The eGPU stability parameters

```
amdgpu.runpm=0 snd_hda_intel.power_save=0 snd_hda_intel.power_save_controller=N pcie_port_pm=off
```

These are not tuning. Each one closes a path that took the GPU off the PCIe bus:

| Parameter | Why |
|---|---|
| `amdgpu.runpm=0` | Stops amdgpu runtime-suspending the GPU into D3. The resume is what fails. |
| `snd_hda_intel.power_save=0` | The eGPU's HDA function (`c4:00.1`) was the *first* device to fail every time — it autosuspended after 10s of silence and then could not resume. |
| `snd_hda_intel.power_save_controller=N` | Same, for the controller rather than the codec. |
| `pcie_port_pm=off` | Stops the bridges/root port above the GPU from suspending underneath it. |

Removing any of these reopens the 2026-08-27 failure. See
`incidents/2026-08-27-egpu-d3-bus-drop.md`.

## The rest of the line

```
quiet nowatchdog splash rw root=UUID=<your-root-uuid>
ttm.pages_limit=27648000 ttm.pages_pool_size=27648000
```

- `ttm.pages_*` raise the TTM page limits for the large unified memory pool on
  Strix Halo (relevant to local LLM work on the iGPU).
- `root=UUID=...` is machine-specific and will differ on a reinstall — take it
  from the new installer, do not copy it from here.

## Applying

```sh
sudoedit /etc/default/limine     # edit KERNEL_CMDLINE[default]
sudo limine-update
cat /proc/cmdline                # after reboot, confirm the params are present
```

## If the eGPU still drops with all of this set

Then the mitigation is not holding and it is worth treating as physical. In order:
reseat both OCuLink ends and the M.2 adapter, check the dock PSU, then try adding
`pcie_aspm=off`. **But first confirm the failure signature actually matches** —
see `CLAUDE.md`. A `device lost from bus` with no `snd_hda_intel` D3 prelude is a
different bug and reseating cables will not fix it.
