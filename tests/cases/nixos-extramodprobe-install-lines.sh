#!/bin/sh
# Case: On NixOS, the generated file emits boot.extraModprobeConfig with
# the standard logger install lines alongside boot.blacklistedKernelModules.
# This is the option-A enforcement-parity fix: blacklist-only would block
# alias-resolution autoload, but explicit modprobe and direct-name
# request_module() would still load the module. The install lines close
# both gaps and produce a syslog event tagged "modulejail" on each blocked
# load attempt.
set -eu

CASE_NAME=nixos-extramodprobe-install-lines
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/case-tree.sh disable=SC1091
. "$REPO_ROOT/tests/lib/case-tree.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

# Force NixOS mode + pin the logger path so the test's assertions are
# stable across hosts (the script defaults to /run/current-system/sw/bin/logger
# but lets MODULEJAIL_LOGGER_PATH override it - the script reads MODULEJAIL_LOGGER_PATH
# at startup into $NIXOS_LOGGER_PATH, which is what gets baked into install lines).
export MODULEJAIL_ON_NIXOS=1
export MODULEJAIL_LOGGER_PATH=/run/current-system/sw/bin/logger
export MODULEJAIL_MODULES_ROOT="$CASE_MODULES_ROOT"

OUT=$CASE_TMP/test-output.nix
"$MODULEJAIL_BIN" --dry-run -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# --- extraModprobeConfig section present ---
assert_grep 'boot\.extraModprobeConfig = ' \
    "$CASE_TMP/stderr" extramodprobe-attr-opening

# --- Install lines indented inside the Nix '' multi-line string ---
# Format: 4 spaces + install <name> + /bin/sh wrapper + logger + tag
assert_grep '    install dummy_1 /bin/sh -c ' \
    "$CASE_TMP/stderr" install-line-dummy_1
assert_grep '    install dummy_2 /bin/sh -c ' \
    "$CASE_TMP/stderr" install-line-dummy_2
assert_grep '    install sctp /bin/sh -c ' \
    "$CASE_TMP/stderr" install-line-sctp

# --- NixOS-specific logger path baked into the install line ---
assert_grep '/run/current-system/sw/bin/logger -t modulejail "blocked: dummy_1"' \
    "$CASE_TMP/stderr" install-line-logger-path-and-tag

# --- Install lines end with `; exit 0` (silent success on logger absence) ---
assert_grep '2>/dev/null; exit 0' \
    "$CASE_TMP/stderr" install-line-exit-zero

# --- Header now documents the logger path ---
assert_grep '^# Logger: /run/current-system/sw/bin/logger$' \
    "$CASE_TMP/stderr" header-logger-line

# --- boot.blacklistedKernelModules is still emitted (kept alongside) ---
assert_grep 'boot\.blacklistedKernelModules = \[' \
    "$CASE_TMP/stderr" blacklist-section-still-present
assert_grep '^  "dummy_1"' \
    "$CASE_TMP/stderr" blacklist-still-lists-modules

# --- nix-instantiate parses the result (only when nix-instantiate is available) ---
if command -v nix-instantiate >/dev/null 2>&1; then
    if ! nix-instantiate --parse "$CASE_TMP/stderr" > /dev/null 2> "$CASE_TMP/nix.err"; then
        case_fail "nix-instantiate --parse rejected the output: $(cat "$CASE_TMP/nix.err")"
    fi
fi

case_pass
