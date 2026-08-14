# Image lifecycle

> **Status: DESIGN ONLY — phase 5 is not built.** Nothing described here exists in code yet.
> There is no `catalogue/images.json`, no `terraform/modules/image_selector`, and the
> catalogue-bump step in `scheduled-rebuild.yml` is an explicit no-op that says so in the
> run summary rather than pretending to work.
>
> This document is the design, written down so the phase can be picked up rather than
> re-derived. Read every claim below as *intended*, not *implemented*.

## Why a lifecycle at all

The failure mode a golden image programme actually hits is not building images. It is
**image sprawl**: forty images in a datastore, nobody sure which are current, teams
deploying whichever one they used last time, and a critical CVE that has to be chased
across an unknown number of derived VMs.

Two things prevent it, and they have to be machine-readable or they get ignored:

1. an authoritative list of what exists and what status each image has, and
2. a consumer that **refuses** to deploy something retired, rather than warning about it.

## Versioning

Semver, and the boundaries are chosen so that the version number answers "what will break
if I take this update?".

| Bump | When | Consumer impact |
|---|---|---|
| **Major** | Base OS change (Rocky 9 → 10), partition layout change, or removal of a package the previous version shipped | Requires testing. May break automation that assumed a path or a filesystem |
| **Minor** | A new hardening control, a package addition, a changed default | Should be safe. May break an application relying on something the control now forbids — which is what the deprecation window is for |
| **Patch** | OS package updates only, no configuration change | Safe. This is what the monthly scheduled rebuild produces |

The monthly rebuild in `scheduled-rebuild.yml` therefore opens **patch** bumps and nothing
else. If a rebuild would change configuration, that is a human's PR.

## Statuses

| Status | Meaning | Consumers |
|---|---|---|
| `current` | The version new deployments should use | Selected by default |
| `deprecated` | Superseded; still deployable, on a clock | Plan gets a warning |
| `retired` | Past `supported_until`; no longer patched | **Plan fails** |

An image becomes `deprecated` the day its successor becomes `current`, and `retired` 90
days later. Ninety days is long enough for a quarterly release cycle to absorb it and short
enough that the estate does not accumulate a long tail.

`supported_until` is an absolute date recorded at build time, not computed at read time —
so an image's expiry does not silently move when the policy changes.

## The catalogue

`catalogue/images.json`, one entry per image version:

```json
{
  "name": "rocky9",
  "os_family": "rhel",
  "version": "1.2.3",
  "status": "current",
  "build_date": "2026-08-14T09:24:22Z",
  "supported_until": "2026-11-14",
  "git_commit": "4ab7209",
  "source_iso_checksum": "sha256:d6eeefdc...",
  "artefacts": {
    "qemu": "builds/qemu-rocky9-1.2.3/rocky9-1.2.3.qcow2",
    "azure_gallery_version": "rocky9/1.2.3"
  },
  "compliance_report": "evidence/compliance-rocky9-1.2.3.json",
  "sbom": "attestations/rocky9-1.2.3.spdx.json",
  "signature": "attestations/rocky9-1.2.3.manifest.sig"
}
```

Every field already exists somewhere in the pipeline — `manifest.json` carries the build
metadata, the goss report carries the compliance result. The catalogue's job is to be the
one place a consumer looks, not to be a new source of truth.

## The Terraform module, and its one job

`terraform/modules/image_selector` takes an OS name and a version constraint, reads the
catalogue, and returns an image identifier. It has **no providers and creates nothing.**
That is deliberate — Terraform earns its place here by refusing bad deployments, not by
being a second EC2 demo.

```hcl
module "base_image" {
  source  = "./modules/image_selector"
  os_name = "rocky9"
  version_constraint = "~> 1.2"
}
```

The interesting part is the `precondition`:

```hcl
lifecycle {
  precondition {
    condition     = local.selected.status != "retired"
    error_message = "Image ${local.selected.name} ${local.selected.version} is retired..."
  }
  precondition {
    condition     = timecmp(plantimestamp(), "${local.selected.supported_until}T00:00:00Z") < 0
    error_message = "Image ... passed supported_until ..."
  }
}
```

**A `precondition`, not a validation warning**, because the whole point is that the plan
fails. A warning is a thing people learn to scroll past.

Covered by `terraform test`, including the negative case — a fixture catalogue containing a
retired image, asserting the plan fails. A guard that has never been seen to refuse anything
is not a guard.

## What happens to already-deployed VMs

The question this model does **not** answer, and the honest thing is to say so.

Retiring an image stops new deployments. It does nothing to the VMs already built from it,
and those are where a CVE actually lives. Closing that loop needs a deployed-inventory
join — every VM carries `/etc/image-build-info` with its image name and version precisely
so that join is possible — but the inventory itself is out of scope here and belongs to the
configuration-management or CMDB layer.

Stated because a lifecycle document that implies retirement fixes running fleets would be
describing something that does not happen.

## Roadmap

Phase 5. Estimated at an evening: the catalogue schema and a fixture, the module, the
`terraform test` cases, and wiring the version bump into `scheduled-rebuild.yml`.

Priority order after the interview is phase 7 (supply chain) first, then this, then phase 8
(Azure), then phase 9 (nested vSphere) — supply chain first because the SBOM and signature
fields above are catalogue entries with nothing behind them until it lands.
