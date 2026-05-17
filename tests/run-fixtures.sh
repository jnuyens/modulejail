#!/bin/sh
# Build + run the per-distro fixture containers. Probe for docker first,
# fall back to podman. On a host with neither, print a clear skip message
# and exit with skip code (77) so the maintainer notices but Plan 02-04's
# SSH-host tests can still run.
#
# Usage:
#   tests/run-fixtures.sh                      # full distro matrix
#   tests/run-fixtures.sh --filter PATTERN     # host-local case scripts
#                                              # matching tests/cases/PATTERN*.sh
#                                              # (no container runtime required;
#                                              # for fast iteration on the dev box)
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

# --- Optional --filter PATTERN mode --------------------------------------
# Runs host-local case scripts under tests/cases/ that match the pattern.
# Each case is self-contained (builds its own synthetic kernel tree under
# a tempdir, exports the test-only plumbing env vars) and exercises a
# single behavior. This mode works on the macOS dev box because the cases
# use MODULEJAIL_MODULES_ROOT to point modulejail at a writable synthetic
# tree instead of /lib/modules.
FILTER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --filter)
            [ $# -ge 2 ] || { printf 'tests/run-fixtures.sh: --filter requires PATTERN\n' >&2; exit 64; }
            FILTER=$2
            shift 2
            ;;
        --filter=*)
            FILTER=${1#--filter=}
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf 'tests/run-fixtures.sh: unknown option: %s\n' "$1" >&2
            exit 64
            ;;
        *)
            printf 'tests/run-fixtures.sh: unexpected argument: %s\n' "$1" >&2
            exit 64
            ;;
    esac
done

if [ -n "$FILTER" ]; then
    # Glob discovery; suppress nullglob-style failure to a clear error.
    set +e
    # Globbing is intentional: the trailing *.sh expands to match case files.
    # shellcheck disable=SC2086,SC2231
    matches=$(ls tests/cases/${FILTER}*.sh 2>/dev/null)
    set -e
    if [ -z "$matches" ]; then
        printf 'tests/run-fixtures.sh: no cases matched: tests/cases/%s*.sh\n' "$FILTER" >&2
        exit 1
    fi
    printf 'modulejail tests: host-local case run (filter=%s)\n' "$FILTER"
    FAIL=0
    TOTAL=0
    for case_file in $matches; do
        TOTAL=$((TOTAL + 1))
        printf '\n-- %s --\n' "$case_file"
        if sh "$case_file"; then
            : # case prints its own [name] PASS line
        else
            FAIL=$((FAIL + 1))
        fi
    done
    if [ "$FAIL" -gt 0 ]; then
        printf '\nmodulejail tests: %d/%d case(s) FAILED.\n' "$FAIL" "$TOTAL" >&2
        exit 1
    fi
    printf '\nmodulejail tests: %d/%d case(s) PASSED.\n' "$TOTAL" "$TOTAL"
    exit 0
fi

# --- Default mode: full distro fixture matrix ----------------------------

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
