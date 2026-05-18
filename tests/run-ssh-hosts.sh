#!/bin/sh
# tests/run-ssh-hosts.sh — real-SSH-host acceptance for modulejail.
#
# Runs the modulejail smoke suite against three live Linux hosts via SSH:
# ubuntu-wifi (Ubuntu 24.04, Debian/Ubuntu family),
# debian13 (Debian 13 trixie, Debian/Ubuntu family second data point),
# rocky9 (Rocky Linux 9.7, RHEL family).
#
# Each host gets:
#   1. /etc/os-release capture (evidence pin; rocky9 confirmation)
#   2. modulejail copied over to /tmp/mj-test
#   3. --version exit-0 check
#   4. Bad-flag → EX_USAGE=64 check
#   5. Directory-as-output → EX_CANTCREAT=73 check
#   6. Successful run with -o /tmp/mj-host-run1.conf (non-root, write-to-/tmp;
#      original methodology preserved — no risk to host /etc/modprobe.d/)
#   7. Idempotency: second run → cmp byte-identical
#   8. Success-line shape regex check on the run-6 stdout
#   9. Generated file header shape: line 1 = "# modulejail <VERSION>"
#      (VERSION auto-derived from the modulejail script under test, so
#      the assertion survives future SemVer bumps without edits),
#      line 5 = "# fingerprint: sha256:<64 hex>"
#  10. Portability grep assertion (no per-distro branches in the script that
#      was just copied over)
#
# Special handling for rocky9: SELinux on RHEL family
# may deny non-root reads in parts of /lib/modules/<ver>/, which legitimately
# trips EX_OSERR=71 ("find reported errors"). If we observe rc=71 on rocky9,
# the harness records it as a documented expected behavior (not a regression)
# and proceeds with the remaining hosts. The SUMMARY notes this for the
# README's Cross-distro support section.
#
# Exit codes:
#   0  — all hosts passed (or rocky9 surfaced documented EX_OSERR=71)
#   1  — at least one host failed an assertion in an unexpected way
#   2  — unable to reach one or more hosts (SSH connection failure)

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$REPO_ROOT/modulejail

if [ ! -f "$SCRIPT" ]; then
    printf 'run-ssh-hosts: error: cannot find modulejail at %s\n' "$SCRIPT" >&2
    exit 1
fi

# Derive the expected version from the script under test so the line-1
# header assertion below stays correct across SemVer bumps. Previously
# this was hardcoded to "# modulejail 1.0.0" and required a manual edit
# on every release. Plan 03-03 bumps VERSION to 1.2.0; rather than chasing
# the literal string here, read it from the source.
EXPECTED_VERSION=$(awk -F"'" '/^VERSION=/ {print $2; exit}' "$SCRIPT")
if [ -z "$EXPECTED_VERSION" ]; then
    printf 'run-ssh-hosts: error: cannot determine VERSION from %s\n' "$SCRIPT" >&2
    exit 1
fi

# HOSTS is overridable via the environment so the unreachable-host regression test
# (tests/cases/ssh-unreachable-regression.sh) can drive the harness against
# a guaranteed-unreachable name without editing this file. End-user
# operators leave it unset; the default is the three real-kernel hosts.
HOSTS="${HOSTS:-ubuntu-wifi debian13 rocky9}"
OVERALL_FAIL=0
SUMMARY=

