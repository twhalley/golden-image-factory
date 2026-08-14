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
