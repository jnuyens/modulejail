#!/bin/sh
# Case: --no-whitelist-file skips an existing default whitelist file.
#
# When --no-whitelist-file is passed, modulejail MUST NOT load the default
# file even if it exists. The info-message MUST be absent from stderr.
# Module names in the default file MUST end up blacklisted (proves the
# default was skipped, not silently merged).
set -eu

CASE_NAME=whitelist-file-default-opt-out
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Plant a default file containing a non-baseline module.
DEFAULT_WL=$CASE_TMP/etc/modulejail/whitelist.conf
mkdir -p "$(dirname "$DEFAULT_WL")"
printf 'vfio_pci\n' > "$DEFAULT_WL"
chmod 0644 "$DEFAULT_WL"
MODULEJAIL_DEFAULT_WHITELIST_FILE=$DEFAULT_WL
export MODULEJAIL_DEFAULT_WHITELIST_FILE

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --no-whitelist-file -o "$OUT" \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail --no-whitelist-file exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# No info-line for default-detection: --no-whitelist-file forced the skip.
if grep -q 'using default whitelist file' "$CASE_TMP/stderr"; then
    case_fail "modulejail emitted default-detection info despite --no-whitelist-file"
fi

# vfio_pci IS in the universe (CASE_TREE plants it), is NOT in
# /proc/modules (CASE_PROC omits it), is NOT in the baseline-conservative,
# and was supposed to be added by the default file we just skipped — so
# it MUST end up blacklisted.
if ! grep -qE '^install vfio_pci ' "$OUT"; then
    case_fail "vfio_pci should be blacklisted (default file was skipped via --no-whitelist-file)"
fi

case_pass
