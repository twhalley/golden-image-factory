# golden-image-factory

How a standard, trustworthy OS image gets built, hardened, tested, signed, published and
retired — on VMware and in the cloud, from one set of provisioning code.

The claim this repo exists to prove:

> Hardened, versioned, tested and attested OS images, produced reproducibly on VMware and
> in the cloud, with evidence of what is inside them and when they expire.

> **Build status: phases 0 and 1 complete** — Rocky 9 and Ubuntu 24.04 both build end to
> end. Phase 2 (Ansible hardening) next. This repo is under active construction and the table below is kept accurate as it goes. Anything not yet built is in
> [Roadmap](#roadmap) with a date, not implied by silence. See
> [Current state](#current-state) for exactly what exists today.

---

## Where each build target actually runs

The load-bearing table. Read it before anything else.

| Packer source | Where it runs | Actually executed? |
|---|---|---|
| `qemu` | Local QEMU/KVM, and a GitHub Actions runner from phase 6 | **Yes, locally** — [Rocky 9.8, 9m06s](evidence/qemu-rocky9-2026-08-14.log) and [Ubuntu 24.04.4, 14m04s](evidence/qemu-ubuntu2404-2026-08-14.log). **Not yet in CI** |
| `vmware-iso` | VMware Workstation, local machine | **Not yet** — validated only; Workstation not yet installed on the build host |
| `vsphere-iso` | Nested ESXi 8 + VCSA, 60-day evaluation | **Not yet** — `packer validate` only until phase 9 lands |
| `azure-arm` | Azure Compute Gallery, free credit | **Not yet** — `packer validate` only; target phase 8 |

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

**Phase 0 — shift-left foundations: complete. Phase 1 — Packer skeleton: complete.**

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
- `scripts/make-build-key.sh` — ephemeral per-build SSH key, so no build credential exists
  in git and none outlives the build.
- [`docs/IMAGE-STANDARD.md`](docs/IMAGE-STANDARD.md) — partition layout, packages and the
  rule that decides what goes in the installer versus configuration management.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — fourteen ADRs.
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
| 2 | `harden_linux` Ansible role, CIS Level 1 subset with a stated applied/not-applied table | next |
| 3 | Windows Server 2022 — `Autounattend.xml`, Ansible over WinRM, `harden_windows`, sysprep | |
| 4 | goss and Pester gates, in-guest, with machine-readable compliance reports | |
| 6 | CI: lint, matrix build, monthly scheduled rebuild, releases | |
| 7 | Supply chain — syft SBOM, trivy CVE **diff** gate, cosign keyless, provenance, one OpenVEX triage | after interview |
| 5 | Image catalogue, lifecycle model, Terraform `image_selector` that refuses expired images | after interview |
| 8 | Azure Compute Gallery as a second publishing target, OIDC only, native `endOfLifeDate` | after interview |
| 9 | Nested ESXi + VCSA lab; `vsphere-iso` from validated-only to executed | after interview |

Phases 5, 7, 8 and 9 are designed but unbuilt. Their design is written into the docs
where it belongs and marked as roadmap; none of it is left sitting in `main` looking
finished.

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
- **It does not apply a CIS benchmark wholesale.** It applies a selected subset with the
  omissions listed and justified. Blanket-applying a benchmark to an image is the easy
  half; choosing is the job.
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
