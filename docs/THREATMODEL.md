# Threat model

> **Status: partial — phase 0 content only.** The full model belongs to phase 7, where the
> artefact-side controls (SBOM, CVE diff gate, signing, provenance, VEX) exist and can be
> reasoned about. This file exists now because phase 0 has already produced residual gaps,
> and a gap recorded when it is discovered is a gap; a gap recorded at the end of a project
> is a memory. Everything below is about the **source** pipeline. Nothing here yet claims
> anything about built images.

## What the phase 0 gates stop

| Threat | Control | Where |
|---|---|---|
| A credential in a known provider format reaching a commit object | gitleaks pre-commit hook | Developer machine |
| A credential already in history, on a branch pushed from a machine without hooks | gitleaks over full history on every PR | CI |
| A credential in a published provider format reaching GitHub at all, even with hooks bypassed | GitHub push protection | GitHub, server-side |
| A misconfigured Terraform resource or GitHub Actions workflow | checkov | CI |
| A force push or deletion rewriting `main` | Ruleset: `non_fast_forward`, `deletion` | GitHub |
| A change merged without passing checks, including by the repo admin | Ruleset with an empty bypass list | GitHub |
| A commit from a key not registered to the account | Ruleset: `required_signatures` | GitHub |
| A build artefact or ISO committed by accident | `check-added-large-files` (512 KB), `.gitignore` | Developer machine |

## What it does not stop — phase 0 residual gaps

Recorded as discovered. None of these are hypothetical; each was established by testing
or by reading what the tooling actually does.

**A low-entropy secret in an unrecognised format.** No gate here catches a short database
password, a bespoke internal token, or a vCenter credential. gitleaks finds what matches a
rule or looks random; push protection finds published provider formats. A vCenter password
is neither. *Mitigation, such as it is:* real values live only in `PKR_VAR_*` environment
variables, `.gitignore` excludes `*.pkrvars.hcl`, and only `.pkrvars.hcl.example` with
dummy values is committed. That is convention and review, not enforcement.

**An AWS key cannot be used to verify the AWS path.** Demonstrated in
[`evidence/gate3-push-protection-2026-08-14.md`](../evidence/gate3-push-protection-2026-08-14.md):
the canonical example pair is allowlisted by gitleaks, and a randomly generated key fails
GitHub's checksum validation. The AWS detection path is therefore **asserted, not tested**,
because testing it honestly would require a real credential.

**A SHA-pinned action can still run unpinned code.** Established the hard way in
[ADR-0008](DECISIONS.md#adr-0008): `bridgecrewio/checkov-action`, correctly pinned to a
full commit SHA, resolved a container image internally and executed checkov 2.0.930 from
2021. Pinning an action pins the action's source, not its transitive runtime. Every
remaining marketplace action in this repo — `actions/checkout`, `actions/setup-python` —
has the same theoretical exposure.

**pip and pre-commit dependencies are version-pinned but not hash-pinned.** `checkov` is
installed by version from PyPI, and `pre-commit` pins hook repositories by **tag**, which
is mutable. A compromised upstream or a retagged release would execute in CI. `pre-commit`'s
local cache limits but does not remove this.

**A maintainer with repository write access.** The ruleset requires a PR and passing
checks, but with `required_approving_review_count: 0` on a single-maintainer repo, a
maintainer can author and merge their own change. Four-eyes review is not demonstrable
here; see [ADR-0004](DECISIONS.md#adr-0004).

**The GitHub-hosted runner itself.** Every gate except the local hooks executes on
infrastructure this repo does not control, using a token this repo does not mint.

**Everything about the built image.** Phase 0 gates source code. Nothing here says
anything about what ends up inside a `.qcow2` — not the upstream ISO's integrity, not the
packages installed from a distribution mirror, not the Packer plugin supply chain, not
runtime drift after deployment. That is phase 7's subject, and until phase 7 lands, this
repo makes **no** claim about artefact integrity.

## Deferred to phase 7

SBOM per image, CVE **diff** gate against the previously published version rather than an
absolute threshold, cosign keyless signing via Fulcio/Rekor, `actions/attest-build-provenance`,
and one real CVE triaged to `not_affected` in an OpenVEX document. Each will be added here
with what it stops and what it does not.
