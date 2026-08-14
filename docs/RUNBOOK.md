# Runbook

> **Status: phase 0 content only.** Build, patch, roll-back and teardown procedures arrive
> with the phases that create the things they operate on. What is here now is workstation
> setup and the two environment traps that cost time if hit blind.

## Contents

- [Build a Linux image](#build-a-linux-image)
- [Workstation setup](#workstation-setup)
- [Pinned tool versions](#pinned-tool-versions)
- [Trap: signed commits that GitHub will not verify](#trap-signed-commits-that-github-will-not-verify)
- [Trap: VMware Workstation and KVM cannot both hold `/dev/kvm`](#trap-vmware-workstation-and-kvm-cannot-both-hold-devkvm)
- [Applying repository settings](#applying-repository-settings)

---

## Build a Linux image

```bash
# 1. Ephemeral build key. Regenerated per build; never committed.
eval "$(scripts/make-build-key.sh)"

# 2. Plugins, pinned by packer/linux/plugins.pkr.hcl
packer init packer/linux

# 3. Validate every source — including the two nothing builds yet, which are
#    precisely the ones that rot unnoticed.
packer validate -var-file=packer/linux/rocky9.pkrvars.hcl packer/linux

# 4. Build. -only is not optional: without it Packer runs all four sources,
#    including azure-arm, which would try to spend money.
packer build \
  -only='linux.qemu.linux' \
  -var-file=packer/linux/rocky9.pkrvars.hcl \
  -var "git_commit=$(git rev-parse --short HEAD)" \
  packer/linux
```

Artefacts land in `builds/` (gitignored) with `manifest.json` alongside.

**Use a local ISO** to avoid re-downloading 1.5 GB per build. Packer accepts a path as
`iso_url`, and the checksum is still verified.

Fetch it with the checksum verified before it is used, and **not** with `curl -C -` and
`--retry` together. If a retry fires against a server that does not honour the range
request, curl appends the whole body again rather than resuming — producing a file that is
larger than the real ISO and silently corrupt. Observed here: a 2.48 GB file for a
1.48 GB ISO. Download to a `.part` name, verify, then rename:

```bash
mkdir -p ~/.cache/golden-image-factory/isos
cd ~/.cache/golden-image-factory/isos
iso=Rocky-9.8-x86_64-minimal.iso
curl -fL --retry 3 --retry-delay 2 -o "${iso}.part" \
  "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/${iso}"
echo "d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4  ${iso}.part" \
  | sha256sum -c - && mv "${iso}.part" "${iso}"
```

```bash
packer build -only='linux.qemu.linux' \
  -var-file=packer/linux/rocky9.pkrvars.hcl \
  -var "iso_url=$HOME/.cache/golden-image-factory/isos/Rocky-9.8-x86_64-minimal.iso" \
  packer/linux
```

**Watch the installer** when a boot command misbehaves — this is the only practical way to
debug `boot_command`, because a wrong keystroke shows up as an SSH timeout 45 minutes
later with no other clue:

```bash
packer build -only='linux.qemu.linux' -var headless=false ...
```

**Build on Workstation instead of QEMU** — note the `/dev/kvm` conflict below:

```bash
packer build -only='linux.vmware-iso.linux' ...
```

### If the build hangs waiting for SSH

Almost always the boot command, not the network. In order of likelihood:

1. The GRUB menu changed in a new ISO point release, so `<up>` selects the wrong entry.
   Re-run with `-var headless=false` and watch.
2. The kickstart failed and anaconda is sitting on an error screen. Same fix — watch it.
3. `/dev/kvm` is held by Workstation's `vmmon`, so QEMU fell back to software emulation and
   is simply slow rather than stuck.

---

## Workstation setup

Clone and enable the local gate:

```bash
git clone https://github.com/twhalley/golden-image-factory
cd golden-image-factory
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg
pre-commit run --all-files
```

Tooling is installed as pinned upstream binaries into `~/.local/bin` rather than from the
distribution's package manager, so local versions match CI. Reasoning in
[ADR-0002](DECISIONS.md#adr-0002).

```bash
# Binaries — adjust versions from the table below
mkdir -p ~/.local/bin && cd "$(mktemp -d)"

curl -fsSLO https://releases.hashicorp.com/packer/1.16.0/packer_1.16.0_linux_amd64.zip
curl -fsSLO https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_linux_amd64.zip
curl -fsSLO https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
curl -fsSLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/tflint_linux_amd64.zip
curl -fsSLO https://github.com/open-policy-agent/conftest/releases/download/v0.69.0/conftest_0.69.0_Linux_x86_64.tar.gz
curl -fsSLO https://github.com/aquasecurity/trivy/releases/download/v0.73.0/trivy_0.73.0_Linux-64bit.tar.gz
curl -fsSLO https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_linux_x86_64.tar.gz
curl -fsSLO https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_SHA256SUMS
curl -fsSLO https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz

grep 'linux_x86_64.tar.gz' goss_0.4.10_SHA256SUMS | sha256sum -c -

for z in *.zip; do unzip -oq "$z"; done
for t in *.tar.gz; do tar xzf "$t"; done
tar xJf shellcheck-v0.11.0.linux.x86_64.tar.xz
install -m 0755 packer terraform tflint gitleaks conftest trivy goss \
                shellcheck-v0.11.0/shellcheck ~/.local/bin/

# Python tooling, each isolated in its own virtualenv
pipx install ansible-core ; pipx install ansible-lint ; pipx install yamllint
pipx install checkov      ; pipx install pre-commit
```

**goss asset naming.** The download is `goss_<version>_linux_x86_64.tar.gz`. Older
documentation and most blog posts reference a bare `goss-linux-amd64` binary at the
release root; that URL now 404s.

### Pinned tool versions

Established 2026-08-14. CI pins the same numbers — `security.yml` holds gitleaks and
checkov versions in its `env:` block.

| Tool | Version | | Tool | Version |
|---|---|---|---|---|
| Packer | 1.16.0 | | ansible-core | 2.21.3 |
| Terraform | 1.15.8 | | ansible-lint | 26.8.0 |
| gitleaks | 8.30.1 | | yamllint | 1.38.0 |
| tflint | 0.64.0 | | checkov | 3.3.11 |
| conftest | 0.69.0 | | pre-commit | 4.6.2 |
| trivy | 0.73.0 | | shellcheck | 0.11.0 |
| goss | 0.4.10 | | | |

Bumping these is manual. Dependabot covers the `github-actions` ecosystem only.

---

## Trap: signed commits that GitHub will not verify

The `main-protection` ruleset requires signed commits. GitHub rejects a push whose commits
it cannot **verify**, which is a stricter condition than "the commit carries a signature".
Three things must line up:

1. the signing key is uploaded to the GitHub account,
2. the commit author email is a **verified** address on that account, and
3. that same email is a UID on the signing key.

Diagnose against what GitHub actually thinks, not against `git log --show-signature`:

```bash
gh api repos/<owner>/<repo>/commits \
  --jq '.[0:5][] | "\(.sha[0:7]) verified=\(.commit.verification.verified) reason=\(.commit.verification.reason)"'
```

`reason=no_user` means the key is not on the account at all. `reason=unverified_email`
means the key is there but the commit email is not a verified account address.

Fix, for a GPG key:

```bash
gh auth refresh -h github.com -s admin:gpg_key      # interactive, browser
gpg --quick-add-uid <FULL_FINGERPRINT> "Your Name <your-verified@example.com>"
gpg --armor --export <KEY_ID> | gh gpg-key add -
git config user.email your-verified@example.com     # repo-local if the global differs
```

Adding the key retroactively re-verifies commits already pushed, so historical commits
turn from `Unverified` to `Verified` without a rebase.

---

## Trap: VMware Workstation and KVM cannot both hold `/dev/kvm`

Relevant from phase 1, where `vmware-iso` builds run locally alongside `qemu` builds, and
critical for phase 9's nested lab.

Both hypervisors coexist on disk. Neither will start a VM while the other holds the
hardware virtualisation device. Symptom is Workstation reporting that it cannot run in
hardware-accelerated mode, or QEMU falling back to software emulation and taking an order
of magnitude longer.

```bash
# Which module is loaded?
lsmod | grep -E '^(kvm_amd|kvm_intel|vmmon)'

# Free the device for Workstation
sudo modprobe -r kvm_amd kvm        # kvm_intel on Intel hosts

# Free it for QEMU/libvirt
sudo modprobe -r vmmon vmnet
sudo modprobe kvm_amd
```

On Arch, Workstation's `vmmon`/`vmnet` modules must be rebuilt against the running kernel
after every kernel upgrade, and need `linux-headers` matching that kernel installed.

---

## Applying repository settings

Idempotent — safe to re-run after any manual change in the GitHub UI, which is the point:
it makes the configuration reviewable rather than remembered.

```bash
scripts/bootstrap-repo-settings.sh                       # current repo
scripts/bootstrap-repo-settings.sh owner/other-repo      # explicit target
```

Verify:

```bash
gh api repos/<owner>/<repo> --jq '.security_and_analysis'
gh api repos/<owner>/<repo>/rulesets --jq '.[] | {name, enforcement}'
```

**Note on merging.** `gh pr merge` may refuse with *"the base branch policy prohibits the
merge"* while `mergeable_state` is `blocked`, even with every required check green — GitHub
reports `blocked` for a ruleset requiring zero approvals. The merge itself is permitted:

```bash
gh api -X PUT repos/<owner>/<repo>/pulls/<n>/merge -f merge_method=squash
```

This is not a bypass — no `--admin` flag, no ruleset exemption, and the merge is refused
normally if a required check has failed.
