---
phase: 03-site-config-syslog-visibility
plan: 02
subsystem: cli + render + tests
tags:
  - cli
  - observability
  - syslog
  - render
  - tests
requirements:
  - REQ-OBS-01
  - REQ-OBS-02
dependency_graph:
  requires:
    - phase-03 plan 01 (WHITELIST_FILE defaults block, EX_DATAERR=65, parse_whitelist_file helper, MODULEJAIL_MODULES_ROOT env override, --filter PATTERN mode, tests/lib/case-env.sh)
    - phase-02 stderr severity-prefix convention (OPS-03)
    - phase-02 sysexits.h taxonomy
  provides:
    - --no-syslog-logging CLI flag (D-31)
    - NO_SYSLOG_LOGGING + USE_LOGGER shell variables
    - emit_install_line() renderer helper (D-36)
    - generation-time logger detection (D-37)
    - "# install-line: ..." header annotation line (D-38) - 6-line header now 7-line
    - MODULEJAIL_LOGGER_PATH env override (test-only plumbing, parallel to MODULEJAIL_PROC_MODULES / MODULEJAIL_KVER / MODULEJAIL_MODULES_ROOT)
    - tests/cases/logger-default-on.sh, logger-opt-out.sh, logger-absent-fallback.sh
  affects:
    - plan 03-03 (release + regression fixture) - the v1.1.4 byte-identical contract (D-39) now needs both --no-syslog-logging AND a header-equivalence test (or a body-only diff), because the header gained one line in this plan
tech_stack:
  added: []
  patterns:
    - awk single-quote-roundtrip ('"'"'"'"' idiom) to emit literal single-quoted /bin/sh -c bodies in install lines
    - One-shot generation-time feature detection over per-eval-time probing (cleaner output, faster, D-37 rationale)
    - Test-only plumbing env vars to expose internal detection knobs to acceptance tests (MODULEJAIL_LOGGER_PATH joins the family)
    - Skip-not-fail for host-dependent positive paths (logger-default-on.sh skips when /usr/bin/logger is absent)
    - Byte-identity (cmp) as a regression invariant for opt-out and silent-fallback paths
key_files:
  created:
    - tests/cases/logger-default-on.sh
    - tests/cases/logger-opt-out.sh
    - tests/cases/logger-absent-fallback.sh
  modified:
    - modulejail
    - tests/cases/whitelist-file-happy.sh   # regex de-hardcoded from /bin/true (Rule 1)
    - tests/lib/run-in-fixture.sh           # step 8 regex extended to accept logger form (Rule 1)
decisions:
  - "MODULEJAIL_LOGGER_PATH was added as test-only plumbing in Task 1 (planner-allowed retroactive change per Task 2 action step 3): the alternative was a chroot or namespace, which would not work on the macOS dev box."
  - "Logger detection is one-shot at generation time (D-37): tested via [ -x \"${MODULEJAIL_LOGGER_PATH:-/usr/bin/logger}\" ]. The detection happens AFTER arg parse and BEFORE pre-flight, so NO_SYSLOG_LOGGING (if set) wins."
  - "Header annotation (D-38) sits BETWEEN the fingerprint line and the 'Do not edit' disclaimer. The 6-line header is now 7 lines. The annotation does NOT enter the fingerprint computation: fingerprint is a function of inputs (kernel, profile, loaded, baseline, whitelist), not render-time decisions. Verified live on ubuntu-wifi: both default and --no-syslog-logging runs produced the same sha256 fingerprint."
  - "Wave 1 assertions that hardcoded /bin/true (whitelist-file-happy.sh body grep; run-in-fixture.sh step 8 regex) were updated to be install-line-form-agnostic (Rule 1 - bug surfaced by this plan's intended behavior change). These belong in the same atomic commit as the feat change because they describe the same semantic change."
metrics:
  duration_minutes: 11
  files_created: 3
  files_modified: 3
  insertions: 249
  deletions: 11
  commits: 2
  test_cases_added: 3
  test_cases_passing: 3
completed_date: "2026-05-18"
---

# Phase 03 Plan 02: --no-syslog-logging + syslog-by-default install lines Summary

