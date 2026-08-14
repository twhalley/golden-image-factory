# Image standard

What a compliant image from this factory contains, and why.

> **Status: phases 1 and 2.** Structure (partitioning, packages, build account, identity
> metadata) and the hardening control table, including everything deliberately not applied.
>
> **What this repo claims:** a *selected subset* of CIS Level 1, listed control by control
> below, applied identically to Rocky 9 and Ubuntu 24.04. It does **not** claim CIS
> certification, CIS Level 2, or full Level 1 conformance. The not-applied table is the
> honest half and is longer than most repos would print.

## The rule this document exists to enforce

Every claim here has a test in `tests/goss/` (phase 4). **If a control is in this document
there is a test for it; if there is no test, the control is not claimed.** That makes this
file the contract between what the factory says it produces and what it demonstrably does,
rather than a description of intent.

Phase 1 predates the test suite, so nothing below is claimed as *verified* yet. It is
claimed as *specified*. The distinction disappears at phase 4.

---

## Partition layout

Set by the kickstart at install time. This is the one part of the image that genuinely
cannot be retrofitted — a filesystem that was not created separately cannot be given its
own mount options later without a rebuild.

Identical on Rocky 9 and Ubuntu 24.04 — same mounts, same sizes, same volume group
name — so one goss suite and one Ansible role cover both.

| Mount | Size | Layout | Why it is separate |
|---|---|---|---|
| `/boot` | 1024 MB | plain partition | Outside LVM so the bootloader does not depend on LVM being assembled |
| `/` | 8192 MB | LVM | |
| `/home` | 1024 MB | LVM | Carries `nodev,nosuid` in phase 2. Small — a server image is not a workstation |
| `/var` | 4096 MB | LVM | A runaway package cache or spool must not fill `/` |
| `/var/log` | 2048 MB | LVM | A log flood must not fill `/` or `/var` |
| `/var/log/audit` | 2048 MB | LVM | **The important one.** `auditd` is configured to halt or stop logging when its filesystem fills. Sharing that filesystem with general logs means any chatty service can trigger it |
| `/var/tmp` | 1024 MB | LVM | Carries `nodev,nosuid,noexec` in phase 2 |
| `/tmp` | 1024 MB | LVM | As above |

**Filesystem type differs by distribution and that is deliberate:** xfs on Rocky, ext4 on
Ubuntu. Each is its distribution's own default and its best-tested path. Forcing one onto
the other would be parity for its own sake, buying nothing and diverging from every piece
of vendor documentation an operator will reach for.

Volume group `vg_root`, single PV on the remaining space, so the image can be grown after
deployment without touching the layout.

**No swap, deliberately.** A golden image should not assume the memory profile of a
workload nobody has chosen yet, and a swap volume sized for one workload is wrong for the
next. Swap is a deployment-time decision, and on most cloud and container-host targets the
correct amount is zero. Recorded as an omission rather than left as an absence.

**BIOS boot, for now.** `bootloader --location=mbr`, and the vSphere source sets
`firmware = "bios"`. UEFI plus Secure Boot is the better answer and is a roadmap item, not
a claim — it needs OVMF wiring on the QEMU source and a matching change on the vSphere and
Workstation sources, and doing it badly produces an image that boots on one platform and
not another.

### Where the boundary between phase 1 and phase 2 sits

Separate filesystems are created here. **Mount options — `nodev`, `nosuid`, `noexec` — are
not**, even though a kickstart can set them with `--fsoptions`.

That looks like an omission and is a decision. Mount options are configuration: they can be
changed on a running system, they are expressed identically on every platform, and the
Azure image has no kickstart at all, because `azure-arm` builds from a marketplace base
image. Putting them in the kickstart would mean the Azure image either misses them or gets
them from a second, divergent implementation. Putting them in the Ansible role means one
definition, applied to every target, and testable by one goss suite.

The general form of the rule, which is the thing worth being able to state:

> **Structural decisions that cannot be changed later go in the installer. Everything else
> goes in configuration management, so it applies equally to targets that have no
> installer.**

---

## Packages

