---
phase: 04-pre-release-cleanup
plan: 04-01
subsystem: hardening + regression + docs + cleanup
tags:
  - release
  - cleanup
  - regression
  - security
  - sanitization
  - sysexits
  - sh-harness
requirements:
  - REQ-CFG-01
  - REQ-CFG-02
  - REQ-OBS-01
  - REQ-OBS-02
dependency_graph:
  requires:
    - phase-03 plan 01 (--whitelist-file, parse_whitelist_file, --filter PATTERN mode, tests/lib/case-env.sh, 9 acceptance cases)
    - phase-03 plan 02 (--no-syslog-logging, USE_LOGGER, emit_install_line, # install-line header annotation, MODULEJAIL_LOGGER_PATH, 3 acceptance cases)
    - phase-03 plan 03 (VERSION='1.2.0', tests/fixtures/v1.1.4-regression/, CHANGELOG.md, run-ssh-hosts.sh auto-derived EXPECTED_VERSION)
    - v1.0.0 audit carry-forward items (CR-01 SSH-harness routing, WR-03 v1.0.0 README deps, IN-01 v1.0.0 line-count)
    - 03-REVIEW.md (4 WARNINGs + 4 INFOs across modulejail / run-ssh-hosts.sh / run-fixtures.sh / man+rpm)
  provides:
    - VERSION='1.2.1' (single source of truth, propagating to blacklist header line 1 + --version output)
    - parse_whitelist_file with typed-sysexits awk error routing (EX_DATAERR=65 for awk's data-error exit, EX_OSERR=71 for awk-internal failure)
    - list_universe + list_loaded canonical-name gate `^[a-zA-Z0-9_]+$` (defense-in-depth — closes the strict-regex-is-the-gate contract for the filesystem-walk path)
    - tests/run-ssh-hosts.sh with correct UNREACHED vs OVERALL_FAIL classification (closes WR-02 / CR-01-v1.0.0)
    - tests/cases/ssh-unreachable-regression.sh (WR-02 regression guard, hermetic via RFC 2606 .invalid TLD)
    - tests/cases/emit-install-line-sanitize.sh (WR-03 Phase 3 defense-in-depth guard, mutation-tested)
    - tests/run-fixtures.sh with unified host-local + container layers (closes WR-05 — host-local cases always run)
    - parse_whitelist_file leading-whitespace tolerance (closes IN-02)
    - header-annotation byte string aligned to D-38 comma form across modulejail, manpage, README, and 2 test cases (closes IN-01 Phase 3)
    - CHANGELOG.md v1.2.1 entry above v1.2.0
  affects:
    - downstream (user UAT + HUAT push): v1.2.0 and v1.2.1 annotated tags both remain user-driven push steps; this plan does NOT cut a tag or push to origin. The user runs `git push origin master && git push origin v1.2.0 v1.2.1` once UAT completes against ubuntu-wifi / debian13 / rocky9.
    - downstream (fleet automation): the SSH-host harness exit-code contract is now correctly enforced (0/1/2) — operators wiring run-ssh-hosts.sh into CI now get true UNREACHED vs FAILED signal separation.
    - downstream (operators on hosts with adversarial-name modules): the canonical-name filter blocks any badly-named .ko* file under /lib/modules from landing in a generated install line. Defense-in-depth, not user-reachable without root-equivalent write access today.
tech_stack:
  added: []
  patterns:
    - "set +e / call / rc=$? / set -e bracketing as the canonical idiom for capturing real return codes under set -eu — used in parse_whitelist_file's awk validator (T-01) and the SSH-host harness's run_host dispatch (T-02). The pattern was already present in run-ssh-hosts.sh's run_host body (lines 102-105, 151-154) — this phase makes it consistent across both files."
    - "RFC 2606 .invalid TLD as a hermetic 'guaranteed-unreachable' SSH target for harness regression tests. DNS-NXDOMAIN returns in ms; ConnectTimeout=10 caps worst-case wall-clock."
    - "Adversarial-filename test fixture pattern: build a synthetic /lib/modules/$KVER/kernel/ tree mixing canonical-name baseline padding with .ko basenames containing single quote, dollar+IFS, and whitespace; assert no adversarial chars survive into the generated install lines."
    - "Mutation-testing via `git revert --no-commit <fix-commit>` to confirm a new regression case actually guards the fix (validates the case under pre-fix code, then restores). Used to validate T-05 against the pre-T-04 modulejail."
    - "Unified host-local + container test discovery in tests/run-fixtures.sh: container matrix is now ADDITIVE to a mandatory host-local layer rather than the only layer in default mode. No container runtime is no longer fatal."
key_files:
  created:
    - tests/cases/ssh-unreachable-regression.sh
    - tests/cases/emit-install-line-sanitize.sh
    - .planning/phases/04-pre-release-cleanup/04-01-SUMMARY.md
  modified:
    - modulejail
    - CHANGELOG.md
    - README.md
    - man/modulejail.8.in
    - tests/run-ssh-hosts.sh
    - tests/run-fixtures.sh
    - tests/cases/logger-absent-fallback.sh
    - tests/cases/logger-opt-out.sh
decisions:
  - "WR-01 fix shape: `set +e; awk ...; rc=$?; set -e; case \"$rc\" in 0) ;; 65) exit $EX_DATAERR ;; *) exit $EX_OSERR ;; esac`. Chosen over the simpler `awk ... || exit $EX_DATAERR` shortcut because it lets us distinguish awk's documented data-error path (rc=65 -> EX_DATAERR) from genuine awk-internal failures (OOM, signal, future program-edit syntax error -> EX_OSERR). Fleet automation case-splitting on sysexits codes now reads correctly."
  - "WR-03 Phase 3 fix: filter applied in BOTH list_universe (after dash-to-underscore gsub) AND list_loaded (after /proc/modules column extraction), per the reviewer's symmetry guidance. No belt-and-suspenders filter inside emit_install_line — the upstream gate is sufficient and a downstream filter would duplicate the regex in three places with no behavioural benefit."
  - "T-04 invariant check: v1.1.4-regression body-identical diff was the live safety contract — running it after the filter edit confirmed 6363/6363 install lines unchanged (no legitimate kernel module is dropped by the new filter)."
  - "T-05 case uses open-coded REPO_ROOT/CASE_TMP/trap boilerplate (the same pattern v1.1.4-regression.sh uses) rather than case-env.sh, because the synthetic tree needs adversarial-name .ko files that case-env's standard fixture does not produce."
  - "WR-05 integration shape (c) from the reviewer's options: host-local cases ALWAYS run, container matrix runs ADDITIVELY when docker/podman is present, no-runtime path is no longer fatal. Aggregate FAIL/TOTAL counters cover both layers."
  - "T-03 / T-05 mutation-test protocol: documented inline at the top of each new regression case so a future reviewer can confirm the case actually guards the fix (git revert --no-commit <fix-commit>, re-run, observe FAIL, restore)."
  - "IN-01 (Phase 3) — semicolon-to-comma in the header annotation — turned into a five-place edit (modulejail + manpage + README + 2 test assertions) when the search for the byte string found it in more places than 03-REVIEW.md listed. All five updated to the comma form; the spec wins."
  - "IN-02 layered onto T-01's awk validator edit: leading-whitespace strip added one block above the existing trailing-whitespace strip, symmetric. Committed in T-07 alongside the other Phase 3 INFO items, not T-01 (kept T-01's commit purely about WR-01 sysexits routing)."
  - "IN-03 DEFERRED: v1.1.4-regression.sh keeps its open-coded boilerplate. Adding a CASE_ENV_NO_UNIVERSE opt-out to case-env.sh would change the contract used by all 13 other host-local cases, for the marginal benefit of ~20 fewer duplicated lines in the one case whose synthetic-tree needs are wildly different (6474 sharded files vs. ~63 hand-listed). The v1.1.4-regression case IS the safety contract for the whole phase; isolating its open-coded boilerplate is the lower-risk choice."
  - "IN-04 DEFERRED: __DATE__ substitution not plumbed because the rpm spec %changelog inherently requires a manual per-release edit (new top changelog block; prior entries' dates MUST NOT change). For the manpage .TH line a __DATE__ substitution would work cleanly but saves no release-checklist step. Recorded as a release-checklist item: on every release bump man/modulejail.8.in:7 .TH date and add a new packaging/rpm/modulejail.spec.in changelog block. For v1.2.1 specifically the date is unchanged (2026-05-18, same as v1.2.0) so no edit needed this release."
  - "v1.0.0 carry-forward items WR-03 and IN-01 are already-discharged before this phase: README.md:122-123 already names `awk, comm, find, sha256sum, and standard coreutils` (the script truly invokes none of grep/sed — verified by greps); README.md no longer contains any line-count claim (a pinned count would invite future rot)."
metrics:
  duration_minutes: 35
  files_created: 3
  files_modified: 8
  commits: 9
  tasks_completed: 9
  source_items_addressed: 11
  closed_with_edit: 5
  closed_with_test: 2
  already_discharged: 2
  deferred_with_rationale: 2
  test_cases_added: 2
  test_cases_passing: 15
  modulejail_lines_pre_phase: 734
  modulejail_lines_post_phase: 792
  v114_regression_body_diff: "byte-identical (6363/6363)"
completed_date: "2026-05-18"
---

# Phase 04 Plan 01: v1.2.1 pre-release cleanup Summary

One-liner: Bundled cleanup pass discharging four Phase 3 review WARNINGs (WR-01 awk-error handling, WR-02 SSH-harness exit-code routing, WR-03 emit_install_line sanitization, WR-05 host-local test discovery), four cosmetic INFO items (IN-01 comma-vs-semicolon, IN-02 leading-whitespace tolerance — closed; IN-03 case-env duplication, IN-04 hardcoded dates — deferred with rationale), and three v1.0.0 audit carry-forward items (CR-01 SSH-harness — closed via T-02; WR-03 v1.0.0 + IN-01 v1.0.0 README items — already-discharged). VERSION bumped 1.2.0 -> 1.2.1; CHANGELOG.md gains a 1.2.1 entry above 1.2.0; two new regression cases (ssh-unreachable-regression, emit-install-line-sanitize); v1.1.4-regression remains byte-identical body-diff PASS at 6363/6363 install lines throughout.

## Source-item disposition matrix

All ten source items enumerated in `must_haves.truths` + the three v1.0.0 carry-forward items mapped to their disposition:

| Item | Source | Disposition | Task | Evidence (file:line) |
| ---- | ------ | ----------- | ---- | -------------------- |
| WR-01 | 03-REVIEW.md:153-205 | closed-with-edit | T-01 | `modulejail:513-547` (set +e / awk / rc=$? / set -e bracket + case dispatch); `modulejail:452-471` (parse_whitelist_file leading-comment block updated with EX_OSERR=71 case) |
| WR-02 | 03-REVIEW.md:206-279 | closed-with-edit | T-02 | `tests/run-ssh-hosts.sh:60-66` (HOSTS env override); `tests/run-ssh-hosts.sh:164-181` (set +e / run_host / rc=$? / set -e / case dispatch) |
| WR-02 regression | 03-REVIEW.md:206-279 | closed-with-test | T-03 | `tests/cases/ssh-unreachable-regression.sh:1-111` (new file, 111 lines, mutation-test recipe embedded) |
| WR-03 (Phase 3) | 03-REVIEW.md:280-351 | closed-with-edit | T-04 | `modulejail:383-394` (list_universe canonical-name gate after dash-to-underscore: comment + `if (n !~ /^[a-zA-Z0-9_]+$/) next`); `modulejail:402-414` (list_loaded canonical-name gate on /proc/modules column 1: `awk '$1 ~ /^[a-zA-Z0-9_]+$/ {print $1}'`) |
| WR-03 (Phase 3) regression | 03-REVIEW.md:280-351 | closed-with-test | T-05 | `tests/cases/emit-install-line-sanitize.sh:1-246` (new file, exercises both install-line forms with 3 adversarial chars; mutation-tested against pre-T-04) |
| WR-05 | 03-REVIEW.md:383-431 | closed-with-edit | T-06 | `tests/run-fixtures.sh:1-31` (rewritten top-of-file invocation contract); `tests/run-fixtures.sh:84-147` (unified host-local + container layers, exit-77 only on no-cases-at-all) |
| IN-01 (Phase 3) | 03-REVIEW.md:432-458 | closed-with-edit | T-07 | `modulejail:679` (printf); `man/modulejail.8.in:277` (example); `README.md:316` (example); `tests/cases/logger-absent-fallback.sh:45` (assertion); `tests/cases/logger-opt-out.sh:26` (assertion) |
| IN-02 (Phase 3) | 03-REVIEW.md:460-484 | closed-with-edit | T-07 | `modulejail:520-527` (IN-02 comment + `{ sub(/^[[:space:]]+/, "") }` added before blank-line skip); `modulejail:455-460` (function comment block updated to document tolerance) |
| IN-03 (Phase 3) | 03-REVIEW.md:486-505 | deferred-with-rationale | T-07 | See decisions block above; CHANGELOG.md v1.2.1 entry "Deferred" subsection |
| IN-04 (Phase 3) | 03-REVIEW.md:507-525 | deferred-with-rationale | T-07 | See decisions block above; CHANGELOG.md v1.2.1 entry "Deferred" subsection |
| CR-01-v1.0.0 | v1.0.0-MILESTONE-AUDIT.md | closed-with-edit | T-02 | Same root cause as WR-02; same fix (`tests/run-ssh-hosts.sh:164-181`) |
| WR-03 v1.0.0 | v1.0.0-MILESTONE-AUDIT.md | already-discharged | T-09 | `README.md:122-123` already reads `awk, comm, find, sha256sum, and standard coreutils`; script invokes none of grep / sed (verified by `grep -vE "^\s*#" modulejail \| grep -E '\b(grep\|sed)\b'` returning empty) |
| IN-01 v1.0.0 | v1.0.0-MILESTONE-AUDIT.md | already-discharged | T-09 | `grep -nE "[0-9]{2,4} lines\|line.* POSIX\|line.* shell" README.md` returns empty — the stale "420 lines" claim was removed in an earlier (pre-Phase-4) edit |

## Per-task commits

All commits land on `master` (this plan does not branch). Each commit is atomic to a single task. Co-Authored-By trailers omitted per user's global preference.

| Task | Commit | Type | Files modified | Lines (+/-) |
| ---- | ------ | ---- | --- | --- |
| T-01 | `4d80ba7` | fix | modulejail | +27 / -3 |
| T-02 | `600ed95` | fix | tests/run-ssh-hosts.sh | +21 / -10 |
| T-03 | `5051e80` | test | tests/cases/ssh-unreachable-regression.sh (new, 111 lines) | +111 / -0 |
| T-04 | `8751994` | fix | modulejail | +22 / -1 |
| T-05 | `d18ac28` | test | tests/cases/emit-install-line-sanitize.sh (new, 246 lines) | +246 / -0 |
| T-06 | `52645cd` | fix | tests/run-fixtures.sh | +87 / -29 |
| T-07 | `48638d9` | fix | modulejail, README.md, man/modulejail.8.in, tests/cases/logger-absent-fallback.sh, tests/cases/logger-opt-out.sh | +18 / -5 |
| T-08 | `2a203ba` | chore | modulejail, CHANGELOG.md | +117 / -1 |
| T-09 | `04f5701` | docs | CHANGELOG.md | +7 / -5 |

Final commit (this SUMMARY): added separately after the per-task chain.

## Post-edit modulejail line count

```
$ wc -l < modulejail
792
```

(Pre-phase: 734; +58 net lines. All growth in defense-in-depth, error-routing, and explanatory comments; no behavioural change to the currently-loaded-keep safety invariant.)

## Host-local case results under new default tests/run-fixtures.sh

Run on macOS dev box (`darwin 25.4.0`, no container runtime present). All 15 host-local cases discovered and run; container matrix not exercised here (operator-side per the README contract).

```
$ sh tests/run-fixtures.sh 2>&1 | grep -E '^\[' | sort
[emit-install-line-sanitize] PASS                                       <- NEW (T-05)
[logger-absent-fallback] PASS
[logger-default-on] PASS
[logger-opt-out] PASS
[ssh-unreachable-regression] PASS                                       <- NEW (T-03)
[v1.1.4-regression] PASS (6363/6363 install lines body-identical ...)   <- safety contract
[whitelist-file-bad-name] PASS
[whitelist-file-bad-perms] PASS
[whitelist-file-comments-and-blanks] PASS
[whitelist-file-dash-form] PASS
[whitelist-file-default-opt-out] PASS
[whitelist-file-default-used] PASS
[whitelist-file-happy] PASS
[whitelist-file-missing] PASS
[whitelist-file-mutually-exclusive] PASS
```

15/15 green. Final harness summary line: `modulejail tests: 15/15 case(s) PASSED.`

## Safety invariants — preserved

- **v1.1.4-regression byte-identical body-diff:** PASS at 6363/6363 install lines after every single one of the 9 task commits. Verified after T-01 (whitelist parser refactor), T-04 (universe+loaded filter — the most behaviour-changing edit), T-06 (test-harness rework), T-07 (IN-02 whitelist tolerance + IN-01 byte string), and T-08 (VERSION bump). The case strips `^# modulejail `, `^# fingerprint:`, and `^# install-line:` before diff, so the IN-01 comma-vs-semicolon edit and the VERSION bump and any fingerprint drift are tolerated by design; everything else stays byte-identical.
- **Single-script invariant:** `modulejail` remains one POSIX `/bin/sh` file at repo root. No daemons, no build step, no language change. `sh -n modulejail` parses clean.
- **Currently-loaded-keep safety invariant:** `list_loaded()` still drives the keep-set via `awk` on `/proc/modules` column 1; the new T-04 canonical-name filter only rejects basenames that contain characters outside `[a-zA-Z0-9_]` — none of which are legal kernel module names. `comm -23 universe.txt keep.txt` still computes the blacklist. Verified end-to-end by the body-identical regression.

## Threat-flag scan

No new security-relevant surface introduced by this phase that is not already enumerated in `<threat_model>` of the plan. New attack-surface deltas (in plain terms):

- T-04 NARROWS the attack surface of the universe walker by dropping any basename outside `[a-zA-Z0-9_]` BEFORE it reaches `emit_install_line`. Net: defense-in-depth gain. No new threat surface added.
- T-02 fixes a misreporting bug in a test harness (`run-ssh-hosts.sh`) but does not change any production code path; no new threat surface.
- T-03 + T-05 add test cases only; no production code path affected.
- T-06 reworks a test harness only; no production code path affected.
- T-07 IN-02 widens the whitelist-file tolerance to accept indented entries; the canonical-name regex still gates content, so no relaxation of the safety contract.

## Authentication gates

None encountered during execution. The SSH-unreachable regression case (T-03) intentionally exercises a non-resolving hostname so no real SSH server contact occurs; the connectivity probe fails at DNS-NXDOMAIN. No secrets fetched; no auth prompts.

## Deviations from plan

- **T-08 + T-09 CHANGELOG coupling:** the plan structured T-08 as "draft CHANGELOG entry" and T-09 as "amend the carry-forward subsection". I drafted the carry-forward subsection inside T-08 (because the CHANGELOG body was a single coherent write at version-bump time), then in T-09 amended that subsection to reflect the final "already-discharged" disposition once the audit ran. Both commits are scoped purely to their declared file sets per the plan's commit-protocol.
- **IN-01 (Phase 3) scope drift:** the plan named modulejail:621 as the single edit site; `grep -nF "silent;" --include='*.sh' --include='*.in' --include='*.md' --include='modulejail' .` found five sites (modulejail, manpage, README, two logger test assertions). All five updated in T-07's single atomic commit. Recorded in T-07's commit message and the disposition table above.
- **T-01 / IN-02 split:** the plan T-07 instructions noted "if T-01 already touched this awk block, layer IN-02 on top". I initially added IN-02 alongside WR-01 in the T-01 edit, then backed it out to keep T-01's commit purely about sysexits routing, and re-added IN-02 in T-07. Net: cleaner per-task atomicity, no behavioural difference.
- **Mutation-test for T-05:** ran `git revert --no-commit 8751994` against the just-committed T-04 fix, re-ran T-05, observed the expected FAIL with the diagnostic `install dollar$IFS /bin/true` and `install evil'name /bin/true` lines (proving the case actually guards the fix), then `git revert --abort` restored. Recorded in T-05's commit message.

## Release HUAT items remaining (NOT executed by this plan)

This plan does NOT cut tags and does NOT push to origin. Two HUAT (human user acceptance + tag) steps remain for v1.2.0 and v1.2.1 together:

1. **HUAT v1.2.0** — the v1.2.0 annotated tag was cut locally in Phase 3 (Plan 03) but never pushed. User runs `git push origin master && git push origin v1.2.0` once UAT against live SSH hosts (ubuntu-wifi / debian13 / rocky9) completes.
2. **HUAT v1.2.1** — this plan does NOT cut the v1.2.1 annotated tag. User does so after reviewing the 9-commit chain in this plan:
   ```
   git tag -a v1.2.1 -m "v1.2.1: bundled cleanup pass — Phase 3 WARNINGs + INFO items + v1.0.0 carry-forward"
   git push origin v1.2.1
   ```

Both pushes are user-driven release gestures, not executor responsibilities, per the project's release contract (Phase 3 SUMMARY note + ROADMAP Phase 4 "no tag push" decision).

## Self-Check: PASSED

Files created (verified present):
- `tests/cases/ssh-unreachable-regression.sh` — FOUND (executable, 111 lines)
- `tests/cases/emit-install-line-sanitize.sh` — FOUND (executable, 246 lines)

Commits exist (verified in `git log`):
- T-01 `4d80ba7` — FOUND
- T-02 `600ed95` — FOUND
- T-03 `5051e80` — FOUND
- T-04 `8751994` — FOUND
- T-05 `d18ac28` — FOUND
- T-06 `52645cd` — FOUND
- T-07 `48638d9` — FOUND
- T-08 `2a203ba` — FOUND
- T-09 `04f5701` — FOUND
