# ARM Sprint 5 -- Release, support contract and the N1X watch item

Index: [`ARM64.md`](ARM64.md). Depends on ARM-2, ARM-3 and ARM-6 (Snapdragon X,
added 2026-11-05, which comes before this sprint).

**Status:** planned 2026-10-11. ARM5-01's part before the merge (the workflow and
`scripts/lyona-release`, checked with stubs) is written 2026-11-12
([evidence](../evidence/arm5-01-release-workflow.md)). ARM5-03, the support
contract, is written 2026-11-12 from the evidence on file
([evidence](../evidence/arm5-03-support-contract.md)), ahead of ARM5-02, whose
run falls after the merge. ARM5-04, the user documentation and the bug report
form, is written 2026-11-12 ([evidence](../evidence/arm5-04-user-docs.md)).
ARM5-01's release run is done in Lyona (#489): `v2026.11.0-beta.1`, published
2026-11-13 with the x86_64, generic aarch64 and Pi images, each checksummed
and signed ([evidence](../evidence/arm5-01-release-workflow.md#the-release-run-in-lyona-2026-11-13)).
What is left is ARM5-02 (#490). **Amended 2026-10-27, by the
maintainer:** ARM5-01's release run happens in Lyona after the merge
([`ARM64.md`](ARM64.md#end-state)), as Lyona-ARM has no releases. GitHub: issues #18 to #21, and
#62 for the deferred ARM5-05
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

**When:** in two parts (amended 2026-10-27). In Lyona-ARM, before the merge,
the workflow and `scripts/lyona-release` changes (3 and 4 below), checked by
the release tests' stubs. In Lyona, after the merge, the release run itself
(1, 2 and the acceptance), on Lyona's GitHub arm64 runners, which cost
nothing in a public repository.

1. **Build:** the generic aarch64 image and the Pi image, built on the
   aarch64 host (A-3: a GitHub arm64 runner), from the same tagged commit as
   the x86_64 image.
2. **Publish** beside the x86_64 image in the release, each with its checksum
   and signed the same way (D-31), with names that say the architecture and
   target (for example `lyona-VERSION-aarch64.iso`,
   `lyona-VERSION-rpi-aarch64.img.xz`).
3. **Release evidence** per `docs/RELEASING.md`: build host, checksums, and
   each target's validation run, or a plain statement of what was not run.
4. **`scripts/lyona-release`** and the release workflows learn the new
   assets; `tests/test-release-workflows.sh` checks them.

**Acceptance:** a pre-release of Lyona, after the merge, with the x86_64,
generic aarch64 and Pi images, each checksummed and signed. Before the merge:
`tests/test-release-workflows.sh` passes with the new assets.

## ARM5-02: Updates on aarch64

1. `lyona-update` check, apply and rollback on the generic image's VM and on a
   Pi, from one release to the next.
2. Package updates (`pacman -Syu`, the Settings pane) against Arch Linux
   ARM's repositories; Topgrade where ARM1-03 kept it.
3. **Record** in the release evidence.

**Acceptance:** an update and a rollback pass on both targets.

Note (2026-10-27): "from one release to the next" needs two releases that
carry the ARM support, and only Lyona makes releases: until the merge,
`lyona-update` on an ARM install takes upstream releases that drop it (#53).
So this run also falls after the merge, after ARM5-01's release; when to
schedule it is the maintainer's call, not decided here.

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

Deferred (2026-10-11) with GB10. Tracked on GitHub since 2026-10-26 (#62,
label `deferred`), not scheduled.

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