Minimal install (`@^minimal-environment`) plus exactly what is required to manage and build
the image. Nothing is included because it might be useful — every package is attack surface
that has to be patched for the supported life of the image.

| Package | Why |
|---|---|
| `openssh-server` | The only remote access path |
| `sudo` | Privilege escalation for the build account and for Ansible `become` |
| `chrony` | Time sync. Audit logs and TLS both become unreliable without it |
| `python3` | Ansible's interpreter |
| `python3-libselinux` | Lets Ansible manage SELinux contexts rather than working around them |
| `tar`, `rsync` | Required by Ansible's file-transfer paths |
| `dnf-utils` | `needs-restarting`, used by the patch workflow in phase 6 |
| guest agent | **One only, matching the platform**: `qemu-guest-agent` for the QEMU source, `open-vm-tools` for the VMware and vSphere sources. Selected per source rather than installing both |

Removed or excluded: `plymouth`, `iwl*-firmware` (wireless firmware has no place on a
server image), `alsa-*`, `biosdevname`, `dracut-config-rescue`.

Documentation is excluded (`--excludedocs`) and the image is brought fully up to date
during `%post`. That currency is a starting point only — what keeps it current is the
monthly scheduled rebuild in phase 6, which is the actual answer to patch management.

---

## Security posture set at install time

| Setting | Value | Note |
|---|---|---|
| Mandatory access control | **enforcing** | SELinux on Rocky, AppArmor on Ubuntu — see below. Never disabled; turning it off is the most common shortcut in a golden image and it silently invalidates a large part of any CIS claim |
| firewalld | enabled, `ssh` only | Default deny inbound |
| root password | locked | Root cannot log in, locally or remotely |
| root SSH | denied (phase 2 enforces in `sshd_config`) | |
| Build account | key-only, no password | See below |
| Timezone | UTC | An image carrying a site's timezone cannot be used at another site |

### Mandatory access control: one claim, two implementations

Rocky enforces with **SELinux**; Ubuntu enforces with **AppArmor**. They are not
interchangeable — different models, different tooling, different policy languages — and
Ubuntu has no `getenforce` at all.

This is not a footnote, because it fixes the vocabulary for everything downstream. The
image standard claims **"mandatory access control is enforcing"**, which is true of both and
testable on both. It does **not** claim "SELinux enforcing", which is true of one. A repo
that writes the second while shipping both distributions is claiming something it does not
deliver on half its images.

The build-time check reflects that: it runs `getenforce` where it exists, `aa-enabled`
otherwise, and **fails the build if neither is present**, rather than degrading to a check
that passes everywhere by asserting nothing. Learned the direct way — the first Ubuntu
build completed a perfect install and then failed at exit 127 on a shared provisioner that
assumed `getenforce`. See ADR-0014.

## The build account

The installer creates one account, `packer`, with a public key injected at build time and
no password. The matching private key is ephemeral: generated per build by
[`scripts/make-build-key.sh`](../scripts/make-build-key.sh), written to a gitignored
directory, and never committed.

The account also gets `/etc/sudoers.d/90-packer-build` granting passwordless sudo, which is
required for Ansible `become` and for the shutdown command.

**Both the account and that sudoers file are removed by the `harden_linux` role before the
image is published (phase 2), and phase 4's goss suite asserts their absence.** Until phase
2 exists, images built from this repo still contain a build account, and that is stated
here rather than discovered later.

This is why the build credential is a key rather than the `ssh_password` most Packer
examples use: a password in a kickstart is a credential in the repository, and it survives
into the image unless something explicitly removes it. `policy/packer.rego` fails the build
if `ssh_password` is ever reintroduced.

## Identity metadata

Every image carries `/etc/image-build-info`, written during `%post` and mode `0444`:

```
IMAGE_NAME=rocky9
IMAGE_VERSION=0.1.0
GIT_COMMIT=<commit the template was built from>
SOURCE_ISO_CHECKSUM=sha256:<digest of the installation media>
BUILD_DATE=<UTC ISO 8601>
BUILDER=<qemu | vmware-iso | vsphere-iso>
```