One-liner: Default-on syslog visibility for blocked modprobe attempts (D-36), with a one-flag opt-out (`--no-syslog-logging`) that restores the v1.1.4 install-line body for operators who need byte-identical regression contracts. Header annotation makes the chosen variant visible without entering the fingerprint.

## Diff Summary of `modulejail`

Seven coordinated changes per the plan, plus the test-only `MODULEJAIL_LOGGER_PATH` env override that the plan retroactively required for Task 2.

### Insertion points (per `<interfaces>`)

1. **Defaults block** — added `NO_SYSLOG_LOGGING=''` and `USE_LOGGER=''` immediately after the Plan-03-01-added `WHITELIST_FILE=''` line.

2. **Arg parser** — added the `--no-syslog-logging)` case branch after `--whitelist-file=*)`. Sets `NO_SYSLOG_LOGGING=1`. No value argument; the flag is binary.

3. **Logger detection** — placed AFTER profile validation, BEFORE pre-flight. The opt-out flag wins; otherwise, detection is `[ -x "${MODULEJAIL_LOGGER_PATH:-/usr/bin/logger}" ]`. The env override is documented inline as test-only plumbing parallel to `MODULEJAIL_PROC_MODULES` / `MODULEJAIL_KVER` / `MODULEJAIL_MODULES_ROOT`. End-user operators leave it unset.

4. **`emit_install_line()` helper** — placed immediately after `parse_whitelist_file()`. Branches on `USE_LOGGER`:
   - When `USE_LOGGER` is set (logger present, opt-out not set), emits the D-36 form:
     ```
     install <name> /bin/sh -c '/usr/bin/logger -t modulejail "blocked: <name>" 2>/dev/null; exit 0'
     ```
   - When `USE_LOGGER` is empty (opt-out OR logger absent), emits the v1.1.4 form:
     ```
     install <name> /bin/true
     ```
   Inline comment documents the awk single-quote-roundtrip idiom (`'"'"'"'"'` is the canonical sh idiom to land a literal single-quote inside an awk program inside a sh single-quoted string).

5. **Header writer** — inserted the install-line annotation BEFORE the disclaimer:
   ```
   if [ -n "$USE_LOGGER" ]; then
       printf '# install-line: /bin/sh + logger (syslog tag: modulejail)\n'
   else
       printf '# install-line: /bin/true (silent; --no-syslog-logging or logger absent)\n'
   fi
   ```
   The 6-line header is now 7 lines. Updated the inline comment from "Write 6-line header" to "Write 7-line header" and refreshed the rationale.

6. **Renderer** — replaced the hardcoded awk install-line emission with `emit_install_line "$blacklist"`.

7. **usage()** — documents `--no-syslog-logging` and `MODULEJAIL_LOGGER_PATH`.

### Wave 1 regression follow-ups (same commit)

- **tests/cases/whitelist-file-happy.sh** — three grep patterns that hardcoded `/bin/true` were widened to `^install <name> ` (no body match). The test's purpose is "module is in/out of the keep-set", not "install-line body is `/bin/true`".
- **tests/lib/run-in-fixture.sh step 8** — the modprobe.d-syntactic-validity regex was extended to accept the logger form alongside `/bin/true`.

Both regressions are direct semantic consequences of the install-line form changing; they ride along in the same `feat(03-02): ...` commit to keep the contract atomic.

## `./modulejail --help` snippet (both v1.2 flags + new env)

```
Options:
  -p, --profile {minimal|conservative|desktop}
                    Built-in baseline profile (default: conservative)
  -o, --output PATH Output path for the generated blacklist file
                    (default: /etc/modprobe.d/modulejail-blacklist.conf)
  --whitelist-file PATH
                    Append module names from PATH to the keep-set.
                    One module per line; '#' starts a comment.
                    File must not be group- or world-writable.
  --no-syslog-logging
                    Force '/bin/true' install lines (v1.1.4 behavior).
                    By default, when /usr/bin/logger is present, blocked
                    module loads are logged to syslog with tag 'modulejail'.
  -V, --version     Show program version and exit
  -h, --help        Show this help text and exit
...
Environment:
  MODULEJAIL_NO_UPDATE_CHECK   Set to any non-empty value to skip the post-run
                               check for a newer release on GitHub.
  MODULEJAIL_LOGGER_PATH       Path to the logger binary used for the syslog
                               install-line detection (default: /usr/bin/logger).
                               Test-only plumbing; end-user operators leave unset.
```

