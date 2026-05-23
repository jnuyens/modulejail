#!/bin/sh
# Case: HDR-01 regression-fixture lock.
# The generated blacklist MUST contain a line matching "^# kernel: \S+$" -
# a non-empty kernel-version token after "# kernel:". This fixture prevents
# a future refactor from silently dropping or renaming the kernel header line.
#
# Cross-reference: the JSON/logfmt schema "kernel_version" field carries the
# same value as the "# kernel: KVER" header line (see OUTPUT FORMATS in
# man/modulejail.8.in). Both are derived from uname -r (or MODULEJAIL_KVER
# in test environments). The test exercises only the file header; the JSON
# schema field is covered by output-format-json.sh.
#
# This test is the D-Phase5-13 documentation+regression-fixture contract.
set -eu

CASE_NAME=header-kernel-line-locked
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# HDR-01 assertion: the "# kernel: KVER" header line must exist with a
# non-empty kernel version token (no whitespace-only value).
assert_grep '^# kernel: \S+$' "$OUT" header-kernel-line-locked

case_pass
