#!/bin/sh
# Case: --output-format with an unknown value exits EX_USAGE=64 with a clear
# stderr error message naming the bad value and the expected valid values.
set -eu

CASE_NAME=output-format-bad-value
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

set +e
"$MODULEJAIL_BIN" --output-format yaml -o "$CASE_TMP/out.conf" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 64 "$rc" "output-format-bad-value-exit-code"
assert_grep '^modulejail: error: unknown --output-format: yaml \(expected json or logfmt\)$' \
    "$CASE_TMP/stderr" "output-format-bad-value-error"

case_pass
