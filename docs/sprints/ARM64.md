# Lyona on ARM (aarch64)

Index for the project that brings Lyona to 64-bit ARM machines. It carries the
targets, what each one needs, the rules that apply to every sprint, the open
decisions (`A-n`), and the **sprint plan**. Each sprint has its own document.
The upstream-sync project has its own index, [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md);
the two are independent.

**Status:** planned 2026-10-11 at the maintainer's request. **Scope for now
(decided 2026-10-11): the generic image and the Raspberry Pi**, through
ARM-1, ARM-2, ARM-3 and ARM-5. GB10 (ARM-4) and N1X are deferred: their
plans stay here, but they are not scheduled (on GitHub since 2026-10-26,
marked deferred). ARM-1 is
done: ARM1-01 to ARM1-05 merged 2026-10-14, ARM1-06 2026-10-19 (#31).
ARM-2 is done: ARM2-01 to ARM2-05 merged 2026-10-22 to 2026-10-25 (#44 to
#54). ARM-3 is done: validated on a real Pi 4 on 2026-11-05 (ARM3-06,
`docs/evidence/arm3-06-raspberry-pi.md`). **Added 2026-11-05, by the maintainer:** Snapdragon X laptops, as
ARM-6, after ARM-3 and before ARM-5, in the generic image. Nothing
here is a support claim: `SPEC.md` still makes Arch x86_64 the
only release target, and an aarch64 target is supported only once its sprint
has met the release validation contract (`SPEC.md` 9.4) on that target.

---

## Targets

| Target | What it is | Image | Verdict |
| --- | --- | --- | --- |
| **Generic aarch64 UEFI** | Any aarch64 machine that boots UEFI with ACPI or a UEFI device tree: virtual machines on Apple Silicon (UTM, Parallels, VMware Fusion), QEMU/KVM on an ARM host, Ampere and other ARM servers and workstations | An installer image, like today's x86_64 one | **Doable. Large.** Closest to the current flow, but the image builder and the installer both need ARM ports |
| **Raspberry Pi 5** | BCM2712, VideoCore VII, 4 to 16 GB | A ready-to-boot SD card (or NVMe) image with Lyona preinstalled and a first-boot wizard | **Doable. Medium.** The most predictable target: Arch Linux ARM supports it, and the GPU runs Mesa (`v3d`) |
| **Raspberry Pi 4** | BCM2711, VideoCore VI, 2 to 8 GB | The same image as the Pi 5 (A-5) | **Doable. Medium.** Slower GPU: the overview's previews and Picom need checking against the lean-desktop goal |
| **NVIDIA GB10** | Grace Blackwell desktop systems: NVIDIA DGX Spark and the OEM GB10 boxes | The generic image, which detects GB10 and installs its kernel and driver (A-7) | **Doable with risk. Large.** Mainline Linux does not yet carry GB10's hardware-enablement patches: without them USB, and so the keyboard and mouse, does not come up. It needs NVIDIA's patched kernel (or a community package of it) and NVIDIA's aarch64 driver, neither of which Arch Linux ARM packages |
| **Snapdragon X laptops** (added 2026-11-05) | Qualcomm X Elite and X Plus laptops: the maintainer's Dell XPS 13 9345 to test, and others with a mainline device tree | The generic image, which picks each laptop's device tree at boot from its hardware IDs (A-10, A-11), as Ubuntu's generic arm64 image and Arch's own `stubble` do | **Doable. Medium to large.** `linux-aarch64` builds the X1E80100 drivers, and mainline has the XPS's device tree and `linux-firmware` its firmware. The work is choosing the device tree on the medium and in the installed system. Only laptops with a mainline device tree are covered |
| **NVIDIA N1X** | The RTX Spark laptops (announced 2026-06-01): the same Grace Blackwell design in a laptop | The generic image, as GB10, if and when it works | **Not doable yet. Watch item.** NVIDIA lists Windows 11 only; the Linux driver's supported-device list has GB10 but no N1X device IDs (checked 2026-10-11). Planned work starts only when both a Linux driver that lists N1X and test hardware exist (A-8) |

What already helps:

- dwm and its helpers (`dwm-xwatch`, `dwm-window-thumb`, `lyona-toml`) are C99
  with Xlib and build on aarch64 unchanged.
- The Quickshell shell and most scripts do not depend on the CPU. Arch Linux
  ARM packages Quickshell for aarch64 (`extra/quickshell`; 0.3.0 on
  2026-10-11, one release behind Arch's 0.3.1).
- `install.sh` already skips CachyOS off x86_64, the dependency map's gaming
  profile is x86_64 only, `install-herdr` accepts aarch64, and `dwm-aur.sh`
  reads per-architecture `source_*` lines.
- `lyona-update` builds from signed source, so updates do not depend on the CPU.

What every ARM target lacks today:

- **Identity.** Arch Linux ARM reports `ID=archarm` (`ID_LIKE=arch`); the
  existing-system installer accepts only `ID=arch` and rejects it.
- **Image builder.** `scripts/build-lyona-arch-iso.sh` layers onto archiso's
  `releng` profile, which is x86_64 only.
- **Installer.** The image installer drives archinstall, which does not support
  Arch Linux ARM; its mirror ranking uses reflector, which ranks Arch's mirrors,
  not Arch Linux ARM's (one geo-balanced host, `mirror.archlinuxarm.org`); its
  keyring is `archlinux-keyring`, not `archlinuxarm-keyring`; and it adds
  CachyOS and detects NVIDIA PCI GPUs, neither of which applies.
- **Packages.** Arch Linux ARM builds most of Arch's repositories, not all, a
  little later, and has no `multilib`. Each name in the dependency map needs a
  `pacman -Si` check on aarch64.

---

## Rules for every sprint

These come from `AGENTS.md` and `SPEC.md` and hold here too.

- **Arch only, exactly.** Arch Linux ARM is accepted as its own identity
  (`ID=archarm`) on `aarch64` only (A-1). Nothing that merely says
  `ID_LIKE=arch` is accepted, and 32-bit ARM (`armv7h`) is out of scope.
- **One dependency map.** ARM package differences live in
  `scripts/dwm-packages.sh`, gated by architecture, never in scattered lists.
- **x86_64 does not regress.** Every sprint keeps the full x86_64 suite green
  and the x86_64 image unchanged except where a change is shared on purpose.
- **NVIDIA-only packages and kernel arguments** are installed only on a machine
  that gets the driver, never shipped in an image, as on x86_64.
- **No support claim without evidence.** A target is called supported only
  after a real install on that hardware (or, for the generic image, on the
  named virtual machines), recorded under `docs/evidence/`, with what was not
  tested said plainly. Until then the images are "experimental".
- **Lean.** Each target's idle CPU and memory with the launcher closed is
  measured and recorded, as `AGENTS.md` asks of the shell; the Pi 4 is the bar.
- **Optional stays optional.** A missing Picom, GPU acceleration or Wi-Fi
  driver must not crash dwm or the shell; the overview falls back to icon
  cards (#244) as it does on x86_64.

---

## Decisions

| ID | Question | Blocks | Recommendation | Status |
| --- | --- | --- | --- | --- |
| **A-1** | Which identity does Lyona accept on ARM? | ARM-1 | `ID=archarm` on `aarch64` only, named in `SPEC.md` section 4 and `AGENTS.md` as a second supported identity, marked experimental until a target qualifies | Decided 2026-10-13 as recommended |
| **A-2** | What builds the generic image? (a) archiso with an aarch64 profile of Lyona's own, (b) archboot, (c) mkosi | ARM-2 | Decide from ARM-2's spike (ARM2-01). Prefer (a) if archiso's aarch64 UEFI boot modes build a working image, so the profile, the builder and its tests stay one design; else (c), which builds any architecture's disk images from a pacman bootstrap | **Decided 2026-10-22: (a)** (ARM2-01, `docs/evidence/arm2-01-spike.md`). archiso v91 built a working aarch64 UEFI image on Arch Linux ARM, unpatched, with six profile changes from releng. archiso is not packaged there, so the builder pins an archiso release |
| **A-3** | Where are ARM images built? (a) A native aarch64 host (an Arch Linux ARM VM on Apple Silicon, or a GitHub arm64 runner), (b) x86_64 with `qemu-user-static` | ARM-2, ARM-3 | **(a).** Emulated chroots are slow and hide faults that only show natively. The maintainer's Apple Silicon VM for local builds; a GitHub arm64 runner for CI | **Decided 2026-10-22: (a)** (ARM2-01). A privileged Arch Linux ARM container on GB10 built the image in about 200 s. The Apple Silicon VM and a GitHub arm64 runner were not tried: ARM2-02 checks the runner |
| **A-4** | What installs the system from the generic image? (a) archinstall, patched for Arch Linux ARM, (b) Lyona's own `pacstrap` path for ARM | ARM-2 | **(b)** unless ARM2-01 finds archinstall works unpatched. It is a smaller surface than a patched archinstall: partition, format, `pacstrap`, `genfstab`, bootloader, then the existing postinstall. The wizard's questions stay the same | **Decided 2026-10-22: (a), unpatched** (ARM2-01). The x86_64 image's configuration installed a booting system. GRUB needs a `/boot/vmlinuz-linux` kept current from `linux-aarch64`'s `/boot/Image` to pair the initramfs: a hook of Lyona's own, on the medium and in the new system. ARM2-03 still tries an encrypted install and adds a firmware boot entry |
| **A-5** | One Raspberry Pi image or two? | ARM-3 | **One** for the Pi 4 and Pi 5, with Arch Linux ARM's `linux-rpi` kernel (4K pages) and the firmware's per-board device trees, as the x86_64 image is one image for every GPU | **Decided 2026-10-26: one image, `linux-rpi`** (ARM3-01). The firmware boots it directly, with no U-Boot; Arch Linux ARM's own Pi tarball ships `linux-aarch64` and U-Boot instead, which the Pi 4 ran for #32. `linux-rpi-16k` (Pi 5 only) is not used: not measured (a Pi 5 arrived 2026-10-27, after this) |
| **A-6** (deferred with ARM-4) | Where do the GB10 kernel and NVIDIA's aarch64 driver come from? (a) Pinned PKGBUILDs built on the machine at install time, (b) a signed Lyona aarch64 package repository, (c) wait for mainline Linux and Arch Linux ARM | ARM-4 | **(a) first**, as Sprint 14 did for the legacy NVIDIA drivers: reviewed, pinned commits, built as the new user, never as root. Measure the build time on GB10 (20 cores); if it is too long, (b), which overlaps the signed package repository already proposed in `ROADMAP.md` "Future Evaluation". Revisit (c) every release | Open |
| **A-7** (deferred with ARM-4) | Does GB10 (and later N1X) get its own image? | ARM-4 | **No.** The generic image detects GB10 (by its SMBIOS or PCI IDs) and offers its kernel and driver, recommended, as the x86_64 image offers `nvidia-open` | Open |
| **A-8** (deferred) | When does N1X work start? | ARM-5 | Only when NVIDIA's Linux driver lists N1X device IDs **and** test hardware is available. Until then it is a watch item, checked at each release | Open |
| **A-10** | How does the generic medium choose a Snapdragon laptop's device tree? (a) `stubble`, packaged by Lyona, (b) systemd-stub's `.dtbauto` and `.hwids` | ARM-6 | Decide from ARM6-01; prefer (b), which needs no new package | Open |
| **A-11** | How does the installed system choose it? (a) the installer writes GRUB's `devicetree` line, (b) the medium's mechanism | ARM-6 | **(a)** unless A-10's choice suits the installed system too | Open |
| **A-9** | How does CI cover ARM? | ARM-1 | A GitHub `ubuntu-24.04-arm` runner running the suite inside an Arch Linux ARM container, on the manual Full suite workflow first, then on pull requests once it is reliable | Decided 2026-10-13 as recommended |

---

## Sprint plan

Six sprints of about two weeks, each one reviewable branch per item. ARM-1
comes first; ARM-2 and ARM-3 depend on it and not on each other; ARM-4 and
ARM-6 depend on ARM-2; ARM-6 runs after ARM-3 and before ARM-5; ARM-5 closes
the project.

| Sprint | Document | Scope | Exit | Depends on |
| --- | --- | --- | --- | --- |
| **ARM-1** | [`ARM-SPRINT-1-FOUNDATION.md`](ARM-SPRINT-1-FOUNDATION.md) | Support contract and identity, the dependency map on aarch64, AUR pins, the code that assumes x86_64, aarch64 CI, `install.sh` on an existing Arch Linux ARM system | `install.sh` reaches a working desktop on an Arch Linux ARM machine (an Arch Linux ARM VM under KVM on GB10, since 2026-10-19; the Pi 4 run moved to ARM3-06), with no x86_64 regression | A-1, A-9 |
| **ARM-2** | [`ARM-SPRINT-2-GENERIC-IMAGE.md`](ARM-SPRINT-2-GENERIC-IMAGE.md) | The builder spike, the aarch64 live medium, the ARM installer path, Arch Linux ARM mirrors and keyring, the image on three virtual machines | The generic image installs a working desktop on three virtual machines: QEMU/KVM, QEMU/KVM with another display path, and libvirt, on the GB10 (UTM and Parallels until 2026-10-25; there is no Mac) | ARM-1, A-2, A-3, A-4 |
| **ARM-3** | [`ARM-SPRINT-3-RASPBERRY-PI.md`](ARM-SPRINT-3-RASPBERRY-PI.md) | The Pi image builder, the first-boot wizard, Pi boot configuration, the desktop on `v3d`, Settings on a Pi, validation on a Pi 4 | One image boots to a working desktop on a real Pi 4, within the lean budget, and on a Pi 5 (8 GB) from an SD card (one since 2026-10-27); the Pi 5's NVMe boot is not tested (no NVMe board) | ARM-1, A-3, A-5 |
| **ARM-4** (deferred) | [`ARM-SPRINT-4-NVIDIA-GB10.md`](ARM-SPRINT-4-NVIDIA-GB10.md) | GB10 detection, its kernel and boot arguments, NVIDIA's aarch64 driver, Picom on NVIDIA aarch64, validation on GB10 hardware | The generic image installs a working desktop with the NVIDIA driver on a real GB10 system | ARM-2, A-6, A-7, hardware |
| **ARM-6** | [`ARM-SPRINT-6-SNAPDRAGON-X.md`](ARM-SPRINT-6-SNAPDRAGON-X.md) | Device-tree selection for Snapdragon X laptops in the generic medium and the installed system, their firmware, the desktop on Adreno X1, validation on a Dell XPS 13 9345 | The generic image installs a working desktop on the XPS 13 9345 with no manual step; other covered laptops "should work, not tested" | ARM-2, ARM-3 (order), A-10, A-11, the XPS |
| **ARM-5** | [`ARM-SPRINT-5-RELEASE-AND-N1X.md`](ARM-SPRINT-5-RELEASE-AND-N1X.md) | Release workflow for the generic and Pi images, the update path on aarch64, the support contract per target, user docs (the N1X watch item is deferred) | Both images published with a release, each target's status recorded | ARM-2, ARM-3, ARM-6 |

Ordering in practice: ARM-3 is the most predictable target and can run beside
ARM-2 once ARM-1 is merged. ARM-4 (GB10) and the N1X watch item are deferred
(2026-10-11); when they are picked up, ARM-4 builds on ARM-2's image and does
not change ARM-5's release of the generic and Pi images. ARM-6 (Snapdragon
X, added 2026-11-05) comes after ARM-3 and before ARM-5, so the release
carries it.

## End state

Decided 2026-10-14: one Lyona repository that builds both the x86_64 and the
ARM versions. Lyona-ARM is where the ARM work happens until ARM-1, ARM-2, ARM-3,
ARM-6 (added 2026-11-05) and ARM-5 are done; then it is merged into Lyona as a whole. Lyona-ARM has no
releases of its own.

**Amended 2026-10-27, by the maintainer:** ARM5-01's release run (a
pre-release carrying the aarch64 images) needs a release, which Lyona-ARM
never makes, so it happens in Lyona after the merge, on Lyona's GitHub
runners (Lyona is public, where standard runners cost nothing; Lyona-ARM is
private, where they are billed). Before the merge, ARM5-01 writes the release
workflow's changes and checks them with the release tests' stubs. So the
merge comes after ARM-1, ARM-2, ARM-3, ARM-6 and ARM-5's pre-merge parts, and ARM-5
closes in Lyona. Until the merge:

- Lyona `main` is synced in often, each time through a pull request merged
  with a merge commit (not squashed), so Git knows what is already in.
- Every ARM difference stays behind `is_arch_family`, an architecture check or
  the dependency map, so the final merge changes nothing on x86_64.
- A fix to code both repositories share is made in Lyona first and synced in.

## Hardware and test machines

| Target | What validates it | Needed by |
| --- | --- | --- |
| Generic | Three configurations on the GB10: QEMU/KVM with virtio-gpu, QEMU/KVM with `bochs-display` and a CD, and a libvirt machine (ARM2-05); the GitHub arm64 runner, for boot only. UTM and Parallels on Apple Silicon were planned; there is no Mac (2026-10-25), so they are not tested. Since the GB10 went (2026-10-27) there is no machine for a generic-image install run: a KVM virtual machine on the 8 GB Pi 5 was the candidate, but the Pi 5 is not available for that (2026-11-05: it runs the maintainer's DNS) | ARM-1, ARM-2, ARM-5 |
| Raspberry Pi | A Pi 4 (4 GB, the floor to test), with an HDMI display, keyboard and mouse, booting from an SD card. A Pi 5 (8 GB) too, since 2026-10-27, from an SD card, for short tests only: it runs the maintainer's DNS (2026-11-05). There is no NVMe board, so its NVMe boot is not tested | ARM-3 |
| GB10 (deferred) | A DGX Spark or an OEM GB10 system, with a display on its HDMI port. None is available since 2026-10-27 | ARM-4 |
| Snapdragon X | The maintainer's Dell XPS 13 9345 (X1E80100), from a USB stick with Secure Boot off; Windows stays on its drive. Other Snapdragon laptops are not tested | ARM-6 |
| N1X (deferred) | An RTX Spark laptop, once A-8's gate is met | after ARM-5 |

Available to the maintainer (2026-10-13): a Raspberry Pi 4 (4 GB) and an
NVIDIA GB10 system. Since 2026-10-27: a Raspberry Pi 5 (8 GB) as well, with no
NVMe board, and the GB10 no longer. Since 2026-11-05: the Pi 5 is the
maintainer's DNS server, borrowed only for short tests, and a Dell XPS 13
9345 (Snapdragon X Elite) is ARM-6's test laptop. No Apple Silicon Mac is named. An emulated aarch64 QEMU VM on an
x86_64 host froze that host (2026-10-13), so ARM-1 tested on the GitHub arm64
runner (ARM1-05) and in a native VM on the GB10 (ARM1-06, below), not in an
emulated VM.

From 2026-10-19 to 2026-10-27 the GB10 (a DGX Spark, on its own Ubuntu-based
OS) was also the aarch64 build and test host. It ran the suite in the Arch
Linux ARM container (`scripts/ci-local.sh --base-image`), native aarch64 VMs
under KVM with UEFI (AAVMF), not emulated, and the image builds: ARM1-06 was
validated in such a VM, because the Pi 4 was not available (its Pi run moved to
ARM3-06), and ARM2-01, ARM2-05, ARM3-01 and ARM3-02 ran there. It is no longer
available (2026-10-27). What is left for aarch64:

- **Image builds before the merge:** the Pi 4 (4 GB), on Arch Linux ARM, as
  root, with the builder's tools and about 15 GB free. It built the Pi image
  from its own SD card in about 1 h 29 min (ARM3-06, 2026-11-04). The Pi 5
  is not a build host (2026-11-05: it runs the maintainer's DNS). The
  builders need an aarch64 Arch Linux ARM host, not a particular board.
- **The suite:** the GitHub arm64 runner (the Full suite workflow, ARM1-05),
  which Lyona-ARM pays for by the minute, so it runs once before the merge
  into Lyona rather than on every change; or the same suite in the Arch Linux
  ARM container on a Pi (`scripts/ci-local.sh --base-image`), slower but free.
- **Release builds:** after the merge, Lyona's arm64 runners (above, End
  state).

## GitHub

Each sprint is a milestone and each of its items an issue, labelled `arm64`. The issues were created 2026-10-11 in technicks89/Lyona and moved here;
[`arm-sprints-github.sh`](arm-sprints-github.sh) creates the milestones and
the "Lyona on ARM" project board, and puts each issue in its milestone.
ARM-4 and ARM5-05 are deferred but tracked, so they are visible on the
board: created 2026-10-26 with the `deferred` label (#57 to #62), ARM-4's
milestone with no due date and the board's Sprint option "ARM-4". Picking
one up removes its `deferred` label and gives ARM-4's milestone a due date.
