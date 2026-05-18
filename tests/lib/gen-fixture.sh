#!/bin/sh
# Generate /lib/modules/6.99.0-fixture/ with touch-empty .ko* files and
# a fake /proc/modules at /tmp/proc-modules. list_universe reads only
# filenames (sub(/.*\//, ""), strip suffix, normalize -); empty files
# satisfy it. The fake /proc/modules names a SUBSET of the synthetic
# modules so the set arithmetic produces a non-empty, non-degenerate
# blacklist that passes the >99% sanity guard.
set -eu

KVER=6.99.0-fixture
TREE=/lib/modules/$KVER/kernel
PROC=/tmp/proc-modules

mkdir -p "$TREE/fs" "$TREE/net" "$TREE/drivers" "$TREE/crypto"

# A small representative set across the four suffix variants.
touch \
    "$TREE/fs/ext4.ko.zst" \
    "$TREE/fs/btrfs.ko.zst" \
    "$TREE/fs/xfs.ko.xz" \
    "$TREE/fs/vfat.ko.gz" \
    "$TREE/net/sctp.ko.zst" \
    "$TREE/net/netfilter.ko.zst" \
    "$TREE/drivers/e1000e.ko" \
    "$TREE/drivers/virtio_net.ko.gz" \
    "$TREE/drivers/usb_storage.ko.zst" \
    "$TREE/crypto/aes_generic.ko.zst" \
    "$TREE/crypto/sha256_generic.ko"

# Pad to ~60 modules so the >99% sanity guard does not trip when keep-set
# (loaded union baseline union whitelist) is small. The baseline alone has 16
# entries; with ~10 "loaded" + 60 universe + ~16 baseline overlap, the
# blacklist will be well under 99%.
i=1
while [ "$i" -le 50 ]; do
    touch "$TREE/drivers/dummy_$i.ko.zst"
    i=$((i + 1))
done

# Fake /proc/modules — names that appear in the synthetic tree (so they
# end up in the keep-set), plus the existing baseline entries are
# automatically included by the script.
{
    printf '%s 16384 1 - Live 0x0000000000000000\n' ext4
    printf '%s 16384 1 - Live 0x0000000000000000\n' btrfs
    printf '%s 16384 1 - Live 0x0000000000000000\n' xfs
    printf '%s 16384 1 - Live 0x0000000000000000\n' e1000e
    printf '%s 16384 1 - Live 0x0000000000000000\n' virtio_net
    printf '%s 16384 1 - Live 0x0000000000000000\n' usb_storage
    printf '%s 16384 1 - Live 0x0000000000000000\n' aes_generic
} > "$PROC"
