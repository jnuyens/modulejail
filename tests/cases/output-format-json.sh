#!/bin/sh
# Case: --output-format json emits a single-line JSON object on stdout with
# schema_version=1, correct tool.name, 64-char hex fingerprint, and output_path.
# Skip (not fail) when jq is absent on the running host.
set -eu

CASE_NAME=output-format-json
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

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --output-format json -o "$OUT" > "$CASE_TMP/stdout" 2>/dev/null || \
    case_fail "modulejail --output-format json exited $? (expected 0)"

# stdout must be exactly one line (strip leading spaces from wc -l for portability).
if [ "$(wc -l < "$CASE_TMP/stdout" | tr -d ' ')" != "1" ]; then
    case_fail "JSON output is not exactly one line"
fi

# stdout must parse as valid JSON.
if ! jq -e . < "$CASE_TMP/stdout" >/dev/null 2>&1; then
    case_fail "JSON output did not parse with jq"
fi

# schema_version must be 1.
sv=$(jq -r .schema_version < "$CASE_TMP/stdout")
assert_eq "1" "$sv" "schema_version"

# tool.name must be "modulejail".
tn=$(jq -r .tool.name < "$CASE_TMP/stdout")
assert_eq "modulejail" "$tn" "tool.name"

# fingerprint must be 64 lowercase hex chars (no sha256: prefix).
fp=$(jq -r .fingerprint < "$CASE_TMP/stdout")
if ! printf '%s' "$fp" | grep -qE '^[0-9a-f]{64}$'; then
    case_fail "fingerprint is not 64 hex chars: $fp"
fi

# output_path must be the OUT path.
op=$(jq -r .output_path < "$CASE_TMP/stdout")
assert_eq "$OUT" "$op" "output_path"

# dry_run must be false (no --dry-run flag passed).
dr=$(jq -r .dry_run < "$CASE_TMP/stdout")
assert_eq "false" "$dr" "dry_run"

case_pass