## Sample Generated File Headers (both install-line forms)

### Default form (logger present)

```
# modulejail 1.1.4
# https://github.com/jnuyens/modulejail
# profile: conservative
# kernel: 6.8.0-110-generic
# fingerprint: sha256:e284ee9741eb544adf1af6c0fffc162dedd6029191673237a8155cd497908686
# install-line: /bin/sh + logger (syslog tag: modulejail)
# Do not edit by hand — regenerate with modulejail(8).
install 104_quad_8 /bin/sh -c '/usr/bin/logger -t modulejail "blocked: 104_quad_8" 2>/dev/null; exit 0'
install 3c574_cs /bin/sh -c '/usr/bin/logger -t modulejail "blocked: 3c574_cs" 2>/dev/null; exit 0'
```

### Opt-out form (--no-syslog-logging)

```
# modulejail 1.1.4
# https://github.com/jnuyens/modulejail
# profile: conservative
# kernel: 6.8.0-110-generic
# fingerprint: sha256:e284ee9741eb544adf1af6c0fffc162dedd6029191673237a8155cd497908686
# install-line: /bin/true (silent; --no-syslog-logging or logger absent)
# Do not edit by hand — regenerate with modulejail(8).
install 104_quad_8 /bin/true
install 3c574_cs /bin/true
```

**Fingerprints match across the two runs on identical inputs** — verified live on ubuntu-wifi. The install-line annotation is a render-time decision; the fingerprint is over inputs only.

## `tests/run-fixtures.sh --filter logger` Output

```
modulejail tests: host-local case run (filter=logger)

-- tests/cases/logger-absent-fallback.sh --
[logger-absent-fallback] PASS

-- tests/cases/logger-default-on.sh --
[logger-default-on] PASS

-- tests/cases/logger-opt-out.sh --
[logger-opt-out] PASS

modulejail tests: 3/3 case(s) PASSED.
```

## `tests/run-fixtures.sh --filter whitelist-file` Output (Wave 1 regression)

```
modulejail tests: host-local case run (filter=whitelist-file)

-- tests/cases/whitelist-file-bad-name.sh --
[whitelist-file-bad-name] PASS

-- tests/cases/whitelist-file-bad-perms.sh --
[whitelist-file-bad-perms] PASS

-- tests/cases/whitelist-file-comments-and-blanks.sh --
[whitelist-file-comments-and-blanks] PASS

-- tests/cases/whitelist-file-happy.sh --
[whitelist-file-happy] PASS

-- tests/cases/whitelist-file-missing.sh --
[whitelist-file-missing] PASS

modulejail tests: 5/5 case(s) PASSED.
```

## Live Syslog Test on ubuntu-wifi

The plan's `<verification>` block #3 (live syslog visibility) ran end-to-end against the `ubuntu-wifi` host (Ubuntu 24.04 with systemd-journald, util-linux logger at `/usr/bin/logger`):

```
$ scp modulejail ubuntu-wifi:/tmp/mj-test
$ ssh ubuntu-wifi 'sudo /tmp/mj-test -o /tmp/mj-test.conf'
modulejail: blacklisted 6363 of 6474 modules (profile=conservative) -> /tmp/mj-test.conf

$ ssh ubuntu-wifi 'head -7 /tmp/mj-test.conf'
# modulejail 1.1.4
# https://github.com/jnuyens/modulejail
# profile: conservative
# kernel: 6.8.0-110-generic
# fingerprint: sha256:e284ee9741eb544adf1af6c0fffc162dedd6029191673237a8155cd497908686
# install-line: /bin/sh + logger (syslog tag: modulejail)
# Do not edit by hand — regenerate with modulejail(8).

$ ssh ubuntu-wifi 'sudo cp /tmp/mj-test.conf /etc/modprobe.d/modulejail-test.conf'
$ ssh ubuntu-wifi 'sudo modprobe vfio_pci 2>&1; sleep 1; journalctl -t modulejail --since "30 seconds ago" -o cat'
modprobe: ERROR: could not insert 'vfio_pci': Unknown symbol in module, or unknown parameter (see dmesg)
blocked: irqbypass
blocked: iommufd
```

