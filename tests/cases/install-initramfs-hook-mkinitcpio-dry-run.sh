#!/bin/sh
# Case: --install-initramfs-hook --dry-run on a mkinitcpio-simulated
# host prints the mkinitcpio install-hook target path and the recommended
# regen command, and does NOT write any file. (Pacman hook path is
# inspected only when pacman is actually present on the dev host, which
# is rare; that branch is covered by the on-host Linux test, not here.)
set -eu

CASE_NAME=install-initramfs-hook-mkinitcpio-dry-run
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

set +e
MODULEJAIL_INITRAMFS_BUILDER=mkinitcpio \
    "$MODULEJAIL_BIN" --install-initramfs-hook --dry-run \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 0 "$rc" "mkinitcpio-dry-run-exit-code"

assert_grep '^modulejail: dry-run: would write /etc/initcpio/install/modulejail-strip \(0755\)$' \
    "$CASE_TMP/stdout" mkinitcpio-dry-run-target-path
assert_grep 'mkinitcpio -P -- -A modulejail-strip' \
    "$CASE_TMP/stdout" mkinitcpio-dry-run-regen-command

if [ -e /etc/initcpio/install/modulejail-strip ]; then
    case_fail "--dry-run wrote the mkinitcpio install hook (should be no-op)"
fi

case_pass
