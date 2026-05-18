#!/bin/sh
# Shared setup for host-local test cases under tests/cases/.
# Sourced (NOT executed) by each case; exports a hermetic synthetic
# kernel-module tree and a fake /proc/modules under $CASE_TMP. Each case
# is responsible for installing an EXIT trap that removes $CASE_TMP.
#
# Inputs (set by the case BEFORE sourcing this file):
#   CASE_NAME - short label printed in pass/fail lines.
#
# Outputs (exported for the modulejail invocation):
#   MODULEJAIL_MODULES_ROOT - synthetic /lib/modules root
#   MODULEJAIL_KVER         - pinned synthetic kernel version
#   MODULEJAIL_PROC_MODULES - path to fake /proc/modules
#   MODULEJAIL_NO_UPDATE_CHECK=1 - suppress the post-run update check
#                                  so cases are network-hermetic.
#   CASE_TMP                - tempdir root (case must rm -rf it on exit)
#
# This file is intentionally minimal: it does NOT define assertion
# helpers (those live in tests/lib/assert.sh) and it does NOT chdir.

# Locate the repo root so cases can be invoked from any cwd.
# tests/cases/<case>.sh -> dirname -> tests/cases -> ../.. -> repo root.
case "${0:-}" in
    /*) CASE_SCRIPT=$0 ;;
    *)  CASE_SCRIPT=$(pwd)/$0 ;;
esac
CASE_DIR=$(cd "$(dirname "$CASE_SCRIPT")" && pwd)
REPO_ROOT=$(cd "$CASE_DIR/../.." && pwd)
export REPO_ROOT
MODULEJAIL_BIN=$REPO_ROOT/modulejail
export MODULEJAIL_BIN

CASE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-case.XXXXXX")
export CASE_TMP

CASE_KVER=6.99.0-case
CASE_MODULES_ROOT=$CASE_TMP/lib/modules
CASE_TREE=$CASE_MODULES_ROOT/$CASE_KVER/kernel
mkdir -p "$CASE_TREE/fs" "$CASE_TREE/net" "$CASE_TREE/drivers" "$CASE_TREE/crypto"

# Representative universe: a handful across the four .ko* suffix variants
# plus padding to keep the >99% sanity guard from tripping on the small
# keep-set (loaded ~7 entries + baseline ~55 + whitelist additions).
touch \
    "$CASE_TREE/fs/ext4.ko.zst" \
    "$CASE_TREE/fs/btrfs.ko.zst" \
    "$CASE_TREE/fs/xfs.ko.xz" \
    "$CASE_TREE/fs/vfat.ko.gz" \
    "$CASE_TREE/net/sctp.ko.zst" \
    "$CASE_TREE/net/netfilter.ko.zst" \
    "$CASE_TREE/net/nft_compat.ko" \
    "$CASE_TREE/drivers/e1000e.ko" \
    "$CASE_TREE/drivers/virtio_net.ko.gz" \
    "$CASE_TREE/drivers/vfio_pci.ko.zst" \
    "$CASE_TREE/drivers/usb_storage.ko.zst" \
    "$CASE_TREE/crypto/aes_generic.ko.zst" \
    "$CASE_TREE/crypto/sha256_generic.ko"

i=1
while [ "$i" -le 50 ]; do
    touch "$CASE_TREE/drivers/dummy_$i.ko.zst"
    i=$((i + 1))
done

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

MODULEJAIL_MODULES_ROOT=$CASE_MODULES_ROOT
MODULEJAIL_KVER=$CASE_KVER
MODULEJAIL_PROC_MODULES=$CASE_PROC
MODULEJAIL_NO_UPDATE_CHECK=1
# Point the default-whitelist-file detector at a path inside $CASE_TMP that
# does not exist. This isolates cases from any /etc/modulejail/whitelist.conf
# that may exist on a developer's machine or a CI runner. Cases that want
# to exercise the default-detection path override this themselves.
MODULEJAIL_DEFAULT_WHITELIST_FILE=$CASE_TMP/default-whitelist-absent.conf
export MODULEJAIL_MODULES_ROOT MODULEJAIL_KVER MODULEJAIL_PROC_MODULES MODULEJAIL_NO_UPDATE_CHECK MODULEJAIL_DEFAULT_WHITELIST_FILE

# Convenience helpers --------------------------------------------------------

# case_pass: print success line and exit 0.
case_pass() {
    printf '[%s] PASS\n' "${CASE_NAME:-unknown-case}"
    exit 0
}

# case_fail MSG: print failure line on stderr and exit 1.
case_fail() {
    printf '[%s] FAIL: %s\n' "${CASE_NAME:-unknown-case}" "$1" >&2
    exit 1
}
