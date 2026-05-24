#!/bin/sh
# tests/run-fixtures.sh — modulejail test harness (host-local + containers).
#
# Invocation contract:
#
#   tests/run-fixtures.sh
#       Default mode. Discovers and runs every host-local case under
#       tests/cases/*.sh. Additionally, if docker or podman is present,
#       builds and runs the per-distro fixture containers (arch, alpine,
#       opensuse). On a host without a container runtime, the host-local
#       cases still run; a stderr banner names the missing runtime.
#
#   tests/run-fixtures.sh --filter PATTERN
#       Restrict the host-local-case run to tests/cases/PATTERN*.sh
#       (glob match). Does NOT run the container matrix. Suitable for
#       fast iteration on the dev box.
#
#   tests/run-fixtures.sh --only-container DISTRO
#       Restricts execution to a single fixture-tier container; DISTRO
#       must be one of: arch, alpine, opensuse. Builds
#       tests/fixtures/$DISTRO/Dockerfile and runs the resulting image.
#       Does NOT run the host-local case layer or the other two
#       containers. Intended for CI matrix per-axis invocation so each
#       CI job exercises exactly one axis with the same harness the
#       local dev path uses. The `=` form (--only-container=DISTRO) is
#       equivalent to the space form.
#
#   tests/run-fixtures.sh --only-host-local
#       Runs ONLY the host-local case layer (every tests/cases/*.sh
#       discovered). Does NOT attempt to build or run any container.
#       Symmetric with --only-container for the host-local CI axis.
#
#   The three flags --filter, --only-container, --only-host-local are
#   mutually exclusive; passing more than one of them together exits 64.
#
# Exit codes:
#   0   every selected case PASSED.
#   1   at least one selected case FAILED (in either layer).
#   64  bad command-line argument: --filter without PATTERN,
#       --only-container without DISTRO, --only-container DISTRO outside
#       the allowlist {arch, alpine, opensuse}, more than one of
#       --filter / --only-container / --only-host-local passed together,
#       --only-container invoked on a host with neither docker nor podman
#       in PATH, or any unknown flag.
#   77  no host-local cases discoverable at all (an impossible state in
#       this repo, but reserved as the autoconf/TAP skip convention if a
#       future operator runs against an empty tests/cases/).
#
# Pre-fix behaviour: the no-container-runtime path exited 77 without
# running anything, so the 13+ new host-local cases under tests/cases/
# (whitelist-file-*, logger-*, v1.1.4-regression, ssh-unreachable-
# regression, emit-install-line-sanitize) were silently skipped on every
# developer-laptop invocation. This file now always runs the host-local
# layer; the container matrix is additive when its runtime is present.
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
ONLY_CONTAINER=""
ONLY_HOST_LOCAL=0
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
        --only-container)
            [ $# -ge 2 ] || { printf 'tests/run-fixtures.sh: --only-container requires DISTRO\n' >&2; exit 64; }
            ONLY_CONTAINER=$2
            shift 2
            ;;
        --only-container=*)
            ONLY_CONTAINER=${1#--only-container=}
            shift
            ;;
        --only-host-local)
            ONLY_HOST_LOCAL=1
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

# --- Mutex + allowed-DISTRO validation -----------------------------------
# The three axis-selector flags (--filter, --only-container,
# --only-host-local) are mutually exclusive. Passing more than one is a
# bad-arg error (exit 64) - same convention as --filter without PATTERN.
FLAG_COUNT=0
[ -n "$FILTER" ]         && FLAG_COUNT=$((FLAG_COUNT + 1))
[ -n "$ONLY_CONTAINER" ] && FLAG_COUNT=$((FLAG_COUNT + 1))
[ "$ONLY_HOST_LOCAL" = 1 ] && FLAG_COUNT=$((FLAG_COUNT + 1))
if [ "$FLAG_COUNT" -gt 1 ]; then
    printf 'tests/run-fixtures.sh: --filter, --only-container, --only-host-local are mutually exclusive\n' >&2
    exit 64
fi

# Allowlist DISTRO so an attacker-controlled value cannot reach the
# docker invocation (T-06-07). Anything outside {arch, alpine, opensuse}
# exits 64 BEFORE the dispatch fork.
if [ -n "$ONLY_CONTAINER" ]; then
    case "$ONLY_CONTAINER" in
        arch|alpine|opensuse) ;;
        *)
            printf 'tests/run-fixtures.sh: --only-container DISTRO must be one of: arch alpine opensuse\n' >&2
            exit 64
            ;;
    esac
fi

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

