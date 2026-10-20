#!/bin/sh
# Case: --install-initramfs-hook --initramfs-builder B --destdir DIR (the
# package-build path) writes the strip hook under DIR for every builder,
# without root, with the same modes a host install uses, and without the
# host-only output (rebuild advice). Also covers the usage errors that keep
# --destdir to a bare hook install with an explicit builder.
#
# Lets a distro spec ship the hook in its file list instead of creating it
# from a post-install script (Fedora review, bug 2541665).
set -eu

CASE_NAME=install-initramfs-hook-destdir
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# The ostree marker must not matter in staging mode: the build host is not
# the target. Point it at an existing file to prove the skip is bypassed.
MARKER=$CASE_TMP/ostree-booted
: > "$MARKER"
export MODULEJAIL_OSTREE_MARKER="$MARKER"

stage() {
    # stage BUILDER -> runs the staging install into $CASE_TMP/root-BUILDER/
    set +e
    "$MODULEJAIL_BIN" --install-initramfs-hook --initramfs-builder "$1" \
        --destdir "$CASE_TMP/root-$1/" \
        > "$CASE_TMP/stdout-$1" 2> "$CASE_TMP/stderr-$1"
    rc=$?
    set -e
    assert_eq 0 "$rc" "$1-exit-code"
    if grep -qE '^modulejail: run `|ostree/immutable' "$CASE_TMP/stdout-$1"; then
        case_fail "$1 staging printed host-only output (rebuild advice or ostree skip)"
    fi
    assert_grep "staged under $CASE_TMP/root-$1 \\(builder: $1\\)" \
        "$CASE_TMP/stdout-$1" "$1-staged-message"
}

mode_of() {
    # Portable octal mode (GNU stat on Linux, BSD stat on macOS).
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

stage dracut
f=$CASE_TMP/root-dracut/usr/lib/dracut/modules.d/99modulejail-strip/module-setup.sh
[ -f "$f" ] || case_fail "dracut module not staged at $f"
assert_eq 755 "$(mode_of "$f")" dracut-mode
# shellcheck disable=SC2016  # literal ${...} in the hook body
assert_grep 'rm -f "\${initdir}/etc/modprobe.d/modulejail-blacklist.conf"' "$f" dracut-strip-line

stage initramfs-tools
f=$CASE_TMP/root-initramfs-tools/etc/initramfs-tools/hooks/zz-modulejail-strip
[ -f "$f" ] || case_fail "initramfs-tools hook not staged at $f"
assert_eq 755 "$(mode_of "$f")" initramfs-tools-mode
# shellcheck disable=SC2016  # literal ${...} in the hook body
assert_grep 'rm -f "\${DESTDIR}/etc/modprobe.d/modulejail-blacklist.conf"' "$f" initramfs-tools-strip-line

stage mkinitcpio
f=$CASE_TMP/root-mkinitcpio/etc/initcpio/install/modulejail-strip
c=$CASE_TMP/root-mkinitcpio/etc/mkinitcpio.conf.d/modulejail-strip.conf
[ -f "$f" ] || case_fail "mkinitcpio install hook not staged at $f"
[ -f "$c" ] || case_fail "mkinitcpio drop-in not staged at $c"
assert_eq 755 "$(mode_of "$f")" mkinitcpio-hook-mode
assert_eq 644 "$(mode_of "$c")" mkinitcpio-dropin-mode
assert_grep '^HOOKS\+=\(modulejail-strip\)$' "$c" mkinitcpio-dropin-line

# Dry run under --destdir writes nothing.
set +e
"$MODULEJAIL_BIN" --install-initramfs-hook --initramfs-builder=dracut \
    --destdir="$CASE_TMP/dry" --dry-run > "$CASE_TMP/stdout-dry" 2>&1
rc=$?
set -e
assert_eq 0 "$rc" dry-run-exit-code
assert_grep "would write $CASE_TMP/dry/usr/lib/dracut/" "$CASE_TMP/stdout-dry" dry-run-path
[ ! -e "$CASE_TMP/dry" ] || case_fail "--dry-run with --destdir created $CASE_TMP/dry"

# Usage errors (exit 64, nothing written).
expect_usage() {
    label=$1; shift
    set +e
    "$MODULEJAIL_BIN" "$@" > "$CASE_TMP/stdout-err" 2> "$CASE_TMP/stderr-err"
    rc=$?
    set -e
    assert_eq 64 "$rc" "$label"
}
expect_usage destdir-needs-builder --install-initramfs-hook --destdir "$CASE_TMP/e1"
expect_usage destdir-needs-install --destdir "$CASE_TMP/e2" --initramfs-builder dracut
expect_usage destdir-not-with-uninstall --uninstall-initramfs-hook --destdir "$CASE_TMP/e3" --initramfs-builder dracut
expect_usage destdir-not-with-generation -p desktop --install-initramfs-hook --initramfs-builder dracut --destdir "$CASE_TMP/e4"
expect_usage unknown-builder --install-initramfs-hook --initramfs-builder bogus --destdir "$CASE_TMP/e5"
for e in e1 e2 e3 e4 e5; do
    [ ! -e "$CASE_TMP/$e" ] || case_fail "usage error case $e wrote $CASE_TMP/$e"
done

case_pass
