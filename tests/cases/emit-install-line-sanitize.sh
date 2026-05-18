#!/bin/sh
# Case: defense-in-depth regression — emit_install_line
# input sanitization. Feeds adversarial filenames through the full
# pipeline and asserts the generated /etc/modprobe.d/-format output
# contains none of the adversarial characters in any install-line
# module-name token, under BOTH the --no-syslog-logging form (v1.1.4
# /bin/true body) AND the default logger form (where the threat
# actually bites — unmatched quotes in module names would break shell
# quoting at modprobe-eval time).
#
# Pre-fix, the universe walker only filtered by .ko* suffix and did
# dash-to-underscore normalization; it did NOT enforce the canonical
# kernel-module regex on the basename. Adversarial filenames under
# /lib/modules/$KVER/ flowed unescaped into install lines:
#     install evil'name /bin/sh -c '/usr/bin/logger -t modulejail ...'
#                                  ^ unmatched single quote breaks shell
# The fix added `if (n !~ /^[a-zA-Z0-9_]+$/) next` in list_universe
# (after the gsub(/-/, "_", n) line) and the same filter in list_loaded.
# Adversarial-named files are dropped from the universe and never reach
# emit_install_line.
#
# This case uses the open-coded REPO_ROOT/CASE_TMP/trap pattern (not
# case-env.sh) because it needs adversarial filenames that case-env's
# standard fixture tree does not have.
set -eu

CASE_NAME=emit-install-line-sanitize
export CASE_NAME

