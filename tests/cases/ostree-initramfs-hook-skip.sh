#!/bin/sh
# Case: on ostree / immutable systems (Fedora Silverblue, Kinoite, CoreOS,
# bootc), --install-initramfs-hook must SKIP cleanly with an explanation
# rather than crash writing a dracut module to the read-only /usr.
#
# Why it is safe to skip: verified on Silverblue 45, the initramfs is
# image-provided and never includes /etc/modprobe.d (not by default, and not
# even with `rpm-ostree initramfs --enable` host-local regeneration), so the
# gh #19 upgrade-then-stale trap the hook guards against does not exist there.
#
# Detection is /run/ostree-booted, overridable via MODULEJAIL_OSTREE_MARKER
# for this test. --dry-run is used so the case can run unprivileged (the
# real-run root gate fires before the hook body); the ostree skip is checked
# on the dry-run path, which reaches the same code.
set -eu

CASE_NAME=ostree-initramfs-hook-skip
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

MARKER=$CASE_TMP/ostree-booted
: > "$MARKER"

set +e
MODULEJAIL_OSTREE_MARKER="$MARKER" MODULEJAIL_INITRAMFS_BUILDER=dracut \
    "$MODULEJAIL_BIN" --install-initramfs-hook --dry-run \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 0 "$rc" "ostree-skip-exit-code"
assert_grep 'ostree/immutable system detected' "$CASE_TMP/stdout" ostree-detected-message
assert_grep 'not needed here' "$CASE_TMP/stdout" ostree-skip-reason

# It must SKIP before the builder logic: no "would write" dracut lines.
if grep -q 'would write' "$CASE_TMP/stdout"; then
    case_fail "ostree run reached the builder path (should skip before it)"
fi

# Control: WITHOUT the marker, the dracut dry-run path is taken (would write).
set +e
MODULEJAIL_INITRAMFS_BUILDER=dracut "$MODULEJAIL_BIN" --install-initramfs-hook --dry-run \
    > "$CASE_TMP/stdout2" 2> "$CASE_TMP/stderr2"
rc2=$?
set -e
assert_eq 0 "$rc2" "non-ostree-dry-run-exit"
if ! grep -q 'would write' "$CASE_TMP/stdout2"; then
    case_fail "non-ostree dry-run did not take the normal builder path"
fi
if grep -q 'ostree/immutable' "$CASE_TMP/stdout2"; then
    case_fail "non-ostree run wrongly reported ostree detection"
fi

case_pass