The same values go into `manifest.json` via the manifest post-processor. Two copies on
purpose: the manifest is what the pipeline and the phase 5 catalogue consume, and
`/etc/image-build-info` is the copy that travels inside the image, so a running VM can
answer "what am I, and can I still be trusted?" without reference to anything external.
`SOURCE_ISO_CHECKSUM` makes a deployed VM traceable to the exact installation media it came
from.

---

## Hardening: what is applied

CIS Distribution Independent Linux Benchmark v2.0.0, Level 1, selected subset. The
distribution-independent numbering is used deliberately: Rocky and Ubuntu have their own
benchmarks with different numbering, and this role targets both. Claiming one benchmark's
section numbers while shipping the other distribution would be worse than using neither.

Implemented by [`ansible/roles/harden_linux`](../ansible/roles/harden_linux). Every task
name carries its section number, so the code maps to the benchmark without this document
in hand.

| CIS | Control | Applied | Note |
|---|---|---|---|
| 1.1.1 | Unused filesystem modules disabled | ✅ | `install ... /bin/true` **and** `blacklist`, plus an initramfs rebuild. Doing only the first leaves udev autoloading open |
| 1.1.2–1.1.9 | `nodev`/`nosuid`/`noexec` on `/tmp`, `/var/tmp`, `/home`, `/var/log`, `/var/log/audit`, `/dev/shm` | ✅ | The pay-off for the phase 1 partition layout. Fails the build if an expected filesystem is missing rather than hardening five of six and reporting success |
| 1.5.1 | ASLR enabled | ✅ | |
| 1.7.1–1.7.2 | Warning banner, MOTD stripped of OS detail | ✅ | Banner is deliberately generic — naming the org or OS version is free reconnaissance |
| 2.1.1 | Time synchronisation | ✅ | chrony on both, so there is one answer across the estate |
| 2.2.x | Unnecessary services disabled and masked | ✅ | avahi, cups, rpcbind, nfs-server |
| 2.3.x | Legacy clients removed | ✅ | telnet, rsh, talk, ypbind, tftp — removed, not just stopped |
| 3.1–3.3 | Kernel network parameters | ✅ | 24 parameters; source routing, redirects, martian logging, rp_filter, syncookies, IPv6 RA |
| 3.5.1 | Host firewall, default deny inbound | ✅ | firewalld (target DROP) on Rocky, ufw on Ubuntu. **Egress deliberately unrestricted** — see below |
| 4.1.1–4.1.2 | auditd installed, enabled, retention configured | ✅ | |
| 4.1.3–4.1.16 | Audit rules | ⚠️ Partial | A working subset: time, identity, network config, MAC policy, logins, permission changes, privilege escalation, modules, mounts. Not the full rule set — see below |
| 4.1.4 | Audit log permissions | ✅ | |
| 5.1.1–5.1.9 | cron/at permissions and allow-list | ✅ | Empty `cron.allow` + removed `cron.deny` — the model people get backwards |
| 5.2.x | SSH server configuration | ✅ | Written as a drop-in, **after verifying** `Include` precedes conflicting settings |
| 5.3.1 | Password quality | ✅ | minlen 14, all four credit classes |
| 5.4.2 | Account lockout | ⚠️ Partial | `faillock.conf` configured; PAM stack not rewritten — see below |
| 5.5.1–5.5.3 | Password ageing, TMOUT, umask | ✅ | umask 027, not 077 — see below |
| 5.6.1 | Only root has UID 0 | ✅ | Asserted, fails the build |
| 5.6.3 | root PATH integrity | ✅ | Asserted, fails the build |
| — | Build account and sudoers removed | ✅ | At shutdown, by the finalisation script — see ADR-0015 |
| — | machine-id, SSH host keys, logs, shell history cleared | ✅ | Every VM from one image would otherwise share a host key |

## Hardening: what is deliberately NOT applied

**This table is the point of the exercise.** Blanket-applying a benchmark to an image is
the easy half and produces something that either breaks workloads or gets switched off
wholesale within a month. Choosing, and being able to say why, is the job.

