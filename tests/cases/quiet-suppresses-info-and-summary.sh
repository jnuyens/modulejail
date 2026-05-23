#!/bin/sh
# Case: --quiet suppresses stdout summary and all non-error stderr output
# (info: lines, notice: lines) while still writing the output file.
set -eu

CASE_NAME=quiet-suppresses-info-and-summary
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Stage a default whitelist file so the info: line would normally fire.
DWL=$CASE_TMP/etc-default-whitelist.conf
printf '# default whitelist for quiet test\next4\n' > "$DWL"
chmod 0644 "$DWL"
MODULEJAIL_DEFAULT_WHITELIST_FILE=$DWL
export MODULEJAIL_DEFAULT_WHITELIST_FILE

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --quiet -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail --quiet exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# stdout must be empty (summary suppressed).
# Strip leading spaces from wc -c for portability (macOS pads with spaces).
if [ "$(wc -c < "$CASE_TMP/stdout" | tr -d ' ')" != "0" ]; then
    case_fail "--quiet did not suppress stdout summary; stdout=$(cat "$CASE_TMP/stdout")"
fi

# stderr must contain no info: or notice: lines.
if grep -qE 'modulejail: (info|notice):' "$CASE_TMP/stderr"; then
    case_fail "--quiet did not suppress info:/notice: lines; stderr=$(cat "$CASE_TMP/stderr")"
fi

# stderr must contain no would-be header lines (no dry-run active).
if grep -qE '^# modulejail' "$CASE_TMP/stderr"; then
    case_fail "--quiet did not suppress would-be header on stderr"
fi

# The output file MUST still be written.
if [ ! -s "$OUT" ]; then
    case_fail "--quiet prevented output file from being written"
fi

case_pass
