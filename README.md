<p align="center">
  <img src="modulejail.png" alt="ModuleJail: lock down unused kernel modules. Reduce risk. Stay secure." width="480">
</p>

A single POSIX shell script that shrinks a Linux host's kernel-module attack
surface by writing a `modprobe.d` blacklist for every kernel module not
currently in use, minus a built-in baseline and an optional sysadmin
whitelist. No daemons, no initramfs changes, no AI inside the tool. One
script, one run, one blacklist file.

## Why?

AI-assisted security scanning is about to do to the Linux kernel what
large-scale fuzzing did to userspace code a decade ago, only faster and at a
much larger scale. Many years of latent privilege-escalation bugs in kernel
modules are about to surface in quick succession over the coming weeks and
months. Long term, this is a major win for kernel security: every disclosure
closes a door that an attacker could otherwise have walked through unseen.
Short term, it is a nightmare for sysadmins. Every public release brings
another race against patch cycles, vendor backports, and reboots across
thousands of hosts.

ModuleJail does not try to fix kernel bugs, and it cannot. It does the one
thing a sysadmin can do today, on any host, in seconds: shrink the attack
surface so that the next disclosed bug is more likely to land on a module the
host is not even loading. A typical Linux host ships with several thousand
kernel modules and uses a few hundred. ModuleJail blacklists the rest. The
next CVE in the unused 90% becomes a non-event on that host, and the fleet
operator buys time to schedule the patch on their own terms instead of
emergency-paging at 03:00.

This is intentionally a boring tool. No AI inside it, no daemon, no
continuous monitoring, no risk scoring, no CVE database lookups. Just one
shell script, run once on a steady-state host, that writes
`/etc/modprobe.d/modulejail-blacklist.conf` to blacklist the thousands of
unused modules, specific to your system.

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.2.4/modulejail | sudo sh
```

> **WARNING: convenient, not safe.** This pipes unverified bytes from the
> network to a root shell. The safer alternative below is the recommended path.

> [!TIP]
> **On a laptop or workstation? Add `-p desktop`.**
>
> The default profile is `conservative` (servers and VMs). It does NOT
> include WiFi, Bluetooth, audio, or video drivers in the baseline, so
> if any of those happen not to be loaded at run time (WiFi disconnected,
> Bluetooth off, headset unplugged, etc.), they may end up blacklisted
> and unavailable on the next boot. The `desktop` profile keeps them in
> the keep-list unconditionally.
>
> ```sh
> curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.2.4/modulejail | sudo sh -s -- -p desktop
> ```
>
> See [Profiles](#profiles) below for the full list.

The script writes its blacklist to `/etc/modprobe.d/modulejail-blacklist.conf`
by default. To use a different path:

```sh
curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.2.4/modulejail | sudo sh -s -- -o /etc/modprobe.d/site-blacklist.conf
```

## The safer alternative

Download, inspect, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/jnuyens/modulejail/v1.2.4/modulejail -o /tmp/modulejail
less /tmp/modulejail
sudo sh /tmp/modulejail
```

This is the recommended path for any production deployment. The script is
plain POSIX shell and inspection takes under ten minutes.

## Native packages (.deb / .rpm / AUR)

For Debian/Ubuntu and RHEL/Fedora/Rocky hosts, prebuilt packages are attached
to the GitHub release page:

```sh
# Debian / Ubuntu:
curl -fsSLO https://github.com/jnuyens/modulejail/releases/download/v1.2.4/modulejail_1.2.4_all.deb
sudo dpkg -i modulejail_1.2.4_all.deb

# RHEL / Fedora / Rocky:
curl -fsSLO https://github.com/jnuyens/modulejail/releases/download/v1.2.4/modulejail-1.2.4-1.noarch.rpm
sudo rpm -i modulejail-1.2.4-1.noarch.rpm
```

For Arch Linux and derivatives (Manjaro, EndeavourOS, ...), modulejail is
in the AUR:

```sh
# With any AUR helper (yay shown; paru, pikaur, etc. work identically):
yay -S modulejail

# Or manually:
git clone https://aur.archlinux.org/modulejail.git
cd modulejail
makepkg -si
```

