# Changelog

All notable changes to ModuleJail are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
