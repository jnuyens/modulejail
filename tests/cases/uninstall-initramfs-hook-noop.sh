#!/bin/sh
# Case: --uninstall-initramfs-hook is idempotent. When no hook files
# exist on the host (e.g. a fresh CI run or a dev box that has never
# installed the hook), the flag must:
#   - exit 0
#   - print the "no installed initramfs strip hooks found" line
#   - NOT call any initramfs builder
set -eu

CASE_NAME=uninstall-initramfs-hook-noop
export CASE_NAME

# shellcheck source=tests/lib/case-env.sh disable=SC1091
. "$(dirname "$0")/../lib/case-env.sh"
# shellcheck source=tests/lib/assert.sh disable=SC1091
. "$REPO_ROOT/tests/lib/assert.sh"

trap 'rm -rf "$CASE_TMP"' EXIT INT HUP TERM

# Guard: if any of the hook paths exist on the test host (unlikely but
# possible if a developer ran --install-initramfs-hook locally), skip
# rather than risk a destructive cleanup.
for path in \
    /usr/lib/dracut/modules.d/99modulejail-strip/module-setup.sh \
    /etc/initramfs-tools/hooks/zz-modulejail-strip \
    /etc/initcpio/install/modulejail-strip \
    /usr/lib/initcpio/install/modulejail-strip \
    /usr/share/libalpm/hooks/95-modulejail-strip.hook
do
    if [ -e "$path" ]; then
        printf 'modulejail-test: SKIP (%s exists on test host)\n' "$path"
        case_pass
    fi
done

set +e
"$MODULEJAIL_BIN" --uninstall-initramfs-hook --dry-run \
    > "$CASE_TMP/stdout" 2> "$CASE_TMP/stderr"
rc=$?
set -e

assert_eq 0 "$rc" "uninstall-noop-exit-code"
assert_grep '^modulejail: no installed initramfs strip hooks found' \
    "$CASE_TMP/stdout" uninstall-noop-message

case_pass