AUR package: <https://aur.archlinux.org/packages/modulejail>

All three packages install `/usr/bin/modulejail`, the `modulejail(8)` manpage
under `/usr/share/man/man8/`, and the README and LICENSE under
`/usr/share/doc/modulejail/`. They depend on `coreutils`, `findutils`, and
`awk`/`gawk` (all standard) and recommend `curl` or `wget` so the optional
post-run update check can reach GitHub. The AUR package additionally lists
`kmod` as a hard dependency (it ships `lsmod` and `modprobe`; on Debian and
RHEL families that package is pulled in by `base`/`@core` and so does not
need to be declared explicitly).

After install, `man 8 modulejail` shows the full reference: options,
profiles, safety model, idempotency, exit codes, environment, and examples.

To rebuild the packages locally from a checkout:

```sh
./packaging/build.sh           # builds whatever this host's tooling supports
./packaging/build.sh --deb     # .deb only (requires dpkg-deb)
./packaging/build.sh --rpm     # .rpm only (requires rpmbuild)
```

Output goes to `packaging/dist/`. The script skips gracefully on hosts
without the matching tooling.

## What ModuleJail is

ModuleJail snapshots the set of currently loaded modules (`/proc/modules`) and
computes the complement against the full module tree
(`/lib/modules/$(uname -r)`). Every module in the complement, minus a built-in
baseline of essential modules and an optional sysadmin-supplied whitelist, is
emitted as an `install <mod>` directive in a `modprobe.d`-compatible
blacklist file. Since v1.2, the directive body is either
`/bin/sh -c 'logger -t modulejail "blocked: <mod>" ...; exit 0'` (default
when `/usr/bin/logger` is available, so blocked attempts produce a syslog
trail) or `/bin/true` (under `--no-syslog-logging`, silent fallback, or when
logger is absent). See the *Viewing blocked module attempts* section below.

The invocation used to create the blacklist file is noted in the header line
that starts with `invocation:`, and can be copied & pasted for reproducible
results.

The tool is aimed at Linux fleet operators who need to harden many servers
against the wave of AI-assisted kernel privilege-escalation discoveries. Every
additional loaded module is additional latent attack surface for the next
disclosed CVE. ModuleJail's model is simple: if it is not loaded today on a
steady-state host, blacklist it.

The script is portable across Debian/Ubuntu, RHEL/Rocky, Arch, Alpine, and
SUSE families. It has no runtime dependencies beyond `awk`, `comm`, `find`,
`sha256sum`, and standard coreutils, all present in every base Linux install
including busybox.

## The safety model

The invariant is: **whatever is currently loaded is assumed necessary for the
host to function, and is preserved.** ModuleJail does not guess; it reads
`/proc/modules` at run time and treats that exact set as the keep-list.

This means the operator's responsibility is to run ModuleJail when the host
is in a known-good, steady-state configuration: after all services are
started, all kernel drivers are loaded, all filesystems are mounted. Running
it on a partial or in-flux system risks blacklisting a module that is
occasionally needed.

The generated file is placed under `/etc/modprobe.d/`. To revert, remove the
file (no reboot needed — see the Reverting section). The built-in baseline
ensures that core filesystems, storage controllers, and essential networking
modules are never blacklisted regardless of the running profile.

## Explicit limitations

- **No initramfs handling.** Modules baked into initramfs are out of scope.
  The loaded-module surface is the target; baked-in modules are not the
  relevant attack vector.
- **No revert tooling.** The revert path is "remove the generated file"
  (no reboot needed; the blacklist is consulted by `modprobe` at load
  time, so removing the file takes effect immediately). Sysadmin
  discipline replaces tool guardrails.
- **No daemon or continuous monitoring.** One-shot script by design.
- **No AI inside the tool.** AI is the threat-model backdrop, not a feature.
- **No per-distro packaging in v1.** The curl one-liner and a cloned repo
  are the distribution channels.
- **No module risk scoring.** The model is "unused implies blacklist," not
  "vulnerable implies blacklist."
