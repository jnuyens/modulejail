#!/bin/sh
# scripts/release.sh - bundle the modulejail release ceremony.
#
# Replaces the ~15 manual steps walked through for v1.4.0 with one
# command. Each step is idempotent and re-runnable; the script checks
# current state before acting (e.g. skips tag creation if the tag
# already exists). Gates pause for explicit y/N before any irreversible
# action (signed tag, push, GitHub release, AUR publish).
#
# Usage:
#
#     scripts/release.sh <version>            # full ceremony
#     scripts/release.sh --dry-run <version>  # print every step, mutate nothing
#     scripts/release.sh --list-checks <version>  # preconditions only
#     scripts/release.sh --from-step N <version>  # resume after partial failure
#
# Preconditions (checked at step 0):
#
#     - working tree is clean
#     - on master branch
#     - origin/master ancestor of HEAD
#     - signing GPG key in keyring
#     - gh CLI authenticated
#     - tests/run-fixtures.sh --only-host-local PASS
#     - CHANGELOG.md has a '## [<version>] - <date>' section
#
# Steps:
#
#     1. Bump VERSION in modulejail; bump v<old>->v<new> URLs in README.
#     2. Release commit (subject overridable via --subject).
#     3. GATE: GPG-sign the annotated tag (annotation pulled from CHANGELOG).
#     4. Push master + tag; wait for CI green.
#     5. Build .deb on $DEB_BUILD_HOST (default: m1) + .rpm on
#        $RPM_BUILD_HOST (default: rocky9). scp artifacts to packaging/dist/.
#     6. Download archive/refs/tags/v<version>.tar.gz; GPG-sign it.
#     7. GATE: gh release create with .deb + .rpm + .sig assets.
#        Verify each asset's HTTP 200 reachability.
#     8. GATE: scripts/publish-aur.sh (PKGBUILD bump + AUR push).
#     9. chore(aur): sync commit + push + final CI watch.
#
# Resume after partial failure: use --from-step N where N is the step
# the script was on when it died. Each step prints its number.
#
# Manual recovery:
#
#     - Pushed tag, want to retract:
#         git push origin :refs/tags/v<version>
#         git tag -d v<version>
#         (Only safe if nothing downstream has consumed the tag yet.)
#     - Created GitHub release, want to retract:
#         gh release delete v<version> --yes
#     - Published to AUR, want to retract:
#         Bump pkgrel manually in AUR repo + force-push.
#
# Environment:
#
#     DEB_BUILD_HOST  ssh host for .deb build (default: m1)
#     RPM_BUILD_HOST  ssh host for .rpm build (default: rocky9)
#     SIGNING_KEY     GPG fingerprint for tag + tarball signing
#                     (default: 095F5C8B39AF010E7B615CD4487BC00D69C2A955)

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

DEB_BUILD_HOST=${DEB_BUILD_HOST:-m1}
RPM_BUILD_HOST=${RPM_BUILD_HOST:-rocky9}
SIGNING_KEY=${SIGNING_KEY:-095F5C8B39AF010E7B615CD4487BC00D69C2A955}
DIST=packaging/dist

EX_OK=0
EX_USAGE=64
EX_SOFTWARE=70

DRY_RUN=0
SKIP_AUR=0
SKIP_DEB=0
SKIP_RPM=0
LIST_CHECKS=0
FROM_STEP=0
SUBJECT=''
VERSION=''

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# *//'
}

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run)      DRY_RUN=1; shift ;;
        --skip-aur)     SKIP_AUR=1; shift ;;
        --skip-deb)     SKIP_DEB=1; shift ;;
        --skip-rpm)     SKIP_RPM=1; shift ;;
        --list-checks)  LIST_CHECKS=1; shift ;;
        --from-step)    [ $# -ge 2 ] || { printf 'release.sh: --from-step requires N\n' >&2; exit $EX_USAGE; }; FROM_STEP=$2; shift 2 ;;
        --from-step=*)  FROM_STEP=${1#--from-step=}; shift ;;
        --subject)      [ $# -ge 2 ] || { printf 'release.sh: --subject requires text\n' >&2; exit $EX_USAGE; }; SUBJECT=$2; shift 2 ;;
        --subject=*)    SUBJECT=${1#--subject=}; shift ;;
        -h|--help)      usage; exit $EX_OK ;;
        -*)             printf 'release.sh: unknown option: %s\n' "$1" >&2; exit $EX_USAGE ;;
        *)              [ -z "$VERSION" ] || { printf 'release.sh: extra positional arg: %s\n' "$1" >&2; exit $EX_USAGE; }; VERSION=$1; shift ;;
    esac
