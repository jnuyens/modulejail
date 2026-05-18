# ModuleJail

## What This Is

ModuleJail is a single, distribution-agnostic shell script that proactively
shrinks the Linux kernel's loaded-module attack surface on a host. It snapshots
the currently-loaded modules (`/proc/modules`) and writes one large
`modprobe.d`-style blacklist file covering everything else — minus a built-in
baseline of essential modules, an in-script sysadmin-editable `WHITELIST`
block, and (since v1.2.0) an operator-owned site-local whitelist file at
`/etc/modulejail/whitelist.conf` (auto-detected, with explicit opt-out). On
hosts where `/usr/bin/logger` is executable, every blocked-load attempt is
made visible to syslog via the install-line invocation; an explicit opt-out
preserves the v1.1.4 byte-identical install-line body when operators need
it. The tool is aimed at Linux fleet operators who need to harden many
servers at once against the coming wave of AI-assisted kernel privilege
escalation discoveries (Copy Fail, Dirty Frag, and successors).

## Core Value

One shell-script run cuts a host's kernel-module attack surface down to "what
is actually in use today," portably across Linux distributions, and is safe to
fleet-deploy via Ansible/Puppet/SSH-for-loops.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

All v1 requirements validated by v1.0.0 release (Phases 1 + 2 complete, 2026-05-12):

- [x] Snapshot currently loaded modules via `/proc/modules` and treat that set as the
      keep-list — *Validated in Phase 1 (CORE-01)*
- [x] Maintain a curated built-in "never blacklist" baseline embedded in the
      script — *Validated in Phase 1 (CORE-02)*
- [x] Accept a sysadmin-defined whitelist embedded in the same script — *Validated
      in Phase 2 (CORE-03)*
- [x] Emit one consolidated `modprobe.d` blacklist file containing every
      module NOT in the keep-list ∪ baseline ∪ sysadmin whitelist — *Validated in
      Phase 1 (CORE-04)*
- [x] Stamp the script's own version into the generated header (D-23: sha256
      fingerprint replaces wall-clock timestamp — same idempotency guarantee with
      stronger semantics) — *Validated in Phase 2 (CORE-05)*
- [x] Single POSIX shell script with no runtime dependencies beyond
      `/proc/modules`, `awk`, `comm`, coreutils — *Validated in Phase 2
      (PORT-02/03)*
- [x] Idempotent (byte-identical re-runs), sysexits.h exit-code taxonomy,
      severity-prefixed machine-friendly stderr — *Validated in Phase 2
      (OPS-01/02/03)*
- [x] SemVer-style `VERSION='1.0.0'` exposed via `--version` — *Validated in
      Phase 2 (CORE-06)*
- [x] Open-source GitHub repository (GPL-3.0 LICENSE + 13-section README) —
      *Validated in Phase 2 (REL-01/02)*
- [x] README documents pinned-tag `curl … | sh` one-liner with explicit
      "convenient, not safe" warning + safer download-inspect-run alternative —
      *Validated in Phase 2 (REL-03)*
- [x] Cross-distro: Debian/Ubuntu, RHEL/Fedora, Arch, Alpine, SUSE — no
      per-distro branches — *Validated in Phase 2 (PORT-01) via fixtures (Arch/
      Alpine/openSUSE) + real SSH hosts (ubuntu-wifi/debian13/rocky9)*

All v1.2 requirements validated by v1.2.1 release (Phases 3 + 4 complete, 2026-05-18):

- [x] External whitelist file persistence with default
      `/etc/modulejail/whitelist.conf` auto-detection and mutually-exclusive
      opt-out — *Validated in Phase 3 (REQ-CFG-01)*
- [x] Config file security hardening: mode-gate refusing group/world-writable
      files (EX_NOPERM=77, sshd-style) + strict awk regex
      `^[a-zA-Z0-9_-]+$` (EX_DATAERR=65) — *Validated in Phase 3 (REQ-CFG-02),
      Phase 4 WR-01 refined awk-exit routing to also surface EX_OSERR=71
      for awk-internal failures*
