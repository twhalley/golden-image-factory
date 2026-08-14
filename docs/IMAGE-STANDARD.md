# Image standard

What a compliant image from this factory contains, and why.

> **Status: phase 1 content.** Structure — partitioning, packages, the build
> account, identity metadata. The applied/not-applied **hardening control table** is
> phase 2 and is not here yet. Until it lands, this repo claims no CIS conformance of any
> kind, and the [README](../README.md) says so.

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

| Mount | Size | Type | Why it is separate |
|---|---|---|---|
| `/boot` | 1024 MB | xfs, plain partition | Outside LVM so the bootloader does not depend on LVM being assembled |
| `/` | 8192 MB | xfs, LVM | |
| `/home` | 1024 MB | xfs, LVM | Carries `nodev,nosuid` in phase 2. Small — a server image is not a workstation |
| `/var` | 4096 MB | xfs, LVM | A runaway package cache or spool must not fill `/` |
| `/var/log` | 2048 MB | xfs, LVM | A log flood must not fill `/` or `/var` |
| `/var/log/audit` | 2048 MB | xfs, LVM | **The important one.** `auditd` is configured to halt or stop logging when its filesystem fills. Sharing that filesystem with general logs means any chatty service can trigger it |
| `/var/tmp` | 1024 MB | xfs, LVM | Carries `nodev,nosuid,noexec` in phase 2 |
| `/tmp` | 1024 MB | xfs, LVM | As above |

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
| SELinux | **enforcing** | Never disabled. Turning SELinux off is the most common shortcut in a golden image and it silently invalidates a large part of any CIS claim |
| firewalld | enabled, `ssh` only | Default deny inbound |
| root password | locked | Root cannot log in, locally or remotely |
| root SSH | denied (phase 2 enforces in `sshd_config`) | |
| Build account | key-only, no password | See below |
| Timezone | UTC | An image carrying a site's timezone cannot be used at another site |

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