Two of `vfio_pci`'s dependencies (`irqbypass`, `iommufd`) are blacklisted; the modprobe attempt fired their install lines, which executed `logger -t modulejail "blocked: <name>"`, and `journalctl -t modulejail` captured both. This is the exact D-36 behavior: operator runs `modprobe X` and gets a syslog trail of which dependency was blocked, no extra tooling required.

The opt-out path was also exercised live:

```
$ ssh ubuntu-wifi 'sudo /tmp/mj-test --no-syslog-logging -o /tmp/mj-nosys.conf'
$ ssh ubuntu-wifi 'head -7 /tmp/mj-nosys.conf'
# modulejail 1.1.4
# https://github.com/jnuyens/modulejail
# profile: conservative
# kernel: 6.8.0-110-generic
# fingerprint: sha256:e284ee9741eb544adf1af6c0fffc162dedd6029191673237a8155cd497908686
# install-line: /bin/true (silent; --no-syslog-logging or logger absent)
# Do not edit by hand — regenerate with modulejail(8).
install 104_quad_8 /bin/true
install 3c574_cs /bin/true
```

Same fingerprint, different install-line variant, different body.

## Commits

| # | Hash      | Type | Summary                                                            |
|---|-----------|------|--------------------------------------------------------------------|
| 1 | `ba74369` | feat | syslog-by-default install lines + --no-syslog-logging opt-out      |
| 2 | `d76d5b4` | test | logger install-line acceptance cases (default-on/opt-out/absent)   |

Both commits are on `worktree-agent-ae575df431225d54d`, branched from `c538c99` (master HEAD after Plan 03-01 merge).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Task 1 verify regex did not match the retroactive env-override**

- **Found during:** Task 1
- **Issue:** The Task 1 `<verify>/<automated>` block grep'd for `'\[ -x /usr/bin/logger \]'` (the bare interface form). The plan's Task 2 explicitly says to update Task 1 retroactively to use `[ -x "${MODULEJAIL_LOGGER_PATH:-/usr/bin/logger}" ]` to enable the absent-fallback test case. The Task 1 verify regex was not updated to match. The plan text is internally consistent (Task 2 action step 3 spells out the retroactive update), the verify command alone is stale.
- **Fix:** Implemented the retroactive form. The plan's Task 1 verify is a stale planner artifact; the live behavior matches the plan's own retroactive spec. Documented in this Summary.
- **Files modified:** modulejail (logger-detection block)
- **Commit:** `ba74369`

**2. [Rule 1 - Bug] Wave 1 whitelist-file-happy regex hardcoded `/bin/true`**

- **Found during:** Task 1 verification (running --filter whitelist-file after Task 1 changes)
- **Issue:** `tests/cases/whitelist-file-happy.sh` had three grep patterns of the form `^install <name> /bin/true$`. The test's stated intent is "module IS / IS NOT in the keep-set", but the assertion conflated that with "install-line body is /bin/true specifically". With default-on logger emission, the body is now /bin/sh + logger form, so the grep returned no matches and the sanity check `! grep -qE '^install dummy_[0-9]+ /bin/true$'` flipped the case from PASS to FAIL. This is a Wave 1 regression that the plan's success criteria explicitly forbids.
- **Fix:** Replaced `/bin/true$` with the install-line-agnostic `^install <name> ` pattern. The test now asserts "the module appears (or does not appear) as an install line", regardless of body form. Reasoning: keep-set semantics, not body form, is what the case is testing.
- **Files modified:** tests/cases/whitelist-file-happy.sh
- **Commit:** `ba74369`

**3. [Rule 1 - Bug] Distro fixture step 8 regex hardcoded `/bin/true`**

