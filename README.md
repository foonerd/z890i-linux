# Linux workstation on Intel Z890: NVMe RAID1, Thunderbolt dock, kernel tuning

Known locally as **Nerbuntu**: Ubuntu, after a nerd has been at it. Ubuntu as shipped is a sensible operating system that makes sensible choices on your behalf. This one has had every one of those choices inspected, several reversed, two kernel parameters argued with at source level, and a display server rebuilt from the next release because the shipped one disagreed with a clock widget.

> **Handling instructions.** Nerbuntu is tuned for the owner's hardware and habits and assumes you have read why. Applied blind it can and will: let a RAID resync run the source drive hard enough that its controller stops answering (a 990 PRO did, at 1.3 GB/s); hand your Thunderbolt dock's PCIe devices to a kernel that has no permission to bring them back (`pcie_aspm=off`); switch off the picture on a Thunderbolt monitor (`thunderbolt.host_reset=0`); hide every GNOME extension you installed yourself (a release upgrade did that, not us); and present a mirror of 3.6 TB as an ejectable volume one click from the trash. The CPU will not pull its own pins out of the socket and the LAN will not walk away, but the 10G card may quietly negotiate 1G with a switch that was never asked, and a Stream Deck plugged into the wrong USB-C port will sit there powered, lit and invisible. Everything in this repository was arrived at by running it, including the parts that are documented as mistakes. Read those first.

Configuration and notes for a mini-ITX Linux workstation built around an Intel Core Ultra 9 285K, a Crucial T700 as the system drive and two Samsung 990 PRO in a Linux software RAID1 (md) for data. The repository started life on an MSI MPG Z890I EDGE TI WIFI under Ubuntu 24.04 and now describes an ASRock Z890I Nova WiFi under Ubuntu 26.04. Both boards are covered; where they differ, the text says which is which.

Everything here was arrived at by running it. Several of the 2025 settings turned out to be wrong and are documented as such rather than removed, because the reasons are the useful part.

## Hardware

| | 2025 build | 2026 build |
|---|---|---|
| Board | MSI MPG Z890I EDGE TI WIFI | ASRock Z890I Nova WiFi (BIOS 3.40) |
| CPU | Intel Core Ultra 9 285K, 8 P-cores + 16 E-cores | same |
| RAM | 2 x 48 GB DDR5 | same |
| System drive | Crucial T700 4 TB, PCIe 5.0 x4 | same, front M.2 slot under the board heatsink |
| Data mirror | 2 x Samsung 990 PRO 4 TB, PCIe 4.0 x4 | same model, rear M.2 slots, flat heatsinks, 120 mm fan on the rear bracket |
| Network | onboard 5 GbE Realtek, Sonnet Solo10G (Aquantia AQC107) in the x16 slot | same card; onboard 5 GbE is a Realtek RTL8126 |
| Thunderbolt | discrete Intel JHL9480 (Thunderbolt 5), firmware connection manager | CPU-integrated Thunderbolt 4, Linux software connection manager |
| Dock | CalDigit TS5 Plus | same |
| OS | Ubuntu 24.04, kernel 6.8 | Ubuntu 26.04.1, kernel 7.0 |

## What is in the repository

```
etc/default/grub                       kernel command line
etc/fstab                              the mirror's mount line
etc/mdadm/mdadm.conf                   array definition
etc/msmtprc, etc/aliases               alert delivery: msmtp relay and the root alias
etc/modprobe.d/mdadm.conf              md_mod start_ro
etc/modprobe.d/nvme.conf               NVMe power-state latency cap
etc/modules-load.d/sensors.conf        Super I/O sensor driver
etc/sysctl.d/90-raid-nvme.conf         kernel tuning (replaces the 2025 sysctl.conf)
etc/systemd/network/10-lan0.link       stable name for the 10G card, by MAC
etc/systemd/network/10-wan0.link       stable name for the onboard port, by driver
etc/udev/rules.d/99-nvme-tuning.rules  scheduler and md read-ahead (replaces the 2025 rule)
etc/udev/rules.d/retired/              the 2025 rule, kept for the record
caldigit-ts5-plus.md                   the dock on both boards
desktop/conkyrc, desktop/conky.desktop conky configuration and its delayed autostart entry
docs/wayland-desktop.md                Xwayland 24.1.10 crash and the held rebuild, conky under Wayland, release-upgrade effects, CPU split
docs/board-swap.md                     moving the mirror and the network to a new board
docs/2025-msi-edge-ti/                 the original tuning paper and sysctl.conf, superseded
hardware/                              DKMS drivers for the Super I/O chip and the Realtek NIC
packages/xwayland/                     Xwayland 2:24.1.14-1 rebuilt for 26.04: package, symbols, source, build log, recipe
```

