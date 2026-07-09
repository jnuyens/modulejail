#!/bin/sh
# Shared boilerplate for host-local test cases under tests/cases/.
# Sourced (NOT executed) by each case; sets REPO_ROOT / MODULEJAIL_BIN /
# CASE_TMP, installs the centralized EXIT trap, and exports the universal
# hermetic-test env vars (MODULEJAIL_NO_UPDATE_CHECK,
# MODULEJAIL_DEFAULT_WHITELIST_FILE). Also provides the case_pass /
# case_fail helpers.
#
# Inputs (set by the case BEFORE sourcing this file):
#   CASE_NAME - short label printed in pass/fail lines.
#
# Outputs (set or exported for the modulejail invocation):
#   REPO_ROOT                       - repo root (cd'd from this script)
#   MODULEJAIL_BIN                  - absolute path to the modulejail script
#   CASE_TMP                        - tempdir root (auto-cleaned on EXIT)
#   MODULEJAIL_NO_UPDATE_CHECK=1    - suppress the post-run update check
#                                     so cases are network-hermetic.
#   MODULEJAIL_DEFAULT_WHITELIST_FILE - absent-by-default whitelist path
#                                     under CASE_TMP, isolating cases from
#                                     any /etc/modulejail/whitelist.conf
#                                     that may exist on a developer's
#                                     machine or CI runner.
#
# Synthetic kernel-module tree builder (the small representative
# universe + fake /proc/modules) MIGRATED to tests/lib/case-tree.sh per
# D-Phase6-14. Cases that want it must source case-tree.sh AFTER this
# file. v1.1.4-regression.sh builds its own 6474-entry universe inline
# and does NOT source case-tree.sh.
#
# Source order (mandatory if case-tree.sh is wanted):
#   . "$REPO_ROOT/tests/lib/case-env.sh"   # sets CASE_TMP first
#   . "$REPO_ROOT/tests/lib/case-tree.sh"  # consumes CASE_TMP
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

# Centralized EXIT trap (D-Phase6-15). The 29 existing host-local cases
# that install their own identical trap keep them as-is - POSIX trap is
# idempotent for identical handlers, so the duplicate is a no-op at
# runtime. v1.1.4-regression.sh (refactored in Plan 06-01) relies on
# this trap exclusively and does NOT install its own.
trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

MODULEJAIL_NO_UPDATE_CHECK=1
# Point the default-whitelist-file detector at a path inside $CASE_TMP that
# does not exist. This isolates cases from any /etc/modulejail/whitelist.conf
# that may exist on a developer's machine or a CI runner. Cases that want
# to exercise the default-detection path override this themselves.
MODULEJAIL_DEFAULT_WHITELIST_FILE=$CASE_TMP/default-whitelist-absent.conf
# Disable NixOS detection by default for tests, so existing tests that expect
# modprobe.d output still work on NixOS systems. NixOS-specific tests can
# override this by setting MODULEJAIL_ON_NIXOS=1.
MODULEJAIL_ON_NIXOS=0
export MODULEJAIL_NO_UPDATE_CHECK MODULEJAIL_DEFAULT_WHITELIST_FILE MODULEJAIL_ON_NIXOS

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