- **Found during:** Task 1 verification (static reading of run-in-fixture.sh after the install-line change)
- **Issue:** `tests/lib/run-in-fixture.sh` step 8 used `grep -Evc '^#|^install [a-zA-Z0-9_]+ /bin/true$|^$'` to count syntactically invalid body lines. Under default-on logger emission inside the Arch/Alpine/openSUSE fixtures (all three ship /usr/bin/logger), every body line would now be a logger-form install line and the regex would report every body line as "invalid", failing the assertion. The bug was not yet observable because the dev box has no container runtime — but it would break every future fixture run on a Linux CI host.
- **Fix:** Extended the regex to accept both forms:
  - v1.1.4 form: `^install [a-zA-Z0-9_]+ /bin/true$`
  - logger form: `^install [a-zA-Z0-9_]+ /bin/sh -c .*logger -t modulejail.*; exit 0.*$`
- **Files modified:** tests/lib/run-in-fixture.sh
- **Commit:** `ba74369`

### Authentication Gates

None for the worktree-local work. The live syslog test on ubuntu-wifi used an existing SSH alias with passwordless sudo (per the user's MEMORY entry); no new credentials were provisioned.

### Deferred Issues

**Pre-existing SC1091 on tests/lib/run-in-fixture.sh** — shellcheck emits an info-level SC1091 ("Not following: tests/lib/assert.sh was not specified as input") because the script sources `/tests/lib/assert.sh` (an absolute container-internal path) rather than a relative path. This is intentional (the script runs inside per-distro fixture containers where the path is correct), but shellcheck cannot resolve it. SC1091 is severity "info"; the project's `shellcheck --shell=sh` invocation includes it. Wave 1's plan did not address it either. Out of scope for Plan 03-02 (this plan modified the file but did not change the source line). Recommend adding `# shellcheck source=/dev/null` or `disable=SC1091` in a future cleanup.

## v1.1.4 Regression Contract (D-39)

This plan's `--no-syslog-logging` flag produces a body byte-identical to v1.1.4. The full file is NOT byte-identical: the header gained one line (`# install-line: ...` annotation, D-38) which v1.1.4 does not have. The plan's D-39 spec ("byte-identical to v1.1.4 when run with the same inputs on the same host") was written before D-38 was finalized; the rigorous regression fixture in Plan 03-03 must therefore compare the body (post-header), not the full file.

Logger-absent-fallback case 3 verifies the matching invariant within the v1.2 surface: a MODULEJAIL_LOGGER_PATH=/nonexistent run is byte-identical (full file, via cmp) to a --no-syslog-logging run on the same host with the same inputs. This is the D-40 silent-fallback contract.

The fully-rigorous archived-v1.1.4-fixture comparison is deferred to Plan 03-03 as noted in that plan's frontmatter.

## What This Plan Did NOT Wire

- **VERSION bump to 1.2.0** is NOT here. `VERSION='1.1.4'` remains unchanged. The bump lands in Plan 03-03 along with packaging + tag.
- **README / manpage updates** are NOT here. Documentation lands in Plan 03-03 alongside the release.
- **Archived v1.1.4 regression fixture** is NOT here. Plan 03-03's responsibility.

## Self-Check: PASSED

Verified all artifacts created/modified by this plan exist and all commits are recorded:

- `modulejail` — FOUND (modified in `ba74369`)
- `tests/cases/whitelist-file-happy.sh` — FOUND (modified in `ba74369`)
- `tests/lib/run-in-fixture.sh` — FOUND (modified in `ba74369`)
- `tests/cases/logger-default-on.sh` — FOUND (created in `d76d5b4`)
- `tests/cases/logger-opt-out.sh` — FOUND (created in `d76d5b4`)
- `tests/cases/logger-absent-fallback.sh` — FOUND (created in `d76d5b4`)
- Commit `ba74369` — FOUND (`git log --oneline`)
- Commit `d76d5b4` — FOUND (`git log --oneline`)

All success criteria met:

- [x] Both tasks executed
- [x] Each atomic commit landed (2 total: feat + test)
- [x] No modifications to STATE.md or ROADMAP.md (orchestrator-owned)
- [x] `shellcheck --shell=sh modulejail` exits 0
- [x] `sh -n modulejail` exits 0
- [x] `tests/run-fixtures.sh --filter logger` passes 3/3
- [x] `tests/run-fixtures.sh --filter whitelist-file` still passes 5/5 (Wave 1 regression)
- [x] Live syslog test on ubuntu-wifi produced `modulejail: blocked: <name>` entries
