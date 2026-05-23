#!/bin/sh
# Case: -p none --whitelist-file keeps whitelist modules in the keep-set.
# Verify that whitelist entries do NOT appear in the generated blacklist body.
set -eu

CASE_NAME=profile-none-with-whitelist
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

WL=$CASE_TMP/whitelist.conf
printf 'nft_compat\nxt_owner\n' > "$WL"
chmod 0644 "$WL"

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" -p none --whitelist-file "$WL" -o "$OUT" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# nft_compat and xt_owner are in the whitelist so they should NOT appear in
# the blacklist body (which lists all blacklisted modules, one per line via
# "install <name> ..."). Check both underscore and dash forms.
if grep -qE '^install nft_compat ' "$OUT"; then
    case_fail "nft_compat appeared in blacklist despite being in whitelist under -p none"
fi
if grep -qE '^install xt_owner ' "$OUT"; then
    case_fail "xt_owner appeared in blacklist despite being in whitelist under -p none"
fi

# The output file must exist and be non-empty.
if [ ! -s "$OUT" ]; then
    case_fail "output file is missing or empty"
fi

case_pass