# --- Optional --only-container DISTRO mode -------------------------------
# CI matrix per-axis dispatch. Builds and runs exactly ONE fixture-tier
# container (arch / alpine / opensuse). Does NOT run the host-local
# layer or the other two containers. DISTRO has already been validated
# against the allowlist {arch, alpine, opensuse} above.
if [ -n "$ONLY_CONTAINER" ]; then
    if command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    elif command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    else
        printf 'tests/run-fixtures.sh: --only-container requires docker or podman; neither found in PATH\n' >&2
        exit 64
    fi
    printf 'modulejail tests: container fixture run (only-container=%s)\n' "$ONLY_CONTAINER"
    img=modulejail-fixture-$ONLY_CONTAINER
    printf '\n== Building %s fixture ==\n' "$ONLY_CONTAINER"
    if ! "$RUNTIME" build -f "tests/fixtures/$ONLY_CONTAINER/Dockerfile" -t "$img" .; then
        printf '[only-container=%s] FAIL (build)\n' "$ONLY_CONTAINER" >&2
        exit 1
    fi
    printf '== Running %s fixture ==\n' "$ONLY_CONTAINER"
    if "$RUNTIME" run --rm "$img" sh /tests/lib/run-in-fixture.sh "$ONLY_CONTAINER"; then
        printf '[only-container=%s] PASS\n' "$ONLY_CONTAINER"
        exit 0
    fi
    printf '[only-container=%s] FAIL\n' "$ONLY_CONTAINER" >&2
    exit 1
fi

# --- Optional --only-host-local mode -------------------------------------
# CI matrix host-local-axis dispatch. Runs every tests/cases/*.sh and
# nothing else. Mirrors the host-local portion of the default-mode flow
# below; the duplication is acceptable per D-Phase6-06 ("same harness,
# axis-selected") - the contract is that the same case-discovery loop
# runs, not that there is a single shared implementation.
if [ "$ONLY_HOST_LOCAL" = 1 ]; then
    HOST_CASES=$(ls tests/cases/*.sh 2>/dev/null || true)
    if [ -z "$HOST_CASES" ]; then
        printf 'tests/run-fixtures.sh: --only-host-local: no host-local cases under tests/cases/\n' >&2
        exit 77
    fi
    printf 'modulejail tests: host-local case run (only-host-local)\n'
    FAIL=0
    TOTAL=0
    for case_file in $HOST_CASES; do
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

# --- Default mode: host-local cases + (optional) container matrix --------

# Detect container runtime up-front. Absence is no longer fatal; the
# host-local cases still run. A stderr banner names the missing runtime
# so operators reading their terminal output notice.
if command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
else
    RUNTIME=""
    printf 'modulejail tests: no container runtime found (docker/podman); running host-local cases only.\n' >&2
    printf 'modulejail tests: install colima/OrbStack on macOS, or run on a Linux host with docker/podman, to enable the container matrix.\n' >&2
fi

# Unified counters for the combined host-local + container layers.
FAIL=0
TOTAL=0

# --- Host-local layer (always runs) --------------------------------------
# Discover every tests/cases/*.sh. Each case is self-contained (builds
# its own synthetic kernel tree under a tempdir, exports test-only env
# vars) and exercises one behaviour. Runs on any host.
HOST_CASES=$(ls tests/cases/*.sh 2>/dev/null || true)
if [ -z "$HOST_CASES" ]; then
    if [ -z "$RUNTIME" ]; then
        # No container runtime AND no host-local cases means nothing
        # was actually exercised. Surface as the autoconf/TAP skip code.
        printf 'modulejail tests: no host-local cases under tests/cases/ and no container runtime; skipping.\n' >&2
        exit 77
    fi
else
    printf 'modulejail tests: running host-local cases under tests/cases/\n'
    for case_file in $HOST_CASES; do
        TOTAL=$((TOTAL + 1))
        printf '\n-- %s --\n' "$case_file"
        if sh "$case_file"; then
            : # case prints its own [name] PASS line
        else
            FAIL=$((FAIL + 1))
        fi
    done
fi

# --- Container layer (only when a runtime is present) --------------------
if [ -n "$RUNTIME" ]; then
    printf '\nmodulejail tests: using %s for container matrix\n' "$RUNTIME"
    for distro in arch alpine opensuse; do
        TOTAL=$((TOTAL + 1))
        img=modulejail-fixture-$distro
        printf '\n== Building %s fixture ==\n' "$distro"
        if ! "$RUNTIME" build -f "tests/fixtures/$distro/Dockerfile" -t "$img" .; then
            FAIL=$((FAIL+1))
            continue
        fi
        printf '== Running %s fixture ==\n' "$distro"
        if "$RUNTIME" run --rm "$img" sh /tests/lib/run-in-fixture.sh "$distro"; then
            printf '[%s] PASS\n' "$distro"
        else
            printf '[%s] FAIL\n' "$distro"
            FAIL=$((FAIL+1))
        fi
    done
fi

# --- Aggregate summary ---------------------------------------------------
if [ "$FAIL" -gt 0 ]; then
    printf '\nmodulejail tests: %d/%d case(s) FAILED.\n' "$FAIL" "$TOTAL" >&2
    exit 1
fi

printf '\nmodulejail tests: %d/%d case(s) PASSED.\n' "$TOTAL" "$TOTAL"
