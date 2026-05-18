#!/bin/sh
# Per-fixture-container assertion runner. Runs inside Arch/Alpine/openSUSE.
# Distro name passed as $1 for output labelling.
set -eu

DISTRO=${1:-unknown}
# shellcheck source=tests/lib/assert.sh
. /tests/lib/assert.sh

# Generate the synthetic kernel tree + fake /proc/modules.
sh /tests/lib/gen-fixture.sh

export MODULEJAIL_PROC_MODULES=/tmp/proc-modules
export MODULEJAIL_KVER=6.99.0-fixture
# Suppress the post-run update check by default so steady-state fixture
# runs are hermetic (no network calls). Specific update-check assertions
# below toggle this variable explicitly.
export MODULEJAIL_NO_UPDATE_CHECK=1
# Point the default-whitelist-file detector at a path that does not exist
# inside the container, so fixture runs are isolated from any
# /etc/modulejail/whitelist.conf that might be baked into a base image.
export MODULEJAIL_DEFAULT_WHITELIST_FILE=/tmp/default-whitelist-absent.conf

# Version-agnostic SemVer regex. The v1.0.0 fixture hardcoded the literal
# string "1.0.0", which broke every fixture run after the first version
# bump. This pattern matches any X.Y.Z, future-proofing across bumps.
SEMVER_RE='[0-9]+\.[0-9]+\.[0-9]+'

printf '== [%s] (1) shellcheck --shell=sh modulejail ==\n' "$DISTRO"
shellcheck --shell=sh /usr/local/bin/modulejail

printf '== [%s] (2) --version exits 0 with valid SemVer ==\n' "$DISTRO"
out=$(/usr/local/bin/modulejail --version)
echo "$out" | head -1 | grep -qE "^modulejail $SEMVER_RE$"

printf '== [%s] (3) --help exits 0 ==\n' "$DISTRO"
/usr/local/bin/modulejail --help > /dev/null

printf '== [%s] (4) bad flag -> EX_USAGE=64 ==\n' "$DISTRO"
set +e
/usr/local/bin/modulejail --nonexistent-flag 2>/dev/null
rc=$?
set -e
assert_eq 64 "$rc" EX_USAGE

printf '== [%s] (5) missing MODULEJAIL_PROC_MODULES -> EX_NOINPUT=66 ==\n' "$DISTRO"
set +e
MODULEJAIL_PROC_MODULES=/nonexistent/path /usr/local/bin/modulejail -o /tmp/x.conf 2>/dev/null
rc=$?
set -e
assert_eq 66 "$rc" EX_NOINPUT

printf '== [%s] (6) successful run -> exits 0, prints success line ==\n' "$DISTRO"
out=$(/usr/local/bin/modulejail -o /tmp/fixture-run1.conf)
echo "$out" | grep -qE '^modulejail: blacklisted [0-9]+ of [0-9]+ modules \(profile=conservative\) -> /tmp/fixture-run1\.conf$'

printf '== [%s] (7) idempotency: two runs byte-identical ==\n' "$DISTRO"
/usr/local/bin/modulejail -o /tmp/fixture-run2.conf > /dev/null
assert_cmp /tmp/fixture-run1.conf /tmp/fixture-run2.conf

printf '== [%s] (8) output is syntactically valid modprobe.d ==\n' "$DISTRO"
# Body lines must be either comments, install lines, or blank. Two install-line
# forms are valid as of Plan 03-02:
#   v1.1.4 form:  install <name> /bin/true
#   logger form:  install <name> /bin/sh -c '/usr/bin/logger -t modulejail "blocked: <name>" 2>/dev/null; exit 0'
# grep exits 1 when count=0 (no non-matching lines found = all valid); suppress
# that exit so set -e does not fire when the file is correct.
bad=$(grep -Evc '^#|^install [a-zA-Z0-9_]+ /bin/true$|^install [a-zA-Z0-9_]+ /bin/sh -c .*logger -t modulejail.*; exit 0.*$|^$' /tmp/fixture-run1.conf || true)
assert_eq 0 "$bad" syntactic-validity

printf '== [%s] (9) PORT-01: no per-distro branches in modulejail ==\n' "$DISTRO"
# Assert grep finds zero per-distro branch patterns (exits 1 = no match = pass).
grep -qE '/etc/os-release|/etc/lsb-release|/etc/redhat-release|/etc/debian_version|ID_LIKE|ID=ubuntu|ID=debian|ID=rhel|ID=fedora|ID=arch|ID=alpine|ID=opensuse' /usr/local/bin/modulejail && { printf 'FAIL [%s]: per-distro branch found in modulejail\n' "$DISTRO" >&2; exit 1; } || true

printf '== [%s] (10) Header shape (version-agnostic) ==\n' "$DISTRO"
head -6 /tmp/fixture-run1.conf | sed -n '1p' | grep -qE "^# modulejail $SEMVER_RE$"
head -6 /tmp/fixture-run1.conf | sed -n '5p' | grep -qE '^# fingerprint: sha256:[0-9a-f]{64}$'

printf '== [%s] (11) --help documents MODULEJAIL_NO_UPDATE_CHECK ==\n' "$DISTRO"
/usr/local/bin/modulejail --help | grep -q 'MODULEJAIL_NO_UPDATE_CHECK'

printf '== [%s] (12) update check: NO_UPDATE_CHECK=1 -> no stderr notice ==\n' "$DISTRO"
# Capture stderr separately; success line is on stdout, notices on stderr.
err=$(MODULEJAIL_NO_UPDATE_CHECK=1 /usr/local/bin/modulejail -o /tmp/fixture-noup.conf 2>&1 >/dev/null)
case "$err" in
    *"notice:"*) printf 'FAIL [%s]: NO_UPDATE_CHECK=1 still produced notice on stderr\n' "$DISTRO" >&2; exit 1 ;;
esac

printf '== [%s] (13) update check: unreachable URL -> silent (graceful failure) ==\n' "$DISTRO"
# Unset the suppressor and point at an unroutable URL. The 10-second
# timeout caps the wait; the function must still return 0 with no notice.
err=$(unset MODULEJAIL_NO_UPDATE_CHECK; \
      MODULEJAIL_UPDATE_URL=https://bogus.invalid.example.com/x \
      /usr/local/bin/modulejail -o /tmp/fixture-unreach.conf 2>&1 >/dev/null)
case "$err" in
    *"notice:"*) printf 'FAIL [%s]: unreachable URL produced notice on stderr\n' "$DISTRO" >&2; exit 1 ;;
esac

printf '== [%s] (14) regression guard: wget call uses busybox-compatible flags ==\n' "$DISTRO"
# Static source check. busybox wget (Alpine) rejects --max-redirect,
# --output-document, and --quiet long forms. v1.1.2 used these and the
# update check was a silent no-op on every Alpine host. v1.1.3 switched
# to the short-flag subset (-q -T -O). If a future edit reintroduces a
# long form, this assertion catches it without needing network.
wget_line=$(grep -E '^[[:space:]]*body=\$\(wget' /usr/local/bin/modulejail || true)
[ -n "$wget_line" ] || { printf 'FAIL [%s]: could not find wget invocation in script\n' "$DISTRO" >&2; exit 1; }
case "$wget_line" in
    *--max-redirect*|*--output-document*|*--quiet*)
        printf 'FAIL [%s]: wget invocation uses busybox-incompatible long flags:\n  %s\n' "$DISTRO" "$wget_line" >&2
        exit 1
        ;;
esac

printf '[%s] FIXTURE PASS (14/14 assertions)\n' "$DISTRO"
