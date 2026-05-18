#!/bin/sh
# Case: regression — SSH-host harness exit-code routing.
#
# Drives tests/run-ssh-hosts.sh against a guaranteed-unreachable host
# (the RFC 2606 `.invalid` TLD, which DNS resolvers MUST reject) and
# asserts the harness exits 2 ("unable to reach one or more hosts"),
# NOT exit 1 ("at least one host failed").
#
# Pre-fix, the harness's host loop used:
#     if ! run_host "$host" "$label"; then
#         rc=$?
#         if [ "$rc" -eq 2 ]; then UNREACHED=$((UNREACHED+1))
#         else                      OVERALL_FAIL=$((OVERALL_FAIL+1))
#         fi
#     fi
# Under POSIX /bin/sh, dash, and bash the `$?` inside `if ! cmd; then`
# is always 0 (the inverted-condition `!` consumes the inner return
# code), so the rc=2 branch was dead and the harness misreported
# every unreachable host as OVERALL_FAIL. The fix:
#     set +e
#     run_host "$host" "real-kernel acceptance"
#     rc=$?
#     set -e
#     case "$rc" in
#         0) ;;
#         2) UNREACHED=$((UNREACHED+1)) ;;
#         *) OVERALL_FAIL=$((OVERALL_FAIL+1)) ;;
#     esac
# captures the real return code and routes correctly.
#
# Mutation-test recipe for a future reviewer who wants to confirm this
# case actually guards the fix (not just runs):
#     git log -1 --pretty=%H tests/run-ssh-hosts.sh   # remember the SHA
#     git stash push -- tests/run-ssh-hosts.sh         # but the fix is
#         # already committed, so use revert instead:
#     git revert --no-commit <fix-commit-sha>
#     sh tests/cases/ssh-unreachable-regression.sh    # expect FAIL
#     git restore --source=HEAD --staged --worktree tests/run-ssh-hosts.sh
#     sh tests/cases/ssh-unreachable-regression.sh    # expect PASS
#
# Hermeticity contract:
# - No real SSH server is contacted (the `.invalid` TLD never resolves).
# - No ~/.ssh/config dependency (BatchMode=yes + ConnectTimeout=10 in
#   the harness already cap wall-clock and refuse password prompts).
# - No sudo requirement.
# - Total wall-clock under ~20s on macOS (one host * 10s timeout cap;
#   in practice DNS-NXDOMAIN returns in milliseconds).
set -eu

CASE_NAME=ssh-unreachable-regression
export CASE_NAME

# Locate repo root relative to this script (open-coded, since this case
# shells out to run-ssh-hosts.sh rather than using case-env.sh's
# synthetic kernel tree).
case "${0:-}" in
    /*) CASE_SCRIPT=$0 ;;
    *)  CASE_SCRIPT=$(pwd)/$0 ;;
esac
CASE_DIR=$(cd "$(dirname "$CASE_SCRIPT")" && pwd)
REPO_ROOT=$(cd "$CASE_DIR/../.." && pwd)
HARNESS=$REPO_ROOT/tests/run-ssh-hosts.sh
if [ ! -f "$HARNESS" ]; then
    printf '[%s] FAIL: missing harness: %s\n' "$CASE_NAME" "$HARNESS" >&2
    exit 1
fi

CASE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/modulejail-ssh-unreachable.XXXXXX")
trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Drive the harness against one synthetic unreachable host. The
# `.invalid` TLD is reserved by RFC 2606 and guaranteed non-resolving;
# DNS-NXDOMAIN returns fast, so the ConnectTimeout=10 cap inside the
# harness is the only thing that could stretch wall-clock and it almost
# never fires for `.invalid`.
HARNESS_STDOUT=$CASE_TMP/harness.stdout
HARNESS_STDERR=$CASE_TMP/harness.stderr
set +e
HOSTS=unreachable-modulejail-test-host.invalid \
    sh "$HARNESS" > "$HARNESS_STDOUT" 2> "$HARNESS_STDERR"
HARNESS_RC=$?
set -e

# Assertion 1: the harness must exit 2 ("unable to reach one or more
# hosts"), NOT 1 ("at least one host failed"). Pre-fix this was 1.
if [ "$HARNESS_RC" -ne 2 ]; then
    printf '[%s] FAIL: harness exited %d, expected 2 (UNREACHED)\n' \
        "$CASE_NAME" "$HARNESS_RC" >&2
    printf '  stdout:\n' >&2
    sed 's/^/    /' < "$HARNESS_STDOUT" >&2
    printf '  stderr:\n' >&2
    sed 's/^/    /' < "$HARNESS_STDERR" >&2
    exit 1
fi

# Assertion 2: the SUMMARY block must contain the literal "UNREACHABLE"
# token for the unreachable host. The harness writes this to stdout
# (the SUMMARY block) and an "N host(s) UNREACHABLE." line to stderr.
# Search both, accept a match in either.
if ! grep -qE 'UNREACHABLE' "$HARNESS_STDOUT" && ! grep -qE 'UNREACHABLE' "$HARNESS_STDERR"; then
    printf '[%s] FAIL: no UNREACHABLE token found in harness output\n' \
        "$CASE_NAME" >&2
    printf '  stdout:\n' >&2
    sed 's/^/    /' < "$HARNESS_STDOUT" >&2
    printf '  stderr:\n' >&2
    sed 's/^/    /' < "$HARNESS_STDERR" >&2
    exit 1
fi

printf '[%s] PASS\n' "$CASE_NAME"
exit 0
