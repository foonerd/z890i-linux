# Xwayland 2:24.1.14-1 rebuilt for Ubuntu 26.04

A locally built package of Ubuntu's `xwayland` 2:24.1.14-1 (the version shipped in the release after 26.04), installed on 26.04.1 to replace 2:24.1.10-1 and held until the archive publishes a fixed version.

## Why

Xwayland 24.1.10 has a NULL-pointer dereference in `damage_report()`, `hw/xwayland/xwayland-window.c`, hit when a client maps a window that gets painted before Xwayland has attached its surface. conky with `own_window = true` does it at every session start and the login loops: Xwayland segfaults, gnome-session relaunches it, conky starts again. Backtrace, symbolised with the matching dbgsym package:

```
damage_report <- damageRegionAppend <- damagePolyFillRect <- miPaintWindow <- miWindowExposures <- MapWindow <- ProcMapWindow
```

Fixed upstream in 24.1.11 by xserver merge request 2190 ("xwayland: Avoid NULL pointer dereference in damage_report()", 2026-04-27). Ubuntu: [bug 2166607](https://bugs.launchpad.net/ubuntu/+source/xwayland/+bug/2166607) describes the crash, [bug 2167539](https://bugs.launchpad.net/ubuntu/+source/xwayland/+bug/2167539) asks for a newer Xwayland in 26.04.

## Files

| File | What |
|---|---|
| `xwayland_24.1.14-1_amd64.deb` | the package, built here |
| `xwayland-dbgsym_24.1.14-1_amd64.ddeb` | its debug symbols, for symbolising a future crash |
| `xwayland_24.1.14-1_amd64.buildinfo` | exact build environment: every installed build dependency and version |
| `xwayland_24.1.14-1_amd64.changes` | build manifest |
| `xwayland_24.1.14-1.dsc`, `xwayland_24.1.14-1.debian.tar.xz` | Ubuntu's source package, unmodified |
| `xwayland_24.1.14.orig.tar.xz`, `.asc` | upstream tarball and signature; sha256 identical to `xorg.freedesktop.org/archive/individual/xserver/xwayland-24.1.14.tar.xz` |
| `build.log.xz` | the full `dpkg-buildpackage` log |
| `SHA256SUMS` | checksums of the above |
| `test-on-disposable-xwayland.sh` | runs a client against a throwaway `:3` server; exit 0 means the server survived |

The source is exactly what Launchpad publishes for 2:24.1.14-1. No patch was added; the package was simply built on 26.04 against 26.04's libraries.

## Build, reproducibly

On Ubuntu 26.04 with `dpkg-dev`:

```
# 1. source, from this directory or from Launchpad
#    https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/xwayland/2:24.1.14-1/<file>
sha256sum -c SHA256SUMS
dpkg-source -x xwayland_24.1.14-1.dsc src        # warns about the missing signing key; the checksums in the .dsc are verified

# 2. build dependencies (what was missing on a 26.04 desktop; dpkg-checkbuilddeps lists them for any machine)
sudo apt install meson libdecor-0-dev libei-dev libepoxy-dev libgcrypt-dev libgbm-dev \
  libnvidia-egl-wayland-dev liboeffis-dev libpixman-1-dev libtirpc-dev libxcvt-dev libxfont-dev \
  libxkbfile-dev libxshmfence-dev libxv-dev libwayland-dev wayland-protocols
cd src && dpkg-checkbuilddeps && echo satisfied

# 3. build (nocheck: the test suite needs a display)
DEB_BUILD_OPTIONS="parallel=$(nproc) nocheck" dpkg-buildpackage -b -us -uc -j$(nproc)
ls -la ../xwayland_24.1.14-1_amd64.deb
```

Build time on a 24-core 285K: under three minutes. The `.buildinfo` lists the exact library versions present; to reproduce bit for bit, match them.

## Install, test, hold

```
./test-on-disposable-xwayland.sh                                   # with the installed Xwayland: expect CRASH on 24.1.10
dpkg-deb -x xwayland_24.1.14-1_amd64.deb /tmp/xw && ./test-on-disposable-xwayland.sh /tmp/xw/usr/bin/Xwayland   # expect OK
sudo apt install ./xwayland_24.1.14-1_amd64.deb
sudo apt-mark hold xwayland
```

The running session keeps the old binary until the next login; conky can return to autostart after that.

## When to drop the hold

```
apt-cache policy xwayland        # once the candidate from the archive is 2:24.1.11 or newer
sudo apt-mark unhold xwayland && sudo apt upgrade
```

If a newer upstream version is needed before that, the same recipe applies to whatever `2:24.1.x-y` the development release carries; the [publishing history](https://launchpad.net/ubuntu/+source/xwayland/+publishinghistory) shows the current one.

## Symbolising a future Xwayland crash

```
journalctl --user -b | grep -A20 '(EE) Backtrace'      # frame offsets like Xwayland (0x...+0x5be4a)
dpkg-deb -x xwayland-dbgsym_24.1.14-1_amd64.ddeb /tmp/dbg
addr2line -f -C -e /tmp/dbg/usr/lib/debug/.build-id/<xx>/<rest>.debug 0x5be4a
```

The `.debug` file name is the build id of the installed `/usr/bin/Xwayland` (`readelf -n /usr/bin/Xwayland | grep 'Build ID'`). For a different Xwayland build, the matching ddeb comes from `ddebs.ubuntu.com/pool/main/x/xwayland/`.
