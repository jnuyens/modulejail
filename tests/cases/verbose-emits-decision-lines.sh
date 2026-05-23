#!/bin/sh
# Case: --verbose emits per-module decision lines on stderr in the form
# "keep: NAME (loaded|whitelist|baseline)" and "blacklist: NAME".
# Decision lines must NOT carry a severity prefix (no "modulejail: keep:").
set -eu

CASE_NAME=verbose-emits-decision-lines
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --verbose -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail --verbose exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# At least one "keep: NAME (loaded)" line must appear (loaded modules are always kept).
if ! grep -qE '^keep: [a-zA-Z0-9_-]+ \(loaded\)$' "$CASE_TMP/stderr"; then
    case_fail "no 'keep: NAME (loaded)' lines found in verbose stderr"
fi

# At least one "keep: NAME (baseline)" line must appear (conservative profile has baseline).
if ! grep -qE '^keep: [a-zA-Z0-9_-]+ \(baseline\)$' "$CASE_TMP/stderr"; then
    case_fail "no 'keep: NAME (baseline)' lines found in verbose stderr"
fi

# At least one "blacklist: NAME" line must appear.
if ! grep -qE '^blacklist: [a-zA-Z0-9_-]+$' "$CASE_TMP/stderr"; then
    case_fail "no 'blacklist: NAME' lines found in verbose stderr"
fi

# Decision lines must NOT carry the "modulejail:" severity prefix.
if grep -qE '^modulejail: keep:' "$CASE_TMP/stderr"; then
    case_fail "keep: lines carry 'modulejail:' severity prefix (should be plain 'keep:')"
fi
if grep -qE '^modulejail: blacklist:' "$CASE_TMP/stderr"; then
    case_fail "blacklist: lines carry 'modulejail:' severity prefix (should be plain 'blacklist:')"
fi

case_pass
