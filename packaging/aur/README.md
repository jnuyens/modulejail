# AUR packaging

This directory holds the canonical `PKGBUILD` for the Arch User Repository
package `modulejail`. The PKGBUILD is tracked in this repo so it is reviewable
in-tree alongside the `.deb` and `.rpm` packaging.

The published AUR git repo (`ssh://aur@aur.archlinux.org/modulejail.git`) is a
publishing-only mirror: `PKGBUILD`, `.SRCINFO`, and `LICENSE` are pushed there.

## Two-license arrangement

This directory has **two different licenses** in play, which is normal for
AUR submissions but worth being explicit about:

- **The PKGBUILD itself (the *recipe*)**: 0BSD, declared via the
  `SPDX-License-Identifier: 0BSD` header in `PKGBUILD` and the full text
  in `LICENSE` next to it. This is the [Arch sources-license recommendation][1]
  and a prerequisite for any future promotion of this package from AUR
  into an official Arch repository (`extra`).
- **The modulejail program itself**: GPL-3.0-only, declared via the
  `license=('GPL-3.0-only')` field in `PKGBUILD`. The upstream license
  text lives in `LICENSE` at the repository root; the AUR package
  installs it at `/usr/share/licenses/modulejail/LICENSE` on user
  systems.

The 0BSD applies *only* to the packaging recipe so anyone can vendor
the PKGBUILD into AUR helpers, mirrors, or templates without friction.
It does not, and cannot, change the modulejail program's GPL-3.0-only
licensing.

[1]: https://wiki.archlinux.org/title/Arch_package_guidelines#Package_sources_licenses

## Publishing a new release to AUR

Prerequisite (one-time): SSH key registered at
<https://aur.archlinux.org/account>.

```sh
cd packaging/aur

# 1. Bump pkgver, reset pkgrel=1.
#    Edit PKGBUILD: pkgver=X.Y.Z, pkgrel=1.

# 2. Refresh the source checksum. This MUST happen before commit -
#    the committed PKGBUILD always carries the real sha256, never SKIP.
updpkgsums

# 3. Smoke-test the build locally.
#    On Arch: makepkg -si
#    On non-Arch host with docker: see "Container smoke test" below.

# 4. Regenerate .SRCINFO (AUR requires this alongside PKGBUILD).
makepkg --printsrcinfo > .SRCINFO

# 5. Commit the in-repo PKGBUILD bump.
git add PKGBUILD       # .SRCINFO is publish-only; not tracked in this repo
git commit -m "release(aur): bump PKGBUILD to vX.Y.Z"

# 6. Mirror PKGBUILD + .SRCINFO + LICENSE into the AUR git repo.
#    First time only:
#      git clone ssh://aur@aur.archlinux.org/modulejail.git ../aur-publish
cp PKGBUILD .SRCINFO LICENSE ../aur-publish/
cd ../aur-publish
git add PKGBUILD .SRCINFO LICENSE
git commit -m "modulejail X.Y.Z"
git push
```

## Container smoke test (non-Arch host)

If you don't have an Arch box reachable, build inside a container on any
host with docker:

```sh
# Stage the PKGBUILD into a scratch dir on a docker-equipped host.
ssh some-linux-host 'mkdir -p /tmp/aur-smoke'
scp PKGBUILD some-linux-host:/tmp/aur-smoke/

ssh some-linux-host 'sudo docker run --rm -v /tmp/aur-smoke:/build archlinux:latest \
  /bin/bash -c "
    set -eu
    pacman -Syu --noconfirm --needed base-devel git pacman-contrib sudo
    useradd -m builder
    echo \"builder ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/builder
    chown -R builder:builder /build
    sudo -u builder bash -lc \"cd /build && updpkgsums && \
      makepkg --printsrcinfo > .SRCINFO && \
      makepkg -s --noconfirm\"
  "'
```

A successful run prints `Finished making: modulejail X.Y.Z-1` and leaves
the `.pkg.tar.zst` in `/tmp/aur-smoke/` on the remote host.

## Notes

- `arch=('any')` is correct: modulejail is pure POSIX shell, no native code.
- `depends=('kmod')` covers `lsmod` and `modprobe`. Everything else
  (POSIX shell, coreutils, sed, awk) is in `base`, which AUR does not
  require declaring.
- `optdepends=('util-linux: logger(1)')` is a documentation gesture;
  `util-linux` itself is in `base` on every standard Arch install. Kept
  because minimal containers may strip it.
- The man page is templated (`man/modulejail.8.in`). The PKGBUILD does the
  same `__VERSION__` substitution that `packaging/build.sh` does for the
  `.deb` and `.rpm` builds, kept as a single `sed` line in `package()` for
  inspectability.
- The committed `sha256sums` is always the real checksum of the
  referenced release tarball. `SKIP` is never acceptable in this
  PKGBUILD (that pattern is for `-git` tracking flavors that pull
  HEAD, which this package does not). Run `updpkgsums` after every
  `pkgver` bump and before committing.
