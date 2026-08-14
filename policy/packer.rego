# Packer template policy.
#
# READ THIS BEFORE TRUSTING IT. These rules exist because checkov, tfsec,
# Terrascan and KICS have deep Terraform policy libraries and effectively no
# Packer HCL2 coverage at all. There is no upstream corpus to inherit here, so
# this file is only ever as good as what is written in it — a handful of
# hand-written assertions, not a maintained benchmark. ADR-0005 states that
# plainly, and phase 4's goss suite against the built artefact is the control
# actually worth trusting.
#
# A second, structural limit: conftest sees the template, not the build. Values
# supplied through variables appear here as the literal string "${var.foo}", so
# these rules can only catch a bad value **hardcoded in the template**. A bad
# value passed at build time is invisible to them. Variable-level `validation`
# blocks in variables.pkr.hcl cover that side; the two are complementary and
# neither is sufficient alone.
#
#   conftest test --parser hcl2 --policy policy packer/linux/*.pkr.hcl

package main

import rego.v1

# Every source block in the document, as {kind, name, body}.
sources contains {"kind": kind, "name": name, "body": body} if {
	some kind, name
	blocks := input.source[kind][name]
	some body in blocks
}

# ---------------------------------------------------------------------------
# Installation media must be pinned to a digest.
#
# `iso_checksum = "none"` is a documented Packer feature that disables checksum
# verification entirely. It is the single highest-value assertion in this file:
# without it, the whole chain of custody from installation media to signed image
# is decorative, because the input could be anything.
# ---------------------------------------------------------------------------
deny contains msg if {
	some s in sources
	lower(s.body.iso_checksum) == "none"
	msg := sprintf(
		"source.%s.%s disables ISO checksum verification (iso_checksum = \"none\"). The image would be built from unverified installation media.",
		[s.kind, s.name],
	)
}

# ---------------------------------------------------------------------------
# No password authentication where a key is possible.
#
# A build password is a credential that lives in the repository and survives
# into the image unless something explicitly removes it. This repo uses an
# ephemeral per-build key instead (scripts/make-build-key.sh).
# ---------------------------------------------------------------------------
deny contains msg if {
	some s in sources
	s.body.ssh_password
	msg := sprintf(
		"source.%s.%s sets ssh_password. Use an ephemeral key pair via ssh_private_key_file; see scripts/make-build-key.sh.",
		[s.kind, s.name],
	)
}

deny contains msg if {
	some s in sources
	s.body.winrm_password
	not startswith(s.body.winrm_password, "${var.")
	msg := sprintf(
		"source.%s.%s hardcodes winrm_password. Pass it as PKR_VAR_* instead — Windows has no key-based equivalent, so the value must at least stay out of the repository.",
		[s.kind, s.name],
	)
}

# ---------------------------------------------------------------------------
# A source with no communicator is a source whose contents are never provisioned
# and never tested. That is a legitimate Packer configuration and an illegitimate
# golden image.
# ---------------------------------------------------------------------------
deny contains msg if {
	some s in sources
	lower(s.body.communicator) == "none"
	msg := sprintf(
		"source.%s.%s sets communicator = \"none\", so nothing can provision or test the image. Every image in this factory must be reachable for hardening and for goss/Pester.",
		[s.kind, s.name],
	)
}

# ---------------------------------------------------------------------------
# TLS verification must not be disabled with a literal in the template.
#
# The nested lab in phase 9 legitimately needs insecure_connection, because VCSA
# ships a self-signed certificate. That is why this checks for a hardcoded true
# rather than banning the setting: the lab passes it as a variable and documents
# why in docs/VSPHERE-PATH.md, which is a decision. A literal `true` committed
# into the source block is a default nobody revisits.
# ---------------------------------------------------------------------------
deny contains msg if {
	some s in sources
	s.body.insecure_connection == true
	msg := sprintf(
		"source.%s.%s hardcodes insecure_connection = true. Pass it as a variable so the value is a per-environment decision rather than a permanent default.",
		[s.kind, s.name],
	)
}

# ---------------------------------------------------------------------------
# No client secret anywhere in an Azure source. Authentication is a GitHub OIDC
# federated credential; if a client_secret ever appears, the OIDC setup has been
# quietly abandoned and the repo's central claim about having no long-lived
# secrets is no longer true.
# ---------------------------------------------------------------------------
deny contains msg if {
	some s in sources
	s.kind == "azure-arm"
	s.body.client_secret
	msg := sprintf(
		"source.%s.%s sets client_secret. This repo authenticates to Azure with an OIDC federated credential and holds no long-lived secret; see ADR-0010.",
		[s.kind, s.name],
	)
}

# ---------------------------------------------------------------------------
# Warnings — real smells, but not build-stopping.
# ---------------------------------------------------------------------------

# An image built from a floating "latest" ISO is not reproducible: the same
# commit produces different images on different days.
warn contains msg if {
	some s in sources
	contains(lower(s.body.iso_url), "latest")
	msg := sprintf(
		"source.%s.%s builds from a floating 'latest' ISO URL, so the same commit will not produce the same image over time. Pin the point release.",
		[s.kind, s.name],
	)
}

# Headless false is right for debugging a boot_command and wrong in CI, where
# there is no display to open.
warn contains msg if {
	some s in sources
	s.body.headless == false
	msg := sprintf(
		"source.%s.%s hardcodes headless = false. Fine while debugging a boot_command locally, but it will not work on a CI runner.",
		[s.kind, s.name],
	)
}
