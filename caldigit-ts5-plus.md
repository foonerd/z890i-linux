# CalDigit TS5 Plus on Linux, on two Z890 boards

The same dock behaves differently on the two boards in this repository, because the two boards manage Thunderbolt differently:

| | MSI MPG Z890I EDGE TI WIFI | ASRock Z890I Nova WiFi |
|---|---|---|
| Thunderbolt host | discrete Intel JHL9480 (Thunderbolt 5) | CPU-integrated Thunderbolt 4 |
| Who creates the tunnels | the controller's own firmware ("Firmware CM") | the Linux `thunderbolt` driver ("software CM") |
| PCIe devices in the dock at boot | brought up by firmware, stay up | brought up by firmware, torn down when Linux takes over, must be re-enumerated by native PCIe hotplug |
| USB 2.0 devices on the dock's Thunderbolt-side ports | work | do not enumerate with BIOS 3.40 (see below) |

The dock internals matter for the second table, so first the layout.

## What is inside the dock

From a teardown and from the USB and PCI trees on Linux:

- An Intel JHL9480 Thunderbolt 5 controller with a built-in USB 3 hub. The three rear Thunderbolt downstream ports and the front hub (Parade PS5512: two front USB-C, front USB-A) hang off this hub. USB 3 traffic to these ports is tunnelled over Thunderbolt; **USB 2.0 traffic is not tunnelled**, it rides the D+/D- wires of the cable to the host's own USB 2.0 controller.
- An ASMedia ASM3142 USB controller on a PCIe tunnel, feeding two ASMedia ASM2074 hubs that serve the rear USB-A and the non-Thunderbolt rear USB-C ports. On Linux these appear as the dock's "USB 3 Hub - B/C" and "USB 2 Hub - B/C" on a separate xHCI bus. USB 2.0 for these ports is handled inside the dock.
- A Marvell/Aquantia AQC113 10 GbE controller on the same PCIe tunnel (`atlantic` driver). The 2025 version of this page attributed the 10 GbE port to `r8152`; that driver belongs to a USB 2.5 GbE adapter, not to the dock.
- Card readers on USB (Genesys GL3231S), audio on USB (C-Media CM6646).

## MSI Z890I EDGE TI (discrete JHL9480)

Out of the box the dock's PCIe-attached devices (the ASMedia controller, the 10 GbE) did not initialise: `lspci -s 06:00.0 -vvv` showed `!!! Unknown header type 7f`. The fix was in the firmware, under **Advanced -> Thunderbolt(TM) Configuration**:

| Setting | Default | Required |
|---|---|---|
| USB4 CM Mode | Software/Auto | **Firmware** |
| PCIE Tunneling over USB4 | Enabled | Enabled |
| Integrated Thunderbolt(TM) Support | Enabled | Enabled |
| Discrete Thunderbolt(TM) Support | Disabled | Disabled |

and under its Integrated Thunderbolt sub-menu: OS Native Resource Balance Disabled, ITBT RTD3 Disabled, both ITBT root ports Enabled, Extra Bus Reserved 56, Reserved Memory 512, Memory Alignment 25, Reserved PMemory 32768, PMemory Alignment 28.

With the firmware connection manager the controller's firmware creates every tunnel before the kernel starts and keeps them; the Linux driver only observes. A full power cycle, not a reboot, is needed after changing the mode. The SD and microSD readers also needed a dock firmware update, which CalDigit only provides as a Windows updater; after it, both slots appear as `CalDigit TS5+ Card Reader` SCSI devices.

Check: `cat /sys/bus/thunderbolt/devices/domain0/security` is `none` or `user`, never `nopcie`; `lspci -s 06:00.0 -vvv` shows `Mem+ BusMaster+` and `Kernel driver in use: xhci_hcd`.

## ASRock Z890I Nova WiFi (integrated Thunderbolt 4)

The Nova's firmware has no connection-manager mode switch; its Thunderbolt menu (guide section 3.4.4) offers PCIE Tunneling over USB4, Integrated Thunderbolt Enable, Discrete Thunderbolt Enable and a USB4 Host Router Class Code. The kernel's software connection manager is in charge. Three things follow.

### 1. Native PCIe hotplug must be in the operating system's hands

At boot the firmware has already enumerated the dock's PCIe devices. When the `thunderbolt` driver loads it resets the host router (`host_reset`, default on since kernel 6.8.8) and builds its own tunnels. The devices the firmware brought up lose their link mid-probe:

```
[4.922] usb usb4: xHCI Host Controller, SerialNumber: 0000:06:00.0
[4.925] ACPI: bus type thunderbolt registered
[4.926] xhci_hcd 0000:06:00.0: HC died; cleaning up
[4.927] atlantic 0000:07:00.0: Unable to change power state from D3cold to D0, device inaccessible
```

