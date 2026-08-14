# Evidence — Rocky 9.8 `minimal.iso` does not match its published checksum

**Date:** 2026-08-14
**Effect on this repo:** the Rocky 9 image is built from `boot.iso`, not `minimal.iso`.
See [ADR-0013](../docs/DECISIONS.md#adr-0013).

This is an upstream publishing inconsistency, found while doing the most routine possible
task: pinning an ISO and its digest. It is recorded because it is the exact failure the
`iso_checksum` field exists to catch, and because it changed a design decision.

## What happened

The first download completed at 2.48 GB against an expected 1.48 GB. Two further
downloads were run to rule out a client-side cause — one dropping `curl -C -` in case a
retry was re-appending rather than resuming, one a single-shot `curl` with no `--retry` at
all. Both produced the same oversized file. The cause was not the client.

```
$ curl -sIL https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/Rocky-9.8-x86_64-minimal.iso
HTTP/2 200
content-type: application/octet-stream
content-length: 2755067904
```

The server sends 2,755,067,904 bytes. The published manifest, fetched from the same
directory, says otherwise:

```
$ curl -fsSL https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/CHECKSUM
# Rocky-9.8-x86_64-boot.iso: 1480048640 bytes
SHA256 (Rocky-9.8-x86_64-boot.iso) = d6eeefdc8437c593d41a3150fcca4a734c55642ed472eecdda99720bb1370881
# Rocky-9.8-x86_64-dvd.iso: 15194259456 bytes
SHA256 (Rocky-9.8-x86_64-dvd.iso) = d2bcbb64c2d67511adf80d40cd9543391a33aea5860a355b1d26d7f55236d01f
# Rocky-9.8-x86_64-minimal.iso: 1480048640 bytes
SHA256 (Rocky-9.8-x86_64-minimal.iso) = d338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4
...
```

Comparing what is claimed against what is served:

| ISO | Manifest | Served | Match |
|---|---:|---:|:--:|
| `Rocky-9.8-x86_64-boot.iso` | 1,480,048,640 | 1,480,048,640 | ✅ |
| `Rocky-9.8-x86_64-dvd.iso` | 15,194,259,456 | 15,194,259,456 | ✅ |
| `Rocky-9.8-x86_64-minimal.iso` | 1,480,048,640 | **2,755,067,904** | ❌ |

One detail points at the manifest being wrong rather than the file: **the manifest gives
`minimal.iso` the same byte count as `boot.iso`** — 1,480,048,640 for both. Identical sizes
for a network-install image and a package-carrying image is not plausible; it is what a
copy-paste or stale entry looks like. The `boot` and `dvd` entries, which do have distinct
sizes, both verify.

### A line of evidence that was tried and does not hold

The obvious next check is the ISO 9660 primary volume descriptor, readable from a byte
range without downloading the whole file:

```
$ curl -sL -r 32768-33279 .../Rocky-9.8-x86_64-minimal.iso | strings | head -3
CD001
                                Rocky-9-8-x86_64-dvd
                                XORRISO-1.5.4 2021.01.30.150001, ...
```

The served `minimal.iso` reports a volume label of `Rocky-9-8-x86_64-dvd`, which looks
conclusive — the file announcing itself as the DVD. **It is not conclusive, and the same
check run against the verified `boot.iso` is why:**

```
$ dd if=Rocky-9.8-x86_64-boot.iso bs=1 skip=32768 count=512 | strings | head -3
CD001
                                Rocky-9-8-x86_64-dvd
                                XORRISO-1.5.4 2021.01.30.150001, ...
```

`boot.iso` — 1.48 GB, digest verified against the manifest, unambiguously not the DVD —
carries **the same label**. Rocky uses one volume label across the 9.8 variants, and the
installer relies on it: the isolinux command line on `boot.iso` reads
`inst.stage2=hd:LABEL=Rocky-9-8-x86_64-dvd`. The label identifies the release, not the
variant, so it says nothing about which file is which.

Kept here rather than deleted because the mistake is instructive. The label reading was
made first, and it was persuasive enough to feel like proof; only checking it against a
known-good file showed it was worthless as evidence. The size comparison across all three
ISOs stands on its own and did not need it.

## It is not one bad mirror

`download.rockylinux.org` is a redirector, so the obvious next question is whether one
mirror is serving a corrupt file. It is not:

```
dl.rockylinux.org              content-length=2755067904
mirror.rockylinux.org          content-length=2755067904
rockylinux.mirrorservice.org   content-length=2755067904
ftp.uni-stuttgart.de           content-length=2755067904
```

Every reachable mirror agrees with every other and disagrees with the manifest. The
content is consistently published; the manifest entry for `minimal` is the outlier.

The manifest is also **not signed** — no PGP block, no detached `.sig` alongside it — so
there is no cryptographic way to establish which side is authoritative. That is worth
knowing independently of this particular mismatch.

## Why the response was to change ISO, not to compute a new digest

The obvious shortcut is to download the 2.75 GB file, compute its SHA-256, and pin that.
It would work, and this repo does not do it.

Pinning a digest computed from an unverified download does not establish integrity — it
records whatever the mirror happened to serve on the day, and every future build then
faithfully reproduces that. The `iso_checksum` field would still be populated, `packer
validate` would still pass, and the chain of custody from vendor to image would be broken
with no visible sign that it had been. For a repository whose central claim is *evidence of
what is inside an image*, that is precisely the wrong trade.

`boot.iso` matches its published digest exactly, so it is used instead. The cost is that
the build becomes a network install: it needs a reachable package mirror, and two builds
from the same commit on different days may pull different package versions. That second
cost is smaller than it appears — the kickstart runs a full `dnf upgrade` during `%post`
either way, so the image was never bit-reproducible over time. What makes a build
accountable is the manifest and the phase 7 SBOM recording exactly what landed, not a
belief that the inputs are frozen.

## What this says about the gate

`iso_checksum` is the least interesting field in a Packer template right up until it is the
only thing standing between an image and unverified installation media. It did its job here
before a single VM was booted.

It is also why `policy/packer.rego` refuses `iso_checksum = "none"` outright — a documented
Packer feature that switches this check off entirely. Anyone who hit this mismatch under
deadline pressure would find that setting within about a minute of searching, and it would
have made the problem disappear rather than be solved.

## Reproducing this

```bash
curl -sIL https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/Rocky-9.8-x86_64-minimal.iso \
  | grep -i content-length
curl -fsSL https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/CHECKSUM | grep minimal
# Read the volume label without downloading 2.75 GB:
curl -sL -r 32768-33279 https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/Rocky-9.8-x86_64-minimal.iso \
  | strings | head -3
```

If a future point release fixes the manifest, switching back to `minimal.iso` is a
two-line change to `packer/linux/rocky9.pkrvars.hcl` plus removing the `url`/`repo`
directives from the kickstart.
