# ARM Sprint 5 -- Release, support contract and the N1X watch item

Index: [`ARM64.md`](ARM64.md). Depends on ARM-2 and ARM-3.

**Status:** planned 2026-10-11. Not started. GitHub: issues #361 to #364
(label `arm64`); milestone "ARM Sprint 5 - Release and support contract", created by
[`arm-sprints-github.sh`](arm-sprints-github.sh).

**Goal:** the generic and Pi images ship with a Lyona release, each target's
status is written down honestly, and users can install and update on ARM from
the docs. ARM5-05, the N1X watch item, is deferred with GB10 (2026-10-11).

| Item | Kind | Gate |
| --- | --- | --- |
| [ARM5-01](#arm5-01-the-release-workflow-for-arm-images) | Release | ARM-2, ARM-3 |
| [ARM5-02](#arm5-02-updates-on-aarch64) | Validation | ARM-2, ARM-3 |
| [ARM5-03](#arm5-03-the-support-contract-per-target) | Policy, docs | ARM5-01, ARM5-02 |
| [ARM5-04](#arm5-04-user-documentation) | Docs | ARM5-03 |
| [ARM5-05](#arm5-05-the-n1x-watch-item) (deferred) | Research | A-8 |

---

## ARM5-01: The release workflow for ARM images

1. **Build:** the generic aarch64 image and the Pi image, built on the
   aarch64 host (A-3), from the same tagged commit as the x86_64 image.
2. **Publish** beside the x86_64 image in the release, each with its checksum
   and signed the same way (D-31), with names that say the architecture and
   target (for example `lyona-VERSION-aarch64.iso`,
   `lyona-VERSION-rpi-aarch64.img.xz`).
3. **Release evidence** per `docs/RELEASING.md`: build host, checksums, and
   each target's validation run, or a plain statement of what was not run.
4. **`scripts/lyona-release`** and the release workflows learn the new
   assets; `tests/test-release-workflows.sh` checks them.

**Acceptance:** a pre-release with the x86_64, generic aarch64 and Pi images,
each checksummed and signed.

## ARM5-02: Updates on aarch64

1. `lyona-update` check, apply and rollback on the generic image's VM and on a
   Pi, from one release to the next.
2. Package updates (`pacman -Syu`, the Settings pane) against Arch Linux
   ARM's repositories; Topgrade where ARM1-03 kept it.
3. **Record** in the release evidence.

**Acceptance:** an update and a rollback pass on both targets.

## ARM5-03: The support contract per target

1. `SPEC.md` section 4's target table gets a row per ARM target with its
   status: supported (validated on the hardware named), experimental (built,
   validated only on VMs or not at all), or not supported.
2. `AGENTS.md`'s "Arch Image Rules" name the ARM images and their build host
   and validation, as they do for the x86_64 image.
3. The README's platform line says the same, no more.

**Acceptance:** every claim in `SPEC.md`, `AGENTS.md` and the README matches
the evidence on file.

## ARM5-04: User documentation

1. `docs/src/install.md`: a section per target (which image, how to write it,
   first boot), what is different on ARM (no CachyOS, no Steam, Arch Linux ARM
   mirrors, the Pi wizard), and how to report a problem with the architecture
   and board.
2. `docs/src/troubleshooting.md`: the known ARM problems the sprints found.
3. `.github/ISSUE_TEMPLATE/bug_report.yaml`: the architecture and board
   fields, if it does not already ask.

**Acceptance:** a user can install each target from the docs alone.

## ARM5-05: The N1X watch item

Deferred (2026-10-11) with GB10; not tracked on GitHub until it is picked up.

1. **Write down the gate (A-8)** in `ARM64.md`: work starts when NVIDIA's
   Linux driver lists N1X device IDs and a laptop is available to test.
2. **Check it at each release** and record the date and result in
   `ARM64.md`.
3. **When the gate opens,** plan an ARM-6 sprint from what is then known.
   The expected shape is ARM-4's (the generic image, a detection, a kernel and
   driver), plus what a laptop needs that a desktop does not: battery and
   charging, suspend and resume, the internal panel and its backlight, Wi-Fi
   and Bluetooth drivers, the touchpad, and external displays.

**Acceptance:** the gate and its first check are recorded.

---

## Project close

The current scope is done when the generic and Pi images are released with
their evidence, and GB10 and N1X are recorded as deferred with the reason. Then this project's
documents move to `docs/sprints/completed/`, as the upstream-sync sprints do.
