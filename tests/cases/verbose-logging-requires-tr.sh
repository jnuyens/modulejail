#!/bin/sh
# Case: --verbose-logging requires `tr` (coreutils) to be executable.
# The enriched install-line pipes /proc/$PPID/cmdline through tr to
# strip control bytes and convert NULs to spaces. If tr is absent at
# blacklist-generation time, the install-line would emit `tr: command
# not found` into syslog at modprobe-time, mangling the log entry.
# modulejail MUST exit EX_NOINPUT=66 with a clear stderr message
# instead of silently generating broken install lines.
#
# Override via MODULEJAIL_TR_PATH (test-only plumbing, parallel to
# MODULEJAIL_LOGGER_PATH).
set -eu

CASE_NAME=verbose-logging-requires-tr
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
set +e
MODULEJAIL_TR_PATH=/nonexistent/tr-binary \
"$MODULEJAIL_BIN" --verbose-logging -o "$OUT" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 66 "$rc" EX_NOINPUT

# stderr MUST cite --verbose-logging and the missing tr path.
if ! grep -q "verbose-logging" "$CASE_TMP/stderr"; then
    case_fail "stderr did not mention --verbose-logging. stderr=$(cat "$CASE_TMP/stderr")"
fi
if ! grep -q "/nonexistent/tr-binary" "$CASE_TMP/stderr"; then
    case_fail "stderr did not cite the missing tr path. stderr=$(cat "$CASE_TMP/stderr")"
fi

# Output file MUST NOT exist.
if [ -e "$OUT" ]; then
    case_fail "output file written despite EX_NOINPUT"
fi

case_pass
