#!/bin/sh
# Case: --quiet does NOT suppress error: lines on stderr. A flag-error path
# (unknown profile) must still emit the error message.
set -eu

CASE_NAME=quiet-does-not-suppress-error
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

set +e
"$MODULEJAIL_BIN" --quiet -p bogus -o "$CASE_TMP/out.conf" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 64 "$rc" "quiet-error-exit-code"
assert_grep '^modulejail: error: unknown profile: bogus' "$CASE_TMP/stderr" "quiet-error-not-silenced"

case_pass
