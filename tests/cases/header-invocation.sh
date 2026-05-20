#!/bin/sh
# Case: with /usr/bin/logger present on the host AND no --no-syslog-logging
# flag, modulejail emits the syslog-logging install-line form and the
# matching header annotation.
#
# Skip (not fail) when /usr/bin/logger is absent on the running host: this
# case asserts the positive default-on path, which is only exercisable when
# logger is actually executable. The complementary logger-absent-fallback.sh
# case covers the negative path via MODULEJAIL_LOGGER_PATH override.
set -eu

CASE_NAME=header-invocation
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header invocation test plain args
assert_grep "^# invocation: $MODULEJAIL_BIN -o $OUT$" \
    "$OUT" header-invocation-plain-args

"$MODULEJAIL_BIN" --whitelist-file '' -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header invocation test empty args
assert_grep "^# invocation: $MODULEJAIL_BIN --whitelist-file '' -o $OUT$" \
    "$OUT" header-invocation-empty-args

OUT="$CASE_TMP/out put.conf"
"$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header invocation test args with spaces
assert_grep "^# invocation: $MODULEJAIL_BIN -o '$OUT'$" \
    "$OUT" header-invocation-args-with-spaces

OUT="$CASE_TMP/out'put.conf"
"$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header invocation test args with single quotes
assert_grep "^# invocation: $MODULEJAIL_BIN -o '$CASE_TMP/out'''put.conf'$" \
    "$OUT" header-invocation-args-with-single-quotes

case_pass
