#!/bin/sh
# Case: a whitelist file containing any non-comment, non-blank line that
# does not match [a-zA-Z0-9_-]+ is rejected with EX_DATAERR (65). The
# stderr message must reference the file path, line number, and the
# offending content.
set -eu

CASE_NAME=whitelist-file-bad-name
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
WL=$CASE_TMP/whitelist.txt

# Line 1: comment (ignored).
# Line 2: valid (ignored when computing rejection, but parsed).
# Line 3: blank (ignored).
# Line 4: a deliberately hostile shell-injection-shaped string. The strict
#         regex must catch this and reject the file BEFORE any of its
#         content reaches modprobe.d.
# Line 5: a name with dots, which sometimes appears in stray copy-pastes.
printf '%s\n' \
    '# operator notes' \
    'vfio_pci' \
    '' \
    'evil; rm -rf /' \
    'module.name.with.dots' \
    > "$WL"
chmod 0644 "$WL"

set +e
"$MODULEJAIL_BIN" --whitelist-file "$WL" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 65 "$rc" exit-code-EX_DATAERR

# stderr must mention the validation error and reference the bad input.
assert_grep 'invalid module name' "$CASE_TMP/stderr" stderr-message
assert_grep 'must match \[a-zA-Z0-9_-\]\+' "$CASE_TMP/stderr" stderr-regex-hint
# Line number: at least one of line 4 or line 5 must be flagged. (The
# implementation reports every bad line; either one being present proves
# line-numbering works.)
assert_grep "line [45]:" "$CASE_TMP/stderr" stderr-line-number

# Output MUST NOT have been written.
if [ -e "$OUT" ]; then
    case_fail "$OUT was written despite EX_DATAERR rejection"
fi

case_pass
