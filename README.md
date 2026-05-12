# ModuleJail

A single POSIX shell script that shrinks a Linux host's kernel-module attack
surface by writing a `modprobe.d` blacklist for every kernel module not
currently in use — minus a built-in baseline and an optional sysadmin
whitelist. No daemons, no initramfs changes, no AI inside the tool. One script,
one run, one blacklist file.

## What ModuleJail is

ModuleJail snapshots the set of currently loaded modules (`/proc/modules`) and
computes the complement against the full module tree (`/lib/modules/$(uname -r)`).
Every module in the complement — minus a built-in baseline of essential modules
and an optional sysadmin-supplied whitelist — is emitted as a `install <mod>
/bin/true` directive in a `modprobe.d`-compatible blacklist file.

The tool is aimed at Linux fleet operators who need to harden many servers
against the wave of AI-assisted kernel privilege-escalation discoveries. Every
additional loaded module is additional latent attack surface for the next
disclosed CVE. ModuleJail's model is simple: if it is not loaded today on a
steady-state host, blacklist it.

The script is portable across Debian/Ubuntu, RHEL/Rocky, Arch, Alpine, and SUSE
families. It has no runtime dependencies beyond `awk`, `grep`, `sed`, `find`,
`sha256sum`, and standard coreutils — all present in every base Linux install
including busybox.

## The safety model

The invariant is: **whatever is currently loaded is assumed necessary for the
host to function, and is preserved.** ModuleJail does not guess — it reads
`/proc/modules` at run time and treats that exact set as the keep-list.

This means the operator's responsibility is to run ModuleJail when the host is
in a known-good, steady-state configuration: after all services are started,
all kernel drivers are loaded, all filesystems are mounted. Running it on a
partial or in-flux system risks blacklisting a module that is occasionally
needed.

The generated file is placed under `/etc/modprobe.d/`. To revert, remove the
file and reboot (see the Reverting section). The built-in baseline ensures that
core filesystems, storage controllers, and essential networking modules are
never blacklisted regardless of the running profile.

## Explicit limitations

- **No initramfs handling.** Modules baked into initramfs are out of scope.
  The loaded-module surface is the target; baked-in modules are not the
  relevant attack vector.
- **No revert tooling.** The revert path is "remove the generated file and
  reboot." Sysadmin discipline replaces tool guardrails.
- **No daemon / continuous monitoring.** One-shot script by design.
- **No AI inside the tool.** AI is the threat-model backdrop, not a feature.
- **No per-distro packaging in v1.** The curl one-liner and a cloned repo are
  the distribution channels.
- **No module risk scoring.** The model is "unused implies blacklist," not
  "vulnerable implies blacklist."
- **No kernel rebuild.** Runtime blacklist only.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.0.0/modulejail | sudo sh
```

> **WARNING — convenient, not safe.** This pipes unverified bytes from the
> network to a root shell. The safer alternative below is the recommended path.

The script writes its blacklist to `/etc/modprobe.d/modulejail-blacklist.conf`
by default. To use a different path:

```sh
curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.0.0/modulejail | sudo sh -s -- -o /etc/modprobe.d/site-blacklist.conf
```

## The safer alternative

Download, inspect, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.0.0/modulejail -o /tmp/modulejail
less /tmp/modulejail
sudo sh /tmp/modulejail
```

This is the recommended path for any production deployment. The script is 420
lines of plain POSIX shell — inspection takes under ten minutes.

## Profiles

ModuleJail ships three built-in baseline profiles. The selected profile
determines which modules are always preserved regardless of loaded state.

```sh
# Profile selection via -p (default: conservative)
sudo sh modulejail -p conservative
sudo sh modulejail -p minimal
sudo sh modulejail -p desktop
```

Profile descriptions (from `--help`):

```
  minimal       Core filesystems + essential kernel modules only
  conservative  Minimal + common server/VM drivers (default)
  desktop       Conservative + WiFi, Bluetooth, audio, video drivers
```

`conservative` is the right choice for virtualised or bare-metal server Linux.
`desktop` is for laptops and workstations where WiFi, Bluetooth, audio, and
video drivers must be preserved. `minimal` is for environments where you have
full control over which drivers are loaded and want the smallest possible
baseline.

## The sysadmin whitelist

A site-local `WHITELIST` variable near the top of the script holds
space-separated module names that are always preserved — beyond the selected
baseline. It ships empty.

To use it, open the script and find the `=== SYSADMIN WHITELIST ===` section:

```sh
# === SYSADMIN WHITELIST ===
# Site-local additions to the keep-set, in addition to the selected baseline
# profile. Modules listed here will never appear in the generated blacklist.
#
# Format: space-separated module names in canonical underscore form
#         (the pipeline normalizes - to _, so either form works).
# Default: empty.
#
# Example (uncomment and adapt):
# WHITELIST='nft_compat xt_owner'
WHITELIST=''
# === END SYSADMIN WHITELIST ===
```

Edit `WHITELIST=''` to add your site-specific modules. The `===` banner anchors
are designed for Ansible template insertion (`lineinfile` or `blockinfile`).

