# Shift-left: where the gates are, what they catch, what they miss

Built in **phase 0, before any Packer code existed**. That order is the argument: a gate
added after the code it guards has already had a chance to be wrong. This document is
deliberately as long on limitations as on capabilities — a gate whose blind spots are
undocumented gives false assurance, which is worse than no gate.

## The three gates

| # | Gate | Where it runs | Bypassable? | What it costs |
|---|---|---|---|---|
| 1 | `pre-commit` hooks | Developer's machine, before the commit object exists | Yes — `git commit --no-verify` | ~2–8 s per commit |
| 2 | `security.yml` on PR | GitHub-hosted runner | No, if branch protection requires it | ~1–2 min per PR |
| 3 | GitHub push protection | GitHub's servers, at `git push` | Only with an audited bypass reason (disabled here by ruleset) | 0 |

Gate 1 is fast and advisory. Gate 2 is slow and authoritative. Gate 3 is the one a
developer cannot turn off, which is why the secret-scanning control lives at all three
levels rather than only the convenient one.

Gates 4 and 5 — artefact SBOM, CVE diff gate, signing and provenance — are phase 7 and
apply to the built image rather than the source. They are documented in
[`THREATMODEL.md`](THREATMODEL.md).

---

## Gate 1 — pre-commit (`.pre-commit-config.yaml`)

Install once per clone:

```bash
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg
pre-commit run --all-files    # first run, to establish a clean baseline
```

| Hook | Catches | Does not catch |
|---|---|---|
| `gitleaks` | High-entropy strings and provider-specific key formats in the staged diff | Secrets that do not match a rule (a bare password, a custom token format), and anything already in history — gate 2 scans history, this one scans the diff |
| `check-added-large-files` (512 KB) | A `.qcow2`, `.vmdk` or ISO committed by accident | A large file added in a commit made with `--no-verify` |
| `detect-private-key` | PEM-format private keys | Keys stored base64-wrapped or in a non-PEM container |
| `yamllint --strict` | Malformed and inconsistent YAML in workflows, Ansible and goss suites | Semantically wrong but well-formed YAML — a valid workflow that does the wrong thing |
| `shellcheck` | Unquoted expansions, `cd` without `&&`, portability errors in provisioner scripts | Logic errors; anything inside a heredoc passed to a guest |
| `ansible-lint` | Role structure, deprecated modules, missing `changed_when`, idempotency smells | Whether the hardening control actually landed on the image — that is phase 4's goss suite, not a linter |
| `terraform_fmt`, `terraform_tflint` | Formatting drift, provider misuse, unused declarations | Anything requiring `terraform init` — see below |
| `packer fmt -check` | Formatting drift in HCL2 templates | Everything else about Packer — see the known gap below |
| `conventional-commit` | Commit messages that break the release-note and semver tooling in phase 5 | Accurate-but-meaningless messages (`fix: fix`) |

**Deliberately not in pre-commit:**

- `terraform validate` and `packer validate` both require an `init` step that reaches the
  network to fetch providers and plugins. A pre-commit hook that fails on a train is a
  pre-commit hook that gets uninstalled. Both run in CI instead.
- `checkov` takes tens of seconds on a cold cache. Same reasoning — CI only.
- `trivy` needs the built artefact, which does not exist at commit time.

**Honest limitation:** every hook here is bypassable with `git commit --no-verify`, and
that is not a flaw to be engineered around — it is why gates 2 and 3 exist. Local hooks
exist to give fast feedback to a cooperating developer, not to constrain a hostile one.

### Two things learned from actually testing this gate

Both from [`evidence/gate1-precommit-secret-block-2026-08-14.md`](../evidence/gate1-precommit-secret-block-2026-08-14.md),
where the test is captured in full.

**AWS's canonical example credentials do not trip gitleaks.** A commit containing
`AKIAIOSFODNN7EXAMPLE` / `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` succeeded — gitleaks
reports `no leaks found`, because that pair is allowlisted upstream to avoid firing on the
documentation it appears in. This is correct behaviour and a trap: validating a secret
scanner with a vendor's published example proves only that the allowlist works. The test
here uses randomly generated key material in the real format instead.

**The block came from entropy, not from an AWS rule.** The finding that stopped the commit
was `generic-api-key` at entropy 4.67 on the secret, not an AWS-specific pattern. gitleaks
detects what matches a rule or looks random — so **a low-entropy secret in an unrecognised
format, such as a short database password or a bespoke internal token, passes all three
gates.** No scanner in this repo catches that. The mitigation is `.gitignore`, the
`*.pkrvars.hcl.example` convention, `PKR_VAR_*` environment variables for real values, and
review — not tooling.

---

## Gate 2 — `security.yml` on every pull request

Three jobs, each with least-privilege permissions. The workflow declares
`permissions: {}` at the top level, so every job starts with nothing and is granted
`contents: read` explicitly.

### `secrets` — gitleaks over full history

Checked out with `fetch-depth: 0` and `persist-credentials: false`. Runs twice, because
the two modes find different things:

- `gitleaks git` walks every commit. A secret committed on Tuesday and deleted on
  Wednesday is still leaked; only a history scan sees it.
- `gitleaks dir` walks the working tree as files on disk.

