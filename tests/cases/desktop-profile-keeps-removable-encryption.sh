#!/bin/sh
# Case: the desktop profile keeps the mainstream removable-encryption
# modules (sha512_generic, essiv, dm_integrity) even when they are NOT
# loaded at run time, so a locked external LUKS drive still opens after a
# reboot. Discriminating control: an exotic wide-block mode (hctr2) is NOT
# in any baseline and MUST still be blacklisted under -p desktop, proving
# the keep is the profile addition and not a blanket crypto pass.
set -eu

CASE_NAME=desktop-profile-keeps-removable-encryption
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Add the encryption modules to the synthetic universe as available but
# UNLOADED (absent from the fake /proc/modules built by case-tree.sh).
# sha512_generic/essiv/dm_integrity are desktop-baseline additions; hctr2
# is the exotic control that stays whitelist-only.
CRYPTO_DIR=$MODULEJAIL_MODULES_ROOT/$MODULEJAIL_KVER/kernel/crypto
touch \
    "$CRYPTO_DIR/sha512_generic.ko.zst" \
    "$CRYPTO_DIR/essiv.ko.zst" \
    "$CRYPTO_DIR/dm_integrity.ko.zst" \
    "$CRYPTO_DIR/hctr2.ko.zst"

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" -p desktop -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header must record profile=desktop.
assert_grep '^# profile: desktop$' "$OUT" desktop-profile-header-line

# The three desktop-baseline encryption modules MUST NOT be blacklisted.
# Install-line body varies (/bin/true vs /bin/sh + logger), so match the
# "^install <name> " prefix agnostically.
for m in sha512_generic essiv dm_integrity; do
    if grep -qE "^install $m " "$OUT"; then
        case_fail "$m should be kept under -p desktop (removable-encryption baseline)"
    fi
done

# Discriminating control: the exotic mode is present-but-unloaded and not
# in any baseline, so it MUST be blacklisted. If this ever stops matching,
# the test is no longer proving anything (blanket keep or missing module).
if ! grep -qE '^install hctr2 ' "$OUT"; then
    case_fail "hctr2 should be blacklisted under -p desktop (exotic, whitelist-only)"
fi

# Sanity: the pipeline actually ran and blacklisted the dummy padding.
if ! grep -qE '^install dummy_[0-9]+ ' "$OUT"; then
    case_fail "no dummy_* module ended up in the blacklist; pipeline did not run"
fi

case_pass
