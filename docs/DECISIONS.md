# Decision record

ADR-style. One entry per non-obvious choice: context, decision, consequence, rejected
alternatives. Appended each phase; never rewritten — a superseded decision gets a new
entry that says so.

---

## ADR-0001 — Shift-left gates are built before the code they gate

**Phase:** 0
**Status:** accepted

**Context.** The natural build order is Packer template first, then hardening, then
"add some CI". Gates added that way are shaped by the code that already exists: they
codify whatever was done rather than constraining what may be done. By the time a secret
scanner is added, the history it would have protected has already been written.

**Decision.** Phase 0 builds `pre-commit`, `security.yml`, repository rulesets and push
protection against an empty repository. The first real commit of Packer code passes
through gates that already existed.

**Consequence.** The acceptance test for phase 0 — a fake AWS key blocked locally and
server-side — is run against a repo with no application code in it, which is the only
moment it can be tested cleanly. Slight cost: `security.yml` needs a guard so the Packer
job no-ops while `packer/` is empty.

**Rejected.** Building the image pipeline first and retrofitting gates. Cheaper by a few
hours, and it makes "shift left" a label applied afterwards rather than a build order.

---

## ADR-0002 — Tooling installed as pinned, checksum-verified binaries in `~/.local/bin`

**Phase:** 0
**Status:** accepted

**Context.** The build host is Arch Linux, where `sudo` requires an interactive password
and rolling-release packages move independently of the repo. Packer, Terraform, gitleaks,
tflint, conftest, trivy, goss and shellcheck all need specific versions that CI can
reproduce.

**Decision.** Upstream release binaries into `~/.local/bin`, versions recorded in
`docs/RUNBOOK.md`. Python tooling (ansible-core, ansible-lint, yamllint, checkov,
pre-commit) via `pipx`, which isolates each into its own virtualenv. goss was verified
against the upstream `SHA256SUMS` at install time.

Versions as of 2026-08-14: Packer 1.16.0, Terraform 1.15.8, gitleaks 8.30.1,
tflint 0.64.0, conftest 0.69.0, trivy 0.73.0, goss 0.4.10, shellcheck 0.11.0,
ansible-core 2.21.3, ansible-lint 26.8.0, checkov 3.3.11, pre-commit 4.6.2.

**Consequence.** Local and CI versions are pinned to the same numbers and drift is a
visible diff rather than a surprise. Updating is manual — Dependabot covers GitHub
Actions, not these.

**Note.** goss's release asset naming is `goss_<ver>_linux_x86_64.tar.gz`, not the bare
`goss-linux-amd64` binary that older documentation and blog posts reference. That older
URL 404s. Recorded because it costs ten minutes to rediscover.

**Rejected.** `pacman -S` for everything — no version pinning against CI, and needs an
interactive password. A devcontainer — real benefit for reproducibility, but it adds a
Docker dependency to a repo whose whole subject is VM images, and the indirection would
confuse rather than clarify.

---

## ADR-0003 — gitleaks runs as a pinned binary in CI, not as the marketplace action

**Phase:** 0
**Status:** accepted

**Context.** `gitleaks/gitleaks-action` is the obvious choice and is SHA-pinnable like any
other action. However it introduces a licence-key concept (`GITLEAKS_LICENSE`) for
organisation accounts, and it is one more third-party action executing in a job that has
read access to the repository.

**Decision.** Download the pinned gitleaks release tarball in the job and verify its
SHA-256 against a checksum committed in the workflow's `env:` block before executing it.

