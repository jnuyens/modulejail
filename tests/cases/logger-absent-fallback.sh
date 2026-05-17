#!/bin/sh
# Case: when /usr/bin/logger is not executable on the host AND
# --no-syslog-logging is not set, modulejail silently falls back to the
# v1.1.4 /bin/true install-line form (D-40). The output MUST be byte-
# identical to a run with --no-syslog-logging on the same inputs.
#
# Simulates "logger absent" via the MODULEJAIL_LOGGER_PATH env-var override
# (test-only plumbing parallel to MODULEJAIL_PROC_MODULES / MODULEJAIL_KVER /
# MODULEJAIL_MODULES_ROOT). The override lets this case run on the macOS
# dev box (which has /usr/bin/logger) without requiring a chroot or
# namespace to actually hide the binary.
set -eu

CASE_NAME=logger-absent-fallback
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT_ABSENT=$CASE_TMP/out-absent.conf
OUT_OPTOUT=$CASE_TMP/out-optout.conf

# Run 1: logger forced absent via MODULEJAIL_LOGGER_PATH=/nonexistent.
# No --no-syslog-logging flag - this is the silent-fallback path.
MODULEJAIL_LOGGER_PATH=/nonexistent \
"$MODULEJAIL_BIN" -o "$OUT_ABSENT" > "$CASE_TMP/stdout-absent" 2> "$CASE_TMP/stderr-absent" || \
    case_fail "modulejail (logger absent) exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr-absent")"

# Run 2: explicit --no-syslog-logging opt-out on the same inputs.
"$MODULEJAIL_BIN" --no-syslog-logging -o "$OUT_OPTOUT" > "$CASE_TMP/stdout-optout" 2> "$CASE_TMP/stderr-optout" || \
    case_fail "modulejail --no-syslog-logging exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr-optout")"

# D-40: the silent-fallback path MUST produce byte-identical output to the
# explicit opt-out path. This is the strict invariant: same header (same
# fingerprint, same /bin/true install-line annotation), same body, same
# trailing newline. cmp catches any drift.
assert_cmp "$OUT_ABSENT" "$OUT_OPTOUT"

# Header annotation MUST be the /bin/true form (defence in depth - cmp
# already proves it, but this asserts the form explicitly).
assert_grep '^# install-line: /bin/true \(silent; --no-syslog-logging or logger absent\)$' \
    "$OUT_ABSENT" header-true-annotation-on-absent-fallback

# D-40 explicitly says NO stderr warning when logger is absent and the
# operator did not pass --no-syslog-logging. Stderr must be empty.
if [ -s "$CASE_TMP/stderr-absent" ]; then
    case_fail "logger-absent path produced stderr output; D-40 says silent fallback: $(cat "$CASE_TMP/stderr-absent")"
fi

# No logger reference in either body (sanity).
if grep -qE 'logger -t modulejail' "$OUT_ABSENT"; then
    case_fail "absent-fallback body references logger -t modulejail; should be /bin/true only"
fi

case_pass
