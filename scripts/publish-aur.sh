#!/bin/sh
# Publish the current packaging/aur/PKGBUILD to AUR.
#
# Idempotent and safe to re-run. Uses this host's SSH key for the AUR push;
# defers .SRCINFO regeneration to a remote Arch host (DEFAULT: archbox)
# because makepkg is not available on macOS.
#
# Typical flow:
#
#     # In modulejail/:
#     # 1. Edit modulejail's VERSION constant.
#     # 2. Run the rest of the release ceremony (CHANGELOG, README URLs,
#     #    commit, tag, git push --tags, build .deb/.rpm, gh release create).
#     # 3. Then:
#     ./scripts/publish-aur.sh
#
# The script:
#   - reads pkgver from the modulejail script's VERSION constant
#   - downloads the GitHub release tarball, computes its sha256
#   - updates packaging/aur/PKGBUILD in place (pkgver, pkgrel=1, sha256sums)
#   - regenerates .SRCINFO on $REMOTE_BUILD_HOST via docker
#   - clones the AUR git repo if not already present locally
#   - mirrors PKGBUILD/LICENSE/.SRCINFO and pushes to AUR
#
# Options:
#   --dry-run        Stop before the AUR push (everything else still runs).
#   --pkgrel-bump    Don't change pkgver; bump pkgrel by 1 instead. Use for
#                    packaging-only changes (e.g. adding a conflicts= line).
#   --no-bump        Skip ALL PKGBUILD modifications - publish the file
#                    exactly as it sits on disk. Use to retry a publish
#                    after a partial failure where the bump already
#                    happened locally.
#
# Environment:
#   REMOTE_BUILD_HOST   SSH host with makepkg installed (default: archbox).
#                       Must be Arch or an Arch derivative - the only command
#                       run remotely is `makepkg --printsrcinfo`, which
#                       requires the pacman/makepkg toolchain.
#   AUR_PUBLISH_DIR     Local path for the AUR git clone (default:
#                       /tmp/aur-modulejail-publish).

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PKGBUILD=$REPO_ROOT/packaging/aur/PKGBUILD
LICENSE=$REPO_ROOT/packaging/aur/LICENSE
SIGNING_KEY=$REPO_ROOT/packaging/aur/modulejail-signing-key.gpg
REMOTE_BUILD_HOST=${REMOTE_BUILD_HOST:-archbox}
AUR_PUBLISH_DIR=${AUR_PUBLISH_DIR:-/tmp/aur-modulejail-publish}

DRY_RUN=0
PKGREL_BUMP=0
NO_BUMP=0
for arg in "$@"; do
    case $arg in
        --dry-run)     DRY_RUN=1 ;;
        --pkgrel-bump) PKGREL_BUMP=1 ;;
        --no-bump)     NO_BUMP=1 ;;
        *) echo "publish-aur.sh: unknown argument '$arg'" >&2; exit 2 ;;
    esac
done

if [ "$PKGREL_BUMP" -eq 1 ] && [ "$NO_BUMP" -eq 1 ]; then
    echo "publish-aur.sh: --pkgrel-bump and --no-bump are mutually exclusive." >&2
    exit 2
fi

# --- read target version from the modulejail script -------------------------
VERSION=$(awk -F"'" '/^VERSION=/ {print $2; exit}' "$REPO_ROOT/modulejail")
if [ -z "$VERSION" ]; then
    echo "publish-aur.sh: could not determine VERSION from modulejail script" >&2
    exit 1
fi
TARBALL_URL=https://github.com/jnuyens/modulejail/archive/refs/tags/v$VERSION.tar.gz

echo "publish-aur.sh: target version = $VERSION"
echo "publish-aur.sh: tarball URL    = $TARBALL_URL"

CURRENT_PKGVER=$(awk -F= '/^pkgver=/ {print $2; exit}' "$PKGBUILD")
CURRENT_PKGREL=$(awk -F= '/^pkgrel=/ {print $2; exit}' "$PKGBUILD")

if [ "$NO_BUMP" -eq 1 ]; then
    # Trust the PKGBUILD as-is. Don't even hit the network for the tarball.
    NEW_PKGVER=$CURRENT_PKGVER
    NEW_PKGREL=$CURRENT_PKGREL
    echo "publish-aur.sh: --no-bump set; publishing PKGBUILD as-is ($NEW_PKGVER-$NEW_PKGREL)"