Identifiers in the configuration files (UUIDs, MAC addresses, serial numbers) are placeholders in angle brackets.

## Kernel command line

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pcie_aspm.policy=performance pcie_port_pm=off kernel_lockdown=none"
```

**`pcie_aspm.policy=performance`, not `pcie_aspm=off` and not `pcie_aspm=force`.** This is the single most consequential line in the repository, and the 2025 version had it wrong twice over.

- `pcie_aspm=off` makes the kernel stop advertising ASPM support to the firmware. The ACPI `_OSC` negotiation then fails its prerequisite check, and the kernel never asks for control of native PCIe hotplug, PME or AER at all; the log shows `_OSC: not requesting OS control; OS requires [ExtendedConfig ASPM ClockPM MSI]` and `/sys/bus/pci/slots` stays empty. On a board with CPU-integrated Thunderbolt, Linux manages the tunnels itself and relies on native hotplug to re-enumerate the dock's PCIe devices after it resets the host router at boot. Without hotplug those devices die at every boot. The source is `drivers/acpi/pci_root.c`: `OSC_PCI_ASPM_SUPPORT` is only set when `pcie_aspm_support_enabled()` is true, and the control request is skipped when the required set is incomplete.
- `pcie_aspm=force` enables ASPM on links whose devices do not claim support and the kernel documentation warns it may lock the system up.
- `pcie_aspm.policy=performance` keeps every link in L0, which is the behaviour both earlier settings were trying to get, while leaving the negotiation intact. The correct log line is `_OSC: OS now controls [PCIeHotplug SHPCHotplug PME AER PCIeCapability LTR DPC]`.

`pcie_port_pm=off` keeps PCIe ports out of runtime power management. It is harmless on a desktop and belt-and-braces for Thunderbolt docks. `intel_pstate=performance`, present in 2025, is not a value the driver recognises and was dropped; the CPU runs at full performance through the HWP energy-performance preference, which the desktop's power profile sets.

**Do not add `thunderbolt.host_reset=0`.** It stops the kernel from resetting the host router at boot, which does keep firmware-created PCIe tunnels alive, but on the Nova it cost the DisplayPort tunnel to a Thunderbolt monitor. The hotplug fix above makes it unnecessary.

## The mirror

- Created with `mdadm --create --level=1 --metadata=1.2 --bitmap=internal --bitmap-chunk=128M`. The **write-intent bitmap** is the difference between a member that dropped out rejoining in minutes and a full 4 TB copy; a 2025 array created without one needed the full copy, and the source drive hung part-way through it.
- A new or replaced member gets its partition table copied from the survivor (`sgdisk -R /dev/new /dev/survivor && sgdisk -G /dev/new`) and is added with `mdadm --manage /dev/md0 --add`. Cap the resync with `dev.raid.speed_limit_max` (see the sysctl file); the kernel default of 200 MB/s is slow, the 2025 value of 10 GB/s let the source drive run at 1.3 GB/s until its controller stopped responding.
- Never `--create --assume-clean` over members that hold data unless both are known identical.
- `fstab` mounts the filesystem by UUID with `nofail`, so a boot with the array absent still completes. It deliberately has no `x-gvfs-show`: with it, the file manager lists the mirror as an ejectable volume.
- **Alerts must have somewhere to go.** On a desktop without an MTA, mdadm's daily degraded-array warning and smartd's temperature warnings are handed to a `sendmail` that does not exist, and an array ran degraded here for ten months unnoticed. `etc/msmtprc` and `etc/aliases` are the working setup: msmtp-mta relaying through an authenticated SMTP submission port, `root` aliased to the mailbox, `MAILADDR` in `mdadm.conf` and `-m` in `smartd.conf` set to it, the password in a root-only file read by `passwordeval`. Install `msmtp-mta` and `bsd-mailx` (smartd's runner needs `/usr/bin/mail`), then test all three paths: `echo test | mail -s test root`, `mdadm --monitor --scan --test --oneshot`, and smartd with `-M test` for one restart.

## udev: what was retired and why

The 2025 rule `99-nvme-optimization.rules` is kept under `etc/udev/rules.d/retired/` and should not be used:

- It ran `setpci` against hard-coded PCI addresses. After a board swap those addresses belonged to other devices, including the 10G card, and it switched ASPM on for them against the kernel's policy.
- It ran `nvme set-feature -f 0x06 -V 2` on `/dev/nvme1` and `/dev/nvme2`. Kernel NVMe names are assigned in enumeration order and changed between boots on both boards, so the rule hit a different pair of drives each time. Value 2 clears the Write Cache Enable bit, which disables the volatile write cache rather than enabling it.
- It set `read_ahead_kb` to 2 GB on every NVMe device and on the md device. That is roughly a thousand times the default and amplifies every sequential read.

`99-nvme-tuning.rules` keeps the two things that were defensible: `mq-deadline` on the NVMe namespaces and a 1 MB read-ahead on md0. It matches on device type, never on a name or an address.

## Stable network interface names

With one PCIe NIC and one onboard port, the bus-numbered names (`enp2s0`, `enp130s0`) change with the board. Seven VLANs were bound to one of them. The two `.link` files name the card `lan0` by its MAC, which travels with the card, and the onboard port `wan0` by its driver. NetworkManager connections then point at `lan0` and `wan0` and survive a board change untouched. Install to `/etc/systemd/network/`, run `update-initramfs -u`, re-point the connections with `nmcli con modify`, reboot.

## Kernel tuning

`etc/sysctl.d/90-raid-nvme.conf` replaces the 2025 `/etc/sysctl.conf`. Ubuntu 26.04's procps no longer ships that file; an upgrade renames a modified one to `sysctl.conf.dpkg-bak` and every setting in it silently stops applying. Two 2025 values are intentionally gone: `vm.nr_hugepages=2048` reserved 4 GB for nothing that used it, and `vm.overcommit_memory=1` disables the allocator's sanity check.

## DKMS modules and firmware

- The NCT6687D/NCT6686D Super I/O driver and the Realtek r8126 driver are in `hardware/`. On the Nova the in-tree `r8169` drives the RTL8126, so only the sensor driver is needed there.
- Modules are signed with a Machine Owner Key. The key lives in the board's NVRAM, so a board swap means either enrolling it again or running with Secure Boot off.
- A release upgrade that keeps the same kernel version string (24.04's HWE 7.0.0-38 to 26.04's 7.0.0-38) does not trigger a DKMS rebuild, yet the modules fail to load with `disagrees about version of symbol module_layout`. Rebuild by hand: `dkms remove <module>/<version> -k $(uname -r)` then `dkms install`.

## Desktop

GNOME 50 on Wayland. The Xwayland shipped with 26.04 crashes on conky's window; the rebuilt 24.1.14 package (`packages/xwayland/`, with the build recipe), conky's stacking against the desktop-icons extension, what a release upgrade does to extensions and to Firefox and Thunderbird debs, and the CPU split between VirtualBox and a KVM-backed app are in `docs/wayland-desktop.md`.

## Verifying a boot

```
grep -E '_OSC: OS now controls' <(journalctl -k -b)     # must list PCIeHotplug
ls /sys/bus/pci/slots                                   # must not be empty
cat /proc/mdstat                                        # [UU], bitmap line present
findmnt /volume1
ip -br link | grep -E '^(lan0|wan0)'
```

## License

MIT, see [LICENSE](LICENSE).
