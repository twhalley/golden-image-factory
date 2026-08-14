# Evidence — Windows Setup does not pick up the answer file on this builder

**Date:** 2026-08-14
**Status: UNRESOLVED.** The Windows Server 2022 templates, hardening role and Pester suite
are written, validated and lint-clean. **The QEMU build has not completed**, so the
[README reality table](../README.md) records `windows2022` as not executed and there is no
build log to commit. That is the whole point of the reality table.

## Symptom

`packer build -only='windows.qemu.windows'` starts the VM, Windows Setup boots, and Setup
stops at the language-selection screen and waits — for a human who is never coming. Packer
waits for WinRM until its timeout and the build fails having produced nothing.

There is no error. Setup behaves exactly as if no answer file had been supplied.

## What was ruled out, and how

Each of these was a separate build attempt with the guest console captured over VNC
(`vncdo -s 127.0.0.1::<port> capture`).

| # | Hypothesis | Test | Result |
|---|---|---|---|
| 1 | Wrong disk bus stops Setup finding a disk | `disk_interface = "sata"` | **Not the cause, but a real bug**: QEMU has no `if=sata` bus and rejects it — *"unsupported bus type 'sata'"* — which surfaces only as "Qemu failed to start" without `PACKER_LOG=1`. Changed to `ide`, which on q35 is the ICH9 AHCI controller |
| 2 | `cd_files` is not reliably searched by Setup | Moved answer file to a floppy | Still not detected |
| 3 | q35 has no floppy controller | Switched `machine_type` to `pc` (i440fx) | **Confirmed and fixed**: on q35 QEMU accepts `-fda` silently and the guest has no controller to read it. On i440fx, WinPE's `wmic logicaldisk` shows `A:` present. Still not detected |
| 4 | The answer file is not actually on the media | Extracted the FAT12 image from `-fda` on the host and parsed it | File present, 10,684 bytes, well-formed XML, no BOM, all four settings passes intact |
| 5 | Setup rejected it and logged an error | Opened a WinPE prompt (`Shift+F10`), read `X:\Windows\Panther\setuperr.log` | **Empty.** Setup logged no error, so it did not parse and reject the file — it never used it |
| 6 | Schema element order is wrong | Reordered `oobeSystem` children to the XSD sequence: `AutoLogon`, `FirstLogonCommands`, `OOBE`, `UserAccounts` | Correct to do — the original order was genuinely wrong — but not the cause |
| 7 | Content before the root element, or non-ASCII characters | Moved the header comment inside `<unattend>`; folded all non-ASCII to ASCII | Still not detected |
| 8 | The floppy filesystem does not mount in WinPE | `wmic logicaldisk get name,volumename` in WinPE | **Strong signal, unresolved**: `A:` reports **no volume label** while both CDs report theirs. The drive exists; its filesystem appears not to mount. Packer writes the floppy with go-diskfs, whose FAT12 BPB is not always accepted |
| 9 | Deliver on media that demonstrably mounts | Added `Autounattend.xml` to `cd_content` as well, so it is on both | Still not detected |

## Where it stands

Attempt 8 is the most likely remaining explanation for the floppy path, and it does not
explain attempt 9 — the CD mounts correctly in WinPE and carries an identical, valid file at
its root, and Setup still did not use it. Something about how this QEMU/OVMF-free BIOS guest
enumerates removable media at the point Setup searches is not yet understood.

**Next things to try**, in order of expected value:

1. Build the floppy image with `mkfs.fat` + `mcopy` and attach it through `qemuargs`,
   bypassing go-diskfs entirely. This directly tests hypothesis 8.
2. Rebuild the installation ISO with the answer file injected at its root, so detection
   does not depend on secondary media at all.
3. Drive the first Setup screens with a `boot_command` and pass `/unattend:` explicitly —
   fragile and the option of last resort, but deterministic.
4. Try the `vmware-iso` source instead. VMware Workstation's virtual floppy is a different
   implementation, and phase 3's acceptance criteria do not require the QEMU path
   specifically.

## What is NOT affected

The failure is in *delivering* the answer file to Setup, not in anything the repo asserts
about the image:

- `packer/windows/*.pkr.hcl` — all three sources pass `packer validate`
- `ansible/roles/harden_windows` — `ansible-lint` clean at the production profile
- `tests/pester/WindowsServer2022.Tests.ps1` — written against the controls in
  `IMAGE-STANDARD.md`

None of that is evidence the image works. It is evidence the code is syntactically sound
and internally consistent, which is a much weaker claim, and the README says so.

## The honest summary

Windows is the phase the brief warned not to cut, and it has not been cut — it is written.
It is also the phase that is not finished, and a repo whose central claim is *evidence of
what is inside an image* cannot report an unbuilt image as built. The reality table says
"not yet", the roadmap carries the four next steps above, and this document exists so that
picking the work back up costs minutes rather than repeating six build attempts.
