#!/bin/sh
# Case: --no-syslog-logging forces the v1.1.4 /bin/true install-line form
# regardless of whether /usr/bin/logger is present on the host
# (byte-identical regression contract).
#
# Always runs (no skip): the opt-out path must be deterministic across all
# hosts, with or without logger. The header annotation must reflect the
# /bin/true variant.
set -eu

CASE_NAME=logger-opt-out
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

OUT=$CASE_TMP/out.conf
"$MODULEJAIL_BIN" --no-syslog-logging -o "$OUT" > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr" || \
    case_fail "modulejail --no-syslog-logging exited $? (expected 0); stderr=$(cat "$CASE_TMP/stderr")"

# Header annotation MUST be the /bin/true form.
assert_grep '^# install-line: /bin/true \(silent, --no-syslog-logging or logger absent\)$' \
    "$OUT" header-true-annotation

# Header annotation MUST NOT be the logger form.
if grep -qE '^# install-line: /bin/sh \+ logger ' "$OUT"; then
    case_fail "header carries logger annotation despite --no-syslog-logging"
fi

# Every body line MUST be either a comment, a v1.1.4 /bin/true install line,
# or a blank line. No logger-form line may appear when --no-syslog-logging
# is set. grep -E exits 1 when there are no non-matching lines (good).
bad=$(grep -Evc '^#|^install [a-zA-Z0-9_-]+ /bin/true$|^$' "$OUT" || true)
assert_eq 0 "$bad" all-body-lines-are-bin-true

# Sanity: at least one /bin/true install line is present (the fixture
# blacklists ~50 dummy modules; no flag-induced filtering removes them).
assert_grep '^install [a-zA-Z0-9_-]+ /bin/true$' "$OUT" body-bin-true-present

# No logger reference anywhere in the body (defence-in-depth assertion
# against future regressions that emit both forms).
if grep -qE 'logger -t modulejail' "$OUT"; then
    case_fail "body references logger -t modulejail despite --no-syslog-logging"
fi

# Success summary on stdout.
assert_grep '^modulejail: blacklisted [0-9]+ of [0-9]+ modules' \
    "$CASE_TMP/stdout" success-summary

case_pass
