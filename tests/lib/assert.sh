#!/bin/sh
# POSIX shell assertion helpers. Sourced by tests/lib/run-in-fixture.sh.
# No bashisms; runs under busybox ash inside the Alpine fixture.

# assert_exit EXPECTED CMD [ARGS...]
#   Run CMD ARGS, capture exit code, assert it equals EXPECTED.
assert_exit() {
    expected=$1; shift
    "$@" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ne "$expected" ]; then
        printf 'assert_exit FAIL: expected %d got %d for: %s\n' "$expected" "$rc" "$*" >&2
        return 1
    fi
}

# assert_grep PATTERN FILE [DESCRIPTION]
assert_grep() {
    pat=$1; file=$2; desc=${3:-grep}
    if ! grep -qE "$pat" "$file"; then
        printf 'assert_grep FAIL [%s]: pattern not found: %s in %s\n' "$desc" "$pat" "$file" >&2
        return 1
    fi
}

# assert_cmp A B
assert_cmp() {
    if ! cmp -s "$1" "$2"; then
        printf 'assert_cmp FAIL: %s != %s\n' "$1" "$2" >&2
        return 1
    fi
}

# assert_eq EXPECTED ACTUAL [DESCRIPTION]
assert_eq() {
    if [ "$1" != "$2" ]; then
        printf 'assert_eq FAIL [%s]: expected %s got %s\n' "${3:-eq}" "$1" "$2" >&2
        return 1
    fi
}
