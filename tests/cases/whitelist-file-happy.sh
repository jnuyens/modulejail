#!/bin/sh
# Case: --whitelist-file FILE on a well-formed, properly-permissioned file.
# Expect exit 0, and the named modules MUST NOT appear in the generated
# blacklist (they are added to the keep-set).
set -eu

CASE_NAME=whitelist-file-happy
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

WL=$CASE_TMP/whitelist.txt
{
    printf '# Operator notes: keep our two site-local modules\n'
    printf 'vfio_pci\n'
    printf '\n'
    printf '# blank line above is allowed\n'
    printf 'nft_compat\n'
} > "$WL"
chmod 0644 "$WL"

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --whitelist-file "$WL" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Modules in the whitelist file MUST NOT appear as install lines in the
# blacklist - they are in the keep-set, so they are excluded. The install
# line body varies (/bin/true vs /bin/sh + logger, per Plan 03-02), so the
# pattern matches "^install <name> " agnostically.
if grep -qE '^install vfio_pci ' "$OUT"; then
    case_fail "vfio_pci should not be blacklisted (it is in the whitelist file)"
fi
if grep -qE '^install nft_compat ' "$OUT"; then
    case_fail "nft_compat should not be blacklisted (it is in the whitelist file)"
fi

# Sanity: at least one module IS blacklisted (the fixture pads with ~50
# dummies that nothing keeps). Pattern is install-line-form-agnostic.
if ! grep -qE '^install dummy_[0-9]+ ' "$OUT"; then
    case_fail "no dummy_* module ended up in the blacklist; pipeline did not run"
fi

# Success line on stdout.
assert_grep '^modulejail: blacklisted [0-9]+ of [0-9]+ modules' "$CASE_TMP/stdout" success-summary

case_pass
