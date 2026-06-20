# Changelog

All notable changes to ModuleJail are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.2] - 2026-06-20

Bug-fix release for the Arch / mkinitcpio strip-hook invocation
pattern. The dracut (RHEL family) and initramfs-tools (Debian /
Ubuntu) paths are unaffected.

### Fixed

- mkinitcpio strip-hook invocation: v1.4.0 and v1.4.1 installed the
  `modulejail-strip` install hook correctly and registered a pacman
  post-transaction trigger, but every callsite used the
  `mkinitcpio -A modulejail-strip -P` pattern, which silently
  no-ops. When `-P` regenerates presets it re-execs `mkinitcpio`
  per preset with a reduced argument set that does NOT inherit
  `-A`, so the strip hook was never added to the build for the
  per-preset run, and the resulting initramfs still contained
  `/etc/modprobe.d/modulejail-blacklist.conf`. Replaced with the
  correct `mkinitcpio -P -- -A modulejail-strip` pattern (the `--`
  forwards the `-A modulejail-strip` argument through the per-preset
  re-exec). Affects three callsites in the script:
  - pacman post-transaction trigger
    (`/usr/share/libalpm/hooks/95-modulejail-strip.hook`)
  - operator-facing one-liner printed by
    `modulejail --install-initramfs-hook`
  - `--install-initramfs-hook --dry-run` output

  Diagnosed by [@welwood08](https://github.com/welwood08) in
  [#19](https://github.com/jnuyens/modulejail/issues/19) using
  `SHELLOPTS=xtrace` on a live Arch host. Verified end-to-end clean
  on Rocky Linux 10.2 (dracut path) the same day to confirm the
  bug is mkinitcpio-specific and the dracut path needs no change.

### Operator notes

- **Arch users who installed v1.4.0 or v1.4.1**: the pacman
  post-transaction trigger has been silently no-op'ing on every
  kernel install / upgrade. Upgrade to v1.4.2, then run once:
  ```sh
  sudo mkinitcpio -P -- -A modulejail-strip
  sudo lsinitcpio /boot/initramfs-$(uname -r).img | grep modulejail-blacklist
  ```
  The second line should be empty after the rebuild. Subsequent
  kernel installs are auto-clean.

- **RHEL / Debian users**: no action required; the dracut and
  initramfs-tools paths were never affected by this bug.

- The post-install `%post` / `postinst` / `post_install` scripts
  still deliberately do NOT run a full `dracut --force --regenerate-all`
  / `update-initramfs -u -k all` / `mkinitcpio -P` because of the
  wall-clock cost during a package upgrade and the lack of
  in-the-wild reports of stale-baked initramfs damage. The operator
  recovery path documented in
  [#19](https://github.com/jnuyens/modulejail/issues/19) covers
  upgrade-from-v1.3 cases where someone suspects their existing
  initramfs may still contain a baked-in blacklist.

## [1.4.1] - 2026-06-08

Regression hotfix for the v1.4.0 desktop-profile SD card addition on
bleeding-edge kernels.

### Fixed

- `rpmb_core` added to `BASELINE_DESKTOP`
  ([#16](https://github.com/jnuyens/modulejail/issues/16), @fonic).
  Between kernel 6.12 and 7.0 the RPMB (Replay Protected Memory Block)
  code was split out of `mmc_core` into its own module. On kernels
  with the split (Arch current, Fedora rawhide, openSUSE Tumbleweed,
  Cachy / Liquorix variants, anyone tracking mainline), `mmc_block`
  declares a hard `depends: mmc_core,rpmb-core` and fails to load with
  missing-symbol errors if `rpmb-core` is in the blacklist.
  v1.4.0's `mmc_core` + `mmc_block` desktop-profile addition therefore
  fixed SD card readers on stable LTS kernels (Debian 13.4 with 6.12,
  Rocky 9.7 with 5.14) but regressed them on 7.0+ kernels. v1.4.1
  closes the gap: `rpmb_core` joins the desktop baseline, and the
  filename normalization the script already does for the underscore
  vs hyphen variance ("rpmb-core" vs "rpmb_core") covers every kernel
  build convention. On older kernels where the module doesn't exist
  separately, listing it is a harmless no-op.

### Credit

- @fonic ([#16](https://github.com/jnuyens/modulejail/issues/16)) for
  the cross-kernel `modinfo mmc_block` diagnosis - this would have
  shipped silently broken on every Arch / Fedora-rawhide / Tumbleweed
  desktop install otherwise.

## [1.4.0] - 2026-06-07

Feature release. Three operator-reported requests close together,
plus the packaging and docs that make them safe to fleet-deploy.

### Added

- `--install-initramfs-hook` / `--uninstall-initramfs-hook`
  ([#19](https://github.com/jnuyens/modulejail/issues/19)). Detects
  the active initramfs builder on the host (dracut on RHEL/Rocky/
  Fedora; initramfs-tools on Debian/Ubuntu; mkinitcpio on Arch) and
  installs a small per-distro hook that strips
  `/etc/modprobe.d/modulejail-blacklist.conf` from rebuilt initramfs
  cpios. Closes the upgrade-then-stale-blacklist class of bug where
  a kernel-package upgrade bakes the modulejail blacklist into the
  new kernel's initramfs and subsequent on-disk edits or full
  revocation do not take effect at early boot. Reported by
  @sometimegithubuser on Rocky Linux 10.2; reproduced independently
  on Rocky 9.7, Debian 13.4, and Arch (kernel 7.0.9). Prints the
  operator-runnable rebuild command after writing the hook; does
  NOT auto-rebuild the initramfs (sysadmin discipline replaces tool
  guardrails). Pair with `--dry-run` to preview the file path that
  would be written. Requires root.
- `--self-update` ([#20](https://github.com/jnuyens/modulejail/issues/20)).
  Fetches the latest stable tag from the GitHub releases API,
  downloads the matching script, splices the operator-edited
  `SYSADMIN WHITELIST` region (marker-bracketed) from the current
  script into the downloaded one, and atomically replaces the
  running script. Default behavior prompts interactively for
  confirmation; `-y` / `--yes` skips the prompt; non-tty invocation
  without `--yes` refuses with exit code 64 (cron / postinst /
  systemd-run must pass `--yes` explicitly). `--dry-run` previews
  the SHA-256 of the downloaded bytes, the splice status, and the
  target path without touching anything. Detects packaged installs
  (`dpkg-query -S` / `rpm -qf` / `pacman -Qo`) and prints a warning
  that `apt upgrade` / `dnf upgrade` / `pacman -Syu` is preferred on
  packaged hosts. External whitelist files (`--whitelist-file PATH`
  or the default `/etc/modulejail/whitelist.conf`) are not read or
  touched. Requires `curl` or `wget`. Requested by @Bundy01.
- `mmc_core` + `mmc_block` to `BASELINE_DESKTOP`
  ([#16](https://github.com/jnuyens/modulejail/issues/16)). SD card
  readers on laptops and workstations no longer need a manual
  whitelist entry to work after a modulejail run. Requested by
  @fonic.
- `MODULEJAIL_INITRAMFS_BUILDER` test-only environment variable
  (analogous to `MODULEJAIL_LOGGER_PATH`, `MODULEJAIL_PROC_MODULES`)
  forcing the initramfs builder detection in the dry-run-mode tests.
- `-y` short alias for `--yes`.
- PATH augmentation at script start (`/usr/sbin`, `/sbin` appended
  if absent) so non-root callers running `--install-initramfs-hook
  --dry-run` find `update-initramfs` on Debian and `dracut` on RHEL
  family (both binaries live under `/usr/sbin/`, which is omitted
  from the default non-root PATH on those distros).

### Changed

- `parse_whitelist_file` now refuses files whose owner is neither
  root (uid 0) nor the invoking user. A non-root owner can write to
  a 0600 file, which would let them inject WHITELIST entries that
  modulejail (running as root) trusts. The error message includes
  `sudo chown root:root <path>` with the actual file path. The
  existing group/world-writable check is unchanged but its error
  message now prefixes the fix with `sudo`.
- README tagline and "Explicit limitations" wording dropped the
  absolute "no initramfs changes" claim; initramfs handling is now
  opt-in via `--install-initramfs-hook` and automatic on packaged
  installs.

### Packaging

- `.deb`: `DEBIAN/postinst` calls `modulejail --install-initramfs-hook`
  on configure; `DEBIAN/prerm` calls `--uninstall-initramfs-hook` on
  remove/deconfigure (skipped on upgrade). Both best-effort: failures
  warn but do not abort the dpkg transaction.
- `.rpm`: `%post` and `%preun` scriptlets call the same flags; the
  uninstall scriptlet is guarded by `$1 == 0` so it runs only on full
  uninstall, not on upgrade.
- AUR: new `modulejail.install` pacman `.install` file with
  `post_install` / `post_upgrade` / `pre_remove` functions calling
  the same `--install`/`--uninstall-initramfs-hook` flags. PKGBUILD
  `install=$pkgname.install` directive added; `optdepends` extended
  with `mkinitcpio` and `curl`. `scripts/publish-aur.sh` ships
  `modulejail.install` to the AUR repo on next publish.
- All packaging paths share one source of truth for hook content:
  the heredocs inside the modulejail script itself.

### Docs

- New `docs/DEFENSE-IN-DEPTH.md` section "Where ModuleJail's policy
  applies (and where it does not)" explaining the threat-model
  argument behind stripping the modulejail blacklist from the
  initramfs: no unprivileged attacker exists during the initrd
  phase, so the defense gain of "keep blacklist active in initramfs"
  is zero, while the cost is a real boot-bricking risk on kernel-
  upgrade-driven module rename (`mpt2sas` -> `mpi3mr` on some LSI
  controllers, similar drift on some Adaptec / network / nvme-
  fabrics drivers). Promised to Jérémy Lal during the v1.4 packaging
  consultation.
- README options reference table extended with `--install-initramfs-
  hook`, `--uninstall-initramfs-hook`, `--self-update`, and `-y` /
  `--yes`. `--whitelist-file` row updated to mention the root-or-
  current-uid ownership requirement.

### Credit

- @sometimegithubuser
  ([#19](https://github.com/jnuyens/modulejail/issues/19)) for the
  Rocky Linux 10.2 upgrade-stale-blacklist bug report and the
  `lsinitrd` confirmation that pinned down the dracut bake-
  blacklist-into-cpio behavior.
- @Bundy01
  ([#20](https://github.com/jnuyens/modulejail/issues/20)) for the
  `--self-update` feature request.
- @fonic ([#16](https://github.com/jnuyens/modulejail/issues/16))
  for the SD card reader desktop-profile addition request.
- Jérémy Lal (@kapouer) for the Debian packaging consultation that
  motivated the threat-model section in `docs/DEFENSE-IN-DEPTH.md`.
- Adam Bambuch (@tjmnmk) for co-maintaining `modulejail-git` on AUR.

## [1.3.6] - 2026-05-30

Hotfix release. A third bug in v1.3.5's `--verbose-logging` install
line, caught and root-caused by @retry-the-user in
[issue #18](https://github.com/jnuyens/modulejail/issues/18) within
two hours of v1.3.5 shipping. Default (non-verbose) install-line
form unchanged; v1.1.4 byte-identical contract preserved.

### Fixed

- `--verbose-logging` install-line emitted bare `\001-\010\013-\037\177`
  as the tr `-d` argument and bare `\0` as the second tr's first
  argument. modprobe's libkmod config parser processes `\\` → `\` on
  the install command BEFORE it reaches the shell, so the bare
  backslash-octal sequences were collapsed to digit strings (`\001`
  → `001`). tr then saw `001-010013-037177` as its argument and
  rejected the `1-0` substring as a reverse-collating range
  (`tr: range-endpoints of '1-0' are in reverse collating sequence
  order`). The pipe failed, `pexe=` ended up empty, and the syslog
  entry was incomplete. **Fix:** double the backslashes in the
  emitted install-line text. `\\001` in the file → modprobe collapses
  to `\001` → shell passes `\001` to tr → tr parses as octal NUL
  byte 1, as intended. Same for `\\010`, `\\013`, `\\037`, `\\177`,
  and `\\0`. Verified end-to-end on Ubuntu 24.04 with kmod 31: the
  resulting syslog line shows the expected `ppid=$N pcomm=modprobe
  loginuid=$M pexe=modprobe $args`.

### Credit

@retry-the-user in
[issue #18](https://github.com/jnuyens/modulejail/issues/18) for the
real-time test of v1.3.5, the `tr: range-endpoints of '1-0'` error
report, and the diagnosis that backslash doubling was the right fix.

### Notes

- v1.3.4 and v1.3.5 had related issues in the verbose-logging
  install line; v1.3.6 is the first version with `--verbose-logging`
  that actually emits correct syslog entries on a stock Linux host
  with modprobe + GNU coreutils tr. Operators on either v1.3.4 or
  v1.3.5 using `--verbose-logging` should upgrade. Operators not
  using `--verbose-logging` see no behavior difference (the default
  install line is byte-identical across the v1.3.4→v1.3.6 patches).

## [1.3.5] - 2026-05-30

Hotfix release. Two bugs in v1.3.4's `--verbose-logging` install line,
both caught by @retry-the-user in
[issue #18](https://github.com/jnuyens/modulejail/issues/18) within
hours of v1.3.4 shipping. v1.1.4 byte-identical install-line body
preserved under default flags. Default (non-verbose) install-line
form unchanged.

### Fixed

- `--verbose-logging` install-line was wrapped in `/bin/sh -c '...'`,
  but `modprobe` already invokes commands via `system() → sh -c`. That
  created a second shell layer, so `$PPID` inside the inner shell
  pointed at the wrapper sh instead of `modprobe`. Result: `pcomm=sh`
  and `pexe=` showed the install-line content itself as the cmdline
  of the wrapper sh - not the actual caller. Fixed: drop the
  `/bin/sh -c '...'` wrapper. modprobe's own `sh -c` is the only
  shell layer; `$PPID` resolves directly to `modprobe`.
- `--verbose-logging` install-line used `$(cat /proc/$PPID/cmdline)`
  to read the cmdline. Shell command substitution strips NUL bytes
  from captured output, so `modprobe\0cpuid\0` became
  `modprobecpuid` in the logger message - argv elements concatenated
  with no visible separator. Fixed: pipe cmdline through `tr` to
  convert NULs to spaces (`tr '\0' ' '`) instead of relying on shell
  substitution.

### Added

- Log-injection hardening (defense-in-depth) in the `--verbose-logging`
  install-line. The cmdline is now also piped through
  `tr -d '\001-\010\013-\037\177'` to strip control bytes (newline,
  carriage return, form-feed, terminal-escape, DEL) before the logger
  message is built. Shell command substitution treats the substituted
  text as data (no second-pass expansion), so **command injection
  via attacker-controlled cmdline content is not possible** - this
  hardening covers log injection only (attacker fabricating fake log
  entries via embedded newlines, or terminal-control sequences
  appearing when an admin views the log with `cat`).
- New `MODULEJAIL_TR_PATH` environment variable (test-only plumbing,
  parallel to `MODULEJAIL_LOGGER_PATH`). `--verbose-logging` now
  requires `tr` to be executable; modulejail exits `EX_NOINPUT=66`
  with a clear message if `/usr/bin/tr` (or the override path) is
  absent, rather than silently generating broken install-lines that
  would emit `tr: command not found` into syslog at modprobe-time.
- New acceptance case `verbose-logging-requires-tr.sh` covering the
  missing-tr error path. Suite is now 34/34 PASS.

### Credit

@retry-the-user in
[issue #18](https://github.com/jnuyens/modulejail/issues/18) for the
real-time bug-hunting: both root causes were diagnosed correctly in
the issue thread (double-shell layering, NUL-stripping by shell
substitution) before this hotfix was committed. The command-injection
question that prompted the log-injection hardening also came from the
same thread.

### Notes

- Operators on v1.3.4 should upgrade to get the corrected
  `--verbose-logging` output. v1.3.4 operators not using
  `--verbose-logging` see no behavior difference between v1.3.4 and
  v1.3.5 (the default install-line is byte-identical).

## [1.3.4] - 2026-05-30

Patch release. One new flag (`--verbose-logging`), five new
`BASELINE_DESKTOP` entries (CPU power management + TUN/TAP), one
documented baseline-addition policy. v1.1.4 byte-identical install-
line body preserved under default flags (no change to default
behavior).

### Added

- `--verbose-logging` flag. Enriches the per-blocked-load `logger`
  call with the caller context, read from `/proc/$PPID/...`: the
  parent PID (`ppid`), audit `loginuid` (persists across `su`/
  `sudo`), parent short command name (`pcomm`), and `argv[0]`
  (`pexe`, naturally NUL-truncated; full `cmdline` is one
  `ps -fp <ppid>` away). Default `logger` output remains the bare
  `"blocked: <module>"` form. Requires `/usr/bin/logger` to be
  executable (modulejail exits `EX_NOINPUT=66` otherwise);
  mutually exclusive with `--no-syslog-logging`. Resolves the
  triage request from @retry-the-user in
  [issue #18](https://github.com/jnuyens/modulejail/issues/18).
  Three new acceptance cases cover the enriched install-line body,
  the mutex with `--no-syslog-logging`, and the
  logger-binary-missing error path.
- `BASELINE_DESKTOP` additions (5 modules, target audience is
  laptops / workstations where modulejail may run before all
  udev/late-load events have settled):
  - `intel_pstate`, `intel_cstate` - modern Intel CPU power
    management.
  - `amd_pstate` - AMD analog of `intel_pstate` (in-kernel since
    6.0).
  - `tun`, `tap` - VPN clients (WireGuard, OpenVPN), VirtualBox/
    VMware, qemu/KVM bridges.

### Changed

- Documented **baseline-addition policy** in the `modulejail`
  script (new comment block above the `Deliberately NOT in any
  baseline` section) and in `README.md` `## Contributing` (new
  `### Baseline-addition policy` subsection). Policy text:

  > Modules join a baseline only when there is observed operator
  > pain in that profile's target audience. CONSERVATIVE target =
  > bare-metal/VM Linux servers (hands-on admins, post-steady-state
  > runs). DESKTOP target = laptops/workstations (set-and-forget
  > UX, ModuleJail may run at any time including before all udev/
  > late-load events have settled). "Defensive add because the
  > kernel sometimes loads it late" is insufficient justification -
  > a real operator-reported breakage in the relevant profile's
  > target audience is the bar.

  `acpi_cpufreq` in `BASELINE_CONSERVATIVE` (added v1.3.2 with the
  same speculative reasoning the policy now disallows) is retained
  for backward compatibility; no future additions follow that
  pattern.
- `BASELINE_DESKTOP` comment header updated to reflect the new
  entries and the target-audience phrasing.

### Credit

- @retry-the-user in
  [issue #18](https://github.com/jnuyens/modulejail/issues/18) for
  the `--verbose-logging` motivation (triage of who-tried-to-load
  what for whitelist decisions).
- @teou1 in
  [issue #16](https://github.com/jnuyens/modulejail/issues/16) for
  the CPU power management + TUN/TAP suggestions and for the
  push-back that catalysed the baseline-addition policy.

### Notes

- `ntfs` declined from the same #16 feedback round. The
  `CONFIG_NTFS_FS` kernel option is explicitly marked backward-
  compat only in the current 7.x tree (`"NTFS filesystem is now
  handled by the NTFS3 driver"`); the actually-maintained driver
  remains `ntfs3` which is already in DESKTOP. Adding `ntfs` would
  pull in deprecated code paths that only exist for users who
  haven't migrated.
- Adding `intel_pstate` / `intel_cstate` / `amd_pstate` to
  `BASELINE_CONSERVATIVE` was considered and declined: on servers
  the cpufreq driver path is either kernel-built-in (the default
  on Debian / Ubuntu Server / RHEL / Amazon Linux), or loaded via
  udev modalias matching within milliseconds of boot. There is no
  load-on-user-action path for CPU governors on servers, so the
  policy bar for `CONSERVATIVE` addition is not met.

## [1.3.3] - 2026-05-29

Hotfix release. The v1.3.2 baseline additions (this morning) broke
the v1.1.4 byte-identical regression test in CI: three of the newly-
baselined modules (`inet_diag`, `tcp_diag`, `udp_diag`) were present
in the v1.1.4-era reference fixture, so moving them from blacklisted
to kept shifted the install-line count by 3 (6363 -> 6360). The
modulejail binary's behavior was correct in v1.3.2; the failing test
was a reference-fixture issue, not a code issue.

### Fixed

- `tests/fixtures/v1.1.4-regression/expected-blacklist.conf`
  regenerated to reflect the v1.3.2 baseline additions. The contract
  scope is clarified in `tests/cases/v1.1.4-regression.sh`: the
  v1.1.4 byte-identical regression contract applies to the install-
  line **rendering** (the per-line `install <name> /bin/true` form),
  not to the **set** of modules that end up in the file. Intentional
  baseline additions are allowed to change the module set; the test
  reference is updated in the same commit. Future baseline additions
  follow the same pattern.

### Notes

- Operators already on v1.3.2 do not need to upgrade for any
  behavioral reason; v1.3.3 ships identical modulejail logic. The
  upgrade is recommended only for clean CI signaling and to be on
  the latest tag.
- Adding `tests/run-fixtures.sh` to the pre-release pre-flight (it
  was previously implicit via CI-on-push; running it locally before
  tagging would have caught this).

## [1.3.2] - 2026-05-29

Patch release. Baseline maturation driven by operator feedback - the
DESKTOP and CONSERVATIVE profiles gain modules that turned out to be
load-on-demand in the wild but were not yet baseline-protected. No
flag changes; no behavior changes outside the keep-set growth. v1.1.4
byte-identical install-line body preserved (6363 / 6363 install lines).

### Added

- `BASELINE_CONSERVATIVE` now includes:
  - `inet_diag`, `tcp_diag`, `udp_diag` - inet socket diagnostics
    auto-loaded by `ss(8)`, `iotop(8)`, and most system-monitor tools
    (KDE System Monitor, GNOME System Monitor, btop, glances).
  - `acpi_cpufreq` - ACPI-based x86 CPU frequency governor. Loaded on
    most laptops and servers that don't use `intel_pstate`. Often
    built-in to distro kernels; baseline addition is a no-op there and
    safety-net on kernels where it ships as a module.
  - `tls` - kernel TLS (kTLS). Increasingly load-on-demand for
    HTTPS-heavy daemons and modern package managers. Server-side too
    (kTLS in nginx, NFS-over-TLS).
- `BASELINE_DESKTOP` (on top of the CONSERVATIVE additions above) now
  includes:
  - `f2fs` - modern flash-friendly filesystem, common on partition
    tools and external drives.
  - `ntfs3` - read/write NTFS driver, in-tree since 5.15. Standard
    for mounting Windows drives.
  - `isofs`, `cdrom` - ISO 9660 and optical-media support, for `.iso`
    mounting and CD/DVD drives.
  - `amd64_edac`, `i7core_edac`, `ie31200_edac` - CPU EDAC (memory
    error detection) for AMD and common Intel families. These are
    loaded by udev later in the boot sequence; including them in the
    baseline avoids the race where a ModuleJail run at steady-state
    might find them not-yet-loaded.

### Credit

@Dizirgee in [issue #16](https://github.com/jnuyens/modulejail/issues/16)
for the well-organized, evidence-based survey of modules that turned
out to need baseline protection. The feedback loop was nicely closed
by @teou1's `examples/blocked-module-popup.sh` (v1.3.1) which
@Dizirgee was using to catch the blocked-module attempts in real time.

### Notes

- Declined from the same issue as better-as-operator-`WHITELIST` rather
  than baseline-default: `ntfs` (superseded by `ntfs3`), `nbd`
  (sysadmin tool, not desktop default), `ib_core` (HPC/datacenter, not
  desktop). Operators with specific needs can add these to the
  `WHITELIST=` line near the top of the script.
- Manjaro forum operators have started a community knowledge base at
  https://forum.manjaro.org/t/howto-modulejail/187877 (authored by
  @andreas85) covering operator-specific module sets we don't bake
  into baselines.

## [1.3.1] - 2026-05-27

Documentation-heavy patch release. One small additive baseline change
(exfat in DESKTOP), one new operator-recipe example, two external doc
contributions, and a substantial new threat-model + defense-in-depth
documentation surface. No flag changes; no behavior changes outside
the DESKTOP profile keep-set. v1.1.4 byte-identical install-line body
still preserved (6363 / 6363 install lines).

### Added

- `exfat` in `BASELINE_DESKTOP`. Windows-formatted flash drives and SD
  cards above 32 GB default to exFAT; without this addition, plugging
  a Windows-formatted USB drive into a desktop-profile host after a
  ModuleJail run could fail to mount. Additive only; no module is
  blacklisted that wasn't already. Contributed by @tjmnmk in
  [PR #13](https://github.com/jnuyens/modulejail/pull/13).
- `examples/blocked-module-popup.sh`: a small desktop-session script
  that tails `journalctl -t modulejail` and fires `notify-send` for
  each blocked module load. Ships under `examples/` because it is a
  separate operator-launched recipe, not a ModuleJail feature (a
  longer-running popup tail would cross the v1 "no daemons" line; the
  v2.0-alpha "Managed Mode" roadmap covers the eventual built-in
  version). Contributed by @teou1 in
  [issue #12](https://github.com/jnuyens/modulejail/issues/12).
- New top-level `## Threat model` section in `README.md` making the
  scope explicit: ModuleJail defends against unprivileged-user → root
  privilege escalation via vulnerable kernel modules, and does **not**
  defend against attackers who already have root (root can `insmod`
  directly, bypassing `modprobe.d/` entirely). Cites the May 2026
  "Copy Fail" CVE (CVE-2026-31431, `algif_aead`) as the canonical
  threat-model fit.
- New `docs/DEFENSE-IN-DEPTH.md` with a 7-tier taxonomy of which
  kernel modules unprivileged users can autoload (socket families,
  AF_ALG crypto, FUSE setuid mount helpers, binfmt, char-devices,
  netlink, user-namespace amplifier) and 5 stand-alone hardening
  recipes that compose with ModuleJail (`kernel.modules_disabled=1`,
  disable unprivileged user namespaces, Secure Boot + lockdown mode,
  module signature enforcement, seccomp per service). Each recipe
  lists who it protects against, how to apply, and what breaks.
- New `## Failing on blocked module loads` section in `README.md`
  plus a full `-f` / `--fail-on-module-load` entry in the manpage
  SYNOPSIS and OPTIONS. The v1.2.3 `-f` flag existed but was
  undocumented. Contributed by @tjmnmk in
  [PR #14](https://github.com/jnuyens/modulejail/pull/14).
- New `## Options reference` table in `README.md` covering every
  flag plus the three `MODULEJAIL_*` environment variables.
  Contributed by @tjmnmk in
  [PR #14](https://github.com/jnuyens/modulejail/pull/14).

### Changed

- In-script `usage()` text extended to document the v1.3.0 flags that
  were added on the manpage side but missed in `--help`:
  `--dry-run`, `--quiet`, `--verbose`, `--output-format {json|logfmt}`,
  and the `-p none` profile arm. `modulejail --help`, the `README.md`
  options table, and the manpage are now in parity.
- README `## Scope of the blacklist (what it blocks, what it doesn't)`
  section now cross-references the new top-level `## Threat model` +
  `docs/DEFENSE-IN-DEPTH.md` instead of duplicating the framing inline.
- Manpage `HEADER FIELDS` section: minor prose cleanup of the
  `# kernel:` line description; behavior unchanged.
- README native-package install snippets: stale `1.2.4` filename
  references in the `dpkg -i` / `rpm -i` lines (left over from the
  v1.3.0 release URL bump) are now consistent with the download URL.

### Internal

- AUR `modulejail` PKGBUILD switched to sequoia-sqv signature
  verification. New `prepare()` invokes `sqv` against a pinned
  `modulejail-signing-key.gpg` shipped in the AUR repo; local source
  filenames use non-trigger extensions (`.tarball-signature`, `.gpg`)
  so `makepkg`'s built-in gpg verifier does not compete. Published as
  AUR `modulejail 1.3.0-2` on 2026-05-25 ahead of this release (no
  upstream code change in that pkgrel). The v1.3.0 GitHub release now
  carries `v1.3.0.tar.gz.sig` as a third asset alongside the .deb and
  .rpm. Per AUR comment from @Velocifyer (2026-05-24): "use sqv, not
  gpg."

### Credit

- @teou1 for [issue #12](https://github.com/jnuyens/modulejail/issues/12)
  (the popup-script contribution and a wiki HOWTO on the Manjaro
  forum at https://forum.manjaro.org/t/howto-modulejail/187877,
  authored by @andreas85).
- @tjmnmk (Adam Bambuch) for PRs #13 and #14, and for picking up
  co-maintainership coordination on AUR `modulejail-git`.
- @Velocifyer for the AUR comment that drove the sequoia-sqv switch.

## [1.3.0] - 2026-05-24

Operator-flexibility CLI surface (four new flags, one new profile, one
new header line) and the first release cut from a hardened pipeline
(GPG-signed annotated tags going forward, GitHub Actions CI matrix on
every push / PR / tag). Single biggest release since v1.2.0.

### Added

- New `-p none` profile. Produces a blacklist that preserves only the
  currently-loaded module set (`lsmod`) and the `--whitelist-file`
  entries, with NO built-in baseline added. Most aggressive profile;
  recommended only when `--whitelist-file PATH` is supplied. The >99%
  blacklist sanity guard is skipped on this profile and an `info:` line
  documents the skip on stderr. Supports the centrally-generated
  deny-list / shared-node operator pattern from frymaster on
  r/archlinux. Closes OPT-01.
- New `--dry-run` flag. Runs the full pipeline (compute the blacklist
  set, render the header, fingerprint the body) but writes NOTHING
  under `/etc/modprobe.d/`. The would-be header is rerouted to stderr;
  `DRY-RUN: would blacklist N modules` summary on stdout. Exit code 0
  on simulated success. Combines cleanly with every other flag. Closes
  OPT-02.
- New `--quiet` flag suppresses all non-error stderr output (info /
  notice lines and the post-run human summary). `error:` lines still
  fire so fleet automation case-splitting on sysexits codes remains
  correct. Closes OPT-03 (quiet half).
- New `--verbose` flag emits per-module decision lines on stderr,
  produced by a single-pass `awk` (O(n), one fork). Mutually exclusive
  with `--quiet` (combining exits `64 EX_USAGE`). Closes OPT-03
  (verbose half).
- New `--output-format json` / `--output-format logfmt` flags emit a
  machine-readable run summary to stdout on success. Schema v1: 11
  fields including `tool_name`, `tool_version`, `kernel_version`,
  `profile`, `modules_available`, `modules_loaded`,
  `modules_blacklisted`, `fingerprint` (sha256, raw hex),
  `output_path`, `dry_run` (bool), `whitelist_file`. JSON form
  round-trips through `jq`; logfmt form round-trips through standard
  logfmt parsers. `--output-format` bypasses `--quiet` (the
  machine-readable summary survives the silencer) but never emits on
  error. Closes OPT-04.
- New `# kernel version: <uname -r>` line in the generated blacklist
  header, on a separate line from the existing ModuleJail version and
  sha256 fingerprint annotations. Lets a recipient of a
  centrally-deployed deny-list see which kernel's module tree produced
  it. The v1.1.4 byte-identical install-line body is preserved under
  `--no-syslog-logging` (6363 / 6363 install lines). Closes HDR-01.
- Twelve new acceptance cases under `tests/cases/` locking the Phase 5
  surface (`-p none`, `--dry-run`, `--quiet`, `--verbose`,
  `--output-format json|logfmt`, `HDR-01` header lock, and the
  `--quiet` + `--verbose` mutex). Total host-local acceptance suite is
  now 30 cases.
- New `## Verifying releases` section in `README.md` documenting the
  `git tag -v v1.3.0` verification path, expected `gpg: Good signature`
  output, two key-import paths (`curl https://github.com/jnuyens.gpg |
  gpg --import` and `gpg --recv-keys <FPR>`), and a maintainer-aside
  `> [!TIP]` callout for the one-time `git config tag.gpgsign true`
  setup.

### Changed

- Generated blacklist header gains a new `# kernel version:` line per
  HDR-01 above. The install-line body remains byte-identical to v1.1.4
  under `--no-syslog-logging` per the D-39 contract; only the header
  annotation set grows.

### Security

- **Annotated release tags are now GPG-signed.** `v1.3.0` is the first
  signed tag; `v1.0.0..v1.2.4` are intentionally left as
  annotated-but-unsigned (history not rewritten; downstream packagers
  rely on commit-immutability). Verification path documented in
  `README.md` `## Verifying releases`. Signing-key fingerprint
  published in the release notes. Closes REL-04.

### Internal

- New `.github/workflows/ci.yml` runs `tests/run-fixtures.sh` on every
  push to `master`, every PR, and every tag push. Five explicit named
  jobs: `lint` (shellcheck across `modulejail`,
  `tests/run-fixtures.sh`, `tests/lib/*.sh`, `tests/cases/*.sh`,
  `scripts/*.sh`) plus `arch` + `alpine` + `opensuse` (the three
  already-supported fixture-tier distros) plus `host-local`. Each
  fixture job calls the same harness the local fixture-test path uses
  (no parallel test logic). Branch protection on `master` requires all
  five checks. Zero secrets in the workflow; only first-party
  `actions/checkout@v4` is used. Closes REL-05.
- `tests/run-fixtures.sh` gains `--only-container DISTRO` and
  `--only-host-local` per-axis selector flags. Three-way mutex with
  `--filter PATTERN`; `DISTRO` is allowlisted against
  `{arch, alpine, opensuse}`; bad usage exits `64 EX_USAGE`. Used by
  the CI matrix to dispatch one job per axis.
- `tests/lib/case-env.sh` split into a slim `case-env.sh` (shared
  boilerplate, centralized `EXIT / INT / HUP / TERM` trap) plus new
  `tests/lib/case-tree.sh` (synthetic kernel-module-tree builder,
  13 representative touches, 50-dummy padding, fake `/proc/modules`).
  `tests/cases/v1.1.4-regression.sh` now sources `case-env.sh` only
  (drops the duplicated boilerplate, migrates four failure paths to
  `case_fail`); the v1.1.4 6363 / 6363 byte-identical install-line
  body contract still holds. Twenty-seven other host-local cases
  source `case-tree.sh` for the synthetic tree builder; two
  open-coded outliers (`emit-install-line-sanitize.sh`,
  `ssh-unreachable-regression.sh`) are deliberately untouched.
  Closes IN-03.
- `man/modulejail.8.in` line 7 `.TH` date is now a `__DATE__`
  placeholder substituted by `packaging/build.sh` at build time
  (parallel to the existing `__VERSION__` substitution). Honours
  `SOURCE_DATE_EPOCH` per reproducible-builds.org, with GNU/BSD
  `date` fallback (`date -u -d '@SDE'` first, `date -u -r SDE`
  second) so both Debian/Fedora build hosts and the macOS dev host
  produce the same output. Closes IN-04.

### Notes

- The v1.1.4 byte-identical install-line body contract (D-39) is held
  through every Phase 5 and Phase 6 commit; `--no-syslog-logging`
  still produces the exact v1.1.4 bytes (6363 / 6363 install lines).
- Phase 6 introduces signed tags forward only. Earlier releases
  (v1.0.0 through v1.2.4) remain annotated-but-unsigned by design;
  re-signing them would require force-pushing history and break
  downstream packagers' commit-immutability assumptions.

## [1.2.4] - 2026-05-20

### Added

- An invocation header — can be copied and pasted for reproducible results.

## [1.2.3] - 2026-05-19

### Added

- New `-f` / `--fail-on-module-load` flag. When set, blocked module
  loads return a non-zero exit code (`modprobe` fails loudly) instead
  of silently succeeding with `/bin/true` / `exit 0`. Useful for
  operators running CI or Ansible against `modprobe` who want
  blacklisted-module attempts to surface as failures rather than
  silent skips. Default behavior unchanged.
- New install-line forms for the flag-on case:
    - silent form: `install <name> /bin/false`
    - logger form: `install <name> /bin/sh -c '/usr/bin/logger -t modulejail "blocked: <name>" 2>/dev/null; /bin/false'`
- Two new acceptance cases:
    - `tests/cases/fail-on-module-load-silent.sh`
    - `tests/cases/fail-on-module-load-logger.sh`

### Compatibility

- The default-off install-line bytes are byte-identical to v1.2.2 in
  both the silent and logger paths. The v1.1.4 byte-identical
  regression contract (`tests/cases/v1.1.4-regression.sh`) still
  passes (6363 / 6363 install lines).
- New header annotations when the flag is set:
    - `# install-line: /bin/false (silent, --fail-on-module-load)`
    - `# install-line: /bin/sh + logger + /bin/false (syslog tag: modulejail, --fail-on-module-load)`
  Default-off header strings unchanged.

### Credit

Proposed by @tjmnmk in [PR #4](https://github.com/jnuyens/modulejail/pull/4); applied directly with the following adjustments to fit the project's POSIX and byte-identical contracts:

- `local install_final_cmd` (a bash/ksh extension; not POSIX) replaced with explicit branching in `emit_install_line`.
- The default-off (`FAIL_ON_MODULE_LOAD=0`) logger path now preserves the trailing `; exit 0` byte-for-byte, instead of swapping to `; /bin/true`. The byte-identical contract for default behavior is intact.
- Two new acceptance cases added under `tests/cases/`.

## [1.2.2] - 2026-05-18

One-line follow-up to v1.2.1: when the host has neither `curl` nor
`wget`, the best-effort update check now leaves an operator-visible
breadcrumb instead of silently giving up.

### Added

- `check_for_updates` emits `modulejail: notice: no curl/wget in PATH,
  cannot check for update` to stderr when neither downloader is
  available on `$PATH`, then returns 0 (the function's documented
  always-succeed contract is preserved). Severity-prefix matches the
  other three `notice:` lines in the same function ("newer release
  available" etc.). Authored by @pepa65 in [PR #1].

### Notes

- `check_for_updates` is best-effort (documented at the function's
  block-comment header). Its exit code is independent of blacklist
  generation; this release does not change any exit-code semantics for
  the script's main job.
- v1.1.4 byte-identical regression: 6363/6363 install lines preserved
  (this patch does not touch the blacklist-rendering codepath).
- Packaging metadata (`packaging/{deb,rpm}/`) and `man/modulejail.8.in`
  pick up `1.2.2` via the existing `__VERSION__` substitution in
  `packaging/build.sh`; the `.TH` line in the manpage stays at
  `2026-05-18` (same calendar day as 1.2.0 / 1.2.1).

[PR #1]: https://github.com/jnuyens/modulejail/pull/1

## [1.2.1] - 2026-05-18

Bundled cleanup pass discharging four code-review findings, two
cosmetic items, and three carry-forward items from the v1.0.0 audit.
No new features, no UX changes.

### Fixed

- `parse_whitelist_file` now propagates real `awk` failures to a
  typed sysexits exit code under `set -eu`. Previously the
  `_awk_status=$?; if [ ... ne 0 ]; then exit $EX_DATAERR; fi` tail
  was dead code: `set -eu` aborts the shell at the `awk` line on any
  non-zero awk exit, before the `if` can run. The new shape brackets
  the `awk` call with `set +e` / `set -e`, captures `rc=$?`, and
  routes 65 to `EX_DATAERR` (the documented data-error path) and any
  other non-zero exit to `EX_OSERR` (awk-internal failure: OOM,
  signal, future program-edit syntax error). Fleet automation
  case-splitting on sysexits codes now reads correctly.
- `tests/run-ssh-hosts.sh` now classifies unreachable hosts as
  `UNREACHED` (harness exit 2) instead of mis-counting them as
  `OVERALL_FAIL` (exit 1). The pre-fix shape
  `if ! run_host ...; then rc=$?` captured the inverted-condition
  `!` exit (always 0 inside the `then` branch under POSIX `/bin/sh`,
  dash, and bash), so the rc=2 dispatch was dead. Replaced with
  `set +e; run_host ...; rc=$?; set -e; case "$rc" in ...`. The
  documented exit-code contract on lines 33-37 is now actually
  enforced.
- Header-annotation byte string aligned to comma form (was a
  semicolon in the implementation): `# install-line:
  /bin/true (silent, --no-syslog-logging or logger absent)`. Edited
  in modulejail, the manpage, the README, and the two logger test
  cases that asserted the byte string.
- Whitelist-file lines may now carry leading whitespace. The `awk`
  validator strips leading whitespace symmetric with the existing
  trailing-whitespace strip before the canonical-regex check, so an
  indented module name (e.g. `  vfio_pci` copy-pasted from a YAML or
  other indented source) is accepted rather than rejected as
  `EX_DATAERR`.
- README.md audited against the two v1.0.0 carry-forward items; both
  are already-discharged. The dependency list at line 122-123 already
  names `awk, comm, find, sha256sum, and standard coreutils`
  correctly (the script truly invokes none of `grep`, `sed`); the
  stale "420 lines" claim was already removed from the README in an
  earlier edit (the script has grown well past that, and any pinned
  count would invite future rot). No further edits needed.

### Security

- Defense-in-depth: `list_universe` and `list_loaded` now filter
  their output to the canonical kernel-module regex
  `^[a-zA-Z0-9_]+$` before names can reach `emit_install_line`.
  Severity: medium; not user-reachable today without root-equivalent
  write access to `/lib/modules/$(uname -r)/`. Closes the documented
  "strict regex is the gate" contract for both the `--whitelist-file`
  path (already gated by `parse_whitelist_file`) AND the filesystem-
  walk path (previously un-gated). Pre-fix reproduction: a `.ko*`
  file under `/lib/modules/$KVER/` with a single quote in its
  basename flowed unescaped into the generated install line, breaking
  the shell-quoting of the logger form (`install evil'name /bin/sh
  -c '/usr/bin/logger ...'`) and causing `modprobe` to evaluate
  syntactically malformed shell at module-load time. New regression
  test `tests/cases/emit-install-line-sanitize.sh` feeds three
  adversarial characters (single quote, `$IFS`, whitespace) through
  the full pipeline under both install-line forms and asserts the
  generated file contains none of those characters in any
  install-line module-name token.

### Changed

- `tests/run-fixtures.sh` with no flags now ALWAYS runs every
  host-local case under `tests/cases/*.sh` (15 cases as of v1.2.1).
  The container distro matrix (arch, alpine, opensuse) is additive
  when a docker or podman runtime is available. Pre-fix, the
  no-container-runtime path exited 77 without running anything, so
  the host-local cases under `tests/cases/` (whitelist-file-*,
  logger-*, v1.1.4-regression) were silently skipped on every
  developer-laptop invocation.

### Added

- `tests/cases/ssh-unreachable-regression.sh`: regression guard for
  the SSH-host harness exit-code routing fix. Drives the harness
  against a guaranteed-unreachable host
  (`unreachable-modulejail-test-host.invalid`, RFC 2606 reserved
  TLD), asserts harness exit 2 and `UNREACHABLE` SUMMARY token.
  Hermetic: no real SSH server, no `~/.ssh/config` dependency, no
  sudo; total wall-clock <100ms on the dev box.
- `tests/cases/emit-install-line-sanitize.sh`: regression guard for
  the defense-in-depth filter. Builds a synthetic
  `/lib/modules/$KVER/kernel/` tree with three adversarial `.ko`
  basenames, runs `modulejail` under both install-line forms,
  asserts the generated blacklist contains no adversarial characters
  in any install-line module-name token. Mutation-tested against a
  pre-fix `modulejail` (filter absent): correctly FAILs with
  diagnostic dumps showing the leaked install lines.

### Deferred (with rationale)

- `case-env.sh` duplication in `v1.1.4-regression.sh`:
  v1.1.4-regression's open-coded REPO_ROOT/CASE_TMP/trap boilerplate
  is kept. Refactoring `case-env.sh` to support a
  `CASE_ENV_NO_UNIVERSE` opt-out would touch the contract used by
  all 13 other host-local cases, for the marginal benefit of ~20
  fewer duplicated lines in the one case whose synthetic-tree needs
  are wildly different (6474 sharded files vs. ~63 hand-listed). The
  v1.1.4-regression case is the safety contract for the release;
  isolating its open-coded boilerplate is the lower-risk choice.
- Hardcoded dates in manpage and rpm spec: `__DATE__` substitution
  not plumbed. The rpm spec changelog inherently needs a manual
  per-release edit (new top changelog block; prior entries must NOT
  change), so `__DATE__` saves nothing there. The manpage `.TH` line
  could use `__DATE__` cleanly but it saves no release-checklist
  step (the human still has to bump VERSION and write CHANGELOG.md).
  Recorded as a release-checklist item: on every release bump
  `man/modulejail.8.in:7` `.TH` date and add a new
  `packaging/rpm/modulejail.spec.in` changelog block.

## [1.2.0] - 2026-05-18

### Added

- New `--whitelist-file PATH` flag (closes [#2](https://github.com/jnuyens/modulejail/issues/2)).
  Reads a site-local whitelist file (one module name per line, `#` comments,
  blank lines ignored), validates each line against `[a-zA-Z0-9_-]+`, refuses
  group- or world-writable files, and appends valid names to the in-script
  `WHITELIST`. Operators no longer lose site-local additions on
  `.deb` / `.rpm` / `curl | sh` reinstalls.
- **Default path** `/etc/modulejail/whitelist.conf`. When the flag is not
  passed and this file exists, ModuleJail auto-detects it with the same
  strict mode and content gates and prints an `info:` line on stderr so
  the choice is never silent. Addresses the silent-error-on-forgotten-flag
  concern raised by @bpmartin20 and @james-rimu in
  [#2](https://github.com/jnuyens/modulejail/issues/2).
- New `--no-whitelist-file` flag to skip the default file for a single run.
  Mutually exclusive with `--whitelist-file PATH` (combining exits
  `64 EX_USAGE` with a clear error).
- New `--no-syslog-logging` flag. Forces the v1.1.4-style
  `install <name> /bin/true` install-line body, for operators who require
  byte-identical output across versions or run on hosts without
  `/usr/bin/logger`.
- New `MODULEJAIL_LOGGER_PATH` env-var override (test-only plumbing, parallel
  to `MODULEJAIL_PROC_MODULES` / `MODULEJAIL_KVER` / `MODULEJAIL_MODULES_ROOT`).
- New `MODULEJAIL_MODULES_ROOT` env-var override (test-only plumbing) — lets
  host-local test cases on non-Linux dev boxes exercise the full pipeline
  against a synthetic `/lib/modules` tree.
- New `MODULEJAIL_DEFAULT_WHITELIST_FILE` env-var override (test-only plumbing)
  for the default-path auto-detection.
- New header annotation `# install-line: ...` documents which install-line
  form is in the generated file.
- New regression fixture under `tests/fixtures/v1.1.4-regression/` pinning
  v1.1.4 output as a permanent baseline (`tests/cases/v1.1.4-regression.sh`).
- Twelve new acceptance cases under `tests/cases/`: nine for `--whitelist-file`
  (happy path, missing file, bad permissions, malformed module name,
  comments-and-blanks, default-path used, default-path opt-out via
  `--no-whitelist-file`, dash-form normalisation regression,
  `--whitelist-file PATH` + `--no-whitelist-file` mutual exclusion),
  three for the logger install-line forms (default-on, opt-out, absent-fallback).

### Fixed

- Whitelist-file entries written in dash form (`nft-compat`) are now
  normalised to underscore form before joining the keep-set, matching the
  documented behaviour and the normalisation already applied by
  `list_baseline` / `list_whitelist` / `list_universe`. Before this fix,
  dash-form entries silently failed to match `/proc/modules`'s underscore
  form and the module was blacklisted anyway. Caught in code review
  before release.

### Changed

- **Default behaviour change:** when `/usr/bin/logger` is executable on the
  host running modulejail (and `--no-syslog-logging` is not set), generated
  install lines now call `logger -t modulejail "blocked: <name>"` so blocked
  module load attempts produce a syslog entry tagged `modulejail`. View via:
    - `journalctl -t modulejail --since '1 hour ago'` on systemd hosts
    - `grep modulejail /var/log/syslog` on syslog hosts

  Set `--no-syslog-logging` to restore the exact v1.1.4 install-line body.
  The generated file's header annotation (`# install-line: ...`) records
  which form was emitted.

### Security

- Whitelist file is rejected if its mode allows group-write or world-write
  (`mode & 022 != 0`), exiting `EX_NOPERM=77` with a `chmod go-w PATH` hint.
  Same hardening sshd applies to `authorized_keys` and sudo applies to
  `sudoers`. Each non-comment line is strictly validated against
  `[a-zA-Z0-9_-]+` to prevent command injection into the generated
  `modprobe.d` file. Rejection exits `EX_DATAERR=65` with a stderr message
  citing the file path, line number, and offending content.

### Internal

- New `EX_DATAERR=65` constant in the sysexits.h block (numeric order between
  `EX_USAGE=64` and `EX_NOINPUT=66`). Documented exit code in `--help`.
- POSIX-portable octal mode parsing (no bashism `$((8#$x))`); shellcheck
  `--shell=sh` clean.
- Pre-existing latent bug fixed: the `cleanup()` EXIT trap's
  `[ -n "$tmp" ] && rm -f "$tmp"` last command silently clobbered explicit
  `exit $EX_*` codes under dash/POSIX `/bin/sh` whenever `$tmp` was still
  empty. Rewritten as an `if`/`then` block with an explicit trailing
  `return 0`. Surfaced by the new whitelist-file rejection paths.
- `tests/run-fixtures.sh` gained `--filter PATTERN` mode for host-local case
  scripts under `tests/cases/`; the default no-flag mode (full distro fixture
  matrix) is unchanged.
- Header annotation does NOT enter the fingerprint computation (fingerprint
  is a function of canonical inputs — kernel, profile, loaded, baseline,
  whitelist — not render-time decisions). Two runs on identical inputs with
  different `--no-syslog-logging` states therefore produce different
  install-line bodies but the same `# fingerprint:` line, preserving the
  v1.0.0 fleet-correlation contract.

### Drivers

- GitHub [Issue #2](https://github.com/jnuyens/modulejail/issues/2)
  (bpmartin20) — external whitelist persistence ask.
- Vincent Homans (email feedback, 2026-05-13) — syslog visibility ask and
  modprobe-override-scope clarification ask.

## [1.1.4] - 2026-05-13

### Added

- Project logo on the README.

### Changed

- Container fixture is version-agnostic (no longer hardcoded to `1.0.0`
  strings) and gains four new assertions covering the v1.1.x update-check
  surface, including a static regression guard against the v1.1.2
  busybox-wget bug.

## [1.1.3] - 2026-05-13

### Fixed

- Update check now works on Alpine / busybox wget. The wget invocation used
  GNU long-form flags (`--quiet`, `--max-redirect=5`, `--output-document=-`)
  that busybox wget rejects, causing the check to silently exit non-zero on
  every Alpine host. Switched to the universal short-flag subset
  (`-q`, `-T 10`, `-O -`) and dropped `--max-redirect` (the GitHub tags API
  does not redirect).

## [1.1.2] - 2026-05-12

### Added

- `modulejail(8)` manpage, installed at `/usr/share/man/man8/modulejail.8.gz`.

## [1.1.1] - 2026-05-12

### Changed

- Swap the order of `Why?` and `What ModuleJail is` in the README so the
  motivation leads.
- Drop the per-distro `%dist` suffix from the RPM filename (was
  `modulejail-X.Y.Z-1.el9.noarch.rpm`, now `modulejail-X.Y.Z-1.noarch.rpm`).
  ModuleJail is a noarch shell script with no per-major-RHEL semantics.

## [1.1.0] - 2026-05-12

### Added

- `.deb` and `.rpm` packaging under `packaging/` with
  `packaging/build.sh` driver.
- Optional post-run check for a newer release on GitHub: silent on any
  failure mode, 10-second hard timeout, only complains when reachable and a
  newer tag exists. Honours `MODULEJAIL_NO_UPDATE_CHECK=<any non-empty>`
  to disable.

## [1.0.1] - 2026-05-12

### Changed

- Documentation cleanup release.

## [1.0.0] - 2026-05-12

### Added

- Initial release. Single POSIX shell script that snapshots
  `/proc/modules`, walks `/lib/modules/$(uname -r)`, computes the complement
  against a built-in baseline plus the sysadmin `WHITELIST`, and writes a
  `modprobe.d` blacklist file.
- Three baseline profiles (`minimal`, `conservative`, `desktop`).
- SemVer `VERSION` constant; sysexits.h-aligned exit codes
  (`64`, `66`, `70`, `71`, `73`, `77`).
- Deterministic SHA-256 fingerprint header — byte-identical idempotency on
  identical inputs.
- Cross-distro support (Debian/Ubuntu, RHEL/Rocky/Fedora, Arch, Alpine,
  openSUSE) with no per-distro code branches.
- Container fixture harness (`tests/run-fixtures.sh`) and SSH-host
  acceptance harness (`tests/run-ssh-hosts.sh`).
- GPL-3.0-only license.

[1.2.0]: https://github.com/jnuyens/modulejail/releases/tag/v1.2.0
[1.1.4]: https://github.com/jnuyens/modulejail/releases/tag/v1.1.4
[1.1.3]: https://github.com/jnuyens/modulejail/releases/tag/v1.1.3
[1.1.2]: https://github.com/jnuyens/modulejail/releases/tag/v1.1.2
[1.1.1]: https://github.com/jnuyens/modulejail/releases/tag/v1.1.1
[1.1.0]: https://github.com/jnuyens/modulejail/releases/tag/v1.1.0
[1.0.1]: https://github.com/jnuyens/modulejail/releases/tag/v1.0.1
[1.0.0]: https://github.com/jnuyens/modulejail/releases/tag/v1.0.0