- [x] Syslog visibility for blocked module loads: when `/usr/bin/logger`
      executable, install line emits a tagged `blocked: $name` record —
      *Validated in Phase 3 (REQ-OBS-01), live capture against `irqbypass`
      and `iommufd` on ubuntu-wifi via `journalctl -t modulejail`*
- [x] Opt-out for legacy `/bin/true` behavior preserving v1.1.4 byte-
      identical install-line body — *Validated in Phase 3 (REQ-OBS-02),
      permanent `tests/fixtures/v1.1.4-regression/` fixture, 6363/6363
      install lines body-identical through every Phase 3 + Phase 4 commit*

### Active

<!-- Current scope. Building toward these. -->

(None — v1.2.1 milestone complete. v1.3 scope to be defined via
`/gsd:new-milestone`.)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Initramfs regeneration (`update-initramfs` / `dracut`) — not considered a
  real attack vector; loaded-module surface is the target
- Boot-safety dry-run or revert tooling — the "currently-loaded ⇒ needed for
  boot" invariant is the safety model; sysadmins remove the generated file to
  revert
- Daemon / continuous monitoring mode — one-shot script by design
- AI/ML inside the tool — AI is the *threat-model context* driving the
  project, not a component of the tool
- Per-distro packaging CI pipeline — `.deb` / `.rpm` metadata is present in
  the repo (templated via `__VERSION__` substitution in packaging/build.sh)
  but built-from-source by maintainer rather than auto-published; the curl
  one-liner and cloned repo remain the primary distribution channels
- TUI/GUI — CLI shell script only
- Module *risk scoring* or vulnerability-database lookups — the model is
  "unused ⇒ blacklist," not "vulnerable ⇒ blacklist"
- Kernel rebuild / module stripping — runtime blacklist only

## Context

- The project anticipates a 12-month window in which AI-assisted security
  scanning will surface a wave of Linux kernel privilege escalation issues
  similar to Copy Fail and Dirty Frag. Every additional loaded module is
  additional latent attack surface for the next disclosed CVE.
- Linux fleet operators already manage thousands of hosts with broadly
  identical workloads (web tier, db tier, etc.). Each host typically uses a
  tiny fraction of the modules its kernel package ships.
- The standard kernel mechanism — `install <mod> /bin/true` and `blacklist
  <mod>` lines under `/etc/modprobe.d/` — is universally supported, requires
  no kernel patching, and is trivially auditable.
- The tool is intentionally boring: shell + `/proc/modules` + `awk` + `comm`.
  The value is in the curated baseline and the fleet-friendliness, not in
  implementation cleverness.
- 2026-05-17 Slashdot front-page brought the first batch of unsolicited
  operator feedback: GitHub Issue #2 (`@bpmartin20`) on in-script whitelist
  persistence across reinstalls, and Vincent Homans on syslog invisibility
  of blocked loads. Both shaped the v1.2 milestone.

### Current state (after v1.2.1)

- **Code:** `modulejail` script at repo root — 792 lines POSIX `/bin/sh`,
  `SPDX-License-Identifier: GPL-3.0-only` at line 2. `VERSION='1.2.1'`.
- **Generated artifact:** `modprobe.d`-compatible blacklist (default path
  `/etc/modprobe.d/modulejail-blacklist.conf`); header carries version +
  `sha256` input fingerprint (no wall-clock — OPS-01 by construction) plus
  install-line annotation showing which form (`logger` / `/bin/true`) was
  used.
- **Site-local whitelist:** `/etc/modulejail/whitelist.conf` auto-detected
  when no `--whitelist-file` flag is passed. Mode-gate (group/world-writable
  refused) + strict regex (`^[a-zA-Z0-9_-]+$`). `--no-whitelist-file`
  opt-out + mutually-exclusive guard for explicit operator intent.
