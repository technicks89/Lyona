# ARM5-03: the support contract per target

ARM Sprint 5 item ARM5-03 (issue #20). Written 2026-11-12. A documentation
change: no new runs. Each status below comes from the evidence already on file,
under the rule in `docs/sprints/ARM64.md` ("No support claim without
evidence"): a target is supported only after a real install on that hardware,
or for the generic image on the virtual machines named, recorded under
`docs/evidence/`, with what was not tested said plainly.

The plan gates ARM5-03 on ARM5-01 and ARM5-02. Both of their runs fall after
the merge into Lyona (the 2026-10-27 amendment), so the contract is written
now and says plainly that no release has carried the aarch64 images yet and
that release-to-release updates are not validated on aarch64. Revisit it after
ARM5-01's pre-release and ARM5-02's run.

## The statuses, and where each comes from

| Target | Status | Evidence |
| --- | --- | --- |
| Generic aarch64 ISO on QEMU/KVM `virt` and libvirt, aarch64 host, UEFI | Supported | `arm2-05-generic-image.md`: six installs (ext4 and btrfs on three configurations) to a working desktop, 2026-10-25. UTM and Parallels were in the plan and were not run |
| Generic aarch64 ISO on the Dell XPS 13 9345 | Supported | `arm6-06-xps13-9345.md`, with `arm6-02` to `arm6-05`, 2026-11-11 |
| Generic aarch64 ISO on other Snapdragon X laptops | Experimental | Covered by the image's device-tree table, not booted (`ARM-SPRINT-6-SNAPDRAGON-X.md`: "should work, not tested") |
| Generic aarch64 ISO on other aarch64 UEFI machines | Experimental | No run |
| Raspberry Pi image on a Pi 4 Model B, SD card | Supported | `arm3-06-raspberry-pi.md`, 2026-11-04 (with the update and rollback of 2026-11-05) |
| Raspberry Pi image on a Pi 5 | Experimental | `arm3-06-raspberry-pi.md`, "Reported, not recorded": booted once, no image, checksum or measurements; NVMe boot not run |
| `install.sh` on an existing Arch Linux ARM system | Experimental | `arm1-06-install-sh.md`: a KVM virtual machine only. The Pi run of it is "Reported, not recorded". This is not the generic image, so the virtual-machine exception does not apply |
| NVIDIA GB10, NVIDIA N1X | Not supported | Removed from the plan 2026-11-12 (`ARM64.md`) |
| 32-bit ARM (`armv7h`) | Not supported | Rejected by the installer (`SPEC.md` section 4, `tests/test-arch-platform.sh`) |

## What changed

- `SPEC.md` section 4: the "Initial release architecture" row becomes "Release
  architectures"; the single experimental Arch Linux ARM row becomes the
  definitions of supported, experimental and not supported and a table with a
  row per aarch64 target, its image, status, evidence and gaps. Section 2's
  goal, the Picom exception for the Pi 4 (5.10), the image contract (5.11) and
  9.4 no longer call the aarch64 medium or the Pi 4 experimental.
- `AGENTS.md`: the Arch Support Contract points at that table; the Repository
  Map no longer calls the aarch64 medium and Pi image builder experimental;
  "Arch Image Rules" name the two aarch64 images, their native build host
  (for a release, the GitHub arm64 runner in an Arch Linux ARM container,
  `scripts/ci-release-aarch64.sh`), their checks, and the targets supported
  today; "Arch Platform Rules" drop "(experimental)" from the identity.
- `README.md`: one paragraph under the platform line with the same statuses,
  linking the table; the installer paragraph says `install.sh` on Arch Linux
  ARM is experimental (validated in a virtual machine, not on a board).
- Stale "no ARM target is supported" wording in `docs/roadmap/ROADMAP.md`,
  `docs/RELEASING.md`, `docs/sprints/ARM64.md` and `docs/src/install.md`.

Not changed: `install.sh`'s message on Arch Linux ARM ("Arch Linux ARM on
aarch64 (experimental)") stays, as the existing-system installer on Arch Linux
ARM is still experimental; `tests/test-arch-platform.sh` checks that message.

## Acceptance

"Every claim in `SPEC.md`, `AGENTS.md` and the README matches the evidence on
file": each supported row names its evidence file, and each gap listed there is
taken from that file's "Not tested" section or its plan. Checked by reading;
there is no automated check of the wording.

## Not done

- No new hardware or virtual-machine run: the contract rests only on the runs
  above.
- ARM5-02 (updates on aarch64, release to release) and ARM5-01's release run:
  after the merge, in Lyona.
- ARM5-04 (the ARM user documentation and the bug-report template) is the next
  item.