done

[ -n "$VERSION" ] || { usage >&2; exit $EX_USAGE; }
VERSION=${VERSION#v}
TAG=v$VERSION

# --- helpers ---

step() {
    n=$1; desc=$2
    printf '\n=== Step %d: %s ===\n' "$n" "$desc"
}

confirm() {
    msg=$1
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'release.sh: dry-run: would prompt: %s\n' "$msg"
        return 0
    fi
    printf '\n%s [y/N] ' "$msg"
    if [ -t 0 ]; then
        read -r resp
    elif (: < /dev/tty) 2>/dev/null; then
        read -r resp < /dev/tty
    else
        printf 'release.sh: error: non-interactive shell; cannot prompt for gate\n' >&2
        exit $EX_USAGE
    fi
    case "$resp" in
        [yY]|[yY][eE][sS]) ;;
        *) printf 'release.sh: cancelled by operator at gate\n'; exit $EX_OK ;;
    esac
}

# dry_or_real CMD [ARGS...]
# Run CMD in real mode; print "would: ..." in dry-run mode.
dry_or_real() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'release.sh: dry-run: would run: %s\n' "$*"
    else
        "$@"
    fi
}

# changelog_section VERSION
# Extract the CHANGELOG.md section for VERSION between '## [VERSION]' and
# the next '## [' heading (exclusive). Empty output means no section.
changelog_section() {
    awk -v needle="## [$1]" '
        index($0, needle) == 1 { in_section=1; print; next }
        in_section && /^## \[/ { exit }
        in_section             { print }
    ' CHANGELOG.md
}

# wait_ci_green COMMIT
# Wait for the GitHub Actions run on COMMIT to register, then watch
# it to completion with --exit-status (non-zero = failure).
wait_ci_green() {
    head_sha=$1
    printf 'release.sh: waiting for CI run on %s...\n' "$(printf '%s' "$head_sha" | cut -c1-8)"
    sleep 5
    until gh run list --branch master --limit 1 --json headSha --jq '.[0].headSha' 2>/dev/null | grep -q "$head_sha"; do
        sleep 5
    done
    run_id=$(gh run list --branch master --limit 1 --json databaseId --jq '.[0].databaseId')
    printf 'release.sh: watching run %s\n' "$run_id"
    gh run watch "$run_id" --exit-status --interval 15 > /dev/null
    printf 'release.sh: CI green\n'
}

# --- Step 0: preconditions ---

step 0 "Preconditions"

# clean tree (no untracked files in tracked areas, no uncommitted changes;
# gitignored paths like packaging/dist/ are excluded by --porcelain)
if [ -n "$(git status --porcelain)" ]; then
    printf 'release.sh: error: working tree not clean\n' >&2
    git status --short >&2
    exit $EX_SOFTWARE
fi

# on master
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "master" ]; then
    printf 'release.sh: error: not on master (current: %s)\n' "$current_branch" >&2
    exit $EX_SOFTWARE
fi

# up to date with origin/master
git fetch -q origin master
behind=$(git rev-list --count HEAD..origin/master)
if [ "$behind" -gt 0 ]; then
    printf 'release.sh: error: local master is %d commits behind origin/master\n' "$behind" >&2
    exit $EX_SOFTWARE
fi

# signing key
if ! gpg --list-secret-keys "$SIGNING_KEY" >/dev/null 2>&1; then
    printf 'release.sh: error: signing key %s not in GPG keyring\n' "$SIGNING_KEY" >&2
    exit $EX_SOFTWARE
fi

# gh authed
if ! gh auth status >/dev/null 2>&1; then
    printf 'release.sh: error: gh CLI not authenticated; run gh auth login\n' >&2
    exit $EX_SOFTWARE