Four categories: controls that would break the build itself, controls that belong at
deployment rather than in the image, controls needing a site-specific decision, and
controls whose cost exceeds their benefit here.

| CIS | Control | Why not |
|---|---|---|
| 4.1.17 | `-e 2` — make audit rules immutable until reboot | **Belongs at deployment.** A golden image is a starting point; freezing the audit configuration means the consuming team cannot add the rules their workload actually needs without a reboot. The line is present and commented in the rules file, ready to be enabled by the deployment |
| 4.1.x | `admin_space_left_action = halt` | **Self-inflicted denial of service.** Halting a production host because its audit partition filled is worse than the risk it mitigates, and it is the single most commonly reverted CIS setting. Mitigated instead by `/var/log/audit` being its own filesystem and `SYSLOG` on the warning threshold |
| 4.1.x | The complete CIS audit rule set | **Volume over signal.** The full set generates enormous noise on a server running one application. The subset applied covers what is actually read during an incident. A deployment with a SIEM budget should extend it |
| 5.4.x | Rewriting the PAM stack to insert `pam_faillock` | **Breaks the build, and worse.** On RHEL this is `authselect`, on Ubuntu `pam-auth-update`; hand-editing `/etc/pam.d` is the most reliable way to produce an image nobody can log into. `faillock.conf` is honoured where the distribution already enables the module, which both do. Marked Partial rather than claimed |
| 3.5.x | Egress firewall rules | **Cannot be known at build time.** A golden image has no idea what its eventual workload must reach. An image shipping guessed egress rules is one whose firewall gets flushed by the first team to deploy it. Egress policy belongs to the deployment |
| 5.5.3 | `umask 077` | **Site-specific decision.** 027 is applied. 077 breaks any workload expecting group-readable files and is a common cause of a hardening role being disabled entirely. Overridable via `harden_linux_umask` |
| 1.1.x | Separate `/var/log/audit` on its own **physical** disk | **Cost exceeds benefit.** It is a separate logical volume, which addresses the fill-up risk. A separate spindle addresses an I/O contention risk this workload profile does not have |
| 1.6.x | SELinux/AppArmor policy authoring | **Out of scope.** Both are enforcing with vendor policy. Writing custom policy for an application nobody has chosen yet is not possible |
| 1.3.x | AIDE / file integrity monitoring | **Belongs at deployment.** A baseline database generated at build time is invalidated by the first legitimate change after deployment. Initialising AIDE is a deployment step |
| 1.4.x | Bootloader password | **Breaks unattended operation.** A GRUB password prevents unattended reboot, which is exactly what a cloud or hypervisor-hosted VM must do. Physical console access is the threat it addresses, and neither Azure nor vSphere exposes one in the relevant sense |
| 1.8.x | GDM / graphical login hardening | **Not applicable.** There is no display manager on a minimal server image |
| 2.2.x | Removing X11, Avahi, print server *packages* | **Already absent.** A minimal install does not have them. The role masks the services in case a later dependency pulls one in |
| 6.x | Full filesystem permission audit | **Not a build-time control.** Scanning every file for world-writable permissions and unowned files is a runtime job, and its findings on a fresh image are always empty by construction |
| — | FIPS mode | **Site-specific decision** with real consequences: it restricts algorithms system-wide and breaks software that uses non-approved crypto. Rocky's installer offers a FIPS boot entry; enabling it is a deployment decision, not an image default |

### Why not use an existing Galaxy CIS role?

Well-maintained roles exist — `ansible-lockdown/RHEL9-CIS` is the obvious one — and they
implement far more of the benchmark than this does.

They were not used, and the reason is the not-applied table above. Those roles are built to
be comprehensive and tuned by a long list of variables, which means the interesting decision
— *which controls does this image apply, and why not the others* — ends up expressed as a
hundred booleans in a vars file that nobody reads as a decision record. Writing a smaller
role made every inclusion and exclusion deliberate and explains each one in the place a
reviewer looks.

For a production estate the trade goes the other way: take the maintained role, and put the
effort into the exception register instead. That is the honest recommendation, and it is not
the same as what a portfolio repo should demonstrate.