else
    # --- verify the tarball is reachable (the tag must already be on GitHub)
    if ! curl -fsI "$TARBALL_URL" >/dev/null 2>&1; then
        echo "publish-aur.sh: tarball $TARBALL_URL not reachable yet." >&2
        echo "  Did you 'git push --tags' already?  This script needs the tag" >&2
        echo "  to exist on GitHub so the AUR PKGBUILD can reference it." >&2
        exit 1
    fi

    # --- compute sha256 of the tarball
    SHA256=$(curl -fsSL "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')
    echo "publish-aur.sh: tarball sha256 = $SHA256"

    if [ "$PKGREL_BUMP" -eq 1 ]; then
        NEW_PKGVER=$CURRENT_PKGVER
        NEW_PKGREL=$((CURRENT_PKGREL + 1))
        echo "publish-aur.sh: --pkgrel-bump set; keeping pkgver=$NEW_PKGVER, bumping pkgrel to $NEW_PKGREL"
    else
        NEW_PKGVER=$VERSION
        NEW_PKGREL=1
        if [ "$NEW_PKGVER" = "$CURRENT_PKGVER" ] && [ "$NEW_PKGREL" -le "$CURRENT_PKGREL" ]; then
            echo "publish-aur.sh: PKGBUILD already at $NEW_PKGVER-$CURRENT_PKGREL; nothing to publish." >&2
            echo "  (If this is a packaging-only change, use --pkgrel-bump.)" >&2
            echo "  (If this is a retry after a partial failure, use --no-bump.)" >&2
            exit 1
        fi
    fi

    # Update pkgver, pkgrel, and only the FIRST entry of the sha256sums array
    # (the tarball hash). The remaining entries (SKIP for the .sig, the stable
    # hash for the signing-key.gpg) span subsequent lines and must be left
    # untouched - matching the closing `)` would corrupt the multi-line array.
    sed -i.bak \
        -e "s/^pkgver=.*/pkgver=$NEW_PKGVER/" \
        -e "s/^pkgrel=.*/pkgrel=$NEW_PKGREL/" \
        -e "s/^sha256sums=('[^']*'/sha256sums=('$SHA256'/" \
        "$PKGBUILD"
    rm -f "$PKGBUILD.bak"

    echo "publish-aur.sh: PKGBUILD updated to $NEW_PKGVER-$NEW_PKGREL with sha256=$SHA256"
fi

# --- regenerate .SRCINFO on the remote Arch host ----------------------------
echo "publish-aur.sh: regenerating .SRCINFO on $REMOTE_BUILD_HOST..."
ssh "$REMOTE_BUILD_HOST" "rm -rf /tmp/aur-smoke && mkdir -p /tmp/aur-smoke"
scp -q "$PKGBUILD" "$REMOTE_BUILD_HOST:/tmp/aur-smoke/PKGBUILD"
ssh "$REMOTE_BUILD_HOST" 'cd /tmp/aur-smoke && makepkg --printsrcinfo > .SRCINFO'
SRCINFO_TMP=$(mktemp)
scp -q "$REMOTE_BUILD_HOST:/tmp/aur-smoke/.SRCINFO" "$SRCINFO_TMP"

# --- prepare the AUR publish clone ------------------------------------------
if [ ! -d "$AUR_PUBLISH_DIR/.git" ]; then
    echo "publish-aur.sh: cloning AUR repo to $AUR_PUBLISH_DIR..."
    rm -rf "$AUR_PUBLISH_DIR"
    git clone --quiet ssh://aur@aur.archlinux.org/modulejail.git "$AUR_PUBLISH_DIR"
else
    echo "publish-aur.sh: refreshing existing AUR clone..."
    git -C "$AUR_PUBLISH_DIR" fetch --quiet
    git -C "$AUR_PUBLISH_DIR" reset --quiet --hard origin/master
fi

cp "$PKGBUILD"    "$AUR_PUBLISH_DIR/PKGBUILD"
cp "$LICENSE"     "$AUR_PUBLISH_DIR/LICENSE"
cp "$SIGNING_KEY" "$AUR_PUBLISH_DIR/modulejail-signing-key.gpg"
cp "$SRCINFO_TMP" "$AUR_PUBLISH_DIR/.SRCINFO"
rm -f "$SRCINFO_TMP"

# Remove the previous-pkgrel .asc filename if it lingers from an older clone.
git -C "$AUR_PUBLISH_DIR" rm --quiet --cached --ignore-unmatch modulejail-signing-key.asc 2>/dev/null || true
rm -f "$AUR_PUBLISH_DIR/modulejail-signing-key.asc"

git -C "$AUR_PUBLISH_DIR" add PKGBUILD LICENSE modulejail-signing-key.gpg .SRCINFO

if git -C "$AUR_PUBLISH_DIR" diff --staged --quiet; then
    echo "publish-aur.sh: no changes vs AUR HEAD; nothing to push."
    exit 0
fi

git -C "$AUR_PUBLISH_DIR" commit --quiet -m "modulejail $NEW_PKGVER-$NEW_PKGREL"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "publish-aur.sh: --dry-run set; stopping before push."
    echo "  AUR clone is in $AUR_PUBLISH_DIR, commit is local-only."
    exit 0
fi

echo "publish-aur.sh: pushing to AUR..."
git -C "$AUR_PUBLISH_DIR" push --quiet
echo "publish-aur.sh: done. https://aur.archlinux.org/packages/modulejail"
