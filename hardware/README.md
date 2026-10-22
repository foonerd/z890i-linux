# Out-of-tree drivers for the Z890 boards

Two DKMS packages, built from upstream sources, with the `.deb` files under `releases/`.

| Driver | Chip | MSI Z890I EDGE TI | ASRock Z890I Nova WiFi |
|---|---|---|---|
| `nct6687d` ([Fred78290/nct6687d](https://github.com/Fred78290/nct6687d)) | Nuvoton NCT6687D / NCT6686D Super I/O: fans, voltages, board temperatures | needed (NCT6687D) | needed (NCT6686D; the driver logs `Found NCT6686D or compatible chip`) |
| `realtek-r8126` ([awesometic/realtek-r8126-dkms](https://github.com/awesometic/realtek-r8126-dkms)) | Realtek RTL8126 5 GbE | needed on kernel 6.8 | not needed on kernel 7.0: the in-tree `r8169` binds the RTL8126 |

Fan and temperature labels in `sensors` output come from the driver's MSI table. On the Nova the labels are the same family but the channels differ: the chassis header reads as `System Fan #6`, `M2_1` is the front M.2 slot's board sensor, and the channel labelled `PCIe x1` is noise. The thermistor header (`T_SENSOR1`) is read by the firmware for its fan curves and is not available through this driver.

## Install

```
sudo apt install dkms build-essential linux-headers-$(uname -r)
sudo apt install ./releases/nct6687d-dkms_20241105-084624_all.deb
sudo apt install ./releases/realtek-r8126-dkms_10.014.01-1_amd64.deb     # MSI board only
printf 'coretemp\nnct6687\n' | sudo tee /etc/modules-load.d/sensors.conf
```

## Two things that bite

**Secure Boot.** DKMS signs the modules with the Machine Owner Key in `/var/lib/shim-signed/mok/`. The enrolled copy of that key lives in the board's NVRAM. After a board swap the new firmware has never seen it; either run `sudo mokutil --import /var/lib/shim-signed/mok/MOK.der` and complete the enrolment at the next boot, or leave Secure Boot off.

**Same kernel version, different build.** Ubuntu 24.04.5's HWE kernel and Ubuntu 26.04's GA kernel are both `7.0.0-38-generic`. The release upgrade replaces the kernel packages, DKMS sees no version change and does not rebuild, and at the next boot the modules refuse to load:

```
nct6687: disagrees about version of symbol module_layout
systemd-modules-load: Failed to insert module 'nct6687': Exec format error
```

Rebuild against the installed kernel by hand:

```
sudo dkms remove nct6687d/20241105-084624 -k $(uname -r)
sudo dkms install nct6687d/20241105-084624 -k $(uname -r)
sudo modprobe nct6687
```

Packages that carry their own kernel hook (VirtualBox, Synology's `synosnap`) rebuilt themselves during the same upgrade.