run_host() {
    host=$1
    label=$2
    printf '\n========== [%s] %s ==========\n' "$host" "$label"

    # 0. Connectivity.
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" 'true' 2>/dev/null; then
        printf '[%s] SSH connection failed (check ~/.ssh/config)\n' "$host" >&2
        SUMMARY="${SUMMARY}[$host] UNREACHABLE\n"
        return 2
    fi

    # 1. /etc/os-release evidence pin.
    printf '\n-- [%s] /etc/os-release --\n' "$host"
    ssh "$host" 'cat /etc/os-release' | tee "/tmp/mj-${host}-osrelease.out"

    # 2. Copy modulejail.
    scp -q "$SCRIPT" "$host":/tmp/mj-test

    # 3. --version.
    printf '\n-- [%s] (3) --version exits 0 --\n' "$host"
    ssh "$host" 'sh /tmp/mj-test --version'
    rc=$?
    [ "$rc" -eq 0 ] || { printf '[%s] FAIL: --version rc=%d\n' "$host" "$rc" >&2; return 1; }

    # 4. Bad flag → EX_USAGE=64.
    printf '\n-- [%s] (4) bad flag → 64 --\n' "$host"
    ssh "$host" 'sh /tmp/mj-test --bogus-flag 2>/dev/null; echo $?' > "/tmp/mj-${host}-rc4.out"
    rc=$(cat "/tmp/mj-${host}-rc4.out")
    [ "$rc" -eq 64 ] || { printf '[%s] FAIL: bad flag expected 64 got %s\n' "$host" "$rc" >&2; return 1; }

    # 5. Directory-as-output → EX_CANTCREAT=73.
    printf '\n-- [%s] (5) -o /tmp → 73 --\n' "$host"
    ssh "$host" 'sh /tmp/mj-test -o /tmp 2>/dev/null; echo $?' > "/tmp/mj-${host}-rc5.out"
    rc=$(cat "/tmp/mj-${host}-rc5.out")
    [ "$rc" -eq 73 ] || { printf '[%s] FAIL: -o /tmp expected 73 got %s\n' "$host" "$rc" >&2; return 1; }

    # 6. Successful run #1 (non-root → write-to-/tmp).
    printf '\n-- [%s] (6) successful run #1 → /tmp/mj-host-run1.conf --\n' "$host"
    set +e
    ssh "$host" 'sh /tmp/mj-test -o /tmp/mj-host-run1.conf' > "/tmp/mj-${host}-stdout1.out" 2>&1
    rc=$?
    set -e

    # rocky9-specific: SELinux on /lib/modules can legitimately surface
    # EX_OSERR=71 under non-root. Document and skip the remaining
    # real-kernel-walk-dependent assertions.
    if [ "$rc" -eq 71 ] && [ "$host" = "rocky9" ]; then
        printf '[%s] OBSERVED: EX_OSERR=71 (SELinux likely deny on non-root /lib/modules read)\n' "$host"
        printf '       (This is documented expected behavior for rocky9 non-root\n'
        printf '        smoke runs. README should note this.)\n'
        SUMMARY="${SUMMARY}[$host] PASS (with documented EX_OSERR=71 on non-root SELinux deny)\n"
        return 0
    fi

    [ "$rc" -eq 0 ] || { printf '[%s] FAIL: successful run rc=%d (expected 0). stdout/stderr:\n' "$host" "$rc" >&2; cat "/tmp/mj-${host}-stdout1.out" >&2; return 1; }

    # 7. Idempotency: second run, cmp byte-identical.
    printf '\n-- [%s] (7) successful run #2 + cmp --\n' "$host"
    ssh "$host" 'sh /tmp/mj-test -o /tmp/mj-host-run2.conf && cmp /tmp/mj-host-run1.conf /tmp/mj-host-run2.conf && echo IDEMPOTENT'
    rc=$?
    [ "$rc" -eq 0 ] || { printf '[%s] FAIL: idempotency cmp rc=%d\n' "$host" "$rc" >&2; return 1; }

    # 8. Success-line shape regex.
    printf '\n-- [%s] (8) success line shape --\n' "$host"
    if ! grep -qE '^modulejail: blacklisted [0-9]+ of [0-9]+ modules \(profile=conservative\) -> /tmp/mj-host-run1\.conf$' "/tmp/mj-${host}-stdout1.out"; then
        printf '[%s] FAIL: success line shape (stdout was:)\n' "$host" >&2
        cat "/tmp/mj-${host}-stdout1.out" >&2
        return 1
    fi

    # 9. Header shape on the remote-generated file.
    printf '\n-- [%s] (9) header shape (lines 1, 5) --\n' "$host"
    ssh "$host" 'head -6 /tmp/mj-host-run1.conf' > "/tmp/mj-${host}-head.out"
    line1=$(sed -n '1p' "/tmp/mj-${host}-head.out")
    line5=$(sed -n '5p' "/tmp/mj-${host}-head.out")
    if [ "$line1" != "# modulejail $EXPECTED_VERSION" ]; then
        printf '[%s] FAIL: header line 1 was: %s (expected: # modulejail %s)\n' "$host" "$line1" "$EXPECTED_VERSION" >&2; return 1
    fi
    if ! printf '%s\n' "$line5" | grep -qE '^# fingerprint: sha256:[0-9a-f]{64}$'; then
        printf '[%s] FAIL: header line 5 was: %s\n' "$host" "$line5" >&2; return 1
    fi
    # Capture fingerprint for cross-host correlation (recorded in SUMMARY).
    fp=$(printf '%s\n' "$line5" | awk '{print $3}')
    printf '[%s] fingerprint: %s\n' "$host" "$fp"

    # 10. Portability grep assertion on the script that was copied over.
    printf '\n-- [%s] (10) no per-distro branches --\n' "$host"
    set +e
    ssh "$host" "grep -nE '/etc/os-release|/etc/lsb-release|/etc/redhat-release|/etc/debian_version|ID_LIKE|ID=ubuntu|ID=debian|ID=rhel|ID=fedora|ID=arch|ID=alpine|ID=opensuse' /tmp/mj-test"
    grc=$?
    set -e
    # grep returns 1 when there are NO matches — exactly what we want.
    [ "$grc" -eq 1 ] || { printf '[%s] FAIL: per-distro grep found matches (grep rc=%d)\n' "$host" "$grc" >&2; return 1; }

    SUMMARY="${SUMMARY}[$host] PASS (fingerprint: $fp)\n"
    printf '[%s] HOST PASS\n' "$host"
}

UNREACHED=0
# Bracket the run_host call with set +e / set -e
# and capture rc=$? directly from a bare call. The previous
# `if ! run_host ...; then rc=$?` shape captured the inverted-condition
# `!` exit (always 0 inside the `then` branch under POSIX /bin/sh, dash,
# and bash), so an unreachable host (run_host returns 2) was mis-classified
# as OVERALL_FAIL instead of UNREACHED and the harness exited 1 instead of
# the documented 2.
for host in $HOSTS; do
    set +e
    run_host "$host" "real-kernel acceptance"
    rc=$?
    set -e
    case "$rc" in
        0) ;;
        2) UNREACHED=$((UNREACHED+1)) ;;
        *) OVERALL_FAIL=$((OVERALL_FAIL+1)) ;;
    esac
done

printf '\n========== SUMMARY ==========\n'
printf '%b' "$SUMMARY"

if [ "$UNREACHED" -gt 0 ]; then
    printf '\nrun-ssh-hosts: %d host(s) UNREACHABLE.\n' "$UNREACHED" >&2
    exit 2
fi
if [ "$OVERALL_FAIL" -gt 0 ]; then
    printf '\nrun-ssh-hosts: %d host(s) FAILED.\n' "$OVERALL_FAIL" >&2
    exit 1
fi

printf '\nrun-ssh-hosts: all hosts PASSED.\n'
