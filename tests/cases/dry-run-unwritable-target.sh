#!/bin/sh
# Case: --dry-run must NOT fail on output-target state (gh #28, elelaysh).
# An unprivileged user has to be able to preview the would-be blacklist even
# when the target directory is not writable. The DRY_RUN guard on the
# output-target pre-flight (directory/symlink/trailing-slash/writability) was
# dropped in the #25 revert of #24; this locks the fixed behavior in.
#
#   --dry-run -o <unwritable>/out.conf  => exit 0, prints the preview, no
#                                          "cannot write" error, no file.
#   (no --dry-run, same path)           => still errors 77 (real runs write).
set -eu

CASE_NAME=dry-run-unwritable-target
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'chmod 0755 "$CASE_TMP/nowrite" 2>/dev/null; rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# A target directory the invoking (non-root) user cannot write to.
mkdir -p "$CASE_TMP/nowrite"
chmod 0555 "$CASE_TMP/nowrite"
OUT="$CASE_TMP/nowrite/out.conf"

GEN_SUMMARY='would blacklist [0-9]+ of [0-9]+ modules'

# --- 1. --dry-run must succeed against the unwritable target ---
set +e
"$MODULEJAIL_BIN" --dry-run -o "$OUT" > "$CASE_TMP/dry.out" 2>&1
rc=$?
set -e
assert_eq 0 "$rc" "dry-run-exit-code-on-unwritable-target"
assert_grep "$GEN_SUMMARY" "$CASE_TMP/dry.out" dry-run-produced-preview
if grep -qi "cannot write to" "$CASE_TMP/dry.out"; then
    case_fail "--dry-run errored on unwritable target dir (gh #28 regression)"
fi
if [ -e "$OUT" ]; then
    case_fail "--dry-run wrote the output file (should touch nothing)"
fi

# --- 2. Control: a REAL run against the same target still errors (77) ---
# Skipped when running as root, where the write-permission bit does not apply.
if [ "$(id -u)" -ne 0 ]; then
    set +e
    "$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/real.out" 2>&1
    rc=$?
    set -e
    assert_eq 77 "$rc" "real-run-blocked-on-unwritable-target"
    assert_grep "cannot write to" "$CASE_TMP/real.out" real-run-cannot-write-message
fi

case_pass
