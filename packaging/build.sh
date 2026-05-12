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
             "$work/usr/share/doc/modulejail"

    sed "s/__VERSION__/$VERSION/g" packaging/debian/control.in > "$work/DEBIAN/control"

    install -m 0755 modulejail                  "$work/usr/bin/modulejail"
    install -m 0644 packaging/debian/copyright  "$work/usr/share/doc/modulejail/copyright"
    install -m 0644 README.md                   "$work/usr/share/doc/modulejail/README.md"

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
    staging=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-rpm-stage.XXXXXX")
    mkdir -p "$staging/$tardir"
    cp modulejail README.md LICENSE "$staging/$tardir/"
    tar -czf "$work/SOURCES/$tardir.tar.gz" -C "$staging" "$tardir"
    rm -rf "$staging"

    sed "s/__VERSION__/$VERSION/g" packaging/rpm/modulejail.spec.in > "$work/SPECS/modulejail.spec"

    rpmbuild --define "_topdir $work" -bb "$work/SPECS/modulejail.spec" >/dev/null

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