fi

# CHANGELOG section
section=$(changelog_section "$VERSION")
if [ -z "$section" ]; then
    printf 'release.sh: error: CHANGELOG.md has no "## [%s]" section\n' "$VERSION" >&2
    printf 'release.sh: write release notes before running release.sh\n' >&2
    exit $EX_SOFTWARE
fi

# tests
if [ "$FROM_STEP" -le 0 ]; then
    printf 'release.sh: running tests/run-fixtures.sh --only-host-local...\n'
    if ! tests/run-fixtures.sh --only-host-local > /dev/null 2>&1; then
        printf 'release.sh: error: host-local tests FAILED\n' >&2
        printf 'release.sh: re-run tests/run-fixtures.sh --only-host-local to see the failure\n' >&2
        exit $EX_SOFTWARE
    fi
fi

printf 'release.sh: preconditions OK\n'

if [ "$LIST_CHECKS" -eq 1 ]; then
    printf 'release.sh: --list-checks: stopping after preconditions\n'
    exit $EX_OK
fi

# --- Step 1: bump VERSION + README URLs ---

if [ "$FROM_STEP" -le 1 ]; then
    step 1 "Bump VERSION + README URLs"

    current_version=$(awk -F"'" '/^VERSION=/ {print $2; exit}' modulejail)
    if [ "$current_version" = "$VERSION" ]; then
        printf 'release.sh: VERSION already %s in modulejail (no-op)\n' "$VERSION"
    else
        printf 'release.sh: bumping VERSION %s -> %s\n' "$current_version" "$VERSION"
        dry_or_real sed -i.bak "s/^VERSION='$current_version'/VERSION='$VERSION'/" modulejail
        [ "$DRY_RUN" -eq 1 ] || rm -f modulejail.bak
    fi

    # README URL bumps. Conservative patterns: anything mentioning the OLD
    # version in a URL or filename context. Historical-fact lines (e.g.
    # 'Debian ITP filed against v1.3.6') do NOT match these patterns
    # because they do not include a /v$old/ URL component, /releases/
    # path, or _$old_ filename suffix.
    if [ "$current_version" != "$VERSION" ] && grep -q "v$current_version" README.md 2>/dev/null; then
        printf 'release.sh: bumping README URLs from v%s -> v%s\n' "$current_version" "$VERSION"
        dry_or_real sed -i.bak \
            -e "s|jnuyens/modulejail/v$current_version/|jnuyens/modulejail/v$VERSION/|g" \
            -e "s|releases/download/v$current_version/|releases/download/v$VERSION/|g" \
            -e "s|modulejail_${current_version}_all.deb|modulejail_${VERSION}_all.deb|g" \
            -e "s|modulejail-${current_version}-1.noarch.rpm|modulejail-${VERSION}-1.noarch.rpm|g" \
            -e "s|currently \`v$current_version\`|currently \`v$VERSION\`|g" \
            -e "s|git tag -a v$current_version |git tag -a v$VERSION |g" \
            README.md
        [ "$DRY_RUN" -eq 1 ] || rm -f README.md.bak
    fi
fi

# --- Step 2: release commit ---

if [ "$FROM_STEP" -le 2 ]; then
    step 2 "Release commit"

    if git diff --quiet HEAD; then
        # Either we're resuming after the commit already happened, or
        # the working tree had no edits to commit. Either way: no-op.
        printf 'release.sh: nothing to commit at HEAD (already at v%s?)\n' "$VERSION"
    else
        subject=${SUBJECT:-"release(v$VERSION): see CHANGELOG.md"}
        # Ensure subject starts with the conventional release prefix.
        case "$subject" in
            "release(v$VERSION):"*) ;;
            *) subject="release(v$VERSION): $subject" ;;
        esac
        dry_or_real git add modulejail CHANGELOG.md README.md
        dry_or_real git commit -m "$subject" -m "Full release notes: CHANGELOG.md [$TAG]"
    fi
fi

# --- Step 3: signed tag (gate) ---

