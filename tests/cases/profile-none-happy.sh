#!/bin/sh
# Case: -p none exits 0, header has profile=none, info: line emits on stderr,
# and the >99% sanity guard does NOT fire even with a tiny module universe.
set -eu

CASE_NAME=profile-none-happy
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
set +e
"$MODULEJAIL_BIN" -p none -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 0 "$rc" "profile-none-exit-code"

# Header must record profile=none.
assert_grep '^# profile: none$' "$OUT" profile-none-header-line

# The -p none info: breadcrumb must appear on stderr.
assert_grep '^modulejail: info: -p none selected' "$CASE_TMP/stderr" profile-none-info-line

# The >99% sanity guard must NOT fire (rc already asserted 0 above; double-check
# no error about >99% appears in stderr).
if grep -qE 'error:.*99%' "$CASE_TMP/stderr"; then
    case_fail ">99% sanity guard fired under -p none (should be skipped)"
fi

case_pass
