#!/bin/sh
# Case: --verbose-logging enriches the per-blocked-load logger call with
# the caller's PPID/loginuid/pcomm/pexe (read from /proc/$PPID/...).
# Default (no flag) keeps the bare "blocked: <module>" form for backward
# compatibility.
#
# Skip (not fail) when /usr/bin/logger is absent on the host: the flag
# requires logger to be executable, and the test asserts behavior of the
# logger-path branch specifically.
set -eu

CASE_NAME=verbose-logging-enriches-install-line
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

if [ ! -x /usr/bin/logger ]; then
    printf '[%s] SKIP: /usr/bin/logger not executable on this host\n' "$CASE_NAME"
    exit 0
fi

OUT_VERBOSE=$CASE_TMP/out-verbose.conf
OUT_DEFAULT=$CASE_TMP/out-default.conf

# Run 1: --verbose-logging on
"$MODULEJAIL_BIN" --verbose-logging -o "$OUT_VERBOSE" \
    > "$CASE_TMP/stdout-verbose" 2> "$CASE_TMP/stderr-verbose" || \
    case_fail "modulejail --verbose-logging exited $? (expected 0)"

# Run 2: default (no flag)
"$MODULEJAIL_BIN" -o "$OUT_DEFAULT" \
    > "$CASE_TMP/stdout-default" 2> "$CASE_TMP/stderr-default" || \
    case_fail "modulejail (default) exited $? (expected 0)"

# Header annotation MUST be the verbose-logging form when --verbose-logging set.
assert_grep '^# install-line: /bin/sh \+ logger \+ ppid/loginuid/pcomm/pexe context \(syslog tag: modulejail, --verbose-logging\)$' \
    "$OUT_VERBOSE" header-verbose-annotation

# Header annotation MUST be the legacy logger form when --verbose-logging is not set.
assert_grep '^# install-line: /bin/sh \+ logger \(syslog tag: modulejail\)$' \
    "$OUT_DEFAULT" header-default-annotation

# Body MUST carry the enriched logger call under --verbose-logging.
# Every install line should reference $PPID, loginuid, pcomm, pexe as
# literal strings (single-quoted; resolved at modprobe time by /bin/sh).
# assert_grep uses ERE (grep -E); the literal `(` chars in the
# `$(...)` substrings need `\(` escape so ERE treats them as literal
# rather than as group-open metacharacters.
# shellcheck disable=SC2016  # the \$PPID etc. are LITERAL by design
assert_grep 'ppid=\$PPID' "$OUT_VERBOSE" body-verbose-ppid
# shellcheck disable=SC2016
assert_grep 'loginuid=\$\(cat /proc/\$PPID/loginuid' "$OUT_VERBOSE" body-verbose-loginuid
# shellcheck disable=SC2016
assert_grep 'pcomm=\$\(cat /proc/\$PPID/comm' "$OUT_VERBOSE" body-verbose-pcomm
# pexe uses tr twice (v1.3.5; v1.3.4 used cat which concatenated argv
# elements because shell substitution strips NULs). First tr strips
# control bytes (\x01-\x08 \x0b-\x1f \x7f) for log-injection
# hardening; second tr converts NUL to space so argv elements show
# as space-separated. Per @retry-the-user in #18. Using grep -F
# (fixed string) here because the install-line content has literal
# backslash-octal sequences that are awkward to match in ERE.
if ! grep -F -e "pexe=\$(/usr/bin/tr -d '\\001-\\010\\013-\\037\\177' < /proc/\$PPID/cmdline" "$OUT_VERBOSE" > /dev/null; then
    case_fail "pexe tr -d control-strip pattern not found in $OUT_VERBOSE"
fi
if ! grep -F -e "| /usr/bin/tr '\\0' ' '" "$OUT_VERBOSE" > /dev/null; then
    case_fail "pexe tr NUL-to-space pattern not found in $OUT_VERBOSE"
fi

# Verbose install line MUST NOT have the /bin/sh -c wrapper (v1.3.5;
# v1.3.4 had one, which caused $PPID to point at the wrapper sh
# instead of modprobe). Per @retry-the-user in #18.
# shellcheck disable=SC2016
if grep -qE "/bin/sh -c '/usr/bin/logger" "$OUT_VERBOSE"; then
    case_fail "verbose install line contains a redundant /bin/sh -c wrapper - \$PPID will point at the wrapper sh, not at modprobe"
fi

# Body MUST NOT carry the enriched form under default (no flag).
# shellcheck disable=SC2016
if grep -qE 'ppid=\$PPID' "$OUT_DEFAULT"; then
    case_fail "default body contains ppid=\\\$PPID (should be bare blocked: <mod>)"
fi

# Body under default MUST carry the bare "blocked: <mod>" v1.2.2 form
# (byte-identical to v1.2.2 by construction).
assert_grep "^install [a-zA-Z0-9_-]+ /bin/sh -c '/usr/bin/logger -t modulejail \"blocked: [a-zA-Z0-9_-]+\" 2>/dev/null; exit 0'\$" \
    "$OUT_DEFAULT" body-default-form

case_pass
