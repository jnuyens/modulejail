#!/bin/sh
# Case: with /usr/bin/logger present on the host AND no --no-syslog-logging
# flag, modulejail emits the D-36 syslog-logging install-line form and the
# matching header annotation (D-38).
#
# Skip (not fail) when /usr/bin/logger is absent on the running host: this
# case asserts the positive default-on path, which is only exercisable when
# logger is actually executable. The complementary logger-absent-fallback.sh
# case covers the negative path via MODULEJAIL_LOGGER_PATH override.
set -eu

CASE_NAME=logger-default-on
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Skip-not-fail when the host has no logger. macOS dev box (Darwin) ships
# /usr/bin/logger; Linux distros with util-linux or bsdmainutils ship it
# too. Minimal containers or unusual hosts may not - skip gracefully.
if [ ! -x /usr/bin/logger ]; then
    printf '[%s] SKIP: /usr/bin/logger not executable on this host\n' "$CASE_NAME"
    exit 0
fi

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header annotation MUST be the logger form.
assert_grep '^# install-line: /bin/sh \+ logger \(syslog tag: modulejail\)$' \
    "$OUT" header-logger-annotation

# Header annotation MUST NOT be the /bin/true form.
if grep -qE '^# install-line: /bin/true ' "$OUT"; then
    case_fail "header carries /bin/true annotation but default-on logger path was expected"
fi

# Body MUST carry at least one D-36-form install line. Pattern:
#   install <name> /bin/sh -c '/usr/bin/logger -t modulejail "blocked: <name>" 2>/dev/null; exit 0'
assert_grep "^install [a-zA-Z0-9_-]+ /bin/sh -c '/usr/bin/logger -t modulejail \"blocked: [a-zA-Z0-9_-]+\" 2>/dev/null; exit 0'\$" \
    "$OUT" body-logger-form

# Body MUST NOT carry any v1.1.4 /bin/true install lines under default-on.
if grep -qE '^install [a-zA-Z0-9_-]+ /bin/true$' "$OUT"; then
    case_fail "body contains v1.1.4 /bin/true install lines but default-on logger path was expected"
fi

# Success summary on stdout.
assert_grep '^modulejail: blacklisted [0-9]+ of [0-9]+ modules' \
    "$CASE_TMP/stdout" success-summary

case_pass