# Locate repo root relative to this script.
case "${0:-}" in
    /*) CASE_SCRIPT=$0 ;;
    *)  CASE_SCRIPT=$(pwd)/$0 ;;
esac
CASE_DIR=$(cd "$(dirname "$CASE_SCRIPT")" && pwd)
REPO_ROOT=$(cd "$CASE_DIR/../.." && pwd)
MODULEJAIL_BIN=$REPO_ROOT/modulejail
if [ ! -x "$MODULEJAIL_BIN" ] && [ ! -f "$MODULEJAIL_BIN" ]; then
    printf '[%s] FAIL: cannot locate modulejail at %s\n' \
        "$CASE_NAME" "$MODULEJAIL_BIN" >&2
    exit 1
fi

CASE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-sanitize.XXXXXX")
trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Build a synthetic /lib/modules/$KVER/kernel/ tree:
#   - 3 adversarial .ko files (single-quote, $IFS, whitespace);
#   - ~13 baseline-name padding (a subset of BASELINE_CONSERVATIVE);
#   - 50 dummy_N modules so the universe is large enough that
#     blacklist/universe stays under 99% (sanity guard at modulejail
#     lines 560-566).
CASE_KVER=6.99.0-sanitize
TREE_ROOT=$CASE_TMP/lib/modules/$CASE_KVER/kernel
mkdir -p "$TREE_ROOT/fs" "$TREE_ROOT/net" "$TREE_ROOT/drivers" \
         "$TREE_ROOT/crypto" "$TREE_ROOT/evil"

# Adversarial files — three distinct adversarial characters per the
# threat model: single quote, dollar+text-that-looks-like-an-IFS-ref,
# whitespace. Quoting carefully so the *shell* invoking touch passes
# the literal bytes through to the filesystem.
touch "$TREE_ROOT/evil/evil'name.ko"        # literal single quote
touch "$TREE_ROOT/evil/dollar\$IFS.ko"      # literal $ then IFS
touch "$TREE_ROOT/evil/with space.ko"       # literal space

# Verify the three adversarial files actually landed on disk (defensive:
# if the touch above silently dropped one we'd silently get a false PASS).
adversarial_count=$(find "$TREE_ROOT/evil" -type f -name '*.ko' | wc -l)
if [ "$adversarial_count" -lt 3 ]; then
    printf '[%s] FAIL: only %d/3 adversarial files were created on disk\n' \
        "$CASE_NAME" "$adversarial_count" >&2
    ls -la "$TREE_ROOT/evil/" >&2
    exit 1
fi

# Baseline-name padding so list_baseline-kept modules are in the universe
# (otherwise comm -23 universe.txt keep.txt subtracts loaded+baseline
# names that are not in the universe, producing only the adversarial
# residue, which after the canonical-name filter would be 0 -> EX_SOFTWARE empty-
# blacklist trip). Reuse the same baseline subset case-env.sh uses.
touch \
    "$TREE_ROOT/fs/ext4.ko.zst" \
    "$TREE_ROOT/fs/btrfs.ko.zst" \
    "$TREE_ROOT/fs/xfs.ko.xz" \
    "$TREE_ROOT/fs/vfat.ko.gz" \
    "$TREE_ROOT/net/sctp.ko.zst" \
    "$TREE_ROOT/net/netfilter.ko.zst" \
    "$TREE_ROOT/net/nft_compat.ko" \
    "$TREE_ROOT/drivers/e1000e.ko" \
    "$TREE_ROOT/drivers/virtio_net.ko.gz" \
    "$TREE_ROOT/drivers/vfio_pci.ko.zst" \
    "$TREE_ROOT/drivers/usb_storage.ko.zst" \
    "$TREE_ROOT/crypto/aes_generic.ko.zst" \
    "$TREE_ROOT/crypto/sha256_generic.ko"

i=1
while [ "$i" -le 50 ]; do
    touch "$TREE_ROOT/drivers/dummy_$i.ko.zst"
    i=$((i + 1))
done

# Synthetic /proc/modules — a handful of canonical names so list_loaded
# is non-empty. None of the adversarial names appear here (they would
# never appear in real /proc/modules; the kernel only exposes canonical
# names). The list_loaded canonical-name filter is exercised by the absence-of-
# noise property: even if /proc/modules had a malformed name, it would
# be filtered.
CASE_PROC=$CASE_TMP/proc-modules
{
    printf '%s 16384 1 - Live 0x0000000000000000\n' ext4
    printf '%s 16384 1 - Live 0x0000000000000000\n' btrfs
    printf '%s 16384 1 - Live 0x0000000000000000\n' xfs
    printf '%s 16384 1 - Live 0x0000000000000000\n' e1000e
    printf '%s 16384 1 - Live 0x0000000000000000\n' virtio_net
    printf '%s 16384 1 - Live 0x0000000000000000\n' usb_storage
    printf '%s 16384 1 - Live 0x0000000000000000\n' aes_generic
} > "$CASE_PROC"

# assert_clean OUTPUT_FILE LABEL: run the two adversarial-character
# grep/awk checks against the generated blacklist and fail with a
# diagnostic dump if either trips.
assert_clean() {
    out=$1
    label=$2

    # Check 1: no single-quote or dollar character anywhere in an
    # install-line module-name token (field 2). Search the whole file
    # first as a coarse net — if any of those characters appear
    # anywhere we want to know.
    if grep -nE "^install [^[:space:]]*['\$]" "$out" >"$CASE_TMP/grep.out"; then
        printf '[%s] FAIL: [%s] install-line module-name field contains shell-special char:\n' \
            "$CASE_NAME" "$label" >&2
        sed 's/^/    /' < "$CASE_TMP/grep.out" >&2
        exit 1
    fi

    # Check 2: every install-line $2 token must match the canonical
    # kernel-module regex. awk-on-field-2 is the tight check.
    awk '/^install / {
        if ($2 ~ /[^a-zA-Z0-9_]/) {
            printf "%d: %s\n", NR, $0
        }
    }' "$out" >"$CASE_TMP/awk.out"
    if [ -s "$CASE_TMP/awk.out" ]; then
        printf '[%s] FAIL: [%s] install-line field 2 contains non-canonical chars:\n' \
            "$CASE_NAME" "$label" >&2
        sed 's/^/    /' < "$CASE_TMP/awk.out" >&2
        exit 1
    fi

    # Bonus check: verify no adversarial basename appears as a token
    # anywhere in the file (catches a hypothetical future regression
    # where the install-line shape changes but the universe walker
    # still admits adversarial names).
    if grep -qE "(evil_name|dollar|with space|with_space)" "$out"; then
        # `evil'name` would not match here because the regex above is
        # alpha-only; the gsub(/-/, "_", n) gate also does not affect
        # single quotes or dollars. But the strings could match if
        # the filter is partial — capture them explicitly.
        :
    fi
    if grep -nE "\\\$IFS|evil'|with space" "$out" >"$CASE_TMP/lit.out"; then
        printf '[%s] FAIL: [%s] adversarial basename leaked into output:\n' \
            "$CASE_NAME" "$label" >&2
        sed 's/^/    /' < "$CASE_TMP/lit.out" >&2
        exit 1
    fi
}

# Run 1: --no-syslog-logging form (v1.1.4 /bin/true body).
OUT1=$CASE_TMP/out.no-logger.conf
MODULEJAIL_MODULES_ROOT=$CASE_TMP/lib/modules \
MODULEJAIL_KVER=$CASE_KVER \
MODULEJAIL_PROC_MODULES=$CASE_PROC \
MODULEJAIL_NO_UPDATE_CHECK=1 \
MODULEJAIL_DEFAULT_WHITELIST_FILE=$CASE_TMP/default-whitelist-absent.conf \
"$MODULEJAIL_BIN" --no-syslog-logging -o "$OUT1" \
    > "$CASE_TMP/stdout.no-logger" 2> "$CASE_TMP/stderr.no-logger" || {
    rc=$?
    printf '[%s] FAIL: modulejail --no-syslog-logging exited %d\n' \
        "$CASE_NAME" "$rc" >&2
    printf '  stderr:\n' >&2
    sed 's/^/    /' < "$CASE_TMP/stderr.no-logger" >&2
    exit 1
}
assert_clean "$OUT1" "--no-syslog-logging"

# Run 2: default logger form. The threat actually bites here — an
# unmatched single quote in field 2 would break the shell quoting of
# the logger install-line body. We need /usr/bin/logger (or any
# executable) at MODULEJAIL_LOGGER_PATH for the USE_LOGGER branch in
# modulejail to fire. macOS dev box ships /usr/bin/logger; fall back
# to /bin/echo on hosts without it (the install-line shape is what
# this test cares about, not logger semantics).
LOGGER_PATH=/usr/bin/logger
if [ ! -x "$LOGGER_PATH" ]; then
    if [ -x /bin/echo ]; then
        LOGGER_PATH=/bin/echo
    else
        printf '[%s] FAIL: no executable available for MODULEJAIL_LOGGER_PATH\n' \
            "$CASE_NAME" >&2
        exit 1
    fi
fi

OUT2=$CASE_TMP/out.logger.conf
MODULEJAIL_MODULES_ROOT=$CASE_TMP/lib/modules \
MODULEJAIL_KVER=$CASE_KVER \
MODULEJAIL_PROC_MODULES=$CASE_PROC \
MODULEJAIL_NO_UPDATE_CHECK=1 \
MODULEJAIL_DEFAULT_WHITELIST_FILE=$CASE_TMP/default-whitelist-absent.conf \
MODULEJAIL_LOGGER_PATH=$LOGGER_PATH \
"$MODULEJAIL_BIN" -o "$OUT2" \
    > "$CASE_TMP/stdout.logger" 2> "$CASE_TMP/stderr.logger" || {
    rc=$?
    printf '[%s] FAIL: modulejail (default logger form) exited %d\n' \
        "$CASE_NAME" "$rc" >&2
    printf '  stderr:\n' >&2
    sed 's/^/    /' < "$CASE_TMP/stderr.logger" >&2
    exit 1
}
assert_clean "$OUT2" "default logger"

# Sanity: confirm the run actually emitted install lines (i.e. the
# universe was large enough that the sanity guard did not trip on a
# pure-baseline keep-set). 50 dummy_N files in the universe should
# all be blacklisted.
n1=$(grep -c '^install ' "$OUT1")
n2=$(grep -c '^install ' "$OUT2")
if [ "$n1" -lt 10 ] || [ "$n2" -lt 10 ]; then
    printf '[%s] FAIL: too few install lines: --no-logger=%d, logger=%d (expected >=10 each)\n' \
        "$CASE_NAME" "$n1" "$n2" >&2
    exit 1
fi

# Confirm the universe sizes were equal for both runs (the only thing
# that differed between the two invocations is USE_LOGGER, so the set
# of blacklisted modules should be identical).
if [ "$n1" -ne "$n2" ]; then
    printf '[%s] FAIL: install-line count drift: --no-logger=%d, logger=%d\n' \
        "$CASE_NAME" "$n1" "$n2" >&2
    exit 1
fi

printf '[%s] PASS\n' "$CASE_NAME"
exit 0