- **No kernel rebuild.** Runtime blacklist only.

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

`conservative` is the right choice for virtualised or bare-metal server
Linux. `desktop` is for laptops and workstations where WiFi, Bluetooth,
audio, and video drivers must be preserved. `minimal` is for environments
where you have full control over which drivers are loaded and want the
smallest possible baseline.

## The sysadmin whitelist

A site-local `WHITELIST` variable near the top of the script holds
space-separated module names that are always preserved, beyond the selected
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

Edit `WHITELIST=''` to add your site-specific modules. The `===` banner
anchors are designed for Ansible template insertion (`lineinfile` or
`blockinfile`).

## Site-local whitelist file

Since v1.2, ModuleJail reads site-local modules from an external file.
This is the preferred path when you do not want to (or cannot) edit the
script in place — for instance because you install ModuleJail via
`.deb` / `.rpm` / `curl | sh` and your site-local additions would
otherwise be lost on the next reinstall.

The default path is `/etc/modulejail/whitelist.conf`. If the file
exists, ModuleJail auto-detects it and prints an `info:` line on
stderr so the choice is not silent:

```
modulejail: info: using default whitelist file /etc/modulejail/whitelist.conf (--no-whitelist-file to opt out)
```

To skip the default for a single run (e.g. during recovery), pass
`--no-whitelist-file`. To use a different location, pass
`--whitelist-file PATH`.

File format:

```sh
# /etc/modulejail/whitelist.conf
# One module per line. Blank lines and '#' comments are allowed.
# Names may be written in either dash or underscore form ("nft-compat"
# or "nft_compat") — the pipeline normalises - to _.
# The file mode MUST NOT be group-writable or world-writable
# (ModuleJail will refuse to run otherwise).

nft_compat
xt_owner
zfs
```

Three ways to invoke:

```sh
# 1. Default location (recommended for production deploys):
sudo install -d -m 0755 /etc/modulejail
sudo install -m 0644 my-whitelist /etc/modulejail/whitelist.conf
sudo modulejail   # auto-detects /etc/modulejail/whitelist.conf

# 2. Explicit non-default path (override or use a site-local NFS mount):
sudo modulejail --whitelist-file /etc/default/modulejail-whitelist

# 3. Skip the default for one run (force "no site-local additions"):
sudo modulejail --no-whitelist-file
```

The file is appended to the in-script `WHITELIST`; the two are additive.
Operators who have been editing the in-script `WHITELIST` (the v1.0
path) keep that edit untouched; the file is a no-side-effect overlay on
top.

ModuleJail enforces two safety gates on the file:

1. **File mode must not be group- or world-writable.** The same
   hardening sshd applies to `authorized_keys` and sudo applies to
   `sudoers`. If the file is `g+w` or `o+w`, ModuleJail refuses to run
   and prints `chmod go-w PATH` as the hint. Exit code is `77`
   (`EX_NOPERM`). Rationale: the module names from this file land in
   the generated `modprobe.d` directives, so an attacker with write
   access to a shared sysadmin group could otherwise inject `install`
   stanzas the kernel would later run.
2. **Each line must match `[a-zA-Z0-9_-]+`.** Comments (`#`) and blank
   lines are skipped silently; everything else must be a plain module
   name. Any malformed line is rejected with a stderr message citing
   the file path, line number, and offending content. Exit code is
   `65` (`EX_DATAERR`).

## Viewing blocked module attempts

Since v1.2, when `/usr/bin/logger` is executable on the host running
ModuleJail (and `--no-syslog-logging` is not set), the generated
install lines call `logger -t modulejail "blocked: <module>"` so a
later `modprobe <module>` attempt produces a syslog entry tagged
`modulejail`:

```sh
# systemd hosts (journald):
sudo journalctl -t modulejail --since '1 hour ago'

# classic syslog hosts:
sudo grep modulejail /var/log/syslog
```

The generated file's header annotates which install-line form is in
use. Look for:

```
# install-line: /bin/sh + logger (syslog tag: modulejail)
```

To opt out and restore the exact v1.1.4 `/bin/true` install-line body
(useful for byte-identical regression contracts, hosts without
`logger`, or minimal/initramfs builds), pass `--no-syslog-logging`:

```sh
sudo modulejail --no-syslog-logging
```

The header annotation then reads:

```
# install-line: /bin/true (silent, --no-syslog-logging or logger absent)
```

If `/usr/bin/logger` is absent on the host AND `--no-syslog-logging`
was not set, ModuleJail silently falls back to the `/bin/true` form
(matching the v1.1.4 behaviour on minimal hosts). No stderr warning is
emitted; the header annotation is the only visible cue.

## Scope of the blacklist (what it blocks, what it doesn't)

A `modprobe.d` blacklist blocks **automatic** module loading: udev
events on hardware hotplug, dependency resolution during
`modprobe foo`, autoloaded modules through the alias system. It does
**not** block, by design:

- `insmod /path/to/module.ko` — `insmod` bypasses `modprobe` entirely
  and never reads `modprobe.d/`. A root user with intent can always
  insert a module directly.
- `modprobe --ignore-install <name>` — `modprobe`'s explicit escape
  hatch. The user is opting out of the install-line indirection that
  ModuleJail relies on.

Both are intentional escape hatches in the kernel module loader.
ModuleJail is a default-safe policy layer: it removes the
auto-loading attack surface (udev hotplug + dependency resolution),
which is what an unprivileged or remote attacker has to work with. It
does not — and could not — prevent a root user with intent from
loading anything they want. Treat the blacklist as the "lock the
front door" tool, not as the "lock the safe" tool.

## Exit codes

Exit codes follow `sysexits.h` conventions (see `man 3 sysexits`). Fleet
automation tools can `case $?` cleanly.

| Code | Meaning |
|------|---------|
| 0    | success |
| 64   | command-line argument error (bad flag, missing value, unknown profile) |
| 65   | invalid data in `--whitelist-file` (malformed module name) |
| 66   | required kernel input missing (`/proc/modules` or `/lib/modules/<kernel>`) |
| 70   | sanity guard tripped (empty blacklist or >99% of modules blacklisted) |
| 71   | OS-level error (mktemp work dir, or find errors on `/lib/modules`) |
| 73   | output path cannot be created (symlink/directory/trailing-slash, or mktemp failure) |
| 77   | target directory not writable (try sudo, or use `-o <other-path>`) |

## Idempotency contract

Two consecutive runs on an unchanged host produce byte-identical output
files. The generated blacklist header carries a sha256 run fingerprint, not
a wall-clock timestamp, computed over the canonical inputs: sorted
loaded-module set, sorted baseline set, sorted whitelist, profile name, and
kernel version. Because the fingerprint is a deterministic function of
inputs, identical inputs produce an identical fingerprint and thus an
identical output file.

```
# fingerprint: sha256:e284ee9741eb544adf1af6c0fffc162dedd6029191673237a8155cd497908686
```

Fleet operators can use the fingerprint to correlate "what was on the host
at hardening time" across machines: two hosts with the same fingerprint had
identical loaded sets, baseline, whitelist, profile, and kernel version when
ModuleJail ran. No wall-clock drift, no spurious diffs in configuration
management systems.

## Update check

After a successful run, ModuleJail performs a best-effort lookup against the
GitHub tags API to see whether a newer release is available. The check has a
10-second hard timeout and is silent on every failure mode (no network, no
`curl` or `wget` installed, parse failure, current version equal to or newer
than the latest tag). It only prints a stderr notice when the upstream
release is strictly newer than the running version.

To disable the check entirely (for offline fleets, restricted networks, or
pipeline-style automation where any unexpected output is noise), set:

```sh
export MODULEJAIL_NO_UPDATE_CHECK=1
```

The check fires only on a successful run. Error paths (bad arguments,
missing `/proc/modules`, sanity-guard trip, etc.) exit before reaching it.

## Cross-distro support

ModuleJail has been verified across two confidence tiers.

### Real-kernel tier (live SSH hosts)

