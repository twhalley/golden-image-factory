# golden-image-factory

How a standard, trustworthy OS image gets built, hardened, tested, signed, published and
retired — on VMware and in the cloud, from one set of provisioning code.

The claim this repo exists to prove:

> Hardened, versioned, tested and attested OS images, produced reproducibly on VMware and
> in the cloud, with evidence of what is inside them and when they expire.

> **Build status: phases 0, 1, 2, 4 and 6 complete; phase 3 written but not building.**
> Both Linux images build, harden and pass 140 assertions each **in CI on every PR**.
> Rocky 9 and Ubuntu 24.04 build, harden and pass their test gates end to end. Windows
> Server 2022 is written, validated and lint-clean, but Setup does not pick up the answer
> file on this builder — see [the write-up](evidence/windows-autounattend-not-detected-2026-08-14.md). This repo is under active construction and the table below is kept accurate as it goes. Anything not yet built is in
> [Roadmap](#roadmap) with a date, not implied by silence. See
> [Current state](#current-state) for exactly what exists today.

---

## Where each build target actually runs

The load-bearing table. Read it before anything else.

| Packer source | Where it runs | Actually executed? |
|---|---|---|
| `qemu` | GitHub Actions runner, and locally | **Yes — on every PR.** Both Linux images build, harden and pass their test gates in CI: [Rocky 21m14s, Ubuntu 15m18s](https://github.com/twhalley/golden-image-factory/actions). Locally too, with committed logs |
| `vmware-iso` | VMware Workstation, local machine | **Not yet** — validated only; Workstation not yet installed on the build host |
| `vsphere-iso` | Nested ESXi 8 + VCSA, 60-day evaluation | **Not yet** — `packer validate` only until phase 9 lands |
| `azure-arm` | Azure Compute Gallery, free credit | **Not yet** — `packer validate` only; target phase 8 |

CI builds use KVM. GitHub-hosted `ubuntu-24.04` runners do have `/dev/kvm`, but it is
`root:kvm` and the runner user is outside that group — so the naive check reports "no KVM",
the build silently drops to TCG software emulation, and fifteen minutes becomes several
hours with nothing in the log saying why. The capability job distinguishes *absent* from
*present-but-inaccessible* and grants access in the second case.

Per image:

| Image | Builds | Hardened | Test gate |
|---|---|---|---|
| Rocky 9.8 | **yes**, locally on QEMU/KVM | yes | **140 assertions, 0 failures** |
| Ubuntu 24.04.4 | **yes**, locally on QEMU/KVM | yes | **140 assertions, 0 failures** |
| Windows Server 2022 | **no** — Setup does not apply the answer file on this builder | role written, lint-clean | Pester suite written, never executed |

No row says "yes" until there is a committed artefact or build log behind it, and the row
says exactly what was executed and where. `qemu` is built locally today and in CI from
phase 6; those are different claims and the table keeps them apart. There are no
synthesised build logs in this repo and there will not be any.

All four sources are covered by `packer validate` on every PR, including the two nothing
builds yet — a source nobody exercises is precisely the one that rots. Getting `azure-arm`
into that set was not free: the plugin authenticates during `prepare`, so it cannot be
validated on dummy variables alone ([ADR-0010](docs/DECISIONS.md#adr-0010)).

**Why there is no Azure VMware Solution here.** AVS provisions a minimum of three
*dedicated bare-metal* nodes charged hourly, and now additionally requires a portable
VMware VCF subscription bought separately from Broadcom. There is no free tier because
there cannot be one for dedicated hosts — the shortfall against free credit is orders of
magnitude, not a margin. Google Cloud VMware Engine and Oracle Cloud VMware Solution have
the same shape. Full reasoning in [ADR-0006](docs/DECISIONS.md#adr-0006).

---

## Current state

**Phases 0 (shift-left), 1 (Packer skeleton), 2 (Ansible hardening), 4 (test gates) and
6 (CI/CD): complete. Phase 3 (Windows): written, not building — see the roadmap.**

What exists and works today:

- `.pre-commit-config.yaml` — gitleaks, large-file guard, private-key detection, yamllint,
  shellcheck, ansible-lint, terraform fmt/tflint, `packer fmt`, and a conventional-commit
  message check. Runs before a commit object exists.
- `.github/workflows/security.yml` — gitleaks over full history plus working tree, checkov
  over Terraform/Actions/Ansible, and `packer fmt` + `packer validate` + conftest over the
  templates. `permissions: {}` at workflow level with per-job grants. Every action pinned to
  a full commit SHA.
- `.github/dependabot.yml` — weekly bumps for those SHA-pinned actions, because a pin that
  is never updated is a pin to a known-vulnerable version.
- `scripts/bootstrap-repo-settings.sh` — re-runnable configuration of secret scanning,
  push protection, squash-only merges and the `main` ruleset with an **empty bypass list**.
- [`docs/SHIFT-LEFT.md`](docs/SHIFT-LEFT.md) — every gate, what it catches, and what it
  misses. Including the part most repos leave out: **IaC scanners cover Terraform well and
  Packer HCL barely at all**, so the Packer templates here are not scanned to the standard
  the Terraform is, and the artefact tests in phase 4 are the control worth trusting.
- `packer/linux/` — four sources (`qemu`, `vmware-iso`, `vsphere-iso`, `azure-arm`) and two
  distributions from **one** set of source blocks, one build block and one manifest. Rocky
  9.8 (kickstart, xfs, SELinux) and Ubuntu 24.04.4 (autoinstall, ext4, AppArmor) both build
  unattended on QEMU/KVM in ~14 minutes to an identical eight-filesystem layout. All four
  sources validate on every PR.
- `policy/packer.rego` — the hand-written OPA policy that stands in for the Packer IaC
  scanning no vendor ships. Five deny rules, each verified to fire against a deliberately
  bad template.
- `ansible/roles/harden_linux` — a selected subset of CIS Level 1 applied identically to
  both distributions, every task tagged with its CIS section. `ansible-lint` clean at the
  **production** profile. The build account, machine-id, SSH host keys and build traces are
  removed at shutdown by a finalisation script, because the account cannot delete itself
  while Packer is logged in as it ([ADR-0015](docs/DECISIONS.md#adr-0015)).
- `tests/goss/` — the test gate, run **inside the guest** before shutdown, so it tests the
  image rather than the template. It asserts the *effective* configuration (`sshd -T`,
  `sysctl -n`) rather than file contents, which is how it caught a hardening control that
  had been reviewed, committed and built three times without being in effect
  ([ADR-0021](docs/DECISIONS.md#adr-0021)).
- `tests/pester/` — the Windows equivalent. Written; never executed, because phase 3 does
  not build.
- `.github/workflows/` — `lint.yml` (fmt, validate across every OS × every source,
  ansible-lint, tflint, yamllint, PSScriptAnalyzer), `security.yml`, `build.yml` (QEMU
  matrix + compliance artefact), and **`scheduled-rebuild.yml`**, which is the answer to
  "how do you handle patch management".
- `scripts/make-build-key.sh` — ephemeral per-build SSH key, so no build credential exists
  in git and none outlives the build.
- [`docs/IMAGE-STANDARD.md`](docs/IMAGE-STANDARD.md) — partition layout, packages and the
  rule that decides what goes in the installer versus configuration management.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — twenty-two ADRs.
- [`evidence/`](evidence/) — the gates tested, with the results that were inconvenient kept
  rather than replaced by ones that pass. Two are worth reading on their own:
  **AWS's canonical example credential pair does not trip gitleaks** (it is allowlisted
  upstream), and **a randomly generated AWS key does not trip GitHub push protection**
  (real key IDs carry a checksum). Both obvious ways to test an AWS secret gate produce a
  false pass. The push-protection test that *did* fire used a Slack webhook, a Stripe key
  and a SendGrid key, and was rejected server-side with `GH013`.

Everything else in the layout below is a directory waiting for its phase.

---

## Roadmap

Dates are targets, not commitments. A phase is marked complete only when its acceptance
criteria are met and its evidence is committed.

| Phase | Scope | Target |
|---|---|---|
| 0 | Shift-left gates, repo rulesets, docs skeleton | **done — 2026-08-14** |
| 1 | Packer skeleton; Rocky 9 kickstart, Ubuntu 24.04 autoinstall; `qemu` build end to end | **done — 2026-08-14** |
| 2 | `harden_linux` Ansible role, CIS Level 1 subset with a stated applied/not-applied table | **done — 2026-08-14** |
| 3 | Windows Server 2022 — `Autounattend.xml`, Ansible over WinRM, `harden_windows`, sysprep | **written, not building** — [4 next steps](evidence/windows-autounattend-not-detected-2026-08-14.md) |
| 4 | goss and Pester gates, in-guest, with machine-readable compliance reports | **Linux done — 2026-08-14**; Pester written, blocked on phase 3 |
| 6 | CI: lint, matrix build, monthly scheduled rebuild, releases | **done — 2026-08-14** (releases are phase 7) |
| 7 | Supply chain — syft SBOM, trivy CVE **diff** gate, cosign keyless, provenance, one OpenVEX triage | after interview |
| 5 | Image catalogue, lifecycle model, Terraform `image_selector` that refuses expired images | after interview |
| 8 | Azure Compute Gallery as a second publishing target, OIDC only, native `endOfLifeDate` | after interview |
| 9 | Nested ESXi + VCSA lab; `vsphere-iso` from validated-only to executed | after interview |

Phases 5, 7, 8 and 9 are designed but unbuilt, and phase 3 is built-but-not-working. None
of it is left sitting in `main` looking finished:

- **Phase 3** has a [written-up diagnosis](evidence/windows-autounattend-not-detected-2026-08-14.md)
  with six ruled-out hypotheses and four ranked next steps, so resuming costs minutes
  rather than repeating the six build attempts.
- **Phases 5, 7, 8 and 9** exist as design in the docs and as directories in the tree, with
  no code pretending to implement them. The `terraform/` lint job and the catalogue bump
  step in `scheduled-rebuild.yml` both no-op with an explicit notice until phase 5 lands,
  rather than failing or silently passing.

---

## What this repo deliberately does not do

- **It is not a cloud migration repo.** Terraform has exactly one job (phase 5): consuming
  images by version and refusing ones past their retirement date. Azure has exactly one
  job (phase 8): being a second publishing target that proves the factory is not tied to
  one platform.
- **It does not claim bit-identical images across platforms.** The `azure-arm` build starts
  from a marketplace base image rather than an ISO — the correct Azure pattern. Azure and
  VMware images share the Ansible roles and the test suites, not the installer
  configuration.
- **It does not apply a CIS benchmark wholesale, and does not claim to.** It applies a
  selected subset of Level 1 with every omission listed and justified in
  [`IMAGE-STANDARD.md`](docs/IMAGE-STANDARD.md) — the not-applied table is longer than the
  applied one. No CIS certification, no Level 2, no claim of full Level 1 conformance.
  Blanket-applying a benchmark to an image is the easy half; choosing is the job.
- **It is a proof of concept, not a production image factory.** Where a control is partial,
  the docs say partial.

---

## Repository layout

```
packer/          four sources — qemu, vmware-iso, vsphere-iso, azure-arm — one build
ansible/         roles shared by every target: common, harden_linux, harden_windows
tests/           goss (Linux) and Pester (Windows), run inside the guest before shutdown
policy/          conftest/OPA policies — the substitute for absent Packer IaC scanning
terraform/       one module: image_selector, which fails a plan on an expired image
catalogue/       images.json — the versioned index of what exists and when it retires
attestations/    OpenVEX documents and signing material
evidence/        real, sanitised build logs and screenshots
docs/            the deliverable
scripts/         repo bootstrap
```

## Documentation

| Document | What it is for |
|---|---|
| [`SHIFT-LEFT.md`](docs/SHIFT-LEFT.md) | Every gate, what it catches, what it misses, why it sits where it sits |
| [`DECISIONS.md`](docs/DECISIONS.md) | ADRs — context, decision, consequence, rejected alternatives |
| [`IMAGE-STANDARD.md`](docs/IMAGE-STANDARD.md) | What a compliant image contains — **partial**: layout and packages now, the applied/not-applied control table is phase 2 |
| `LIFECYCLE.md` | Versioning, statuses, retirement, consumer obligations (phase 5) |
| [`THREATMODEL.md`](docs/THREATMODEL.md) | What this pipeline stops and, honestly, what it does not — **partial**, phase 0 source-side gaps only; artefact side is phase 7 |
| [`RUNBOOK.md`](docs/RUNBOOK.md) | Copy-paste procedures — **partial**: workstation setup and environment traps now; build, patch, roll back and tear down arrive with the phases that create them |
| `VSPHERE-PATH.md` | Nested lab, evaluation expiry, production differences (phase 9) |

## Quickstart

```bash
git clone https://github.com/twhalley/golden-image-factory
cd golden-image-factory
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg
pre-commit run --all-files
```

Tool versions are pinned and listed in [ADR-0002](docs/DECISIONS.md#adr-0002).

## Sibling repos

- **[`payments-platform-poc`](https://github.com/twhalley/payments-platform-poc)** —
  Kubernetes, GitOps and software supply-chain integrity: how workloads get deployed and
  proven.
- **[`slo-reliability-poc`](https://github.com/twhalley/slo-reliability-poc)** — SLOs,
  error budgets and incident response on AWS/EKS: how running services are measured and
  defended.
- **this repo** — the layer underneath both: how the OS image they run on is built,
  hardened, tested, signed, published and retired.
