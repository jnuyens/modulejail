#!/bin/sh
# Case: --install-initramfs-hook composition (gh #27).
#
#  1. Combined with a generation flag (`-p desktop --install-initramfs-hook`)
#     modulejail FIRST regenerates the blacklist (honouring the profile /
#     whitelist) and THEN installs the hook, in a single run. Previously the
#     hook flag was a standalone action that exited before generation, so
#     -p/whitelist were silently ignored (the bug Rick hit).
#  2. A BARE `--install-initramfs-hook` (no generation flags) stays hook-only,
#     so the packaged postinst call never regenerates the blacklist at
#     package-install time.
#
# Uses MODULEJAIL_INITRAMFS_BUILDER=dracut to force builder detection and
# --dry-run so nothing is written and no root is needed.
set -eu

CASE_NAME=install-initramfs-hook-composes-with-generation
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

GEN_SUMMARY='modulejail: DRY-RUN: would blacklist [0-9]+ of [0-9]+ modules'
HOOK_LINE='modulejail: dry-run: would write /usr/lib/dracut/modules.d/99modulejail-strip/module-setup.sh'

# --- 1. Composed run: generation flag + hook flag => BOTH happen ---
OUT=$CASE_TMP/composed.txt
set +e
MODULEJAIL_INITRAMFS_BUILDER=dracut \
    "$MODULEJAIL_BIN" -p desktop --install-initramfs-hook --dry-run -o "$CASE_TMP/out.conf" \
    > "$OUT" 2>&1
rc=$?
set -e

assert_eq 0 "$rc" "composed-exit-code"
# Generation ran (would have written the blacklist).
assert_grep "$GEN_SUMMARY" "$OUT" composed-generation-ran
# Hook install ran too.
assert_grep "$HOOK_LINE" "$OUT" composed-hook-ran
# Sentinel: dry-run wrote neither the blacklist nor the dracut hook file.
if [ -e "$CASE_TMP/out.conf" ]; then
    case_fail "composed --dry-run wrote the blacklist (should be no-op)"
fi

# --- 2. Bare hook flag: hook only, generation must NOT run ---
BARE=$CASE_TMP/bare.txt
set +e
MODULEJAIL_INITRAMFS_BUILDER=dracut \
    "$MODULEJAIL_BIN" --install-initramfs-hook --dry-run \
    > "$BARE" 2>&1
rc=$?
set -e

assert_eq 0 "$rc" "bare-exit-code"
# Hook install ran.
assert_grep "$HOOK_LINE" "$BARE" bare-hook-ran
# Generation did NOT run (no blacklist summary at all).
if grep -qE "$GEN_SUMMARY" "$BARE"; then
    case_fail "bare --install-initramfs-hook regenerated the blacklist (must stay hook-only)"
fi

case_pass
