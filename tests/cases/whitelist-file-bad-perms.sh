#!/bin/sh
# Case: whitelist files with group- or world-write bits set are rejected
# with EX_NOPERM (77) and a chmod-hint stderr message.
set -eu

CASE_NAME=whitelist-file-bad-perms
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf

check_rejection() {
    mode=$1
    label=$2
    WL=$CASE_TMP/whitelist-$label.txt
    printf 'vfio_pci\n' > "$WL"
    chmod "$mode" "$WL"

    set +e
    "$MODULEJAIL_BIN" --whitelist-file "$WL" -o "$OUT" \
        > "$CASE_TMP/stdout-$label" 2> "$CASE_TMP/stderr-$label"
    rc=$?
    set -e

    assert_eq 77 "$rc" "exit code for $label (mode=$mode)"
    assert_grep 'must not be group- or world-writable' "$CASE_TMP/stderr-$label" "$label-stderr-message"
    assert_grep "chmod go-w" "$CASE_TMP/stderr-$label" "$label-stderr-chmod-hint"
    assert_grep "whitelist file $WL" "$CASE_TMP/stderr-$label" "$label-stderr-path-quoted"

    # Output file MUST NOT exist (rejection happens before write).
    if [ -e "$OUT" ]; then
        case_fail "$label: $OUT was written despite rejection"
    fi
}

# Group-writable (0664).
check_rejection 0664 group-writable

# World-writable (0666).
check_rejection 0666 world-writable

case_pass
