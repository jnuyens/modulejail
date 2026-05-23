#!/bin/sh
# Case: --dry-run leaves no file at the output path, prints DRY-RUN summary
# on stdout, and prints the would-be 8-line header block on stderr.
set -eu

CASE_NAME=dry-run-writes-nothing
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/should-not-exist.conf
"$MODULEJAIL_BIN" --dry-run -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail --dry-run exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# The output file MUST NOT exist after --dry-run.
if [ -e "$OUT" ]; then
    case_fail "--dry-run wrote file at $OUT (should write nothing)"
fi

# stdout must contain the DRY-RUN summary line.
assert_grep '^modulejail: DRY-RUN: would blacklist [0-9]+ of [0-9]+ modules \(profile=[a-z]+\)' \
    "$CASE_TMP/stdout" dry-run-stdout-summary

# stderr must contain all 8 header lines.
assert_grep '^# modulejail' "$CASE_TMP/stderr" dry-run-header-line-1
assert_grep '^# https://github.com/jnuyens/modulejail$' "$CASE_TMP/stderr" dry-run-header-line-2
assert_grep '^# profile:' "$CASE_TMP/stderr" dry-run-header-line-3
assert_grep '^# kernel:' "$CASE_TMP/stderr" dry-run-header-line-4
assert_grep '^# fingerprint: sha256:[0-9a-f]{64}$' "$CASE_TMP/stderr" dry-run-header-line-5
assert_grep '^# install-line:' "$CASE_TMP/stderr" dry-run-header-line-6
assert_grep '^# invocation:' "$CASE_TMP/stderr" dry-run-header-line-7
assert_grep '^# Do not edit by hand' "$CASE_TMP/stderr" dry-run-header-line-8

# No orphaned dotfile should remain in the target directory.
if ls "$CASE_TMP"/.modulejail-blacklist.conf.* 2>/dev/null | grep -q .; then
    case_fail "orphaned temp dotfile found in $CASE_TMP after --dry-run"
fi

case_pass