gitleaks is installed from a **pinned release, checksum-verified in the workflow**,
rather than via the marketplace action. Rationale in
[`DECISIONS.md`](DECISIONS.md#adr-0003).

### `iac` — checkov

Frameworks: `terraform`, `github_actions`, `ansible`, `dockerfile`, `secrets`.
`soft_fail: false` — findings fail the PR. `download_external_modules: false` so the scan
does not reach out to arbitrary registries.

### `packer-policy` — `packer fmt` and (from phase 1) OPA policy

Guarded so it no-ops cleanly while `packer/` is still empty.

---

## Gate 3 — GitHub repository settings

These are not in the repo, because GitHub does not store them there. They are recorded
here so the configuration is reviewable, and evidenced by the screenshots in
[`evidence/`](../evidence/).

| Setting | Value | Why |
|---|---|---|
| Secret scanning | Enabled | Catches what gitleaks' ruleset misses, using GitHub's partner patterns |
| **Push protection** | Enabled | Blocks the push itself, server-side. Not bypassable by `--no-verify` |
| Push protection bypass | No bypass allowed | A bypass that anyone can grant themselves is not a control |
| Dependabot | Enabled, `github-actions` ecosystem, weekly | SHA-pinned actions never drift — and never get patched either, without this |
| Branch protection on `main` | PR required, **0** approving reviews, stale reviews dismissed, review threads must resolve | 0 approvals is deliberate on a single-maintainer repo — see [ADR-0004](DECISIONS.md#adr-0004). Everything else still applies to the admin |
| Required status checks | `gitleaks`, `checkov`, `packer fmt + opa policy` | Strict mode: branch must be up to date |
| Require signed commits | Yes | See the commit-signing note below |
| Force push / deletion | Blocked | |
| Ruleset bypass list | Empty, including for the repo admin | The admin is the most valuable account to compromise |

Apply with the script in [`../scripts/bootstrap-repo-settings.sh`](../scripts/bootstrap-repo-settings.sh).
Verified working: see [`evidence/gate3-push-protection-2026-08-14.md`](../evidence/gate3-push-protection-2026-08-14.md),
where a push carrying fabricated Slack, Stripe and SendGrid credentials was rejected
server-side with `GH013` after local hooks were deliberately bypassed.

### Push protection is pattern-based, and an AWS key is the wrong way to test it

The same test found something worth carrying into how anyone verifies this control.
**A randomly generated AWS access key ID is not detected by push protection**, because a
real one encodes an account identifier and checksum after the `AKIA` prefix; a random
string matches the shape but fails the structure and is discarded as a false positive.
Meanwhile gitleaks allowlists AWS's canonical published example pair. So the two obvious
ways to test an AWS secret gate both produce a false pass, at different gates, for
different reasons:

| Test credential | Gate 1 (gitleaks) | Gate 3 (push protection) |
|---|---|---|
| `AKIAIOSFODNN7EXAMPLE` | allowlisted — not detected | not detected |
| Random `AKIA` + 16 chars | detected, via generic entropy | **not detected** |
| A real AWS key | detected | detected |

Test with a checksum-free provider format instead — a Slack webhook URL, a Stripe or
SendGrid key. More generally: push protection recognises **published provider formats**.
It will not catch a bespoke internal token, a database password, or a vCenter credential,
because those have no format for GitHub to recognise — and those are precisely the secrets
this repo handles. That is why real values live in `PKR_VAR_*` environment variables and
only `*.pkrvars.hcl.example` with dummy values is committed.

### Commit signing — a prerequisite that bites

Requiring signed commits rejects a push whose commits GitHub cannot *verify*, which needs
two things to line up:

1. the signing key registered on the GitHub account, and
2. the commit author email being a **verified address on that account** and present as a
   UID on the signing key.

A locally-signed commit whose email is not on the key or not verified on GitHub shows as
`Unverified` and is rejected by the ruleset. Fix, for a GPG key:

```bash
gpg --quick-add-uid <FINGERPRINT> "Your Name <your-verified@example.com>"
gpg --armor --export <FINGERPRINT> | gh gpg-key add -    # needs `gh auth refresh -s admin:gpg_key`
git config user.email your-verified@example.com          # per-repo, if the global one differs
```

---

## Known gap: IaC scanners barely cover Packer

This is the most important paragraph in this document.

Checkov, tfsec, Terrascan and KICS all have deep Terraform and CloudFormation coverage,
reasonable Kubernetes and Dockerfile coverage, and **effectively no policy library for
Packer HCL2**. Packer templates are not scanned in any way comparable to Terraform. Any
repo claiming "IaC scanning" while shipping mostly Packer is overstating what it has.

What is actually done here instead, and none of it is equivalent:

| Substitute | Real assurance it provides |
|---|---|
| `packer fmt -check` | Formatting only. Zero security value. |
| `packer validate` in CI, all four sources with dummy vars | Syntax, variable wiring, plugin resolution. Catches a broken `vsphere-iso` block that nobody builds. No security value. |
| `conftest`/OPA policies under `policy/` | Bespoke assertions written for *this* repo: no plaintext credential defaults, `ssh_password` never set where a key is possible, `communicator` never `none`, ISO checksums always pinned rather than `none`. Real, but only as good as the policies written — there is no upstream corpus to inherit. |
| goss / Pester in phase 4 | The strongest control of the four, because it tests the **built image** rather than the template that claims to build it. |

The honest summary: for Terraform, an off-the-shelf scanner with hundreds of maintained
rules. For Packer, a handful of hand-written rules and a test suite against the artefact.
The artefact tests are the ones to trust.

---

## Deliberately deferred

Named here so they read as decisions rather than omissions:

- **SARIF upload to GitHub code scanning.** Would put checkov and gitleaks findings in the
  Security tab. Deferred to phase 7, where the artefact scanners produce findings worth an
  alert lifecycle. Phase 0's job was to make the gates exist and be green.
- **Signed pre-commit hook revisions.** `pre-commit` pins hook repos by tag, not SHA.
  Tags are mutable. `pre-commit`'s own cache mitigates but does not solve this; the
  residual risk is recorded in [`THREATMODEL.md`](THREATMODEL.md).
- **A self-hosted runner.** Would remove the trust dependency on GitHub-hosted runners,
  and add a much larger one on a machine in a spare room. Not worth it here.
