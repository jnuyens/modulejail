#!/bin/sh
# Case: the build-time switch for distro packages. Applying the documented
# sed line to the script flips UPDATE_CHECK_DEFAULT from 1 to 0 (exactly one
# line changes), and the flipped copy no longer runs the post-run update
# check even with MODULEJAIL_NO_UPDATE_CHECK unset. Control: the unmodified
# script does print the notice against the same fake "newer" tag.
#
# The fake tags endpoint is a file:// URL, so this needs curl (wget has no
# file:// support). Without curl the network half is skipped.
set -eu

CASE_NAME=update-check-build-switch
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# The sed line must be the one the script's own comment documents.
SED_EXPR='s/^UPDATE_CHECK_DEFAULT=1$/UPDATE_CHECK_DEFAULT=0/'
grep -qF "sed -i '$SED_EXPR' modulejail" "$MODULEJAIL_BIN" \
    || case_fail "script comment no longer documents: sed -i '$SED_EXPR' modulejail"

PATCHED=$CASE_TMP/modulejail-packaged
sed "$SED_EXPR" "$MODULEJAIL_BIN" > "$PATCHED"
chmod 0755 "$PATCHED"
changed=$(diff "$MODULEJAIL_BIN" "$PATCHED" | grep -c '^>' || true)
assert_eq 1 "$changed" sed-changes-exactly-one-line
assert_grep '^UPDATE_CHECK_DEFAULT=0$' "$PATCHED" patched-switch-off

if ! command -v curl >/dev/null 2>&1; then
    printf '[%s] note: curl not found, skipping the update-check run half\n' "$CASE_NAME"
    case_pass
    exit 0
fi

printf '[\n  {\n    "name": "v99.0.0",\n    "zipball_url": "x"\n  }\n]\n' > "$CASE_TMP/tags.json"
URL="file://$CASE_TMP/tags.json"

run() {
    # run SCRIPT LABEL: a normal generation run with the check enabled at run time.
    set +e
    env -u MODULEJAIL_NO_UPDATE_CHECK MODULEJAIL_UPDATE_URL="$URL" \
        "$1" -o "$CASE_TMP/out-$2.conf" > "$CASE_TMP/stdout-$2" 2> "$CASE_TMP/stderr-$2"
    rc=$?
    set -e
    assert_eq 0 "$rc" "$2-exit-code"
}

run "$MODULEJAIL_BIN" stock
assert_grep 'newer release is available: v99.0.0' "$CASE_TMP/stdout-stock" stock-prints-notice

run "$PATCHED" packaged
if grep -q 'newer release is available' "$CASE_TMP/stdout-packaged" "$CASE_TMP/stderr-packaged"; then
    case_fail "packaged copy (UPDATE_CHECK_DEFAULT=0) still ran the update check"
fi

case_pass
