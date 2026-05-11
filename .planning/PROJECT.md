# ModuleJail

## What This Is

ModuleJail is a single, distribution-agnostic shell script that proactively
shrinks the Linux kernel's loaded-module attack surface on a host. It snapshots
the currently `insmod`'d modules and writes one large `modprobe.d`-style
blacklist file covering everything else — minus a built-in baseline of
essential modules and an optional sysadmin-supplied whitelist embedded in the
script itself. It is aimed at Linux fleet operators who need to harden many
servers at once against the coming wave of AI-assisted kernel privilege
escalation discoveries (Copy Fail, Dirty Frag, and successors).

## Core Value

One shell-script run cuts a host's kernel-module attack surface down to "what
is actually in use today," portably across Linux distributions, and is safe to
fleet-deploy via Ansible/Puppet/SSH-for-loops.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Snapshot currently loaded modules via `lsmod` and treat that set as the
      keep-list
- [ ] Maintain a curated built-in "never blacklist" baseline embedded in the
      script (essentials: core fs, crypto, common storage drivers, etc.)
- [ ] Accept a sysadmin-defined whitelist embedded in the same script (simple
      list near the top, easy to edit before deploy)
- [ ] Emit one consolidated `modprobe.d` blacklist file containing every
      module NOT in the keep-list ∪ baseline ∪ sysadmin whitelist
- [ ] Stamp the script's own version and run timestamp into a header comment
      of the generated blacklist file
- [ ] Be a single POSIX-ish shell script with no runtime dependencies beyond
      `lsmod`, `awk`/`grep`, and standard coreutils — portable across major
      Linux distributions
- [ ] Behave well in fleet automation: idempotent (re-runs converge), useful
      exit codes, machine-friendly stdout/stderr
- [ ] Carry a SemVer-style version string inside the script and expose it via
      `--version`
- [ ] Ship an open-source repository (license + README) on GitHub
- [ ] README documents a `curl … | sh` one-liner for direct execution from
      GitHub, with an explicit "this is convenient, not safe" warning and a
      "download-then-inspect-then-run" alternative

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
- Per-distro packaging (`.deb`/`.rpm`) for v1 — the curl one-liner and a
  cloned repo are the distribution channels
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
- The tool is intentionally boring: shell + `lsmod` + `grep`. The value is in
  the curated baseline and the fleet-friendliness, not in implementation
  cleverness.

## Constraints

- **Tech stack**: Single shell script (POSIX-friendly, bash acceptable if
  needed) — no Python, no Go, no compiled artifacts. Why: must run on minimal
  base images and air-gapped boxes with nothing pre-installed.
- **Dependencies**: Only `lsmod`, `awk`/`sed`/`grep`, coreutils, and a writable
  `/etc/modprobe.d/`. Why: portability across Debian/Ubuntu/RHEL/Fedora/Arch/
  Alpine/SUSE without per-distro branches.
- **Distribution**: GitHub-hosted, curl-pipe-shell installable. Why: matches
  the workflow fleet operators already use; no package-manager gating.
- **Safety model**: "Currently-loaded module ⇒ keep" is the only safety
  guarantee. Why: keeps the script simple and predictable; sysadmin opts in
  knowingly.
- **Auditability**: Generated blacklist file must carry tool version and run
  timestamp in its header. Why: fleet operators need to know which version of
  ModuleJail produced the current state of a given host.

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Pure shell script, no compiled artifact | Maximum portability across distros; zero install footprint beyond coreutils | — Pending |
| One-shot `lsmod` snapshot as keep-list (no observation window) | Simplicity; sysadmin runs it when the workload is steady-state | — Pending |
| Safety = "loaded ⇒ keep" invariant; no dry-run / revert flow | Keeps scope tight; sysadmin discipline replaces tool guardrails | — Pending |
| Built-in baseline + sysadmin whitelist embedded directly in the script | One-file deploy; no external config file to lose; trivially diff-able in version control | — Pending |
| Skip initramfs handling | Loaded-module surface is the target; baked-in modules are not considered the relevant attack vector | — Pending |
| No AI inside the tool | AI is the threat-model backdrop, not a feature; keep the tool boringly auditable | — Pending |
| Version-stamp the generated blacklist file | Fleet operators need to correlate host state with the tool revision that produced it | — Pending |
| README ships a `curl … \| sh` one-liner with an explicit warning | Practicality for the target audience while flagging the trust tradeoff | — Pending |

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
*Last updated: 2026-05-11 after initialization*
