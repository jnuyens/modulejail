#!/bin/sh
# Case: --fail-on-module-load with --no-syslog-logging produces /bin/false
# install lines (silent form). The whole install command returns non-zero,
# so modprobe fails loudly for blacklisted modules instead of silently
# succeeding.
#
# Also asserts that the default-off (no -f flag) silent path is byte-
# identical to v1.1.4 (preserved by the v1.1.4-regression.sh case, but
# defended here too for the local diff).
set -eu

CASE_NAME=fail-on-module-load-silent
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT_FAIL=$CASE_TMP/out-fail.conf
OUT_DEFAULT=$CASE_TMP/out-default.conf

# Run 1: --no-syslog-logging --fail-on-module-load
"$MODULEJAIL_BIN" --no-syslog-logging --fail-on-module-load -o "$OUT_FAIL" \
    > "$CASE_TMP/stdout-fail" 2> "$CASE_TMP/stderr-fail" || \
    case_fail "modulejail --no-syslog-logging --fail-on-module-load exited $? (expected 0)"

# Run 2: --no-syslog-logging without -f (default)
"$MODULEJAIL_BIN" --no-syslog-logging -o "$OUT_DEFAULT" \
    > "$CASE_TMP/stdout-default" 2> "$CASE_TMP/stderr-default" || \
    case_fail "modulejail --no-syslog-logging exited $? (expected 0)"

# Header annotation MUST be the /bin/false form when -f is set.
assert_grep '^# install-line: /bin/false \(silent, --fail-on-module-load\)$' \
    "$OUT_FAIL" header-false-annotation

# Header annotation MUST be the /bin/true form when -f is not set.
assert_grep '^# install-line: /bin/true \(silent, --no-syslog-logging or logger absent\)$' \
    "$OUT_DEFAULT" header-true-annotation-default

# Body MUST carry /bin/false install lines under -f.
assert_grep '^install [a-zA-Z0-9_-]+ /bin/false$' "$OUT_FAIL" body-false-form

# Body MUST NOT carry /bin/true lines under -f.
if grep -qE '^install [a-zA-Z0-9_-]+ /bin/true$' "$OUT_FAIL"; then
    case_fail "body contains /bin/true install lines under --fail-on-module-load (should be /bin/false)"
fi

# Body MUST carry /bin/true install lines under default-off (byte-identical
# to v1.1.4 / v1.2.2).
assert_grep '^install [a-zA-Z0-9_-]+ /bin/true$' "$OUT_DEFAULT" body-true-form-default

# Body MUST NOT carry /bin/false lines under default-off.
if grep -qE '^install [a-zA-Z0-9_-]+ /bin/false$' "$OUT_DEFAULT"; then
    case_fail "body contains /bin/false install lines without --fail-on-module-load (default should be /bin/true)"
fi

case_pass
