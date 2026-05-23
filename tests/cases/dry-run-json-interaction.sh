#!/bin/sh
# Case: --dry-run --output-format json emits JSON with dry_run=true and
# output_path set to the would-be path; the would-be header still appears
# on stderr; the output file is NOT written.
# Skip (not fail) when jq is absent on the running host.
set -eu

CASE_NAME=dry-run-json-interaction
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

if ! command -v jq >/dev/null 2>&1; then
    printf '[%s] SKIP: jq not present\n' "$CASE_NAME"
    exit 0
fi

OUT=$CASE_TMP/would-be-output.conf
"$MODULEJAIL_BIN" --dry-run --output-format json -o "$OUT" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail --dry-run --output-format json exited $? (expected 0)"

# The output file MUST NOT exist.
if [ -e "$OUT" ]; then
    case_fail "--dry-run --output-format json wrote file at $OUT (should write nothing)"
fi

# stdout must parse as valid JSON.
if ! jq -e . < "$CASE_TMP/stdout" >/dev/null 2>&1; then
    case_fail "JSON output did not parse with jq"
fi

# dry_run must be true.
dr=$(jq -r .dry_run < "$CASE_TMP/stdout")
assert_eq "true" "$dr" "dry_run-field"

# output_path must be the would-be path (not null or empty).
op=$(jq -r .output_path < "$CASE_TMP/stdout")
assert_eq "$OUT" "$op" "output_path-would-be"

# stderr must contain the would-be header lines.
assert_grep '^# modulejail' "$CASE_TMP/stderr" dry-run-json-header-line-1
assert_grep '^# fingerprint:' "$CASE_TMP/stderr" dry-run-json-header-line-5
assert_grep '^# Do not edit by hand' "$CASE_TMP/stderr" dry-run-json-header-disclaimer

case_pass
