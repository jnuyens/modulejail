#!/bin/sh
# Case: uhid (userspace HID) is kept by the desktop profile but not by
# conservative (gh #16, reported by teou1: a Bluetooth Logitech M525 mouse
# stopped working because uhid was blacklisted).
#
# BlueZ creates Bluetooth mice/keyboards as input devices via /dev/uhid, so
# BT HID needs uhid loaded. It is desktop-scoped (the whole BT stack lives in
# BASELINE_DESKTOP, not conservative), so:
#   -p desktop       => uhid kept (not blacklisted) even when unloaded
#   -p conservative  => uhid blacklisted (servers/VMs have no BT input)
# The conservative arm is the discriminating control: if it ever stops
# blacklisting uhid, the desktop keep is no longer proving desktop-scoping.
set -eu

CASE_NAME=desktop-profile-keeps-uhid
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Add uhid to the synthetic universe as available but UNLOADED (absent from
# the fake /proc/modules built by case-tree.sh).
touch "$MODULEJAIL_MODULES_ROOT/$MODULEJAIL_KVER/kernel/drivers/uhid.ko.zst"

# --- desktop: uhid MUST be kept ---
DESK=$CASE_TMP/desktop.conf
"$MODULEJAIL_BIN" -p desktop -o "$DESK" > "$CASE_TMP/d.out" 2> "$CASE_TMP/d.err" || \
    case_fail "modulejail -p desktop exited $? (expected 0); stderr=$(cat "$CASE_TMP/d.err")"
assert_grep '^# profile: desktop$' "$DESK" desktop-header
if grep -qE '^install uhid ' "$DESK"; then
    case_fail "uhid should be kept under -p desktop (Bluetooth HID baseline)"
fi
# Sanity: the pipeline ran and blacklisted the dummy padding.
if ! grep -qE '^install dummy_[0-9]+ ' "$DESK"; then
    case_fail "no dummy_* module blacklisted under -p desktop; pipeline did not run"
fi

# --- conservative: uhid MUST be blacklisted (discriminating control) ---
CONS=$CASE_TMP/conservative.conf
"$MODULEJAIL_BIN" -p conservative -o "$CONS" > "$CASE_TMP/c.out" 2> "$CASE_TMP/c.err" || \
    case_fail "modulejail -p conservative exited $? (expected 0); stderr=$(cat "$CASE_TMP/c.err")"
if ! grep -qE '^install uhid ' "$CONS"; then
    case_fail "uhid should be blacklisted under -p conservative (desktop-scoped, not a server module)"
fi

case_pass
