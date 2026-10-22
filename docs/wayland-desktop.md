# GNOME on Wayland: the custom parts

Ubuntu 26.04, GNOME 50, Wayland session, two 2560x1440 monitors side by side. The X11 clients that still matter here (conky, a few Electron apps, VirtualBox) run under Xwayland.

## Xwayland 24.1.10 crashes when conky maps its window

Ubuntu 26.04 ships Xwayland 2:24.1.10-1. It has a NULL-pointer dereference in `damage_report()` (hw/xwayland/xwayland-window.c) that is hit when a client maps a window whose exposure is painted before Xwayland has attached its surface. conky with `own_window = true` does exactly that at session start. The effect is a login loop: Xwayland segfaults, conky dies with an X I/O error, gnome-session relaunches both, repeat. With conky out of autostart the session is fine, and plain X clients such as xeyes or xclock never trigger it.

Upstream fixed it in Xwayland 24.1.11 (xserver merge request 2190, April 2026). Ubuntu tracks it as bug 2166607, with bug 2167539 asking for a newer Xwayland in 26.04; the next Ubuntu release already ships 2:24.1.14-1. Until the update reaches 26.04, the fix is to rebuild that package on 26.04 and hold it:

```
# source of the newer package, verified against the xorg.freedesktop.org tarball
dget https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/xwayland/2:24.1.14-1/xwayland_24.1.14-1.dsc   # or fetch the .dsc, .orig.tar.xz, .orig.tar.xz.asc and .debian.tar.xz by hand
dpkg-source -x xwayland_24.1.14-1.dsc src && cd src
dpkg-checkbuilddeps                      # install what it lists; all are ordinary 26.04 packages
DEB_BUILD_OPTIONS="nocheck" dpkg-buildpackage -b -us -uc -j$(nproc)
sudo apt install ../xwayland_24.1.14-1_amd64.deb
sudo apt-mark hold xwayland
```

Test before trusting it, on a disposable server so the session cannot be harmed: `Xwayland :3 -rootless &` then `DISPLAY=:3 conky` for ten seconds; the server must survive. Unhold when the archive publishes a fixed version.

To get a symbolised backtrace of an Xwayland crash: the `xwayland-dbgsym` ddeb from ddebs.ubuntu.com, then `addr2line -f -e usr/lib/debug/.build-id/<id>.debug <offset>` for each frame offset in the journal's backtrace.

## conky under Xwayland

`desktop/conkyrc` is the configuration in use; `desktop/conky.desktop` the autostart entry.

- `own_window_type = 'normal'` with hints `undecorated,below,sticky,skip_taskbar,skip_pager` is what works on Mutter. `override` is unmanaged and ends up on top of everything; `desktop` ends up under the desktop-icons layer.
- **Stacking against Desktop Icons NG.** Both conky and the desktop-icons extension ask to be kept at the bottom, and whichever is lowered last ends up underneath. When conky starts at the same second as the shell, it is conky, and it is invisible while running correctly. The autostart entry delays it: `Exec=sh -c "sleep 10; exec conky"`. Proven by the inverse: toggling the extension off and on re-creates its windows below conky and conky appears.
- Position: `alignment = 'top_right'`, `gap_x = 0`, `gap_y = 0` puts the panel on the screen edge. `xinerama_head = 1` selects the second monitor; under Xwayland Mutter clamps a window taller than the monitor to its height and moves it to y=0.
- The `ARRAY` block shows the md state in colour, the resync percentage while one runs, and the composite temperature of each NVMe from `sensors`. Fan names come from the Super I/O driver and change with the board.
- conky reads Wi-Fi through the deprecated wireless extensions and logs a warning about it; harmless.

## What a release upgrade does to the desktop

Seen on the 24.04 to 26.04 upgrade; each is a few minutes to undo once known.

- **User extensions are switched off wholesale** by `org.gnome.shell disable-user-extensions = true`, not per extension. GSConnect and Drive Menu disappear until it is set back to `false`; enabling individual extensions does nothing while the global switch is on.
- **Tiling Assistant** (Ubuntu's shipped extension) stays enabled on GNOME 50 but no longer tiles; it has also turned off `org.gnome.mutter edge-tiling` and emptied the Super+Left/Right bindings to take them over. Disabling the extension restores the native settings by itself.
- **Firefox and Thunderbird debs.** Pins keep apt from replacing them with Ubuntu's transitional snap packages: `Package: firefox` / `Pin: version 1:1snap*` / `Pin-Priority: -1`, and the same for `thunderbird*` with `2:1snap*`. The release upgrader nevertheless installs the seeded `firefox` and `thunderbird` snaps straight through snapd; the debs survive, and `snap remove --purge firefox thunderbird` after the first boot leaves only the deb launchers. Keep the PPA pin for Thunderbird at 600, not 1001: a pin above 1000 forces a downgrade when the PPA's build for the new release is older than the installed one.
- **GNOME Software starts twice**, from the XDG autostart entry and from its systemd user unit, and the unit fails on the bus name. A user override of the autostart entry with `Hidden=true` leaves the unit alone to start it.
- **Online Accounts asks for Google again**: the newer provider uses a different sign-in flow and client identity, and the stored token is refused. One-time.

## CPU split between VirtualBox and a KVM-backed app

VirtualBox VMs and an application that runs its own KVM virtual machine (an Electron desktop app with a sandboxed Linux VM) share the box. On a 285K, 8 P-cores and 16 E-cores without hyper-threading, the two are kept apart with `taskset`: VirtualBox on cores 0-15 through a local copy of its `.desktop` file (`Exec=taskset -c 0-15 VirtualBox %U`), the app on 16-23. The app regenerates its own `.desktop` file at every start, so its pin lives in a wrapper earlier in the session's `PATH`:

```
#!/bin/sh
exec taskset -c 16-23 /usr/lib/<app>/<app> "$@"
```

at `~/.local/bin/<app>`. The session `PATH` on Ubuntu puts `~/.local/bin` before `/usr/bin`, so the app's own launcher, URL-scheme activation and terminal launches all go through it, and the KVM VM inherits the mask. cgroup `AllowedCPUs` on the app's scope would be cleaner, but the `cpuset` controller is not delegated to the user session by default.