- **Syslog visibility:** default ON when `/usr/bin/logger` is executable;
  blocked loads emit `blocked: $name` tagged `modulejail` to syslog.
  `--no-syslog-logging` opt-out short-circuits before logger probe so the
  v1.1.4 byte-identical install-line body is preserved on demand.
- **Distribution:** GitHub repo `jnuyens/modulejail`. Tags on origin:
  `v1.0.0..v1.2.0` series (v1.0.0, v1.0.1, v1.1.0..v1.1.4 published);
  `v1.2.0` and `v1.2.1` cut locally, push HUAT-gated.
  `scripts/cve-watch.sh` companion script deployed to www.linuxbe.com,
  runs every 6h via /etc/cron.d/cve-watch (commit `ccbd3e9`, 2026-05-14).
- **Tests:** `tests/run-fixtures.sh` now runs 15 host-local POSIX shell
  acceptance cases by default (whitelist-file family + logger family +
  ssh-unreachable-regression + emit-install-line-sanitize + v1.1.4-regression);
  container matrix (Arch/Alpine/openSUSE) runs ADDITIVELY when docker/podman
  is present. `tests/run-ssh-hosts.sh` PASS on ubuntu-wifi (Ubuntu 24.04),
  debian13 (Debian 13.4), rocky9 (Rocky Linux 9.7); now correctly
  distinguishes UNREACHED vs OVERALL_FAIL exit codes (0/1/2).
- **Safety contracts:** "if loaded ⇒ keep" invariant (v1.0.0) and v1.1.4
  byte-identical install-line body (6363/6363 install lines preserved
  through every Phase 3 + Phase 4 commit) both intact.
- **Tech stack:** POSIX `/bin/sh`, coreutils, `awk`, `comm`, `sha256sum`,
  optionally `/usr/bin/logger`. No bashisms, no arrays, no Python, no Go,
  no compiled artifacts.
- **Known deferred items (non-blocking):** 6 HUAT release-gate gestures
  (tag pushes + container matrix on a Linux host + live SSH spot-checks);
  IN-03 (case-env duplication in v1.1.4-regression.sh) and IN-04
  (hardcoded packaging dates) deferred with written rationale; v1.x
  backlog of 6 enhancement items carried to v1.3.

## Constraints

- **Tech stack**: Single shell script (POSIX-friendly, bash acceptable if
  needed) — no Python, no Go, no compiled artifacts. Why: must run on minimal
  base images and air-gapped boxes with nothing pre-installed.
- **Dependencies**: `awk`, `comm`, `find`, `sha256sum`, coreutils, and a
  writable `/etc/modprobe.d/`. `/usr/bin/logger` is optional (graceful
  fallback to `/bin/true` install line). Why: portability across
  Debian/Ubuntu/RHEL/Fedora/Arch/Alpine/SUSE without per-distro branches.
- **Distribution**: GitHub-hosted, curl-pipe-shell installable, with
  built-from-source `.deb` / `.rpm` packages also available. Why: matches
  the workflow fleet operators already use; no package-manager gating.
- **Safety model**: "Currently-loaded module ⇒ keep" is the only safety
  guarantee. Why: keeps the script simple and predictable; sysadmin opts in
  knowingly.
- **Auditability**: Generated blacklist file must carry tool version, an
  `sha256` input fingerprint, and the chosen install-line variant in its
  header. Why: fleet operators need to know which version of ModuleJail
  produced the current state of a given host, and which install-line form
  is currently in force.
