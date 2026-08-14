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