## Exit codes

Exit codes follow `sysexits.h` conventions (see `man 3 sysexits`). Fleet
automation tools can `case $?` cleanly.

| Code | Meaning |
|------|---------|
| 0    | success |
| 64   | command-line argument error (bad flag, missing value, unknown profile) |
| 66   | required kernel input missing (`/proc/modules` or `/lib/modules/<kernel>`) |
| 70   | sanity guard tripped (empty blacklist or >99% of modules blacklisted) |
| 71   | OS-level error (mktemp work dir, or find errors on `/lib/modules`) |
| 73   | output path cannot be created (symlink/directory/trailing-slash, or mktemp failure) |
| 77   | target directory not writable (try sudo, or use `-o <other-path>`) |

## Idempotency contract

Two consecutive runs on an unchanged host produce byte-identical output files.
The generated blacklist header carries a sha256 run fingerprint — not a
wall-clock timestamp — computed over the canonical inputs: sorted loaded-module
set, sorted baseline set, sorted whitelist, profile name, and kernel version.
Because the fingerprint is a deterministic function of inputs, identical inputs
produce an identical fingerprint and thus an identical output file.

```
# fingerprint: sha256:e284ee9741eb544adf1af6c0fffc162dedd6029191673237a8155cd497908686
```

Fleet operators can use the fingerprint to correlate "what was on the host at
hardening time" across machines — two hosts with the same fingerprint had
identical loaded sets, baseline, whitelist, profile, and kernel version when
ModuleJail ran. No wall-clock drift; no spurious diffs in configuration
management systems.

## Cross-distro support

ModuleJail has been tested across two confidence tiers before the v1.0.0 tag:

### Real-kernel tier (live SSH hosts, Plans 02-03 and 02-04)

| Host | Distro | Kernel | Result |
|------|--------|--------|--------|
| ubuntu-wifi | Ubuntu 24.04.4 LTS (Noble Numbat) | 6.8.0-110-generic | PASS (6363/6474 modules blacklisted) |
| debian13 | Debian GNU/Linux 13.4 (trixie) | 6.12.74+deb13+1-amd64 | PASS (4091/4227 modules blacklisted) |
| rocky9 | Rocky Linux 9.7 (Blue Onyx) | 5.14.0-503.35.1.el9_5.x86_64 | PASS (2253/2338 modules blacklisted) |

Note for rocky9: On hosts with strict SELinux enforcement, non-root execution
may encounter a `find` permission denial on `/lib/modules/`, causing
EX_OSERR=71. This is expected documented behavior. Use `sudo` or relax the
relevant SELinux policy if this occurs.

### Fixture-container tier (synthetic kernel module trees, Plan 02-03)

| Distro | Base image | Shell | Result |
|--------|-----------|-------|--------|
| Arch Linux (latest) | `archlinux:latest` | `/bin/sh` (bash) | PASS (10/10 assertions) |
| Alpine Linux (latest) | `alpine:latest` | busybox ash | PASS (10/10 assertions) |
| openSUSE Tumbleweed | `opensuse/tumbleweed:latest` | `/bin/sh` | PASS (10/10 assertions) |

Fixture containers run against a synthetic `/lib/modules/6.99.0-fixture/` tree
with representative `.ko`, `.ko.gz`, `.ko.xz`, and `.ko.zst` files to exercise
all four suffix variants.

The `MODULEJAIL_PROC_MODULES` and `MODULEJAIL_KVER` environment variables are
test-only plumbing (analogous to `TMPDIR` or `GIT_DIR`) used by the fixture
harness to point the script at synthetic `/proc/modules` and module tree paths.
End-user operators leave these unset.

## Reverting

Remove the generated file under `/etc/modprobe.d/` and reboot, or `modprobe`
the specific modules you need back without rebooting.

```sh
# Full revert (requires reboot):
sudo rm /etc/modprobe.d/modulejail-blacklist.conf
sudo reboot

# Selective reload without reboot (bring back a specific module):
sudo modprobe <module_name>
```

The generated file uses `install <module> /bin/true` directives, which block
autoloading. Explicitly loading with `modprobe` overrides the blacklist for
the current boot session only; the restriction re-applies after the next reboot
unless the file has been removed.

## Contributing

The test matrix lives in `tests/`. Both harnesses are POSIX shell scripts
runnable by anyone with the prerequisites:

```sh
# Container fixture suite (Arch/Alpine/openSUSE):
# Requires: docker or podman; exits 77 if neither is found (graceful skip).
./tests/run-fixtures.sh

# Real-SSH-host acceptance suite (ubuntu-wifi, debian13, rocky9):
# Requires: SSH key access to the three hosts configured in the harness.
./tests/run-ssh-hosts.sh
```

`./tests/run-fixtures.sh` exits 77 on macOS or any host without a container
runtime — that is the documented graceful degradation (autoconf/TAP skip
convention). Run it on a Linux host with Docker or Podman.

Both harnesses are shellcheck-clean (`shellcheck --shell=sh`).

## License

GPL-3.0-only. See the [LICENSE](LICENSE) file for the full text.
