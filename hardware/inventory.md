# Hardware inventory

Snapshot taken 2026-09-13. Reference for identifying the machine after a
reinstall — PCI addresses in particular are referenced throughout this repo.

## Base

```
CPU      : AMD RYZEN AI MAX+ 395 w/ Radeon 8060S
Memory   : 125Gi
Kernel   : 7.2.4-1-cachyos
Distro   : CachyOS
Desktop  : KDE Plasma (Wayland)
```

## eGPU chain (PCI)

```
00:03.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Strix/Strix Halo GPP Bridge [1022:150b]
c2:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Upstream Port of PCI Express Switch [1002:1478] (rev 24)
c3:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 XL Downstream Port of PCI Express Switch [1002:1479] (rev 24)
c4:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0)
c4:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 HDMI/DP Audio Controller [1002:ab40]
```

## Link budget

The OCuLink hop is the bottleneck and should look like this in `dmesg`:

```
pci 0000:c2:00.0: 63.012 Gb/s available PCIe bandwidth, limited by 16.0 GT/s PCIe x4 link at 0000:00:03.1 (capable of 504.112 Gb/s with 32.0 GT/s PCIe x16 link)
```

Anything lower means the link trained badly — a genuine reason to suspect cabling.

## Displays

Both DisplayPort monitors hang off the 9070 XT (`card0`), not the iGPU (`card1`).

```
card0-DP-2  connected
card0-DP-3  connected
```

## Storage

```
NAME          SIZE TYPE MOUNTPOINTS
zram0       125.1G disk [SWAP]
nvme0n1       1.8T disk 
├─nvme0n1p1     4G part /boot
└─nvme0n1p2   1.8T part /
```
