---
phase: 03-site-config-syslog-visibility
plan: 01
subsystem: cli + config + tests
tags:
  - cli
  - config
  - security
  - validation
  - tests
requirements:
  - REQ-CFG-01
  - REQ-CFG-02
dependency_graph:
  requires:
    - phase-02 sysexits.h taxonomy (EX_USAGE, EX_NOINPUT, EX_NOPERM, EX_OSERR)
    - phase-02 stderr severity-prefix convention (OPS-03)
    - phase-02 list_whitelist / list_baseline helper style
  provides:
    - --whitelist-file PATH CLI flag (D-30)
    - parse_whitelist_file() helper (validation gate)
    - EX_DATAERR=65 constant in the sysexits.h block
    - MODULEJAIL_MODULES_ROOT env override (test-only plumbing)
    - tests/cases/ directory + host-local --filter PATTERN mode
  affects:
    - plan 03-02 (logger install line) - shares the keep-set pipeline
    - plan 03-03 (release + regression fixture) - depends on REQ-CFG-* shipped here
tech_stack:
  added: []
  patterns:
    - awk-based line-numbered input validation (mirrors find-stderr-gate pattern from Phase 2)
    - POSIX-portable octal mode parsing via string-digit inspection (no $((8#$x)))
    - Helper-outside-pipeline pattern to make exit codes propagate (no pipefail in POSIX)
    - EXIT trap with explicit `return 0` to avoid clobbering exit code
key_files:
  created:
    - tests/cases/whitelist-file-happy.sh
    - tests/cases/whitelist-file-bad-perms.sh
    - tests/cases/whitelist-file-bad-name.sh
    - tests/cases/whitelist-file-missing.sh
    - tests/cases/whitelist-file-comments-and-blanks.sh
    - tests/lib/case-env.sh
  modified:
    - modulejail
    - tests/run-fixtures.sh
decisions:
  - "EX_DATAERR=65 inserted in numeric order between EX_USAGE=64 and EX_NOINPUT=66 (NOT between EX_NOINPUT and EX_SOFTWARE as the plan text said - that was a planner typo; the plan's own stated rationale 'numeric order matches sysexits.h' agreed with our placement)"
  - "Mode parsing uses POSIX-portable string-digit inspection on the last three octal digits, not bash's $((8#$mode)) form (which triggers shellcheck SC3052 under --shell=sh)"
  - "parse_whitelist_file is called OUTSIDE the merge pipeline; its output is captured to $workdir/whitelist-file.txt and then merged with list_whitelist via sort -u. POSIX /bin/sh has no pipefail, so an exit inside an LHS-of-pipe is otherwise swallowed."
  - "Added MODULEJAIL_MODULES_ROOT env override (defaulting to /lib/modules) so host-local cases on macOS dev box can exercise the full pipeline without a writable /lib/modules"
metrics:
  duration_minutes: 10
  files_created: 6
  files_modified: 2
  insertions: 513
  deletions: 10
  commits: 3
  test_cases_added: 5
  test_cases_passing: 5
completed_date: "2026-05-18"
---

# Phase 03 Plan 01: --whitelist-file flag with strict validation Summary

One-liner: Added `--whitelist-file PATH` to modulejail with mode-gate + strict-regex validation, line-numbered awk error messages, sysexits.h-accurate exit codes, and five host-local POSIX shell test cases covering every code path.

## Diff Summary of `modulejail`

Five insertion points plus one pre-existing-bug fix and one POSIX-correctness restructure.

### Insertion points (per `<interfaces>`)

1. **sysexits.h block** — added `EX_DATAERR=65` between `EX_USAGE=64` and `EX_NOINPUT=66` (numeric order; see Deviations Rule 1 below). Updated the leading comment to list `65=dataerr`.

2. **Defaults block** — added `WHITELIST_FILE=''` immediately after `output=...`.

3. **Arg parser** — added `--whitelist-file)` and `--whitelist-file=*)` case branches after `-o|--output`, both with EX_USAGE rejection on missing/empty PATH.

4. **Helper definition** — added `parse_whitelist_file()` immediately after `list_whitelist()`. Mirrors the existing list_* helpers' style and conventions. Validation gates:
   - missing/unreadable → EX_NOINPUT (66)
   - group- or world-writable → EX_NOPERM (77) with chmod hint
   - any non-comment, non-blank line that doesn't match `^[a-zA-Z0-9_-]+$` → EX_DATAERR (65), with file path + line number + offending content in stderr.
   - Lines starting with `#` and blank/whitespace-only lines are silently skipped (D-32).
   - CRLF line endings tolerated (strips trailing `\r`).

5. **Pipeline** — replaced the single-line `list_whitelist > "$workdir/whitelist.txt"` with a two-step form: first `parse_whitelist_file "$WHITELIST_FILE" > "$workdir/whitelist-file.txt"` runs OUTSIDE any pipeline (so its exit codes propagate), then `{ list_whitelist; cat "$workdir/whitelist-file.txt"; } | sort -u > "$workdir/whitelist.txt"` merges.

6. **`list_universe` + pre-flight** — generalized the hardcoded `/lib/modules` to `${MODULEJAIL_MODULES_ROOT:-/lib/modules}` (new test-only plumbing env var; see Deviations Rule 3). Documented inline as parallel to MODULEJAIL_PROC_MODULES and MODULEJAIL_KVER.

7. **usage()** — documented `--whitelist-file PATH` in the Options block; added exit code `65 = invalid data in whitelist file` to the Exit codes block.

### EXIT-trap correctness fix (Rule 1 - pre-existing bug surfaced by this plan)

The cleanup() function used `[ -n "${tmp:-}" ] && rm -f "$tmp"` as its last command. When `tmp` is still empty (every error path before the render block), the `[ -n "" ]` test returns 1, the `&&` short-circuits, and under dash/POSIX /bin/sh the trap's non-zero exit CLOBBERS the script's `exit $EX_*` value, returning 1 instead. Rewrote as `if [ -n "${tmp:-}" ]; then rm -f "$tmp"; fi` plus an explicit trailing `return 0`. Documented inline so the gotcha does not regress.

This bug was latent before Plan 03-01: all of the existing `exit $EX_*` paths either fired before the trap was installed, or happened to be after `tmp` had been assigned a real value. Plan 03-01 introduced four new exit paths (parse_whitelist_file's EX_NOINPUT / EX_NOPERM / EX_DATAERR / EX_OSERR) all of which sit in the previously-untriggered region.

## `./modulejail --help` snippet (new flag)

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
  -V, --version     Show program version and exit
  -h, --help        Show this help text and exit
...
Exit codes:
  0   success
  64  command-line argument error (bad flag, missing value, unknown profile)
  65  invalid data in whitelist file (malformed module name)
  66  required kernel input missing (/proc/modules or /lib/modules/<kernel>)
  70  sanity guard tripped (empty blacklist or >99% of modules blacklisted)
  71  OS-level error (mktemp work dir, or find errors on /lib/modules)
  73  output path cannot be created (symlink/directory/trailing-slash, or mktemp failure)
  77  target directory not writable (try sudo, or use -o <other-path>)
```

## `tests/run-fixtures.sh --filter whitelist-file` output

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

## Commits

| # | Hash      | Type   | Summary                                                            |
|---|-----------|--------|--------------------------------------------------------------------|
| 1 | `a54dcba` | feat   | Add --whitelist-file flag, EX_DATAERR=65, parse_whitelist_file(), MODULEJAIL_MODULES_ROOT |
| 2 | `dc349cf` | fix    | Make whitelist-file rejection exit codes propagate (trap clobber + pipeline propagation) |
| 3 | `c587cec` | test   | Add five whitelist-file acceptance cases + host-local --filter runner |

All three commits are on `worktree-agent-aee9976278e9d52b6`, branched from `ccbd3e9` (master HEAD at execute time).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Numeric-order placement of EX_DATAERR=65**
- **Found during:** Task 1
- **Issue:** The plan said "Insert `EX_DATAERR=65` between `EX_NOINPUT=66` and `EX_SOFTWARE=70`". The accompanying rationale was "so the numeric order matches sysexits.h" — but 65 numerically belongs between 64 and 66, not between 66 and 70. The plan text contradicted its own rationale.
- **Fix:** Placed EX_DATAERR=65 between EX_USAGE=64 and EX_NOINPUT=66, in numeric order. Updated the leading comment to list `65=dataerr` in the canonical order.
- **Files modified:** modulejail (sysexits.h block)
- **Commit:** `a54dcba`

**2. [Rule 1 - Bug] POSIX-portable octal mode parsing**
- **Found during:** Task 1
- **Issue:** The plan's interface used `_mode_dec=$((8#$_mode))` for octal-to-decimal conversion. This is bash arithmetic base-conversion syntax; shellcheck SC3052 flags it under `--shell=sh` ("In POSIX sh, arithmetic base conversion is undefined") and the project's "no bashisms / pass shellcheck --shell=sh" constraint forbids it.
- **Fix:** Rewrote as string-digit inspection of the last three octal digits. Extract via `awk '{print substr($0, length($0)-2, 3)}'` then `cut -c2` / `cut -c3` for the group and world digits. A digit with the 2-bit set (write bit) is one of `2,3,6,7`; match via `case ... in *[2367]*)`. Verified against all common modes (644/664/666/600/700/0644/0664/0666/4755/2755). Pure POSIX, zero bashisms.
- **Files modified:** modulejail (parse_whitelist_file mode-gate)
- **Commit:** `a54dcba`

**3. [Rule 1 - Bug] parse_whitelist_file exit codes did not propagate**
- **Found during:** Task 2 (running the new cases)
- **Issue:** The plan's interface put `parse_whitelist_file` on the LHS of a pipe: `{ list_whitelist; parse_whitelist_file "$WHITELIST_FILE"; } | sort -u > $workdir/whitelist.txt`. POSIX /bin/sh has no `pipefail`, so any `exit $EX_*` inside the LHS is silently swallowed: the pipeline succeeds with whatever data leaked through to sort. The three rejection-path cases (bad-name, bad-perms, missing) all observed exit 0 instead of the expected sysexits codes.
- **Fix:** Run `parse_whitelist_file` BEFORE the merge pipeline, capturing its output to `$workdir/whitelist-file.txt`. Then merge with `list_whitelist` via `{ list_whitelist; cat $workdir/whitelist-file.txt; } | sort -u`. The helper's `exit $EX_*` calls now reach the top-level script.
- **Files modified:** modulejail (pipeline integration)
- **Commit:** `dc349cf`

**4. [Rule 1 - Bug] EXIT trap clobbered exit status (pre-existing)**
- **Found during:** Task 2 (after fix #3, the cases still got exit 1 instead of 65/66/77)
- **Issue:** Pre-existing latent bug in modulejail's cleanup function. The line `[ -n "${tmp:-}" ] && rm -f "$tmp"` returns 1 whenever `$tmp` is still empty (every error path between trap-install and the render-block mktemp). Under dash/POSIX /bin/sh, an EXIT trap whose last command exits non-zero CLOBBERS the script's `exit $EX_*` value with its own return code. Reproduced in a minimal test (`exit 65` from a script with a `&&`-using EXIT trap → outer exit code becomes 1, not 65). Plan 03-01 surfaced the bug because it introduced four new exit paths in the previously-untriggered region.
- **Fix:** Rewrote `[ ... ] && rm -f ...` as `if [ ... ]; then rm -f ...; fi`, then appended an explicit `return 0` to the cleanup function. Documented the gotcha inline (multi-line comment) so future edits do not regress. Verified: cases now observe exit 65/66/77 as expected.
- **Files modified:** modulejail (cleanup function)
- **Commit:** `dc349cf`

**5. [Rule 3 - Blocking] Added MODULEJAIL_MODULES_ROOT env override**
- **Found during:** Task 2 (before writing the cases)
- **Issue:** The plan's `<behavior>` says "All five cases pass when run via `tests/run-fixtures.sh` on the dev box (macOS)". But modulejail hardcoded `/lib/modules/$_kver` as the universe root; macOS has no `/lib/modules` at all, and pre-flight rejects with EX_NOINPUT before any whitelist-file code runs. Without a way to point modulejail at a synthetic kernel tree under a writable tempdir, the cases could only run inside a Linux container fixture, which contradicts the plan's stated dev-box runnable requirement.
- **Fix:** Added `MODULEJAIL_MODULES_ROOT` env override defaulting to `/lib/modules`, mirroring the existing test-only-plumbing pattern of `MODULEJAIL_PROC_MODULES` and `MODULEJAIL_KVER`. Documented inline as parallel to those. Modified both the pre-flight existence check and `list_universe`'s `find` invocation to honour it. End-user behavior is unchanged (operators leave it unset; default is `/lib/modules`).
- **Files modified:** modulejail (pre-flight + list_universe)
- **Commit:** `a54dcba`

**6. [Rule 3 - Blocking] tests/run-fixtures.sh --filter PATTERN mode**
- **Found during:** Task 2 (before writing the cases)
- **Issue:** The plan's verify block invokes `tests/run-fixtures.sh --filter whitelist-file`. The existing `run-fixtures.sh` was strictly a per-distro Docker fixture builder/runner with no `--filter`, no `tests/cases/` directory, no host-local mode. On macOS without colima/OrbStack, it exits 77 (skip) — so `--filter whitelist-file` would never reach the new cases.
- **Fix:** Added `--filter PATTERN` and `--filter=PATTERN` long-options to `run-fixtures.sh`. When set, the script bypasses Docker entirely, globs `tests/cases/PATTERN*.sh`, runs each case directly on the host (cases use MODULEJAIL_MODULES_ROOT to point at a synthetic tree), and reports a M/N PASSED summary. The default no-flag mode is unchanged (full distro matrix).
- **Files modified:** tests/run-fixtures.sh
- **Commit:** `c587cec`

### Authentication Gates

None. This is a pure-shell change inside the worktree; no external services, no credentials.

## v1.1.4 Regression Contract

Case 5 (`whitelist-file-comments-and-blanks.sh`) verifies a smaller surrogate for D-39: a run with a whitelist file containing only comments and blank lines produces an output that is byte-identical (`assert_cmp`) to a run without `--whitelist-file` at all. Because the fingerprint header is computed over the canonical-sorted whitelist content, byte-identical output proves the no-op file does not perturb the fingerprint.

The stronger, fully-rigorous v1.1.4 byte-identical regression test (an archived v1.1.4 fixture tarball with canned `/proc/modules` and baseline inputs, regenerated via `git checkout v1.1.4 -- modulejail` then `diff`) is **deferred to Plan 03-03** as explicitly noted in the plan's `<verification>` block. Plan 03-01 ships the necessary condition; Plan 03-03 supplies the sufficient one.

## What This Plan Did NOT Wire

- **`--no-syslog-logging`** is **NOT** wired in this plan. The `EX_DATAERR=65` constant, `--whitelist-file PATH`, and `parse_whitelist_file()` helper are all in place, but the logger install-line generation (D-36 / D-37 / D-38 / D-40) is deferred to Plan 03-02. Confirmed: `grep -c 'no-syslog-logging' modulejail` returns 0.
- **VERSION bump to 1.2.0** is **NOT** wired in this plan. `VERSION='1.1.4'` is unchanged. The bump is part of Plan 03-03's release work.
- **README / manpage updates** are **NOT** in this plan. Documentation lands in Plan 03-03 alongside the release.

## Self-Check: PASSED

Verified all artifacts created/modified by this plan exist and all commits are recorded:

- `modulejail` — FOUND (modified in `a54dcba`, `dc349cf`)
- `tests/run-fixtures.sh` — FOUND (modified in `c587cec`)
- `tests/lib/case-env.sh` — FOUND (created in `c587cec`)
- `tests/cases/whitelist-file-happy.sh` — FOUND
- `tests/cases/whitelist-file-bad-perms.sh` — FOUND
- `tests/cases/whitelist-file-bad-name.sh` — FOUND
- `tests/cases/whitelist-file-missing.sh` — FOUND
- `tests/cases/whitelist-file-comments-and-blanks.sh` — FOUND
- Commit `a54dcba` — FOUND (`git log --all`)
- Commit `dc349cf` — FOUND (`git log --all`)
- Commit `c587cec` — FOUND (`git log --all`)

All success criteria met:

- [x] Both tasks executed
- [x] Each atomic commit landed (3 total: feat + fix + test)
- [x] No modifications to STATE.md or ROADMAP.md (orchestrator-owned)
- [x] `shellcheck --shell=sh modulejail` exits 0
- [x] `sh -n modulejail` exits 0
- [x] `tests/run-fixtures.sh --filter whitelist-file` passes 5/5
