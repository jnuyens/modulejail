#!/bin/sh
# Case: man/modulejail.8.in must lint clean (no undefined macros, no
# unrecognized requests, no empty .UR/.UE blocks). Catches the class
# of bug reported in #23 (the .URL macro from www.tmac, which isn't
# loaded by default in Debian's groff pipeline, produced a lintian
# warning and the URL did not render).
#
# Renders the template by substituting __VERSION__ / __DATE__ (any
# placeholder values, since this case only checks groff syntax), then
# runs `mandoc -T lint` and greps stderr for ERROR / WARNING lines.
# Any such line fails the case.
#
# Skips with exit 77 (autoconf/TAP "skip") on hosts without mandoc.
# macOS, Debian, Rocky, and Arch all ship mandoc in their base image
# or as a tiny dependency, so the skip path is rare in CI.
set -eu

CASE_NAME=manpage-no-groff-warnings
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

if ! command -v mandoc >/dev/null 2>&1; then
    printf '[%s] SKIP (mandoc not available on host)\n' "$CASE_NAME"
    exit 77
fi

manpage_in="$REPO_ROOT/man/modulejail.8.in"
if [ ! -f "$manpage_in" ]; then
    case_fail "man/modulejail.8.in not found at $manpage_in"
fi

rendered="$CASE_TMP/modulejail.8"
sed \
    -e 's/__VERSION__/0.0.0-test/g' \
    -e 's/__DATE__/2000-01-01/g' \
    "$manpage_in" > "$rendered"

# mandoc -T lint writes diagnostics to stderr. Capture, then filter
# for ERROR / WARNING / UNSUPP lines. STYLE lines are not flagged
# (they are subjective; ERROR / WARNING are objective groff bugs).
mandoc -T lint "$rendered" > "$CASE_TMP/lint.out" 2> "$CASE_TMP/lint.err"

# All mandoc diagnostic lines look like:
#   mandoc: <file>:<line>:<col>: <LEVEL>: <message>
# Match against ERROR, WARNING, UNSUPP. STYLE and BADARG would also be
# possible but are out of scope for this gate.
filtered="$CASE_TMP/lint.filtered"
grep -E '^mandoc:.*:(ERROR|WARNING|UNSUPP):' "$CASE_TMP/lint.err" \
    > "$filtered" 2>/dev/null || true

if [ -s "$filtered" ]; then
    printf 'mandoc -T lint produced ERROR/WARNING/UNSUPP diagnostics:\n' >&2
    sed 's/^/  /' "$filtered" >&2
    case_fail "manpage has groff lint findings (see above)"
fi

case_pass