if [ "$FROM_STEP" -le 3 ]; then
    step 3 "Sign annotated tag $TAG (irreversible once pushed)"

    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        printf 'release.sh: tag %s already exists locally; skipping creation\n' "$TAG"
    else
        printf '\nrelease.sh: tag annotation (from CHANGELOG):\n---\n%s\n---\n' "$section"
        confirm "Sign and create tag $TAG with the above annotation?"
        if [ "$DRY_RUN" -eq 0 ]; then
            git tag -s "$TAG" -u "$SIGNING_KEY" -m "modulejail $TAG" -m "$section"
            git tag --verify "$TAG" 2>&1 | grep -E '^gpg: (Signature|Good)' || true
        else
            printf 'release.sh: dry-run: would git tag -s %s with CHANGELOG section\n' "$TAG"
        fi
    fi
fi

# --- Step 4: push + CI watch ---

if [ "$FROM_STEP" -le 4 ]; then
    step 4 "Push master + tag, watch CI"
    confirm "Push master + tag $TAG to origin?"
    dry_or_real git push origin master "$TAG"

    if [ "$DRY_RUN" -eq 0 ]; then
        wait_ci_green "$(git rev-parse HEAD)"
    fi
fi

# --- Step 5: build .deb + .rpm ---

if [ "$FROM_STEP" -le 5 ]; then
    step 5 "Build .deb on $DEB_BUILD_HOST + .rpm on $RPM_BUILD_HOST"
    mkdir -p "$DIST"

    if [ "$SKIP_DEB" -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ] || ssh -o ConnectTimeout=5 "$DEB_BUILD_HOST" 'exit 0' 2>/dev/null; then
            printf 'release.sh: building .deb on %s\n' "$DEB_BUILD_HOST"
            dry_or_real ssh "$DEB_BUILD_HOST" "rm -rf /tmp/mj-rel-build && git clone --quiet --depth 1 --branch $TAG https://github.com/jnuyens/modulejail.git /tmp/mj-rel-build && cd /tmp/mj-rel-build && packaging/build.sh --deb"
            dry_or_real scp -q "$DEB_BUILD_HOST:/tmp/mj-rel-build/packaging/dist/modulejail_${VERSION}_all.deb" "$DIST/"
            dry_or_real ssh "$DEB_BUILD_HOST" 'rm -rf /tmp/mj-rel-build'
        else
            printf 'release.sh: warning: %s unreachable; skipping .deb build (--skip-deb to silence)\n' "$DEB_BUILD_HOST"
        fi
    fi

    if [ "$SKIP_RPM" -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ] || ssh -o ConnectTimeout=5 "$RPM_BUILD_HOST" 'exit 0' 2>/dev/null; then
            printf 'release.sh: building .rpm on %s\n' "$RPM_BUILD_HOST"
            dry_or_real ssh "$RPM_BUILD_HOST" "rm -rf /tmp/mj-rel-build && git clone --quiet --depth 1 --branch $TAG https://github.com/jnuyens/modulejail.git /tmp/mj-rel-build && cd /tmp/mj-rel-build && packaging/build.sh --rpm"
            dry_or_real scp -q "$RPM_BUILD_HOST:/tmp/mj-rel-build/packaging/dist/modulejail-${VERSION}-1.noarch.rpm" "$DIST/"
            dry_or_real ssh "$RPM_BUILD_HOST" 'rm -rf /tmp/mj-rel-build'
        else
            printf 'release.sh: warning: %s unreachable; skipping .rpm build (--skip-rpm to silence)\n' "$RPM_BUILD_HOST"
        fi
    fi
fi

# --- Step 6: download tarball + sign ---

