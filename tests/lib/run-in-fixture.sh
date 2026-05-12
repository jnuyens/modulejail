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

printf '== [%s] (1) shellcheck --shell=sh modulejail ==\n' "$DISTRO"
shellcheck --shell=sh /usr/local/bin/modulejail

printf '== [%s] (2) --version exits 0 ==\n' "$DISTRO"
out=$(/usr/local/bin/modulejail --version)
echo "$out" | head -1 | grep -qx 'modulejail 1.0.0'

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
# Body lines must be either comments, install lines, or blank.
# grep exits 1 when count=0 (no non-matching lines found = all valid); suppress
# that exit so set -e does not fire when the file is correct.
bad=$(grep -Evc '^#|^install [a-zA-Z0-9_]+ /bin/true$|^$' /tmp/fixture-run1.conf || true)
assert_eq 0 "$bad" syntactic-validity

printf '== [%s] (9) PORT-01: no per-distro branches in modulejail ==\n' "$DISTRO"
# Assert grep finds zero per-distro branch patterns (exits 1 = no match = pass).
grep -qE '/etc/os-release|/etc/lsb-release|/etc/redhat-release|/etc/debian_version|ID_LIKE|ID=ubuntu|ID=debian|ID=rhel|ID=fedora|ID=arch|ID=alpine|ID=opensuse' /usr/local/bin/modulejail && { printf 'FAIL [%s]: per-distro branch found in modulejail\n' "$DISTRO" >&2; exit 1; } || true

printf '== [%s] (10) Header shape ==\n' "$DISTRO"
head -6 /tmp/fixture-run1.conf | sed -n '1p' | grep -qx '# modulejail 1.0.0'
head -6 /tmp/fixture-run1.conf | sed -n '5p' | grep -qE '^# fingerprint: sha256:[0-9a-f]{64}$'

printf '[%s] FIXTURE PASS\n' "$DISTRO"
