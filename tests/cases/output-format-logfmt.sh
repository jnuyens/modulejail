#!/bin/sh
# Case: --output-format logfmt emits a single-line key=value summary on stdout
# with schema_version=1, tool_name=modulejail, 64-char hex fingerprint, and
# output_path matching the -o target.
set -eu

CASE_NAME=output-format-logfmt
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --output-format logfmt -o "$OUT" > "$CASE_TMP/stdout" 2>/dev/null || \
    case_fail "modulejail --output-format logfmt exited $? (expected 0)"

# stdout must be exactly one line (strip leading spaces from wc -l for portability).
if [ "$(wc -l < "$CASE_TMP/stdout" | tr -d ' ')" != "1" ]; then
    case_fail "logfmt output is not exactly one line"
fi

# Must start with schema_version=1 tool_name=modulejail.
if ! grep -qE '^schema_version=1 tool_name=modulejail ' "$CASE_TMP/stdout"; then
    case_fail "logfmt output does not start with 'schema_version=1 tool_name=modulejail '"
fi

# fingerprint must be 64 lowercase hex chars (no sha256: prefix).
if ! grep -qE 'fingerprint=[0-9a-f]{64}' "$CASE_TMP/stdout"; then
    case_fail "logfmt fingerprint field is not 64 hex chars"
fi

# output_path must contain the OUT path.
if ! grep -qE "output_path=$OUT( |\$)" "$CASE_TMP/stdout"; then
    case_fail "logfmt output_path does not match -o target: $OUT"
fi

case_pass
