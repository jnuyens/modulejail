# Security Policy

ModuleJail runs as root and writes the module blacklist a host relies on to
shrink its kernel attack surface. A flaw in it can weaken exactly the
protection an operator believes is in place, so security reports are taken
seriously.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub's private
vulnerability reporting:

1. Open the [Security tab](https://github.com/jnuyens/modulejail/security) of
   this repository.
2. Click **Report a vulnerability**.
3. Include the modulejail version (`modulejail --version`), the OS/distro and
   kernel, and a reproduction if you have one.

This keeps the report private until a fix is ready and lets us issue a GitHub
Security Advisory (and a CVE where warranted). Please do not open a public
issue for a suspected vulnerability.

## What is in scope

Use the private channel when a flaw could weaken the protection ModuleJail is
meant to provide, or let untrusted input run with its privileges:

- **Fails open.** ModuleJail keeps or whitelists a module it should have
  blacklisted, silently leaving attack surface the operator believes is
  closed. Under-protecting is the failure that matters most for a tool like
  this.
- **Integrity and supply chain.** A signature-verification bypass, the
  `--self-update` path fetching or accepting tampered bytes, or any way to
  subvert the `curl ... | sh` install into running attacker-controlled code
  as root.
- **Local exploitation of the tool.** Symlink or TOCTOU races on the output
  path, unsafe temp-file handling, or whitelist-file parsing that a local
  user could abuse while modulejail runs as root.

## What is not in scope

- **A host that will not boot, or a needed module getting blacklisted.** This
  is a correctness and availability bug, not attacker-driven exploitation. It
  is real and worth fixing, so please report it as a normal
  [issue](https://github.com/jnuyens/modulejail/issues), not through the
  private channel. Recovery is the Golden Rule in the README (enable
  everything you need, then lock down) plus removing
  `/etc/modprobe.d/modulejail-blacklist.conf`.
- **Vulnerabilities in the kernel modules ModuleJail blacklists.** The model
  is "unused implies blacklist," not "vulnerable implies blacklist." A CVE in
  some kernel module is not a ModuleJail vulnerability.

## Supported versions

ModuleJail ships as a single script on a rolling release. Only the **latest
released version** is supported; the fix for a security issue is to upgrade
(`--self-update`, or your distro package once available). Downstream
packagers (for example Debian) handle security updates for their packaged
versions through their own channels.

## What to expect

This is a small, volunteer-maintained project, so responses are best-effort
rather than bound by an SLA. As a rough guide:

- Acknowledgement within a few days.
- A fix for a confirmed, serious issue in the next release, with a GitHub
  Security Advisory and credit to the reporter unless they prefer to remain
  anonymous.

## Verifying releases

Release tags from `v1.3.0` onward are GPG-signed. See
[Verifying releases](README.md#verifying-releases) in the README for the key
and the verification steps.
