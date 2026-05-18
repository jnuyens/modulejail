# Changelog

All notable changes to ModuleJail are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] - 2026-05-18

Bundled cleanup pass discharging four Phase 3 review WARNINGs, four
cosmetic INFO items, and the three v1.0.0 audit carry-forward items.
No new features, no UX changes.

### Fixed

- **WR-01:** `parse_whitelist_file` now propagates real `awk` failures
  to a typed sysexits exit code under `set -eu`. Previously the
  `_awk_status=$?; if [ ... ne 0 ]; then exit $EX_DATAERR; fi` tail was
  dead code: `set -eu` aborts the shell at the `awk` line on any
  non-zero awk exit, before the `if` can run. The new shape brackets
  the `awk` call with `set +e` / `set -e`, captures `rc=$?`, and
  routes 65 to `EX_DATAERR` (the documented data-error path) and any
  other non-zero exit to `EX_OSERR` (awk-internal failure: OOM,
  signal, future program-edit syntax error). Fleet automation
  case-splitting on sysexits codes now reads correctly.
- **WR-02 / CR-01-v1.0.0:** `tests/run-ssh-hosts.sh` now classifies
  unreachable hosts as `UNREACHED` (harness exit 2) instead of
  mis-counting them as `OVERALL_FAIL` (exit 1). The pre-fix shape
  `if ! run_host ...; then rc=$?` captured the inverted-condition
  `!` exit (always 0 inside the `then` branch under POSIX `/bin/sh`,
  dash, and bash), so the rc=2 dispatch was dead. Replaced with
  `set +e; run_host ...; rc=$?; set -e; case "$rc" in ...`. The
  documented exit-code contract on lines 33-37 is now actually
  enforced.
- **IN-01:** Header-annotation byte string aligned to the D-38 spec's
  comma form (was a semicolon in the implementation): `# install-line:
  /bin/true (silent, --no-syslog-logging or logger absent)`. Edited
  in modulejail, the manpage, the README, and the two logger test
  cases that asserted the byte string.
- **IN-02:** Whitelist-file lines may now carry leading whitespace.
  The `awk` validator strips leading whitespace symmetric with the
  existing trailing-whitespace strip before the canonical-regex check,
  so an indented module name (e.g. `  vfio_pci` copy-pasted from a
  YAML or other indented source) is accepted rather than rejected as
  `EX_DATAERR`.
- **WR-03 v1.0.0 / IN-01 v1.0.0:** README.md audited against the two
  v1.0.0 carry-forward items. The dependency list at line 122-123
  already named `comm` correctly (closes WR-03 v1.0.0); the stale
  "420 lines" claim from the original v1.0.0 audit has been removed
  from the README (the script has grown to ~750 lines and the claim
  invites future rot — replaced with a qualitative phrasing).

### Security

- **WR-03 (Phase 3) defense-in-depth:** `list_universe` and
  `list_loaded` now filter their output to the canonical kernel-module
  regex `^[a-zA-Z0-9_]+$` before names can reach `emit_install_line`.
  Severity: medium; not user-reachable today without root-equivalent
  write access to `/lib/modules/$(uname -r)/`. Closes the documented
  "strict regex is the gate" contract for both the `--whitelist-file`
  path (already gated by `parse_whitelist_file`) AND the filesystem-
  walk path (previously un-gated). Pre-fix reproduction: a `.ko*` file
  under `/lib/modules/$KVER/` with a single quote in its basename
  flowed unescaped into the generated install line, breaking the
  shell-quoting of the logger form (`install evil'name /bin/sh -c
  '/usr/bin/logger ...'`) and causing `modprobe` to evaluate
  syntactically malformed shell at module-load time. New regression
  test `tests/cases/emit-install-line-sanitize.sh` feeds three
  adversarial characters (single quote, `$IFS`, whitespace) through
  the full pipeline under both install-line forms and asserts the
  generated file contains none of those characters in any install-
  line module-name token.

### Changed

- **WR-05:** `tests/run-fixtures.sh` with no flags now ALWAYS runs
  every host-local case under `tests/cases/*.sh` (15 cases as of
  v1.2.1). The container distro matrix (arch, alpine, opensuse) is
  additive when a docker or podman runtime is available. Pre-fix, the
  no-container-runtime path exited 77 without running anything, so
  the host-local cases under `tests/cases/` (whitelist-file-*,
  logger-*, v1.1.4-regression) were silently skipped on every
  developer-laptop invocation.

### Added

- `tests/cases/ssh-unreachable-regression.sh`: regression guard for
  the WR-02 / CR-01-v1.0.0 SSH-host harness exit-code routing fix.
  Drives the harness against a guaranteed-unreachable host
  (`unreachable-modulejail-test-host.invalid`, RFC 2606 reserved
  TLD), asserts harness exit 2 and `UNREACHABLE` SUMMARY token.
  Hermetic: no real SSH server, no `~/.ssh/config` dependency, no
  sudo; total wall-clock <100ms on the dev box.
- `tests/cases/emit-install-line-sanitize.sh`: regression guard for
  the WR-03 (Phase 3) defense-in-depth filter. Builds a synthetic
  `/lib/modules/$KVER/kernel/` tree with three adversarial `.ko`
  basenames, runs `modulejail` under both install-line forms, asserts
  the generated blacklist contains no adversarial characters in any
  install-line module-name token. Mutation-tested against a pre-T-04
  `modulejail` (filter absent): correctly FAILs with diagnostic dumps
  showing the leaked install lines.

### Deferred (with rationale)

- **IN-03** (case-env.sh duplication in v1.1.4-regression.sh):
  v1.1.4-regression's open-coded REPO_ROOT/CASE_TMP/trap boilerplate
  is kept. Refactoring case-env.sh to support a `CASE_ENV_NO_UNIVERSE`
  opt-out would touch the contract used by all 13 other host-local
  cases, for the marginal benefit of ~20 fewer duplicated lines in
  the one case whose synthetic-tree needs are wildly different (6474
  sharded files vs. ~63 hand-listed). The v1.1.4-regression case is
  the safety contract for the whole phase; isolating its open-coded
  boilerplate is the lower-risk choice.
- **IN-04** (hardcoded dates in manpage and rpm spec): `__DATE__`
  substitution not plumbed. The rpm spec changelog inherently needs
  a manual per-release edit (new top changelog block; prior entries
  must NOT change), so `__DATE__` saves nothing there. The manpage
  `.TH` line could use `__DATE__` cleanly but it saves no release-
  checklist step (the human still has to bump VERSION and write
  CHANGELOG.md). Recorded as a release-checklist item: on every
  release bump `man/modulejail.8.in:7` `.TH` date and add a new
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
  form and the module was blacklisted anyway. Caught by the v1.2 code-review
  gate before release.

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
