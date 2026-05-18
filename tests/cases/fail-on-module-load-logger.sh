#!/bin/sh
# Case: --fail-on-module-load with the logger form (default-on when
# /usr/bin/logger is executable) replaces the trailing `; exit 0` with
# `; /bin/false`, so modprobe fails loudly after the syslog message is
# emitted.
#
# Also asserts that the default-off (no -f flag) logger path is byte-
# identical to v1.2.2 (i.e. still uses `; exit 0`).
#
# Skip (not fail) when /usr/bin/logger is absent on the host, matching the
# pattern in logger-default-on.sh.
set -eu

CASE_NAME=fail-on-module-load-logger
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

if [ ! -x /usr/bin/logger ]; then
    printf '[%s] SKIP: /usr/bin/logger not executable on this host\n' "$CASE_NAME"
    exit 0
fi

OUT_FAIL=$CASE_TMP/out-fail.conf
OUT_DEFAULT=$CASE_TMP/out-default.conf

# Run 1: default-on logger + --fail-on-module-load
"$MODULEJAIL_BIN" --fail-on-module-load -o "$OUT_FAIL" \
    > "$CASE_TMP/stdout-fail" 2> "$CASE_TMP/stderr-fail" || \
    case_fail "modulejail --fail-on-module-load exited $? (expected 0)"

# Run 2: default-on logger without -f (default)
"$MODULEJAIL_BIN" -o "$OUT_DEFAULT" \
    > "$CASE_TMP/stdout-default" 2> "$CASE_TMP/stderr-default" || \
    case_fail "modulejail (default) exited $? (expected 0)"

# Header annotation MUST be the logger + /bin/false form when -f is set.
assert_grep '^# install-line: /bin/sh \+ logger \+ /bin/false \(syslog tag: modulejail, --fail-on-module-load\)$' \
    "$OUT_FAIL" header-logger-false-annotation

# Header annotation MUST be the legacy logger form when -f is not set.
assert_grep '^# install-line: /bin/sh \+ logger \(syslog tag: modulejail\)$' \
    "$OUT_DEFAULT" header-logger-default-annotation

# Body MUST carry `; /bin/false` in the logger trailer when -f is set.
assert_grep "^install [a-zA-Z0-9_-]+ /bin/sh -c '/usr/bin/logger -t modulejail \"blocked: [a-zA-Z0-9_-]+\" 2>/dev/null; /bin/false'\$" \
    "$OUT_FAIL" body-logger-false-form

# Body MUST NOT carry `; exit 0` under -f.
if grep -qE "; exit 0'\$" "$OUT_FAIL"; then
    case_fail "body contains '; exit 0' under --fail-on-module-load (should be '; /bin/false')"
fi

# Body MUST carry `; exit 0` under default-off (byte-identical to v1.2.2).
assert_grep "^install [a-zA-Z0-9_-]+ /bin/sh -c '/usr/bin/logger -t modulejail \"blocked: [a-zA-Z0-9_-]+\" 2>/dev/null; exit 0'\$" \
    "$OUT_DEFAULT" body-logger-default-form

# Body MUST NOT carry `; /bin/false` under default-off.
if grep -qE "; /bin/false'\$" "$OUT_DEFAULT"; then
    case_fail "body contains '; /bin/false' without --fail-on-module-load (default should be '; exit 0')"
fi

case_pass
