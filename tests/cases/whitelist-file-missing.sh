#!/bin/sh
# Case: --whitelist-file PATH where PATH does not exist (or is not
# readable) is rejected with EX_NOINPUT (66).
set -eu

CASE_NAME=whitelist-file-missing
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
BOGUS=$CASE_TMP/does-not-exist/anywhere/whitelist.txt

set +e
"$MODULEJAIL_BIN" --whitelist-file "$BOGUS" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 66 "$rc" exit-code-EX_NOINPUT
assert_grep "whitelist file $BOGUS does not exist or is not readable" "$CASE_TMP/stderr" stderr-message

# Output MUST NOT have been written.
if [ -e "$OUT" ]; then
    case_fail "$OUT was written despite EX_NOINPUT rejection"
fi

case_pass