| Distro | Kernel | Result |
|--------|--------|--------|
| Ubuntu 24.04.4 LTS (Noble Numbat) | 6.8.0-110-generic | PASS (6363 of 6474 modules blacklisted) |
| Debian GNU/Linux 13.4 (trixie) | 6.12.74+deb13+1-amd64 | PASS (4091 of 4227 modules blacklisted) |
| Rocky Linux 9.7 (Blue Onyx) | 5.14.0-503.35.1.el9_5.x86_64 | PASS (2253 of 2338 modules blacklisted) |
| Arch Linux (rolling, 2026-05-23) | 7.0.9-arch2-1 | PASS (6416 of 6481 modules blacklisted) |

Note for Rocky/RHEL hosts: on hosts with strict SELinux enforcement,
non-root execution may encounter a `find` permission denial on
`/lib/modules/`, causing exit code 71 (`EX_OSERR`). This is expected,
documented behaviour. Use `sudo`, or relax the relevant SELinux policy, if
this occurs.

### Fixture-container tier (synthetic kernel module trees)

| Distro | Base image | Shell | Result |
|--------|-----------|-------|--------|
| Arch Linux (latest) | `archlinux:latest` | `/bin/sh` (bash) | PASS (10/10 assertions) |
| Alpine Linux (latest) | `alpine:latest` | busybox ash | PASS (10/10 assertions) |
| openSUSE Tumbleweed | `opensuse/tumbleweed:latest` | `/bin/sh` | PASS (10/10 assertions) |

Fixture containers run against a synthetic
`/lib/modules/6.99.0-fixture/` tree with representative `.ko`, `.ko.gz`,
`.ko.xz`, and `.ko.zst` files to exercise all four suffix variants.

The `MODULEJAIL_PROC_MODULES` and `MODULEJAIL_KVER` environment variables
are test-only plumbing (analogous to `TMPDIR` or `GIT_DIR`) used by the
fixture harness to point the script at synthetic `/proc/modules` and module
tree paths. End-user operators leave these unset.

## Reverting

Remove the generated file. The blacklist is consulted by `modprobe` at
load time, not loaded into the kernel persistently, so removing the file
takes effect immediately — no reboot needed.

```sh
# Full revert (instant, no reboot needed):
sudo rm /etc/modprobe.d/modulejail-blacklist.conf

# Selective: bring back a specific module right now, even while the
# blacklist file is still in place (`modprobe` is the explicit-load
# path that overrides the blacklist):
sudo modprobe <module_name>
```

The generated file uses `install <module> ...` directives (with either a
`/bin/sh + logger` body or `/bin/true`, see *Viewing blocked module
attempts* above), which block autoloading via udev events and dependency
resolution. Explicit `sudo modprobe <name>` invocations override the
blacklist immediately, regardless of whether the file is still present.
If the file is still in place, the override applies only to that single
explicit load — subsequent autoload attempts (from udev or other modules
requiring the named module as a dependency) will be blocked again. To
make the unblock permanent, remove the blacklist file. See *Scope of the
blacklist* above for the precise list of what `modprobe.d` install
directives do and do not intercept.

## Contributing

The test matrix lives in `tests/`. Both harnesses are POSIX shell scripts
runnable by anyone with the prerequisites:

```sh
# Container fixture suite (Arch/Alpine/openSUSE):
# Requires: docker or podman; exits 77 if neither is found (graceful skip).
./tests/run-fixtures.sh

# Real-SSH-host acceptance suite:
# Requires: SSH key access to the hosts configured in the harness.
./tests/run-ssh-hosts.sh
```

`./tests/run-fixtures.sh` exits 77 on any host without a container runtime;
that is the documented graceful degradation (autoconf/TAP skip convention).
Run it on a Linux host with Docker or Podman.

Both harnesses are shellcheck-clean (`shellcheck --shell=sh`).

## Star History

<a href="https://www.star-history.com/#jnuyens/modulejail&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jnuyens/modulejail&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jnuyens/modulejail&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=jnuyens/modulejail&type=Date" />
 </picture>
</a>

## License

Copyright (C) 2026 Jasper Nuyens <jnuyens@linuxbe.com>

GPL-3.0-only. See the [LICENSE](LICENSE) file for the full text.