They come back only if the kernel owns native PCIe hotplug on the root port. With `pcie_aspm=off` on the kernel command line it does not, because the `_OSC` negotiation requires ASPM support to be advertised before any control is requested (see the README). The combination that works:

- kernel: `pcie_aspm.policy=performance` instead of `pcie_aspm=off`;
- firmware, **Advanced -> Chipset Configuration -> PCI Express Native Control: Enabled**. ASRock's description, "enhanced PCI Express power saving in OS", is misleading; this is the switch that lets the firmware grant native hotplug, PME and AER to the OS.

Verified state: `journalctl -k -b | grep '_OSC: OS now controls'` lists `PCIeHotplug`, `/sys/bus/pci/slots` has entries for the Thunderbolt root ports and the dock's bridges, and both `06:00.0` (xhci_hcd) and `07:00.0` (atlantic) have drivers bound. A single `HC died` line may still appear at the moment of the host reset; the device is re-probed afterwards. Nine non-fatal AER "ACSViol" errors on the Thunderbolt root port during that same second are the re-enumeration and are recovered.

What did **not** help, tried and reverted: `pcie_port_pm=off` alone, disabling ASPM and L1 substates in the firmware, a udev rule setting `power/control=on` on the bridges (it runs after the failure), and `thunderbolt.host_reset=0`, which kept the dock's PCIe devices alive but took the picture away from a Thunderbolt-attached Dell U2724DE. Do not use it on this board.

### 2. USB 2.0 devices on the Thunderbolt-side ports do not enumerate

With BIOS 3.40, no USB 2.0 device ever appeared behind the dock's front hub or its rear Thunderbolt downstream ports, on any boot, while USB 3 devices in the same ports worked. The Thunderbolt USB controller's USB 2.0 root port (`usb1` on `00:0d.0`) never saw a connect, and the dock's USB 2.0 hub half for that path was absent. USB 2.0 is carried on the cable's D+/D- pair to the host's USB 2.0 PHY, and the routing of that pair for the Type-C ports is done by the board's PD controller and EC firmware. The kernel cannot intervene: the firmware exposes no UCSI device (`PNP0CA0`) and no Intel PMC mux device the kernel's drivers could bind to; `/sys/class/typec` does not exist.

Workaround: put USB 2.0 devices, or a hub that carries them, on the dock's **rear USB-A** ports (or its non-Thunderbolt rear USB-C). Those are on the ASM3142 and get their USB 2.0 inside the dock. A Stream Deck XL moved from a rear Thunderbolt port to a rear USB-A port enumerated immediately.

A USB 2.0 device plugged straight into the board's own Thunderbolt ports is the test that separates a dock-specific case from a board-wide one; on this system it has not been done yet.

### 3. Firmware settings that are relevant, from the ASRock guide

| Menu (Advanced Mode) | Setting | Value |
|---|---|---|
| Advanced > Intel(R) Thunderbolt | PCIE Tunneling over USB4 | Enabled |
| | Integrated Thunderbolt(TM) Enable | Enabled |
| | Discrete Thunderbolt(TM) Enable | Disabled |
| | USB4 Host Router Class Code | Auto |
| Advanced > Chipset Configuration | PCI Express Native Control | **Enabled** |
| | PCIE ASPM Support, PCH PCIE ASPM Support, DMI ASPM | Disabled (matches the kernel policy; not what fixes the dock) |
| | Re-Size BAR Support | Enabled |
| | Deep Sleep | Disabled |
| Security | Secure Boot | Disabled, or enrol the DKMS signing key |

## Checking a boot

```
journalctl -k -b | grep -E '_OSC: OS now controls|HC died|Boot code hanged'
ls /sys/bus/pci/slots
lsusb -t          # the dock's B and C hubs appear on their own xHCI buses; A on the Thunderbolt USB tunnel
boltctl list      # dock and any Thunderbolt monitor "authorized"
```

## References

- [Linux kernel Thunderbolt/USB4 documentation](https://docs.kernel.org/admin-guide/thunderbolt.html)
- [Kernel source: `_OSC` negotiation in drivers/acpi/pci_root.c](https://github.com/torvalds/linux/blob/master/drivers/acpi/pci_root.c)
- [ChargerLab teardown of the TS5 Plus](https://www.chargerlab.com/teardown-of-caldigit-ts5-plus-thunderbolt-5-dock/)
- [CalDigit TS5 Plus](https://www.caldigit.com/thunderbolt-5-dock/)
