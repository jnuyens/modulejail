#!/bin/sh
# Case: default whitelist file auto-detection.
#
# When --whitelist-file is NOT passed and the path resolved by
# $MODULEJAIL_DEFAULT_WHITELIST_FILE (default: /etc/modulejail/whitelist.conf)
# exists, modulejail picks it up automatically with the same strict mode
# and content gates. An "info:" line MUST appear on stderr documenting
# the auto-detected path, so operators are not surprised.
set -eu

CASE_NAME=whitelist-file-default-used
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Plant a fake default whitelist file in CASE_TMP and point the env
# override at it. case-env.sh has already set the var to a non-existent
# path; we override here.
DEFAULT_WL=$CASE_TMP/etc/modulejail/whitelist.conf
mkdir -p "$(dirname "$DEFAULT_WL")"
{
    printf '# default whitelist file used for auto-detection test\n'
    printf 'vfio_pci\n'
    printf 'nft_compat\n'
} > "$DEFAULT_WL"
chmod 0644 "$DEFAULT_WL"
MODULEJAIL_DEFAULT_WHITELIST_FILE=$DEFAULT_WL
export MODULEJAIL_DEFAULT_WHITELIST_FILE

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Info line MUST be on stderr (severity-prefixed per OPS-03).
assert_grep "^modulejail: info: using default whitelist file $DEFAULT_WL" \
    "$CASE_TMP/stderr" default-detection-info

# Modules from the default file MUST NOT appear in the blacklist.
if grep -qE '^install vfio_pci ' "$OUT"; then
    case_fail "vfio_pci should not be blacklisted (default whitelist file has it)"
fi
if grep -qE '^install nft_compat ' "$OUT"; then
    case_fail "nft_compat should not be blacklisted (default whitelist file has it)"
fi

# Sanity: at least one module IS blacklisted.
if ! grep -qE '^install dummy_[0-9]+ ' "$OUT"; then
    case_fail "no dummy_* module ended up in the blacklist; pipeline did not run"
fi

case_pass
