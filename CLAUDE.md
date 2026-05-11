# ModuleJail

A single shell script that proactively shrinks a Linux host's loaded-module
attack surface by writing a `modprobe.d` blacklist for every kernel module not
currently in use (minus a built-in baseline and an optional sysadmin
whitelist).

## Project Context

- **Purpose:** Hardening tool for Linux fleet operators against the coming
  wave of AI-assisted kernel privilege-escalation discoveries.
- **Form factor:** Single POSIX-friendly shell script. No daemons, no
  initramfs changes, no AI inside the tool, no per-distro packaging in v1.
- **Safety model:** Whatever is currently loaded (`lsmod`) is assumed
  necessary for the host to function — it is preserved. Everything else is
  blacklisted.
- **Distribution:** GitHub repo, installable via `curl … | sh` (with the
  obvious warnings) or `git clone`.

## Planning Documents

This project is managed with [Get Shit Done (GSD)](https://github.com/anthropics/get-shit-done). The
`.planning/` directory is **local only** (not tracked in git — see
`.gitignore`).

- `.planning/PROJECT.md` — project context, requirements, decisions
- `.planning/REQUIREMENTS.md` — v1 requirements with traceability
- `.planning/ROADMAP.md` — phase breakdown (2 phases)
- `.planning/STATE.md` — current state and next action
- `.planning/config.json` — GSD workflow configuration

## GSD Workflow

When working on this project, follow GSD's phase-based workflow:

1. **Plan a phase:** `/gsd:plan-phase N` — creates `.planning/phase-N/PLAN.md`
2. **Execute a phase:** `/gsd:execute-phase N` — runs the plan with atomic
   commits per task
3. **Check progress:** `/gsd:progress` — shows where you are
4. **Resume work:** `/gsd:resume-work` — pick up after a context reset

## Conventions

- **Source of truth:** A single shell script (name TBD in Phase 1) at the
  repository root.
- **No build step:** The script ships as-is. No compilation, no transpilation.
- **Version string:** Maintained inside the script (SemVer). Stamped into
  every generated blacklist file's header.
- **Generated artifact:** One `modprobe.d`-compatible blacklist file. Path
  configurable; defaults to `/etc/modprobe.d/modulejail-blacklist.conf`.
- **Testing:** Phase 2 introduces container-based smoke tests across major
  distros (Debian/Ubuntu, RHEL/Fedora, Arch, Alpine, SUSE).

## What This Tool Is NOT

- Not a daemon, not a service, not a continuous monitor.
- Not initramfs-aware. Modules baked into initramfs are out of scope.
- Not AI-powered. AI is the *threat-model backdrop*, not a feature.
- Not a vulnerability scanner. The model is "unused ⇒ blacklist," not
  "vulnerable ⇒ blacklist."

See `.planning/PROJECT.md` for the full out-of-scope list with rationale.
