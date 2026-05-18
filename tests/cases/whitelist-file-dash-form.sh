#!/bin/sh
# Case: dash form module names in --whitelist-file are normalized to underscore
# form before joining the keep-set.
#
# Regression for the v1.2 code-review BLOCKER: the manpage and README both
# document "Module names are accepted in both dash and underscore form;
# the pipeline normalises - to _ internally." Before the fix, the
# parse_whitelist_file output was concatenated into whitelist.txt without
# the tr '-' '_' pass that list_baseline / list_whitelist / list_universe
# all apply, so a file entry "nft-compat" silently failed to match
# /proc/modules's "nft_compat" and the module got blacklisted anyway.
set -eu

CASE_NAME=whitelist-file-dash-form
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Whitelist file uses dash form for two modules that the synthetic
# universe carries in underscore form (nft_compat.ko and vfio_pci.ko.zst,
# both planted by case-env.sh).
WL=$CASE_TMP/whitelist.conf
{
    printf '# Dash-form entries; pipeline must normalize them.\n'
    printf 'nft-compat\n'
    printf 'vfio-pci\n'
} > "$WL"
chmod 0644 "$WL"

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --whitelist-file "$WL" -o "$OUT" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# After normalization, the underscore-form names should be in the keep-set
# and therefore MUST NOT appear in the blacklist.
if grep -qE '^install nft_compat ' "$OUT"; then
    case_fail "nft_compat should not be blacklisted (whitelist file had dash form 'nft-compat')"
fi
if grep -qE '^install vfio_pci ' "$OUT"; then
    case_fail "vfio_pci should not be blacklisted (whitelist file had dash form 'vfio-pci')"
fi

# Defense-in-depth: the dash form MUST NOT appear in the blacklist either
# (no install lines for the literal dash names should be present, since
# /proc/modules and list_universe both use underscore form).
if grep -qE '^install nft-compat ' "$OUT"; then
    case_fail "dash form 'nft-compat' leaked into blacklist; normalization failed"
fi

case_pass
