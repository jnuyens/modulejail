#!/bin/sh
# Case: --quiet and --verbose are mutually exclusive.
# Combining them MUST exit EX_USAGE=64 with a clear stderr error.
set -eu

CASE_NAME=quiet-verbose-mutually-exclusive
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

set +e
"$MODULEJAIL_BIN" --quiet --verbose -o "$CASE_TMP/out.conf" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 64 "$rc" "rejection-exit-code"
assert_grep "mutually exclusive" "$CASE_TMP/stderr" "rejection-stderr-message"

# Defense-in-depth: no output file should have been written.
if [ -f "$CASE_TMP/out.conf" ]; then
    case_fail "modulejail wrote an output file despite the usage error"
fi

case_pass
