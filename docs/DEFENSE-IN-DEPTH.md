# Defense-in-depth recipes for ModuleJail

ModuleJail is one layer in a larger kernel-hardening stack. This document
covers two things:

1. The **threat surface ModuleJail is built to address** - kernel modules
   that unprivileged users can cause to load via ordinary syscalls, and
   which therefore become latent attack surface for the next privilege-
   escalation CVE in those modules.
2. **Recipes for stacking other kernel hardening on top of ModuleJail**,
   so a single defense gap does not become a chain to root.

If you want the one-page summary, see the [Threat model](../README.md#threat-model)
section in the README. This document is the long version.

---

## Part 1 - Who can load which kinds of kernel modules

The Linux kernel autoloads modules in response to a wide set of triggers.
For ModuleJail's purposes the interesting question is: **which of these
triggers can an unprivileged local user reach, without already holding
root or any administrator capability?**

There are seven distinct trigger tiers. The first three are the
practically-important ones; the rest are narrower but worth understanding.

### Tier 1 - Socket family and protocol autoload

**Kernel mechanism:** `__sock_create()` calls `request_module("net-pf-%d",
family)` if no handler is registered for the requested address family.
After the family loads, `inet_create()` and siblings may further call
`request_module("net-pf-%d-proto-%d-type-%d", ...)` for SOCK_RAW /
SOCK_DGRAM / SOCK_SEQPACKET with a non-default `protocol` value.

**Trigger:** a single `socket(2)` call.
**Capability required:** none for the autoload itself. Some families do
check a capability *after* loading (`AF_PACKET` checks `CAP_NET_RAW`;
`AF_BLUETOOTH` HCI socket checks `CAP_NET_ADMIN`) but **the module is in
memory and its `init()` code has already run** by then. The autoload
happens before the capability check.

Modules reachable this way, with recent CVE examples:

| Family / proto | Module(s) autoloaded | Recent CVE |
|---|---|---|
| `AF_VSOCK` | `vsock`, `vmw_vsock_*`, `virtio_transport` | CVE-2025-21756 UAF, CVE-2025-40248 disconnect race |
| `AF_INET / SOCK_RAW / IPPROTO_SCTP` | `sctp`, `sctp_diag` | CVE-2025-40331 TOCTOU in diag path |
| `AF_INET / SOCK_DCCP` | `dccp_ipv4`, `dccp_ipv6` | Recurring UAFs; DCCP is deprecated upstream but still shipped |
| `AF_TIPC` | `tipc` | CVE-2021-43267 remote RCE |
| `AF_RDS` | `rds`, `rds_tcp`, `rds_rdma` | Multiple historical UAFs |
| `AF_CAN` | `can`, `can_raw`, `can_bcm`, `can_gw`, `j1939` | Recurring `can_bcm` UAFs |
| `AF_NFC` | `nfc`, `nci`, `nci_core` | CVE-2024-26581 OOB |
| `AF_X25 / AX25 / NETROM / ROSE / DECNET / IPX / APPLETALK` | namesake modules | Legacy. Many distros ship `blacklist net-pf-N` for these out of the box. |
| `AF_LLC` (proto 2) | `llc2` | Dead infrastructure; trivial trigger |
| `AF_MCTP` | `mctp` | Newer (5.15+); thin audit |
| `AF_QIPCRTR` | `qrtr`, `qrtr_*` | Qualcomm IPC; CVE-2024 UAFs |
| `AF_SMC` | `smc`, `smc_diag` | RDMA over IP; CVE-2024 series |
| `AF_BLUETOOTH` | `bluetooth`, then `l2cap`, `rfcomm`, `bnep`, `hidp`, `cmtp` | RCE history (BlueBorne family) |

A complete demonstration that an unprivileged user can drive five different
module loads from one program, with no capabilities at all:

```c
int s = socket(AF_VSOCK, SOCK_STREAM, 0);          /* autoloads vsock + transport */
int t = socket(AF_INET, SOCK_RAW, IPPROTO_SCTP);   /* autoloads sctp */
int u = socket(AF_TIPC, SOCK_SEQPACKET, 0);        /* autoloads tipc */
int v = socket(AF_CAN,  SOCK_RAW, CAN_RAW);        /* autoloads can + can_raw */
int w = socket(AF_X25,  SOCK_SEQPACKET, 0);        /* autoloads x25 */
```

Each `socket()` may return `-EPERM`. That does not undo the load.

**ModuleJail coverage:** strong. The `conservative` baseline holds none of
these. On any host where `lsmod` does not currently show one of these,
ModuleJail blacklists it; the next `socket()` call returns `-EAFNOSUPPORT`
or `-EPROTONOSUPPORT` and no module is loaded.

### Tier 2 - AF_ALG crypto autoload

**Kernel mechanism:** `socket(AF_ALG, SOCK_SEQPACKET, 0)` returns a
socket; `bind()` with a `struct sockaddr_alg` containing an algorithm
name calls `request_module("algif-type-X")` AND
`request_module("crypto-X")` to pull in both the algif glue and the
algorithm implementation.

**Trigger:** `socket()` + `bind()`.
**Capability required:** none.

| Module class | Examples | Notable CVE |
|---|---|---|
| `algif_*` glue | `algif_skcipher`, `algif_hash`, `algif_aead`, `algif_rng` | **CVE-2026-31431 "Copy Fail"** — splice + AF_ALG → 4-byte arbitrary write to page-cache → setuid binary corruption → root |
| Cipher implementations | `aria`, `aegis128`, `chacha20poly1305`, `sm4`, `streebog`, `serpent`, `twofish`, `camellia`, `cast5/6`, `tea`, `tgr192`, `wp512` | Several OOB-read CVEs across the family |
| Mode implementations | `cts`, `lrw`, `xcbc`, `vmac`, `pcrypt` | `pcrypt` parallel crypto; historical races |

Trigger code:

```c
int s = socket(AF_ALG, SOCK_SEQPACKET, 0);
struct sockaddr_alg sa = { .salg_family = AF_ALG };
strcpy((char*)sa.salg_type, "aead");
strcpy((char*)sa.salg_name, "rfc4106(gcm(aria))");  /* autoloads aria + gcm + algif_aead */
bind(s, (struct sockaddr*)&sa, sizeof(sa));
```

**The Copy Fail (CVE-2026-31431) connection:** the mitigation every
upstream advisory recommends - `install algif_aead /bin/false` in
`/etc/modprobe.d/disable-algif-aead.conf` - is one line of what ModuleJail
generates automatically, applied to the entire class of unused crypto
glue modules. This is the most direct fit between ModuleJail's design and
the May 2026 marquee CVE.

**ModuleJail coverage:** excellent for `algif_*` (not in any baseline →
blacklisted on every host that is not actively using AF_ALG via
`cryptsetup`, kTLS over QUIC, or similar). Correct for the primitives
(`aes_generic`, `aesni_intel`, `sha256_generic`, `xts`, `cbc` are kept
because dm-crypt, WireGuard, kTLS all need them at runtime).

### Tier 3 - Filesystem autoload via setuid mount helpers

**Kernel mechanism:** `mount(2)` calls `request_module("fs-%s", fstype)`.
The bare syscall needs `CAP_SYS_ADMIN`, but setuid helpers can do the
load on the user's behalf.

| Helper | Module(s) loaded | Notes |
|---|---|---|
| `/usr/bin/fusermount3` | `fuse` | Any user; sshfs, snap, AppImage all go through this |
| `/usr/bin/ntfs-3g` (when setuid) | `fuse` | Same indirection |
| `/usr/sbin/mount.cifs` | `cifs`, `nls_*` | Common on hosts with SMB shares |
| `/usr/sbin/mount.ecryptfs_private` | `ecryptfs` | Has had its own CVEs; some distros dropped the setuid |

**Plus a non-mount autoload path for the same modules:** some
filesystem modules also register kernel key types and request-key
upcalls. The kernel `cifs.ko` module registers the `cifs.spnego` key
type at module-init time; once loaded, an unprivileged user can call
`request_key("cifs.spnego", attacker_controlled_description, ...)`,
which the kernel routes to the userspace `cifs.upcall` helper running
as root. The helper trusts the attacker-supplied description fields
as if they came from the kernel CIFS client - the basis of the
**CIFSwitch** disclosure (May 2026). On a host where `cifs.ko` is
not loaded, `request_key()` returns `-ENOKEY` and the chain breaks
at step one; on a host where `cifs.ko` IS loaded (CIFS-client host
that mounts SMB shares), modulejail's blacklist alone does not
protect, and the host needs the upstream kernel patch.

**ModuleJail coverage:** aggressive. `fuse`, `cifs`, `nfs`, `nfsv3`,
`nfsv4`, `ceph`, `ecryptfs` are not in any baseline, so they get
blacklisted by default on hosts that are not actively using those
filesystems. **If your operators use sshfs, snap mounts, AppImages,
or `ntfs-3g`, add `fuse` to your sysadmin WHITELIST. If your hosts
mount SMB shares as CIFS clients, add `cifs` (and `nls_*` if
specific code pages are needed). NFS-mounting clients need `nfs` +
the protocol versions in use. Samba SERVERS (running `smbd`) and
`ksmbd` SERVERS do not need `cifs.ko` and should leave it
blacklisted.**

### Tier 4 - binfmt autoload via execve()

**Kernel mechanism:** `execve()` of a file iterates registered binfmt
handlers; if none match a magic / extension, `request_module("binfmt-XXXX",
magic)` is called.

| Module | Triggered by |
|---|---|
| `binfmt_misc` | Files matching a registered handler (qemu-user, Java jars, Mono) |
| `binfmt_aout` | a.out magic - you can craft a 4-byte file and `execve()` it |
| `binfmt_em86` | EM86 magic |
| `binfmt_flat` | uClinux flat-binary magic |

Surface is small but the modules are old and lightly-audited.

**ModuleJail coverage:** all four blacklisted by default in every profile.
Correct.

### Tier 5 - Character-device autoload via /dev/X open

**Kernel mechanism:** opening a character device file with no driver bound
to its major:minor calls `request_module("char-major-%d-%d", major,
minor)`. Some distros pre-create `/dev/X` nodes via static udev rules
even when no module is loaded; the open then triggers the load.

Practical examples: `/dev/ppp` → `ppp_generic`, `/dev/net/tun` → `tun`,
`/dev/uinput` → `uinput`, `/dev/loop-control` → `loop`.

**Reality check:** this tier is mostly defended on a default modern install
because the device nodes are themselves created in response to module-init
events. The pre-created-node path is largely historical (devfs era).

**ModuleJail coverage:** indirect but correct - the modules are not in
`lsmod` and so get blacklisted.

### Tier 6 - Netlink subsystem autoload

**Kernel mechanism:** `socket(AF_NETLINK, SOCK_RAW, NETLINK_X)` triggers
`request_module("net-pf-16-proto-%d", X)`. Some `NETLINK_X` values gate
the capability check before, some after.

| Family | Module | Notes |
|---|---|---|
| `NETLINK_NETFILTER` (12) | `nfnetlink`, `nf_tables`, `nfnetlink_log`, `nfnetlink_queue` | **The big one.** Almost every nf_tables LPE chain starts here. |
| `NETLINK_GENERIC` (16) | usually built-in; loads per-family `genl` modules (`l2tp`, `gtp`, ...) | GTP CVE-2024 family |
| `NETLINK_XFRM` (6) | `xfrm_user`, `xfrm_algo` | IPsec keying |

### Tier 7 - The user-namespace amplifier

`unshare(CLONE_NEWUSER | CLONE_NEWNET)` is unprivileged on every
mainstream distro that ships unprivileged user namespaces enabled
(Debian, Fedora, Arch by default; Ubuntu since 24.04 with AppArmor-gated
unprivileged-userns). Inside the new namespace, the caller has **full
`CAP_NET_ADMIN`, `CAP_SYS_ADMIN`, `CAP_NET_RAW`** - the bits that
gate Tier 1, Tier 5, Tier 6.

**Effect:** every autoload trigger that had a "must hold CAP_X" gate
becomes reachable by any unprivileged user. This is the mechanism behind:

- CVE-2024-1086 (nf_tables UAF) - universal LPE via userns + netlink + tier-6 autoload
- CVE-2023-35001 (nf_tables stack OOB) - same path
- CVE-2022-34918 (nf_tables) - same path

User namespaces are the single biggest amplifier of Tier 1, 5, 6 risk.
Without them enabled, many of these LPE chains require root the attacker
already has. See [Recipe 2](#recipe-2---disable-unprivileged-user-namespaces)
below for the kill-switch.

---

## Part 2 - Defense-in-depth recipes

The recipes below are stand-alone hardening steps that ModuleJail does
not provide but that compose well with it. Each lists who it protects
against, what it costs, and what breaks if you enable it.

### Recipe 1 - kernel.modules_disabled=1 (freeze the loader)

**What it does:** sets a one-way kernel switch. Once enabled, **no further
kernel modules can be loaded until the next reboot, by anyone, including
root**. Even `insmod /path/to/module.ko` fails with `-EPERM`.

**Who it protects against:** an attacker who has already achieved root
and wants to load a malicious kernel module (rootkit, debugger backdoor,
hidden network sniffer) without rebooting. Pairs with ModuleJail: ModuleJail
ensures only legitimate modules are auto-loadable while modules can still
be loaded; this recipe says "and now we're done, freeze."

**How to apply:**

```sh
# After the last boot-time module has loaded and the host is in
# steady-state, run:
sudo sysctl -w kernel.modules_disabled=1

# To persist across reboots, add a one-line systemd oneshot unit that
# runs after multi-user.target settled. Example /etc/systemd/system/
# modules-disabled.service:
#
# [Unit]
# After=multi-user.target
# RequiresMountsFor=/etc /proc
#
# [Service]
# Type=oneshot
# ExecStart=/sbin/sysctl -w kernel.modules_disabled=1
# RemainAfterExit=yes
#
# [Install]
# WantedBy=multi-user.target
```

**What breaks:** any service that loads modules late (some VPN clients,
USB hotplug for unusual devices, virtualization helpers that pull in
modules on first guest start). Test on one host before deploying.

**Trade-off:** one-way; the only way to load another module is to reboot.
Most production servers reach steady state within 30 seconds of boot;
this is the right time to flip the switch.

### Recipe 2 - Disable unprivileged user namespaces

**What it does:** prevents unprivileged users from creating new user
namespaces with `unshare(CLONE_NEWUSER)`. This closes Tier 7 (the
amplifier) above.

**Who it protects against:** every LPE chain that starts with `unshare()`
to gain in-namespace `CAP_NET_ADMIN` / `CAP_SYS_ADMIN`. The entire
nf_tables CVE family (CVE-2024-1086, CVE-2023-35001, CVE-2022-34918, ...)
is mitigated by this single switch.

**How to apply:**

- **Debian, Fedora, Arch:**

  ```sh
  echo 'kernel.unprivileged_userns_clone=0' | sudo tee /etc/sysctl.d/99-no-userns.conf
  sudo sysctl --system
  ```

- **Ubuntu (24.04+):** the corresponding control is an AppArmor profile.
  Edit `/etc/apparmor.d/abstractions/userns` or remove the `userns,`
  capability from the profiles that grant it. The simpler equivalent:

  ```sh
  echo 'kernel.apparmor_restrict_unprivileged_userns=1' | sudo tee /etc/sysctl.d/99-no-userns.conf
  sudo sysctl --system
  ```

**What breaks:** container runtimes that use unprivileged user namespaces
(rootless Podman, rootless Docker, BubbleWrap-based sandboxes including
Flatpak, some browsers' sandboxing). On servers without containerised
workloads, this is usually free. On developer workstations, expect
breakage.

**Trade-off:** Edera's 2024 study found enabling unprivileged userns
expands the unprivileged kernel attack surface by **262%**. If your host
does not run unprivileged containers, the disable is almost pure win.

### Recipe 3 - Secure Boot + kernel lockdown mode

**What it does:** when Secure Boot is enabled and the kernel boots in
`lockdown=integrity` (or `lockdown=confidentiality`) mode, root loses
the ability to load unsigned modules, write `/dev/mem`, use `kexec` to
boot unsigned images, attach `kprobes` / `kgdb`, and several other
privileged channels.

**Who it protects against:** the strongest layer in this stack against a
malicious root user. A compromised root can no longer just `insmod
rootkit.ko` even with a valid module file - the kernel will refuse
unsigned modules outright.

**How to apply:** distro-specific, but the high-level path is:

1. Enable Secure Boot in firmware. Enroll the distro's Microsoft-signed
   shim or your own MOK.
2. Boot a distro kernel that supports lockdown. All mainstream distros
   (Debian, Fedora, Ubuntu, openSUSE) ship lockdown-aware kernels.
3. Verify with `cat /sys/kernel/security/lockdown` - should show
   `[integrity]` or `[confidentiality]`.

**What breaks:** out-of-tree modules that are not signed (the NVIDIA
proprietary driver, ZFS, VirtualBox modules, custom kernel modules built
by the operator). These need to be signed against an MOK enrolled in the
firmware. The DKMS framework on modern distros handles MOK signing if the
operator follows the prompts at install time.

**Trade-off:** the highest assurance available short of fully measured
boot, but the firmware-enrollment dance is a one-time effort per host.

### Recipe 4 - Module signature enforcement

**What it does:** the in-kernel `CONFIG_MODULE_SIG_FORCE=y` (or the
runtime equivalent `module.sig_enforce=1` on the kernel command line)
makes the kernel refuse any module that is not signed with a key in its
trusted keyring. Lighter-weight than full lockdown.

**Who it protects against:** a root user (or a process that has achieved
arbitrary kernel writes via a CVE) that wants to load a custom module.
The module file would have to be signed; without the signing key, it
cannot.

**How to apply:**

```sh
# Most distros ship modules signed already; the runtime enforcement
# switch can be flipped via kernel command line. Add to GRUB config:
echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT module.sig_enforce=1"' \
    | sudo tee -a /etc/default/grub
sudo update-grub  # or grub2-mkconfig -o /boot/grub2/grub.cfg

# Verify after reboot:
cat /sys/module/module/parameters/sig_enforce  # should be Y
```

**What breaks:** same as Recipe 3 - unsigned out-of-tree modules. The
DKMS sign-with-MOK workflow handles this; manual `insmod`'ing a built
module won't.

**Trade-off:** strictly weaker than lockdown but doesn't require Secure
Boot. Useful on hosts where the firmware path is not available
(rented VMs, older hardware).

### Recipe 5 - Seccomp-bpf at the application layer

**What it does:** application-level filter that lists allowed syscalls;
everything else returns `EPERM`. A web server that never needs to talk
to the kernel via `socket(AF_VSOCK, ...)` should never be able to.

**Who it protects against:** a partial compromise of a single service
(SSRF, deserialisation bug, unsafe upload handler) where the attacker
has the service's execution context but not arbitrary syscall ability.
A seccomp filter that denies `socket()` for unusual families closes the
Tier 1 autoload path for that service.

**How to apply:**

```sh
# systemd service hardening (one line per restriction):
[Service]
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX  # whitelist; deny everything else
SystemCallFilter=@system-service
SystemCallFilter=~@privileged
LockPersonality=yes
NoNewPrivileges=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
```

**What breaks:** depends entirely on the service. Test under load. Tools
like `strace -c` and `systemd-analyze syscall-filter` help build the
allowlist.

**Trade-off:** scales per-service rather than per-host. Pair with
ModuleJail for hosts that run many services with different syscall needs;
ModuleJail closes the auto-load surface globally, seccomp closes specific
syscalls per service.

---

## How the recipes stack

A reasonable production stack, in order of operational cost:

1. **ModuleJail at install time** - removes the auto-load surface for
   every unused module. Cost: one shell-script run per host.
2. **`kernel.unprivileged_userns_clone=0`** (Recipe 2) on servers - kills
   Tier 7 amplification. Cost: one sysctl line. Free on hosts without
   unprivileged containers.
3. **Module signature enforcement** (Recipe 4) - kernel command line
   addition. Cost: one reboot, requires MOK for any out-of-tree modules.
4. **`kernel.modules_disabled=1` after boot settles** (Recipe 1) -
   freezes the loader. Cost: one systemd unit, requires verification
   that no service loads modules late.
5. **Secure Boot + lockdown** (Recipe 3) - the highest layer. Cost: one-
   time firmware-enrollment effort per host.
6. **Seccomp per service** (Recipe 5) - depth on the most exposed
   services. Cost: per-service profile authoring.

ModuleJail is Step 1 because it has the lowest deployment cost, defends
the largest class of CVEs (every "unprivileged-user autoloads vulnerable
module → LPE" chain), and does not require a reboot. The other recipes
each add one more layer that an attacker has to bypass.

---

## Sources

- [Copy Fail (CVE-2026-31431) — Wiz](https://www.wiz.io/blog/copyfail-cve-2026-31431-linux-privilege-escalation-vulnerability)
- [CVE-2026-31431 Sysdig analysis (mitigation = install algif_aead /bin/false)](https://www.sysdig.com/blog/cve-2026-31431-copy-fail-linux-kernel-flaw-lets-local-users-gain-root-in-seconds)
- [CIFSwitch - 19-year-old Linux CIFS trust-boundary bug (CIQ, May 2026)](https://ciq.com/blog/cifswitch-ai-19-year-bug)
- [CVE-2025-21756 vsock UAF — SentinelOne](https://www.sentinelone.com/vulnerability-database/cve-2025-21756/)
- [CVE-2025-40331 SCTP TOCTOU (NVD)](https://nvd.nist.gov/vuln/detail/CVE-2025-40331)
- [TIPC remote RCE (CVE-2021-43267)](https://www.sentinelone.com/labs/tipc-remote-linux-kernel-heap-overflow-allows-arbitrary-code-execution/)
- [User namespaces add 262% kernel attack surface — Edera](https://edera.dev/stories/user-namespaces-are-not-a-security-boundary)
- [Linux kernel module autoloading — duasynt](https://duasynt.com/blog/linux-kernel-module-autoloading)
- [Restricting automatic kernel-module loading — LWN](https://lwn.net/Articles/740455/)
- [Hardening Linux against netlink socket privesc](https://www.systemshardening.com/articles/linux/linux-netlink-socket-hardening/)
- [xairy/linux-kernel-exploitation (curated index)](https://github.com/xairy/linux-kernel-exploitation)
