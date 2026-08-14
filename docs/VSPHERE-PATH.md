# The vSphere path

> **Status: DESIGN ONLY — phase 9 is not built.** The `vsphere-iso` sources for both Linux
> and Windows exist and are validated on every PR, but nothing has ever been built against a
> vCenter. There is no nested lab yet. The README reality table says `packer validate` only,
> and it means it.

## Why this is a nested lab and not a cloud service

The obvious way to get a real vCenter is a managed VMware service. All three are ruled out
for the same reason, recorded in [ADR-0006](DECISIONS.md#adr-0006):

**Azure VMware Solution** provisions a minimum of **three dedicated bare-metal nodes** on
first creation, charged hourly, and now additionally requires a portable VMware VCF
subscription bought separately from Broadcom. There is no free tier, because there cannot be
one for dedicated hosts. Google Cloud VMware Engine and Oracle Cloud VMware Solution have
the same shape.

This matters more than "it is expensive". The gap between free credit and a three-node
bare-metal minimum is orders of magnitude, not a margin — so there is no clever way to
squeeze a demo into it, and anyone claiming otherwise has not priced it.

## The licensing trap that costs an evening

Broadcom publishes **two different ESXi 8.0U3e installer builds**, and they are not
interchangeable:

| Build | Licence | Usable here? |
|---|---|---|
| vSphere Hypervisor (free) | Embedded free licence | **No.** A free-licensed host **cannot join vCenter**, and its management API is **read-only** — so Packer's `vsphere-iso` builder cannot drive it at all |
| Evaluation / licensed | 60-day full-feature evaluation | **Yes.** Joins vCenter, full API |

Download the evaluation build. The free one looks correct right up to the point where the
API refuses every write, and the error does not mention licensing.

VCSA ships with its own 60-day evaluation. Sixty days covers an interview and most of a
three-month contract.

## Hardware

Checked before planning this, because committing an evening to it and discovering the host
cannot hold it is the expensive way to find out ([ADR-0007](DECISIONS.md#adr-0007)).

| Component | Needs | Available |
|---|---|---|
| VCSA, tiny deployment | ~14 GB RAM, 2 vCPU | |
| Nested ESXi host | 8–16 GB RAM, 4 vCPU | |
| **Total** | **~24–30 GB** | **62 GB (45 GB free), 16 threads, 1.2 TB** |

Sufficient with margin.

## What is planned

1. VMware Workstation as the outer hypervisor. **Not yet installed on the build host** —
   this is a prerequisite, not a step.
2. One nested ESXi 8.0U3e host from the evaluation installer, with hardware-assisted
   virtualisation exposed to the guest.
3. VCSA deployed in tiny mode onto that host.
4. Build one Linux image end to end through `vsphere-iso`: resource pool, datastore, folder,
   `convert_to_template`, content library publishing.

The virtual hardware choices are already in the templates and were made to be right rather
than to be defaults — hardware version 21 (vSphere 8), `pvscsi` and `vmxnet3` for Linux,
`lsilogic-sas` and `e1000e` for Windows because Windows Setup has no in-box paravirtual
driver and cannot see a `pvscsi` disk.

## What a nested lab does NOT represent

The reason this section exists is that "I ran it on vSphere" and "I ran it on a nested lab"
are different claims, and the second is the true one.

| Not representative | Why |
|---|---|
| Storage performance | A datastore on a virtual disk on a laptop SSD. Any timing conclusion is meaningless |
| DRS, HA, vMotion | Single host. None of them can be exercised |
| Distributed switching | Standard vSwitch only; a vDS needs multiple hosts to mean anything |
| Storage policies, vSAN | Not present |
| Scale | One host, a handful of VMs |
| Certificate handling | `insecure_connection = true` against VCSA's self-signed certificate. **Production must not do this** — it is a variable rather than a hardcoded literal precisely so it is a per-environment decision, and `policy/packer.rego` denies a hardcoded `true` |

**What it does represent, genuinely:** that the template drives a real vCenter API, that the
guest OS customisation works against real VMware virtual hardware, that
`convert_to_template` produces a usable template, and that content library publishing works.
Those are the parts the template is responsible for.

## What would change against production vCenter

- `insecure_connection = false` and a real CA-issued certificate
- Credentials from a secrets manager, not `PKR_VAR_*` in a shell
- A dedicated service account with the minimum vCenter role rather than
  `administrator@vsphere.local`
- Cluster, datastore and folder from the target estate
- Content library replication to the sites that need the template
- Probably a build VLAN with no route to production

## Evaluation expiry

The 60-day clock starts when the lab is built. **Nothing has been installed yet, so there is
no expiry date to record.** When phase 9 starts, the date goes here, and what breaks when it
lapses is: the host drops to a restricted mode, the vCenter connection fails, and
`vsphere-iso` builds stop. The templates and roles are unaffected — only the ability to
execute them against vSphere.

## Roadmap

Phase 9, last in priority order, because it is the most hardware-dependent and the most
time-boxed by licensing. Prerequisite: VMware Workstation installed on the build host.