**Consequence.** The workflow is a few lines longer and the checksum must be bumped by
hand alongside the version. In exchange the supply chain for this step is one HTTPS
download with a verified digest, no marketplace dependency, and no licence-key
conditionality — and it demonstrates the pinning discipline the rest of the repo argues
for. `actions/checkout` and `actions/setup-python` remain SHA-pinned marketplace actions;
the point is not to eliminate actions but to be deliberate about each one. This decision
was vindicated for a different tool within the hour — see [ADR-0008](#adr-0008).

**Rejected.** The marketplace action, for the reasons above. Vendoring the gitleaks
binary into the repo — defeats the large-file rule and rots silently.

---

## ADR-0004 — A ruleset with an empty bypass list, and zero required approvals

**Phase:** 0
**Status:** accepted

**Context.** `main` must be protected. GitHub offers classic branch protection and the
newer rulesets. Classic protection always leaves administrators able to bypass, and
`enforce_admins` is a single blunt toggle.

**Decision.** A ruleset named `main-protection` with `"bypass_actors": []` — the
repository admin is subject to it. Required signed commits, required status checks in
strict mode, squash-only merges, no deletion, no force push.

`required_approving_review_count` is **0**. On a single-maintainer repo a rule demanding
an approver who cannot exist either blocks every merge or gets bypassed, and a bypass
would destroy the empty bypass list that is the interesting part of this configuration.
The rest of the ruleset still applies: PR required, checks must pass, commits must be
signed.

**Consequence.** No self-merge shortcut exists — every change goes through a PR whose
checks must pass, including the author's. The honest limitation is that a
single-maintainer repo cannot demonstrate four-eyes review; it can only demonstrate that
everything else is enforced without exception. Stated in `SHIFT-LEFT.md` rather than left
for a reviewer to notice.

**Rejected.** Classic branch protection with `enforce_admins` — nearly equivalent, but it
cannot express an empty bypass list as data, and rulesets are where GitHub is investing.
Setting the review count to 1 and adding a bypass actor for the admin — theatre.

---

## ADR-0005 — Packer HCL is not meaningfully covered by IaC scanning, and this is stated rather than papered over

**Phase:** 0
**Status:** accepted

**Context.** The repo claims IaC scanning as a control. Checkov, tfsec, Terrascan and KICS
have large maintained Terraform policy libraries and essentially nothing for Packer HCL2.
This repo is mostly Packer.

**Decision.** Run checkov where it is genuinely useful (Terraform, GitHub Actions
workflows, Ansible), and cover Packer with `packer fmt -check`, `packer validate` across
all four sources, and hand-written `conftest`/OPA policies under `policy/` asserting the
things that can actually be asserted about a template. Document the gap prominently in
`SHIFT-LEFT.md` and state that the phase 4 artefact tests, not the template scanning, are
the control worth trusting.

**Consequence.** The repo cannot claim its Packer templates are scanned to the standard
its Terraform is. It can claim the built images are tested, which is the stronger claim
anyway.

**Rejected.** Running checkov over `packer/` and reporting a clean result. It would be
clean because there is nothing to find, not because there is nothing wrong, and an
interviewer who knows the tooling would read it as either ignorance or spin.

---

## ADR-0006 — Azure VMware Solution is not used; the vSphere path is a nested evaluation lab

**Phase:** 0 (recorded early because it shapes the README's reality table)
**Status:** accepted

**Context.** The repo wants a genuinely executed `vsphere-iso` build. The obvious cloud
route is a managed VMware offering.

**Decision.** No Azure VMware Solution. Real vCenter comes from a nested ESXi 8 host plus
VCSA inside VMware Workstation, both under 60-day evaluation licensing (phase 9).

**Consequence.** The vSphere build is real but nested, so storage performance, DRS/HA and
distributed switching are not representative, and the environment expires. Both facts are
documented in `docs/VSPHERE-PATH.md` rather than glossed.

**Rejected.**
- **Azure VMware Solution** — provisions a minimum of three *dedicated bare-metal* nodes
  charged hourly, and now additionally requires a portable VMware VCF subscription
  purchased separately from Broadcom. There is no free tier, because there cannot be one
  for dedicated hosts. Free credit is short by orders of magnitude, not by a margin.
- **Google Cloud VMware Engine, Oracle Cloud VMware Solution** — same shape, same
  dedicated-node minimum, same conclusion.
- **The free vSphere Hypervisor build of ESXi 8.0U3e** — Broadcom ships two different
  installer builds. The free-licensed one cannot join vCenter and exposes a read-only
  management API, so Packer's `vsphere-iso` builder cannot drive it. The
  evaluation/licensed build is required.

---

## ADR-0007 — Hardware is sufficient for the nested lab

**Phase:** 0
**Status:** accepted

**Context.** Phase 9 needs VCSA (tiny deployment, ~14 GB RAM) and a nested ESXi host
(8–16 GB) running simultaneously inside Workstation. Committing an evening to it before
checking the headroom is how evenings get wasted.

**Decision.** Verified before planning phase 9: 62 GiB RAM (45 GiB available),
16 threads on a Ryzen 7 3800X, 1.2 TB free. Sufficient with margin. Phase 9 stays in
scope as an executed path rather than a validated-only one.

**Consequence.** The README reality table can promise a real `vsphere-iso` build, subject
to phase 9 actually landing before interview day. Until it does, the table says
`packer validate` only — the promise is not written until the build log is committed.

**Note.** VMware Workstation was not installed at phase 0 and is being installed
separately. Workstation and KVM cannot both drive `/dev/kvm` concurrently; the two
hypervisors coexist on disk but not at runtime. Documented in `RUNBOOK.md`.

---

## ADR-0008 — checkov runs from a pinned pip install, not the marketplace action

**Phase:** 0
**Status:** accepted

**Context.** `security.yml` initially used `bridgecrewio/checkov-action`, SHA-pinned to
`v12.1347.0` as the pinning policy requires. It failed on first run. The reason is worth
recording in full:

```
##[command]/usr/bin/docker run ... bridgecrew/checkov:2.0.930 ...
checkov: error: argument --framework: invalid choice:
  'terraform,github_actions,ansible,dockerfile,secrets'
```

A current, correctly SHA-pinned action was executing **checkov 2.0.930** — a 2021 release,
three major versions behind the 3.3.11 in use locally. That version has no `ansible`
framework at all, and takes `--framework` as repeated space-separated values rather than
the comma-separated string the action passes.

**The general lesson, which matters more than the fix.** Pinning an action to a full commit
SHA pins *the action's source*. It does not pin what the action runs. This one resolves a
container image tag internally, so the SHA pin gave a precise handle on a wrapper around an
unpinned, four-year-stale dependency. The security theatre was invisible until it happened
to break.

**Decision.** Install checkov directly with `pip install checkov==3.3.11`, version held in
the workflow's `env:` block alongside the gitleaks pin, and invoke it with the correct
space-separated framework list. Consistent with [ADR-0003](#adr-0003).

**Consequence.** One fewer marketplace dependency and a version that is actually the one
tested locally. Two residual gaps, stated rather than hidden: the pip install is
version-pinned but **not hash-pinned**, so it trusts PyPI and checkov's transitive
dependency tree; and the version must be bumped by hand, since Dependabot covers the
`github-actions` ecosystem here, not inline pip pins. Both go in `THREATMODEL.md`.

**Rejected.** Pinning the action to an older tag whose bundled container is newer —
guesswork, and it would recur. Passing `framework: all` to make the error go away —
would have masked the stale version entirely, which is the actual defect.

---

## ADR-0009 — The kickstart is served over HTTP and reached by editing the GRUB entry

**Phase:** 1
**Status:** accepted

**Context.** Anaconda can be pointed at a kickstart in two ways. Packer's built-in HTTP
server plus an `inst.ks=` kernel argument typed by `boot_command`, or a volume labelled
`OEMDRV` containing `/ks.cfg`, which anaconda finds automatically with no kernel argument
and no keystrokes at all.

`boot_command` is the fragile part of any ISO-based Packer build. EL9 removed isolinux and
boots the installer through GRUB2 on both BIOS and UEFI, so the `<tab>`-then-append pattern
that every EL7 and EL8 example uses does not apply — the entry has to be opened with `e`,
the cursor moved onto the `linux` line, and the edit committed with Ctrl-X rather than
Enter.

**Decision.** HTTP plus a GRUB edit, as specified. The boot command is a per-OS variable
rather than part of the shared source block, and every keystroke in it is commented in
`rocky9.pkrvars.hcl` with what it is for.

**Consequence.** The templated kickstart can carry build-time values — the ephemeral SSH
public key, the image version, the git commit — because `templatefile()` renders it into
`http_content` at build time. That is what keeps the build public key out of the
repository. An `OEMDRV` volume would need the rendered file written to disk first.

The cost is a boot command that depends on the installer's GRUB menu layout, so a change to
the Rocky ISO's default entry ordering breaks the build. It fails loudly at the SSH timeout
rather than silently, which is the acceptable failure mode.

**Rejected.** `OEMDRV` via `cd_files`/`cd_label` — genuinely more robust, needs no
keystrokes, and is the better choice for a build that must never flake. Not taken because
templating the kickstart is worth more here than removing the boot command, and because the
HTTP path is what the brief specified. Recorded because it is the first thing to switch to
if the boot command proves unreliable in CI.

---

## ADR-0010 — Azure authenticates with an OIDC token in `client_jwt`, which is also what makes the source validatable

**Phase:** 1 (wiring), 8 (execution)
**Status:** accepted

**Context.** Two requirements collided. Azure auth must be a GitHub OIDC federated
credential with no client secret anywhere. And `packer validate` must cover all four
sources on every PR, including `azure-arm`, so that a source nobody builds cannot rot
unnoticed.

The azure plugin authenticates during `prepare`, not at build time. With no credentials it
fails validation outright:

```
No valid set of authentication values specified:
  to use the Managed Identity of the current machine, do not specify any of the fields below:
  - client_secret
  - client_jwt
  - client_cert_path
  - use_azure_cli_auth
```

Tested and rejected: omitting `client_id`, setting `use_azure_cli_auth = false`, and
supplying `ARM_OIDC_TOKEN` in the environment. All three fail the same way. **`packer
validate` for `azure-arm` is not credential-free**, and any repo claiming to validate an
Azure source with purely dummy variables should be read carefully.

**Decision.** Set `client_jwt = var.azure_oidc_token`. This is not a workaround — it is the
correct wiring for a federated credential. `client_jwt` is the field the plugin expects a
federated OIDC assertion in; the workflow requests a short-lived token from the Actions
runtime and passes it as `PKR_VAR_azure_oidc_token`. The variable carries a dummy default,
which is what makes `packer validate` pass locally and in PRs with no Azure access.

**Consequence.** All four sources validate with `packer validate`, and the same field
carries the real token in phase 8 — the validation path and the production path are the
same code, not two configurations that can drift. No client secret exists to leak;
`policy/packer.rego` fails the build if `client_secret` ever appears in an Azure source.

**Rejected.** Excluding `azure-arm` from validation and documenting the gap — acceptable,
but it leaves the least-exercised source also the least-checked. A dummy `client_secret` to
satisfy `prepare` — would have put a fake secret in the repo and, worse, made the
secret-based auth path the one that gets tested.

---

## ADR-0011 — Structure goes in the installer, configuration goes in Ansible

**Phase:** 1
**Status:** accepted

**Context.** Some hardening can be expressed in more than one place. Mount options such as
`nodev,nosuid,noexec` can be set by the kickstart with `--fsoptions`, or by Ansible editing
`/etc/fstab`. Doing both is worse than either.

**Decision.** The installer does only what cannot be changed afterwards — principally the
filesystem layout, since a filesystem that was not created separately cannot be given its
own mount options without a rebuild. Everything else, mount options included, is the
Ansible role's job.

**Consequence.** The deciding factor is `azure-arm`, which has no kickstart at all because
it builds from a marketplace base image. Any control implemented in the kickstart either
misses the Azure image or needs a second, divergent implementation for it. Controls
implemented in Ansible apply to all four targets from one definition and are covered by one
goss suite.

This makes the kickstart look thinner than a typical hardened-image kickstart. That is the
intended shape, and `IMAGE-STANDARD.md` states the rule so it does not read as an omission.

**Rejected.** Setting mount options in the kickstart because it is "closer to the metal" —
it produces two sources of truth for a control, and the Azure image silently gets the weaker
one.

---

## ADR-0012 — The build credential is an ephemeral key pair, not a password

**Phase:** 1
**Status:** accepted

**Context.** Most Packer ISO examples set a build password in the kickstart and
`ssh_password` in the source. It is simple and it works. It also means a credential lives in
the repository, and it survives into the published image unless something explicitly
removes it.

**Decision.** `scripts/make-build-key.sh` generates an ed25519 key per build into a
gitignored directory and prints the `PKR_VAR_*` exports. The public half is injected into
the templated kickstart at build time; the private half never leaves the build host. The
`packer` account is created with a locked password and is key-only.

**Consequence.** No build credential exists in git at any point, and the credential's
lifetime is one build. Slight friction: a build needs `eval "$(scripts/make-build-key.sh)"`
first, which is documented in `RUNBOOK.md` and handled by a step in CI.

`policy/packer.rego` denies any source that sets `ssh_password`, so the shortcut cannot be
reintroduced quietly. The `packer` account and its sudoers file are removed by the
`harden_linux` role in phase 2, and phase 4's goss suite asserts they are gone — until
then, `IMAGE-STANDARD.md` states plainly that built images still contain a build account.

**Rejected.** `ssh_password` with a value from `PKR_VAR_*` — keeps the secret out of git but
still puts a password on the image. A long-lived committed public key — no secret in the
repo, but every image ever built would trust one key that cannot be rotated without
rebuilding all of them.

---

## ADR-0013 — Rocky 9 is built from `boot.iso`, because `minimal.iso` cannot be verified

**Phase:** 1
**Status:** accepted

**Context.** Pinning the Rocky 9.8 ISO and its digest — the most routine step in the phase —
produced a download of 2.48 GB against a published 1.48 GB. Client-side causes were ruled
out by repeating the download without `curl -C -` and again with no `--retry` at all; the
size was unchanged.

The server sends 2,755,067,904 bytes for `Rocky-9.8-x86_64-minimal.iso`. The `CHECKSUM`
manifest in the same directory claims 1,480,048,640. `boot.iso` and `dvd.iso` both match
their published digests exactly; only `minimal` disagrees, and the manifest gives it the
same byte count as `boot.iso` — which is what a stale or copy-pasted entry looks like. Four
independent mirrors serve byte-identical content, so this is a manifest problem rather than
a corrupt mirror. The manifest is unsigned, so there is no cryptographic way to decide which
side is authoritative.

A second line of evidence was tried and discarded: the served `minimal.iso` reports an ISO
volume label of `Rocky-9-8-x86_64-dvd`, which reads as conclusive. It is not — the verified
`boot.iso` carries the identical label, because Rocky labels by release rather than by
variant and the installer depends on it (`inst.stage2=hd:LABEL=Rocky-9-8-x86_64-dvd`). The
evidence file keeps the discarded reasoning rather than quietly dropping it.

Full detail: [`evidence/rocky98-minimal-iso-checksum-mismatch-2026-08-14.md`](../evidence/rocky98-minimal-iso-checksum-mismatch-2026-08-14.md).

**Decision.** Build from `Rocky-9.8-x86_64-boot.iso`, whose digest verifies, and declare the
package source in the kickstart with `url` and `repo` directives. The image becomes a
network install.

**Consequence.** The build now requires a reachable package mirror, and two builds from the
same commit on different days may pull different package versions. The second cost is
smaller than it looks: the kickstart runs a full `dnf upgrade` in `%post` regardless, so the
image was never bit-reproducible across time. Accountability comes from the manifest and the
phase 7 SBOM recording what actually landed, not from pretending the inputs are frozen.

If a later point release fixes the manifest, reverting is two lines in
`rocky9.pkrvars.hcl` plus dropping the `url`/`repo` directives.

**Rejected — and this is the important part.** Downloading the 2.75 GB file, computing its
SHA-256, and pinning that. It would work, `packer validate` would pass, and the
`iso_checksum` field would be populated. It would also mean pinning a digest derived from an
unverified download: the value would record whatever the mirror served that day, every
future build would faithfully reproduce it, and the chain of custody from vendor to image
would be broken with nothing visible to show it. For a repo whose claim is evidence of
what is inside an image, that is exactly the wrong trade.

Also rejected: `dvd.iso`, which verifies but is 15 GB; and `iso_checksum = "none"`, which is
a real Packer feature, would have made the problem vanish in under a minute, and is denied
outright by `policy/packer.rego` for precisely this reason.

---

## ADR-0014 — The image standard claims "mandatory access control", not "SELinux"

**Phase:** 1
**Status:** accepted

**Context.** The shared verification provisioner ran `getenforce` and asserted `Enforcing`.
That is correct on Rocky and meaningless on Ubuntu, which enforces with AppArmor and ships
no `getenforce` binary. The first Ubuntu build completed a flawless install — all eight
filesystems, identity metadata written — and then died at exit 127 on that one line.

The tempting fixes are both wrong. Dropping the check to `getenforce || true` makes it pass
everywhere by asserting nothing. Branching the provisioner per family duplicates the step
that exists specifically to be shared.

**Decision.** One check that runs `getenforce` where it exists, `aa-enabled` otherwise, and
**fails if neither is present**. And, more importantly, the wording changes: the image
standard claims **mandatory access control is enforcing**, not that SELinux is.

**Consequence.** The claim is now true of every image the factory produces and testable on
every one of them by phase 4's goss suite. It also sets the pattern for phase 2, where the
same split recurs and matters much more — a CIS Level 1 subset written against SELinux does
not transfer to AppArmor, and the applied/not-applied table has to say so per family rather
than implying one benchmark covers both.

**Rejected.** Claiming "SELinux enforcing" in the image standard while shipping Ubuntu —
false on half the images, and the kind of claim that survives right up until someone checks.
Building only RHEL-family images to avoid the problem — the job description names both
families, and the divergence is the interesting part rather than an obstacle.

---

## ADR-0015 — The build account is removed at shutdown, not by the hardening role

**Phase:** 2
**Status:** accepted

**Context.** `harden_linux` must remove the `packer` build account and its passwordless
sudoers entry before the image is published. Packer is logged in **as that account**, and
after the last provisioner it opens a fresh session to run `shutdown_command`. Deleting the
account from a provisioner therefore breaks the connection Packer needs to shut the machine
down, and the build fails having done everything correctly.

**Decision.** Split it. The role installs `/usr/local/sbin/image-finalize.sh`, and the
source's `shutdown_command` invokes that script through `sudo`. Running as root, it removes
the sudoers file, kills and deletes the account, clears machine-id, SSH host keys, shell
history, package caches and build logs, trims free space, and powers off — one action that
does not need to survive its own effects.

The shutdown command falls back to a plain `shutdown -P now` when the script is absent, so
a build with the Ansible provisioner disabled still terminates rather than hanging for the
full `shutdown_timeout`.

**Consequence, and it is a real one.** Phase 4's goss suite runs in-guest *before*
finalisation, so **it cannot assert that the build account is gone** — at the moment it
runs, the account is still there and still required. The absence has to be verified against
the artefact offline instead. That limitation is stated in `IMAGE-STANDARD.md` rather than
left for someone to assume the in-guest suite covers it.

Secondary benefit: machine-id and SSH host key removal belong in the same place. Every VM
built from an image that kept its host keys presents the same keys, so a
man-in-the-middle against one is a man-in-the-middle against all of them — and a shared
machine-id makes cloned VMs collide on DHCP leases.

**Rejected.** Removing the account in the last provisioner and letting Packer fail — the
artefact is discarded on failure, so this produces no image at all. Locking the account
instead of deleting it — leaves a real account with a real authorized_keys file in the
published image, which is the thing being avoided. A systemd oneshot that cleans up on
first boot — the published image still contains the account, so anyone inspecting the
artefact finds it.

---

## ADR-0016 — A smaller hand-written role, not an off-the-shelf CIS role

**Phase:** 2
**Status:** accepted

**Context.** Maintained CIS roles exist — `ansible-lockdown/RHEL9-CIS` is the obvious one —
and they implement far more of the benchmark than this repo does.

**Decision.** Write a smaller role covering a selected subset, with every applied control
tagged by CIS section and every omitted control listed with its reason in
`docs/IMAGE-STANDARD.md`.

**Consequence.** Less coverage. In exchange, the interesting decision — *which controls this
image applies and why not the others* — is expressed as prose a reviewer reads, rather than
as a hundred booleans in a vars file that nobody reads as a decision record. The
not-applied table is longer than the applied table, and deliberately so: it separates
controls that break the build, controls belonging at deployment, controls needing a
site-specific decision, and controls whose cost exceeds their benefit.

**For a production estate the trade goes the other way** — take the maintained role and put
the effort into the exception register instead. That is the honest recommendation, and it is
stated in `IMAGE-STANDARD.md` rather than left implied, because it is not the same as what a
portfolio repo should demonstrate.

**Rejected.** Importing the Galaxy role and tuning it — better coverage, but the repo would
then be demonstrating the ability to set variables. Claiming full CIS Level 1 — untrue, and
the sort of claim that survives exactly until someone runs a scanner against the image.

---

## ADR-0017 — Windows WinRM teardown and sysprep run as one shutdown command

**Phase:** 3
**Status:** accepted

**Context.** To reach a freshly installed Windows machine, the build configures WinRM over
HTTP with Basic authentication and `AllowUnencrypted`. Every one of those settings is a
serious finding in a published image. They must not survive, and they cannot be removed
from an Ansible task: Packer's next action after provisioning is `shutdown_command`, and
that command travels over WinRM. Disabling the transport from a task means sysprep never
runs, the image is never generalised, and the build fails having done everything else
correctly.

**Decision.** `harden_windows` stages `C:\Windows\image-finalize.ps1` as its last task, and
the source's `shutdown_command` invokes it. The script reverses the permissive settings,
removes the listener and both the custom and built-in firewall rules, disables the service,
then runs `sysprep /generalize /oobe /shutdown /mode:vm`. It severs its own transport and
powers off, so nothing needs to outlive its own effects. Same shape as the Linux
finalisation script ([ADR-0015](#adr-0015)).

**Consequence, stated rather than glossed.** The Pester suite runs in-guest *before* this,
so it **cannot** assert that WinRM is disabled — at the moment it runs, WinRM is up and
required. What it asserts instead is the *contract*: that the script exists and contains
each teardown step. That is weaker than testing the result, and saying so is the point; an
assertion that silently tested nothing would be worse. The end state is verified against the
artefact offline.

`/shutdown` and not `/reboot`, deliberately: rebooting runs the specialize pass and undoes
generalisation, producing an image that is not generalised while appearing to have been
sysprepped.

**Rejected.** Tearing down WinRM in a task and letting Packer fail — produces no artefact.
Leaving WinRM enabled and documenting it — the permissive configuration is the single worst
thing that could ship in this image. A scheduled task that cleans up on first boot — the
published image still contains the listener, so anyone inspecting the artefact finds it.

---

## ADR-0018 — Windows uses a per-build password because it has no key equivalent

**Phase:** 3
**Status:** accepted

**Context.** The Linux images authenticate the build with an ephemeral SSH key
([ADR-0012](#adr-0012)), so no build credential exists in the repository and none outlives
the build. WinRM has no equivalent: it authenticates with a username and password, and
`Autounattend.xml` must contain the Administrator password in plaintext for Setup to apply
it.

**Decision.** Accept the password, and constrain everything around it. It is generated per
build, supplied only through `PKR_VAR_winrm_password`, never written to the repository, and
substituted into the answer file at build time via `templatefile()` — the same mechanism the
kickstart uses for the SSH public key. The variable enforces a 14-character minimum. Sysprep
disables the built-in Administrator during generalisation, and `policy/packer.rego` denies
any source that hardcodes `winrm_password` rather than taking it from a variable.

**Consequence.** The Windows image has a weaker build-credential story than the Linux images
and that asymmetry is a property of the platform, not of the pipeline. Stating it plainly is
better than implying parity: the answer file genuinely does contain a plaintext password
while the build runs, and the mitigation is its lifetime and blast radius, not its absence.

**Rejected.** WinRM over HTTPS with a self-signed certificate — moves the trust problem
rather than solving it, since Packer must then skip certificate validation anyway. A fixed
password in a `.pkrvars.hcl` — a credential in the repository, which is the thing being
avoided.

---

## ADR-0019 — Windows is written and validated but NOT built; the reality table says so

**Phase:** 3
**Status:** accepted, unresolved

**Context.** The Windows Server 2022 templates, `harden_windows` role and Pester suite are
complete, `packer validate` passes for all three sources, and `ansible-lint` is clean at the
production profile. **The QEMU build does not complete.** Windows Setup stops at the
language-selection screen and never applies the answer file, with no error logged in
`setuperr.log`.

Six build attempts ruled out: the disk bus (QEMU has no `if=sata`), CD versus floppy
delivery, the missing floppy controller on q35 (real, fixed by moving to i440fx), the file's
presence and validity on the media (extracted and parsed on the host), XSD element ordering,
and content before the root element. Full detail in
[`evidence/windows-autounattend-not-detected-2026-08-14.md`](../evidence/windows-autounattend-not-detected-2026-08-14.md).

**Decision.** Ship the code, mark the image **not executed** in the README reality table, and
write up what was tried so resuming costs minutes rather than repeating six builds. Do not
add a `windows2022` job to `build.yml`.

**Consequence.** Phase 3's acceptance criteria are not met and the README says so. The
strongest temptation here was to describe the templates as "complete" and let the reality
table's `packer validate` row carry the implication that the image works — a claim nobody
would immediately check. Passing `validate` means the template is syntactically sound and
internally consistent. It is not evidence that an image was produced, and this repo's entire
argument is the difference between those two things.

A permanently failing CI job would be the other wrong answer: a red check that everyone
learns to ignore is worse than a documented gap.

**Rejected.** Claiming the phase complete on the strength of validation. Deleting the
Windows work to keep the repo tidy — the brief is explicit that Windows and testing are what
distinguish this repo, and unfinished-and-documented beats absent.

---

## ADR-0020 — The hardening broke the build tooling, and the tooling moved

**Phase:** 4
**Status:** accepted

**Context.** With phase 2's controls applied, every shell provisioner after the Ansible run
started failing:

```
bash: line 1: /tmp/script_7933.sh: Permission denied
Script exited with non-zero exit status: 126
```

Packer's shell provisioner uploads its script to `/tmp` and executes it. `harden_linux`
mounts `/tmp` with `noexec` (CIS 1.1.2). The control worked exactly as designed and broke
the tool that applied it.

**Decision.** Set `remote_folder` to the build account's home. `/home` is mounted
`nodev,nosuid` but deliberately **not** `noexec`, so scripts run there and the `/tmp`
control stays intact.

**Consequence.** This is the shape of the argument that comes up whenever a hardening
baseline meets a real system, in miniature: the control is correct, something legitimate
broke, and there are two ways out. Relaxing `/tmp` to `exec` would have fixed the build in
one character and quietly removed a control the image standard claims and the goss suite
asserts. Moving the tooling costs one line and keeps both.

It is also a good answer to "a CIS control breaks the application team's app": find out what
the control is actually protecting, find out what the application actually needs, and change
the thing that is cheaper to change — after establishing that it is genuinely cheaper, not
just closer to hand.

**Rejected.** Mounting `/tmp` without `noexec`. Running provisioners before the hardening —
would work, and would mean nothing that runs afterwards is ever tested against the hardened
image, which is the state the test gate exists to verify.

---

## ADR-0021 — The sshd drop-in is named `00-`, not `99-`, and the test suite is why we know

**Phase:** 4
**Status:** accepted

**Context.** `harden_linux` writes its sshd configuration as a drop-in under
`/etc/ssh/sshd_config.d/`, originally named `99-cis-hardening.conf` on the usual convention
that a high number sorts last and therefore wins.

**That convention is backwards for sshd.** OpenSSH takes the **first** value it sees for most
keywords, and `Include` processes the drop-in directory in lexical order. RHEL 9 ships
`50-redhat.conf`, which contains `X11Forwarding yes`. A `99-` prefixed file is read *after*
it and loses — silently. The file exists, its contents are exactly right, a review of the
repository passes, and X11 forwarding is still enabled on the image.

**Decision.** Rename to `00-cis-hardening.conf` so the hardening is read before any
distribution drop-in.

**How this was found, which is the point.** Phase 4's goss suite asserts the **effective**
configuration by parsing `sshd -T` output, not just the contents of the file it wrote. On
the first run: 138 assertions, 137 passed, and the single failure was
`x11forwarding no` missing from the effective configuration.

A suite that checked only the file — which is the obvious thing to write, and what the
`file:` assertions in `shared.yaml` do — would have reported a clean pass on an image where
the control was not in effect. That is precisely the false pass the test gate exists to
catch, and it caught it on a control that had been reviewed, committed and built three times
without anyone noticing.

The same reasoning is why the suite reads `sysctl -n` from the running kernel rather than
trusting `/etc/sysctl.d/99-cis.conf`, and why the role asserts the `Include` directive
precedes any conflicting setting before writing the drop-in at all.

**Rejected.** Editing `50-redhat.conf` — it is package-owned and an upgrade replaces it.
Editing `sshd_config` directly — same problem, and it loses the single-file property that
makes the hardening readable and removable as a unit.

---

## ADR-0022 — Split goss suites merge by key, and a duplicate key silently deletes assertions

**Phase:** 4
**Status:** accepted

**Context.** The goss suite is split: `shared.yaml` holds everything true of both
distributions, and `rocky9.yaml` / `ubuntu2404.yaml` include it and add their own. Both the
shared file and each OS file originally asserted things about `/etc/image-build-info`.

goss merges included gossfiles **by key**. A second `file:` block for the same path does not
add to the first — it **replaces** it. The only sign is a warning in the output:

```
[WARN] Duplicate key detected: 'file: /etc/image-build-info'.
The value from a later-loaded goss file has overwritten the previous value.
```

Six assertions from `shared.yaml` — including that the image records `HARDENED=true` and the
originating git commit — were being silently dropped, on every image, while the suite
reported a pass.

**Decision.** Per-OS additions that concern a resource already asserted in `shared.yaml` are
written as `command:` assertions with distinct keys instead. Anything genuinely
distribution-specific gets its own key; nothing redefines a key from the shared file.

**Consequence.** A test suite that quietly tests less than it appears to is worse than a
smaller suite, because it is trusted more. Worth carrying into any layered test
configuration — the same trap exists in Ansible variable precedence and in Kubernetes
kustomize overlays, and in all three it presents as a passing run rather than an error.

**Rejected.** Ignoring the warning — it is a warning precisely because the tool cannot tell
whether the override was intended, and here it was not.
