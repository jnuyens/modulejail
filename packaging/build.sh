#!/bin/sh
# Build .deb and .rpm packages for modulejail.
#
# Reads VERSION from the modulejail script (single source of truth) and
# emits artifacts to packaging/dist/ (gitignored). Skips gracefully if
# the respective build tooling is absent on the host.
#
# Usage:
#     packaging/build.sh           # build whatever this host can build
#     packaging/build.sh --deb     # build only the .deb
#     packaging/build.sh --rpm     # build only the .rpm
#
# Tooling:
#     .deb -> requires dpkg-deb (Debian/Ubuntu: apt install dpkg)
#     .rpm -> requires rpmbuild (RHEL/Fedora: dnf install rpm-build)
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

VERSION=$(awk -F"'" '/^VERSION=/ {print $2; exit}' modulejail)
if [ -z "$VERSION" ]; then
    printf 'build.sh: error: cannot determine VERSION from modulejail script\n' >&2
    exit 1
fi

# BUILD_DATE: honor SOURCE_DATE_EPOCH per reproducible-builds.org spec.
# Used to substitute __DATE__ in the manpage's .TH line (IN-04).
# Falls back to UTC wall-clock if SOURCE_DATE_EPOCH is unset.
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    case "$SOURCE_DATE_EPOCH" in
        ''|*[!0-9]*)
            printf 'build.sh: error: SOURCE_DATE_EPOCH is set but not a positive integer: %s\n' \
                "$SOURCE_DATE_EPOCH" >&2
            exit 1
            ;;
    esac
    # GNU date (Debian/Fedora build hosts): date -u -d "@SDE"
    # BSD date (macOS dev host): date -u -r SDE
    # Try GNU form first; fall back to BSD form. One of the two works on every
    # supported build host. Silent stderr on the failing form (2>/dev/null).
    BUILD_DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d' 2>/dev/null || \
                 date -u -r "$SOURCE_DATE_EPOCH" '+%Y-%m-%d')
else
    BUILD_DATE=$(date -u '+%Y-%m-%d')
fi

# Parse mode (default: build both).
want_deb=1
want_rpm=1
case "${1:-}" in
    --deb) want_rpm=0 ;;
    --rpm) want_deb=0 ;;
    '')    ;;
    *)     printf 'build.sh: error: unknown option: %s\n' "$1" >&2
           printf 'usage: %s [--deb|--rpm]\n' "$0" >&2
           exit 64 ;;
esac

DIST=packaging/dist
mkdir -p "$DIST"

printf '== modulejail v%s ==\n' "$VERSION"
printf '   output dir: %s/\n\n' "$DIST"

build_deb() {
    if ! command -v dpkg-deb >/dev/null 2>&1; then
        printf 'skip: .deb (dpkg-deb not found; install on Debian/Ubuntu with: apt install dpkg)\n'
        return 0
    fi

    work=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-deb.XXXXXX")
    trap 'rm -rf "$work"' EXIT INT HUP TERM

    mkdir -p "$work/DEBIAN" \
             "$work/usr/bin" \
             "$work/usr/share/doc/modulejail" \
             "$work/usr/share/man/man8" \
	     "$work/usr/lib/systemd/system"

    sed "s/__VERSION__/$VERSION/g" packaging/debian/control.in > "$work/DEBIAN/control"

    install -m 0755 packaging/debian/postinst   "$work/DEBIAN/postinst"
    install -m 0755 modulejail                  "$work/usr/bin/modulejail"
    install -m 0644 packaging/debian/copyright  "$work/usr/share/doc/modulejail/copyright"
    install -m 0644 README.md                   "$work/usr/share/doc/modulejail/README.md"
    install -m 0644 systemd/modulejail.service  "$work/usr/lib/systemd/system/modulejail.service"
    install -m 0644 systemd/modulejail.timer  "$work/usr/lib/systemd/system/modulejail.timer"

    # Manpage: substitute __VERSION__ and __DATE__, then gzip with -n (no name/timestamp)
    # so the .deb is byte-deterministic across rebuilds with identical inputs.
    sed -e "s/__VERSION__/$VERSION/g" -e "s/__DATE__/$BUILD_DATE/g" man/modulejail.8.in > "$work/usr/share/man/man8/modulejail.8"
    gzip -9n "$work/usr/share/man/man8/modulejail.8"

    out="$DIST/modulejail_${VERSION}_all.deb"
    dpkg-deb --build --root-owner-group "$work" "$out" >/dev/null
    printf 'built: %s\n' "$out"

    rm -rf "$work"
    trap - EXIT INT HUP TERM
}

build_rpm() {
    if ! command -v rpmbuild >/dev/null 2>&1; then
        printf 'skip: .rpm (rpmbuild not found; install on RHEL/Fedora with: dnf install rpm-build)\n'
        return 0
    fi

    work=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-rpm.XXXXXX")
    trap 'rm -rf "$work"' EXIT INT HUP TERM

    tardir="modulejail-$VERSION"
    mkdir -p "$work/SOURCES" "$work/SPECS" "$work/BUILD" "$work/RPMS" "$work/SRPMS" "$work/BUILDROOT"

    # Stage the source tarball that the spec's %setup will unpack.
    # Manpage source is templated and pre-substituted here so the spec's
    # %install can just copy it into the buildroot.
    staging=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-rpm-stage.XXXXXX")
    mkdir -p "$staging/$tardir"
    cp modulejail README.md LICENSE systemd/modulejail.service systemd/modulejail.timer "$staging/$tardir/"
    sed -e "s/__VERSION__/$VERSION/g" -e "s/__DATE__/$BUILD_DATE/g" man/modulejail.8.in > "$staging/$tardir/modulejail.8"
    tar -czf "$work/SOURCES/$tardir.tar.gz" -C "$staging" "$tardir"
    rm -rf "$staging"

    sed "s/__VERSION__/$VERSION/g" packaging/rpm/modulejail.spec.in > "$work/SPECS/modulejail.spec"

    # Suppress the per-distro %dist tag so the resulting RPM filename is
    # the same regardless of which RHEL/Fedora major was used to build it
    # (modulejail-X.Y.Z-1.noarch.rpm, not modulejail-X.Y.Z-1.el9.noarch.rpm).
    # ModuleJail is a noarch shell script; the dist origin carries no
    # technical meaning here.
    rpmbuild --define "_topdir $work" \
             --define "dist %{nil}" \
             -bb "$work/SPECS/modulejail.spec" >/dev/null

    # Copy built RPMs to dist/.
    find "$work/RPMS" -name '*.rpm' -type f | while read -r rpm; do
        cp "$rpm" "$DIST/"
        printf 'built: %s/%s\n' "$DIST" "$(basename "$rpm")"
    done

    rm -rf "$work"
    trap - EXIT INT HUP TERM
}

[ "$want_deb" = 1 ] && build_deb
[ "$want_rpm" = 1 ] && build_rpm

echo ""
printf 'Done. Artifacts in %s/:\n' "$DIST"
ls -1 "$DIST" 2>/dev/null || true