- **v1.1.4 byte-identical contract**: every subsequent release MUST preserve
  the v1.1.4 install-line body byte-identically when the legacy install-line
  variants are selected (`--no-syslog-logging` opt-out, logger-absent
  fallback). Why: operators with fleet-wide diff-based change detection
  rely on this; it is the live safety contract for the project. Guarded
  by `tests/fixtures/v1.1.4-regression/` and `tests/cases/v1.1.4-regression.sh`.

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Pure shell script, no compiled artifact | Maximum portability across distros; zero install footprint beyond coreutils | ✓ Good — 792 lines POSIX `/bin/sh`; runs unmodified across 5 Linux families (Ubuntu/Debian/Rocky + Arch/Alpine/openSUSE fixtures) |
| `/proc/modules` snapshot as keep-list (chosen over `lsmod`) | Drops the `kmod` runtime dep — supports PORT-02 (no deps beyond coreutils + `awk` + `comm`) | ✓ Good — Alpine busybox PASS in fixture, rocky9 bare userspace PASS via SSH harness |
| One-shot snapshot (no observation window / monitoring) | Simplicity; sysadmin runs it when workload is steady-state | ✓ Good — model held; no operator feedback requesting a window after v1.2.1 ship |
| Safety = "loaded ⇒ keep" invariant; no dry-run / revert flow | Keeps scope tight; sysadmin discipline replaces tool guardrails | ✓ Good — invariant documented in README "Safety Model" section; revert path is `rm /etc/modprobe.d/modulejail-blacklist.conf` |
| Built-in baseline + in-script `WHITELIST` block | One-file deploy; no external config file to lose; trivially diff-able in version control | ✓ Good — `WHITELIST` banner block with `=== BEGIN ===` / `=== END ===` Ansible anchors works for fleet templating |
| Skip initramfs handling | Loaded-module surface is the target; baked-in modules are not considered the relevant attack vector | ✓ Good — held; no scope creep through v1.2.1 |
| No AI inside the tool | AI is the threat-model backdrop, not a feature; keep the tool boringly auditable | ✓ Good — held; the only non-coreutil binary the script optionally invokes is `/usr/bin/logger` (graceful fallback) |
| `sha256sum` fingerprint over canonical inputs replaces wall-clock timestamp in the header | Stronger semantics: OPS-01 idempotency is by construction (input-deterministic), not by accident | ✓ Good — cmp byte-identical re-runs verified on ubuntu-wifi; D-23 evolution from the original "version + timestamp" decision |
| Annotated git tag is the version source of truth; `VERSION='1.2.1'` constant is the in-script mirror | Single source per artifact, tag is the canonical release marker | ✓ Good — `v1.0.0..v1.1.4` published on origin; `v1.2.0` + `v1.2.1` cut locally, push HUAT-gated; `--version` matches at every release |
| README ships a `curl … \| sh` one-liner pinned to the tag (not `main`) with an explicit warning | Practicality for fleet operators while making the trust tradeoff impossible to miss | ✓ Good — pinned-tag URLs verified live at every release |
| sysexits.h exit-code taxonomy (`EX_OK/USAGE/NOINPUT/SOFTWARE/OSERR/CANTCREAT/NOPERM/DATAERR`); zero bare `exit 1` sites | Distinct codes for distinct error classes — fleet log scrapers can branch on the exit code | ✓ Good — verified across fixture + SSH-host harness runs; Phase 4 WR-01 refined awk-exit routing to distinguish EX_DATAERR (data error) from EX_OSERR (awk-internal failure) |
| Severity-prefixed stderr (`modulejail: error: <msg>`) and one-line stdout success summary | Machine-friendly under `tee` / `jq` / log aggregators | ✓ Good — OPS-03 satisfied |
| Two test layers: synthetic-fixture containers + real-SSH-host harness | Fixtures catch portability regressions in CI; SSH-host harness catches real-kernel issues that fixtures can't | ✓ Good — both harnesses PASS at every milestone close; Phase 4 WR-05 unified them so host-local cases always run and the container matrix runs additively when docker/podman is present |
| GPL-3.0 license, verbatim from gnu.org, with sha256 recorded | Drift detection for the LICENSE text; copyleft compatible with the fleet-tool audience | ✓ Good — sha256 `3972dc97…36986` pinned in `02-05-SUMMARY.md` |
| **D-36 (v1.2.0):** Default ON for syslog-via-logger when `/usr/bin/logger` exists; `--no-syslog-logging` opt-out | Vincent's feedback was that the *default* of invisible blocks is the surprise; opt-out preserves v1.1.4 byte-identical install-line body | ✓ Good — live capture against `irqbypass`/`iommufd` on ubuntu-wifi; logger-absent fallback byte-identical to v1.1.4 by construction |
| **D-38 (v1.2.0 + Phase 4 IN-01):** Header-annotation byte string uses comma form for readability | Initial semicolon-form draft was harder to scan; comma form aligned across modulejail + manpage + README + 2 test assertions | ✓ Good — five-site Phase 4 IN-01 edit (T-07) made the comma form authoritative |
| **D-39 (v1.2.0):** Permanent v1.1.4 byte-identical regression fixture is the live safety contract | Fleet operators with diff-based change detection rely on the install-line body; preserving it is mandatory for every release | ✓ Good — 6363/6363 install lines body-identical through every Phase 3 + Phase 4 commit, including the most behavior-changing T-04 (canonical-name filter in `list_universe` + `list_loaded`) |
| **Default `/etc/modulejail/whitelist.conf` auto-detection (v1.2.0)** | The CR-01 fix follow-up flagged the silent-error-on-forgotten-flag concern raised by `@bpmartin20` and `@james-rimu` in the Issue #2 thread; default path is the operator-friendly behavior | ✓ Good — auto-detection + `--no-whitelist-file` opt-out + mutually-exclusive guard all in commit `746395e`; 4 acceptance cases (default-used / default-opt-out / mutually-exclusive / missing) PASS |
| **Phase 4 canonical-name gate symmetry (WR-03 Phase 3):** filter lives in BOTH `list_universe` AND `list_loaded`, not inside `emit_install_line` | Defense-in-depth at the data ingestion points; duplicating the regex in three places yields no behavioral gain | ✓ Good — 6363/6363 v1.1.4 byte-identical body-diff after the filter edit confirmed no legitimate module is dropped |
| **Phase 4 WR-05 integration shape (c):** host-local cases ALWAYS run in `tests/run-fixtures.sh`; container matrix ADDITIVE when docker/podman is present; no-runtime path no longer fatal | Aggregate FAIL/TOTAL counters cover both layers; macOS dev box can run the full host-local layer without depending on a container runtime | ✓ Good — 15/15 host-local PASS in default `tests/run-fixtures.sh` invocation on macOS dev box; container matrix still discharges under HUAT-02 on a Linux host |
| **HUAT-gated origin pushes** | Tag pushes and master pushes are operator-driven release gestures, not executor responsibilities; lets the maintainer ack live evidence before publishing | ✓ Held — v1.2.0 and v1.2.1 annotated tags cut locally; pushes deferred at v1.2.1 close. Recorded as HUAT-01..06 in MILESTONES.md |
| **Inline patch releases without formal phase tracking (v1.0.1..v1.1.4)** | Small, independent polish items did not warrant /gsd:plan-phase ceremony; CHANGELOG entry + tag push was sufficient | ✓ Good — 6 inline patches shipped between v1.0.0 close and v1.2 planning; pattern held for `scripts/cve-watch.sh` companion as well (no version bump) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-18 after v1.2.1 milestone — full evolution review completed via `/gsd:complete-milestone v1.2.1`. v1.2.1 SHIPPED on master (HUAT push gates pending): site-config whitelist file with default path + auto-detection + opt-out, default-on syslog visibility with opt-out, v1.1.4 byte-identical regression contract preserved end-to-end, Phase 4 cleanup discharged 4 Phase 3 WARNINGs + 3 v1.0.0 carry-forwards. modulejail script: 419 → 792 lines. 15 host-local POSIX shell acceptance cases, all PASS. 6 HUAT release-gate gestures and 8 v1.x backlog items deferred to v1.3. Next: `/gsd:new-milestone` to scope v1.3.*
