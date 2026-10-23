# Moving the mirror and the network to a new board

What carried over from the MSI Z890I EDGE TI to the ASRock Z890I Nova WiFi without change, what had to be prepared, and the order that worked. Same CPU, same memory, same three NVMe drives, same PCIe NIC, same dock.

## Carries over by itself

- The root filesystem and the EFI system partition. The ESP holds the fallback loader `\EFI\BOOT\BOOTX64.EFI`, so a firmware with an empty NVRAM boots Ubuntu without an entry and recreates the "ubuntu" entry on the first boot.
- The md array: assembled by UUID from `mdadm.conf`, mounted by filesystem UUID from `fstab`. Kernel NVMe names change between boards and between boots; nothing may depend on them.
- Anything keyed on the CPU: microcode, `intel_pstate`, VT-x and VT-d once enabled in the new firmware.

## Prepare before the swap

1. **Stable network names.** Install the two `.link` files from `etc/systemd/network/`, run `sudo update-initramfs -u`, then re-point every NetworkManager connection: `nmcli con modify <name> connection.interface-name lan0` for the trunk, `nmcli con modify <vlan> vlan.parent lan0` for each VLAN, `connection.interface-name wan0` for the WAN side. Reboot once on the old board and confirm `ip -br link` shows `lan0` and `wan0` up. The migration of the network is then independent of the hardware change.
2. **Retire anything bound to PCI addresses.** The 2025 udev rule in `etc/udev/rules.d/retired/` is the example: its `setpci` targets became the wrong devices on the new board.
3. **Decide on Secure Boot.** The DKMS signing key does not travel with the drives (see `hardware/README.md`).
4. **Park anything that syncs a directory on the mirror.** A cloud-sync client started on a boot where the array is absent sees an empty mount point. Disable its autostart until the volume is confirmed mounted.
5. **Keep the old array members intact until the new mirror is whole.** If one member is being replaced by a new drive, the removed member is a complete copy of the data as of the last clean shutdown and is the fallback if the survivor fails during the rebuild. Zero its superblock before any other use, so it can never be auto-assembled by mistake.

## First boot on the new board

Firmware: Secure Boot as decided, VT-x and VT-d on, XMP on, Re-Size BAR on, Deep Sleep off, VMD controller off (with VMD on, the NVMe drives are hidden behind Intel's RAID controller and the md array cannot assemble), PCI Express Native Control on. Then, before any application is opened:

```
cat /proc/mdstat                 # the survivor alone, [U_], or [UU] if both members moved
findmnt /volume1
ip -br link | grep -E '^(lan0|wan0)'
ls -L ~/.cargo > /dev/null       # or any symlink into the mirror
journalctl -k -b | grep -E '_OSC: OS now controls|disagrees about version'
```

A new member is added after the partition table is replicated from the survivor:

```
sudo sgdisk -R /dev/<new> /dev/<survivor> && sudo sgdisk -G /dev/<new>
sudo sysctl -w dev.raid.speed_limit_max=1000000
sudo mdadm --manage /dev/md0 --add /dev/<new>p1
watch -n 30 'cat /proc/mdstat; sensors | grep Composite'
```

With the write-intent bitmap already on the array, a member that merely dropped out rejoins with `--re-add` in minutes; a blank drive always needs the full copy.

## Things that only show up afterwards

- Sensor labels change with the Super I/O chip; any dashboard reading named fan channels needs its names updated.
- The DKMS modules may need a manual rebuild even when the kernel version string is unchanged (`hardware/README.md`).
- Integrated versus discrete Thunderbolt is a different driver path for a dock (`caldigit-ts5-plus.md`).
- The desktop file manager presents an fstab mount as an ejectable volume if the entry carries `x-gvfs-show`; remove the option and use a bookmark.

## Offloading home directories: what not to symlink

Before the upgrade, large directories were moved off the system drive and replaced by symlinks into the mirror, so the backup image of the root disk stayed small. That works for toolchain caches (`~/.cargo`, `~/.rustup`, `~/.npm`, `~/.nvm`, `~/.gradle`) and for bulk data. It does not work for the state directory of any application that runs a sandbox or a virtual machine:

- Claude Desktop's Cowork VM refused to start with `open .../.config/Claude/claude-code-vm/<ver>/claude: too many levels of symbolic links`. The helper opens the binary with symlink-free path resolution, so a single symlink anywhere in the path fails with that error, which is the kernel's `RESOLVE_NO_SYMLINKS` result, not an actual loop.
- Cursor's `~/.cursor` behaved the same way under its AppArmor-confined sandbox.

Move such directories back as real directories (`rsync -aHAX`, verify with `rsync -n --checksum`, then swap), and keep the offload for caches and data only. A bind mount instead of a symlink would not have helped either; virtiofs does not share it into the VM.

