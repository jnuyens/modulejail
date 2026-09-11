#!/bin/sh
# Case: --install-initramfs-hook --dry-run on a mkinitcpio-simulated
# host prints the mkinitcpio install-hook target path, the HOOKS conf.d
# drop-in that makes the strip run inside the distro's single build, and
# the recommended `mkinitcpio -P` regen command, and does NOT write any
# file. Regression guard for gh #29: the old separate pacman trigger that
# ran a SECOND `mkinitcpio -P -- -A modulejail-strip` must be gone. (The
# legacy-trigger-removal line only prints when that file exists on the dev
# host, so it is not asserted here.)
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
assert_grep '^modulejail: dry-run: would write /etc/mkinitcpio.conf.d/modulejail-strip.conf \(0644\): HOOKS\+=\(modulejail-strip\)$' \
    "$CASE_TMP/stdout" mkinitcpio-dry-run-confd-dropin
# shellcheck disable=SC2016  # backticks are literal text in the grep pattern
assert_grep 'would run `mkinitcpio -P`' \
    "$CASE_TMP/stdout" mkinitcpio-dry-run-regen-command

# Regression guard (gh #29): the double-build form must not come back.
if grep -qF -- '-A modulejail-strip' "$CASE_TMP/stdout"; then
    case_fail "dry-run still references the old double-build 'mkinitcpio -P -- -A modulejail-strip'"
fi

if [ -e /etc/initcpio/install/modulejail-strip ]; then
    case_fail "--dry-run wrote the mkinitcpio install hook (should be no-op)"
fi
if [ -e /etc/mkinitcpio.conf.d/modulejail-strip.conf ]; then
    case_fail "--dry-run wrote the mkinitcpio conf.d drop-in (should be no-op)"
fi

case_pass