if [ "$FROM_STEP" -le 6 ]; then
    step 6 "Download tarball + GPG sign"

    if [ "$DRY_RUN" -eq 0 ]; then
        if [ ! -f "$DIST/$TAG.tar.gz" ]; then
            curl -fsSL -o "$DIST/$TAG.tar.gz" "https://github.com/jnuyens/modulejail/archive/refs/tags/$TAG.tar.gz"
            printf 'release.sh: downloaded %s\n' "$DIST/$TAG.tar.gz"
        else
            printf 'release.sh: %s already present; reusing\n' "$DIST/$TAG.tar.gz"
        fi
        if [ ! -f "$DIST/$TAG.tar.gz.sig" ]; then
            gpg --detach-sign -u "$SIGNING_KEY" -o "$DIST/$TAG.tar.gz.sig" "$DIST/$TAG.tar.gz"
            printf 'release.sh: signed tarball\n'
        else
            printf 'release.sh: %s.sig already present; reusing\n' "$DIST/$TAG.tar.gz"
        fi
        gpg --verify "$DIST/$TAG.tar.gz.sig" "$DIST/$TAG.tar.gz" 2>&1 | grep -E '^gpg: (Signature|Good)' || true
    else
        printf 'release.sh: dry-run: would download archive/refs/tags/%s.tar.gz + gpg --detach-sign\n' "$TAG"
    fi
fi

# --- Step 7: gh release create (gate) ---

if [ "$FROM_STEP" -le 7 ]; then
    step 7 "Publish GitHub release"

    if gh release view "$TAG" --repo jnuyens/modulejail >/dev/null 2>&1; then
        printf 'release.sh: GitHub release %s already exists; skipping create\n' "$TAG"
    else
        confirm "Create GitHub release $TAG (visible to everyone)?"
        # Build asset list from whatever exists in dist/ (skipped builds
        # earlier don't show up here, so the release still creates).
        assets=""
        for f in "modulejail_${VERSION}_all.deb" "modulejail-${VERSION}-1.noarch.rpm" "$TAG.tar.gz.sig"; do
            [ -f "$DIST/$f" ] && assets="$assets $DIST/$f"
        done
        # shellcheck disable=SC2086  # word-splitting on $assets is intentional
        dry_or_real gh release create "$TAG" --title "modulejail $TAG" --notes-from-tag $assets
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        printf 'release.sh: verifying asset URLs:\n'
        for f in "modulejail_${VERSION}_all.deb" "modulejail-${VERSION}-1.noarch.rpm" "$TAG.tar.gz.sig"; do
            [ -f "$DIST/$f" ] || continue
            url="https://github.com/jnuyens/modulejail/releases/download/$TAG/$f"
            code=$(curl -sLI -o /dev/null -w '%{http_code}' "$url")
            printf '  %s -> HTTP %s\n' "$url" "$code"
        done
    fi
fi

# --- Step 8: AUR publish (gate) ---

if [ "$FROM_STEP" -le 8 ] && [ "$SKIP_AUR" -eq 0 ]; then
    step 8 "AUR publish via scripts/publish-aur.sh"

    # Check whether AUR is already at this version; if so, skip.
    aur_current=$(awk -F= '/^pkgver=/ {print $2; exit}' packaging/aur/PKGBUILD)
    if [ "$aur_current" = "$VERSION" ]; then
        printf 'release.sh: local PKGBUILD already at %s; running publish-aur.sh --no-bump\n' "$VERSION"
        confirm "Publish PKGBUILD as-is to AUR?"
        dry_or_real scripts/publish-aur.sh --no-bump
    else
        confirm "Bump PKGBUILD and publish to AUR?"
        dry_or_real scripts/publish-aur.sh
    fi
fi

# --- Step 9: chore(aur) commit + push + CI ---

if [ "$FROM_STEP" -le 9 ] && [ "$SKIP_AUR" -eq 0 ]; then
    step 9 "chore(aur) sync commit + push + CI"

    if git diff --quiet HEAD -- packaging/aur/PKGBUILD; then
        printf 'release.sh: PKGBUILD already in sync (no commit)\n'
    else
        dry_or_real git add packaging/aur/PKGBUILD
        dry_or_real git commit -m "chore(aur): sync PKGBUILD to $VERSION-1 (published)"
        dry_or_real git push origin master
        if [ "$DRY_RUN" -eq 0 ]; then
            wait_ci_green "$(git rev-parse HEAD)"
        fi
    fi
fi

# --- done ---

printf '\n=== release.sh: %s ceremony complete ===\n' "$TAG"
printf 'github:  https://github.com/jnuyens/modulejail/releases/tag/%s\n' "$TAG"
[ "$SKIP_AUR" -eq 0 ] && printf 'aur:     https://aur.archlinux.org/packages/modulejail\n'
