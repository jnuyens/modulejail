#!/bin/sh
# Build + run the per-distro fixture containers. Probe for docker first,
# fall back to podman. On a host with neither, print a clear skip message
# and exit with skip code (77) so the maintainer notices but Plan 02-04's
# SSH-host tests can still run.
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

if command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
else
    printf 'modulejail tests: no container runtime found (docker/podman); skipping fixtures.\n' >&2
    printf 'modulejail tests: install colima/OrbStack on macOS, or run on a Linux host with docker/podman.\n' >&2
    exit 77
fi

printf 'modulejail tests: using %s\n' "$RUNTIME"

FAIL=0
for distro in arch alpine opensuse; do
    img=modulejail-fixture-$distro
    printf '\n== Building %s fixture ==\n' "$distro"
    "$RUNTIME" build -f "tests/fixtures/$distro/Dockerfile" -t "$img" . || { FAIL=$((FAIL+1)); continue; }
    printf '== Running %s fixture ==\n' "$distro"
    if "$RUNTIME" run --rm "$img" sh /tests/lib/run-in-fixture.sh "$distro"; then
        printf '[%s] PASS\n' "$distro"
    else
        printf '[%s] FAIL\n' "$distro"
        FAIL=$((FAIL+1))
    fi
done

if [ "$FAIL" -gt 0 ]; then
    printf '\nmodulejail tests: %d fixture(s) FAILED.\n' "$FAIL" >&2
    exit 1
fi

printf '\nmodulejail tests: all fixtures PASSED.\n'
