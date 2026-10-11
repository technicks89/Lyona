# ARM Sprint 1 -- Foundation: Lyona on an existing Arch Linux ARM system

Index: [`ARM64.md`](ARM64.md).

**Status:** planned 2026-10-11. Not started.

**Goal:** `install.sh` installs Lyona on an existing Arch Linux ARM (aarch64)
system and reaches a working desktop, and CI builds and tests on aarch64. No
image yet: that is ARM-2 and ARM-3, which both build on this sprint.

| Item | Kind | Gate |
| --- | --- | --- |
| [ARM1-01](#arm1-01-the-support-contract-and-the-identity) | Policy, installer | A-1 |
| [ARM1-02](#arm1-02-the-dependency-map-on-aarch64) | Packaging | ARM1-01 |
| [ARM1-03](#arm1-03-aur-pins-and-downloaded-binaries-on-aarch64) | Packaging | ARM1-02 |
| [ARM1-04](#arm1-04-code-that-assumes-x86_64) | Fix | none |
| [ARM1-05](#arm1-05-aarch64-ci) | CI | A-9 |
| [ARM1-06](#arm1-06-validate-installsh-on-arch-linux-arm) | Validation | ARM1-01 to ARM1-04, an aarch64 VM |

---

## ARM1-01: The support contract and the identity

1. **Contract.** Under A-1, `SPEC.md` section 4 gains Arch Linux ARM
   (`ID=archarm`, `aarch64` only) as a second accepted identity, with the
   target table marking it "experimental (ARM64 project)". `AGENTS.md`'s "Arch
   Support Contract" and "Arch Platform Rules" say the same. This is an
   intentional requirement change, made in the same change as the code.
2. **Detection.** The `/etc/os-release` check (`scripts/dwm-utils.sh`, and
   `install.sh`'s use of it) accepts `ID=arch` on any supported architecture
   and `ID=archarm` on `aarch64` only. Everything else, including
   `ID_LIKE=arch` derivatives and `archarm` on `armv7h`, is rejected before any
   package or system change, with a message naming the identity and the
   architecture found.
3. **One variable for "Arch family".** Code that now tests
   `$DISTRO_ID == "arch"` (CachyOS, Topgrade, the optional profiles in
   `install.sh`) tests a helper instead (for example `is_arch_family`), so the
   ARM identity reaches the same paths and the architecture gates stay where
   they are (CachyOS stays x86_64 only).
4. **Tests.** The platform test (`make check-arch-platform`) gains cases for
   `archarm` on `aarch64` (accepted), `archarm` on `armv7h` (rejected), a
   derivative with `ID_LIKE=arch` (rejected), and `arch` on `aarch64`
   (accepted: Arch's own aarch64 port, if it ever ships, is still Arch).

**Acceptance:** the identity tests pass; a stubbed `install.sh` run on
`archarm`/`aarch64` gets past the identity check and skips CachyOS with its
existing message.

## ARM1-02: The dependency map on aarch64

1. **Survey.** On an Arch Linux ARM system, run `pacman -Si` for every
   package every profile in `scripts/dwm-packages.sh` resolves to, and record
   the result in `docs/evidence/` (found, version, or missing).
2. **Gate what is missing.** Each missing package is either gated by
   architecture in the map, with a comment saying why, or replaced by what
   Arch Linux ARM ships. No new package lists outside the map.
3. **Profiles that do not apply on aarch64.** Gaming is already x86_64 only.
   The NVIDIA profiles (`arch:gpu-nvidia*`) and the CachyOS kernels resolve to
   nothing on aarch64 (GB10's driver is ARM-4's own profile). `multilib` is
   never enabled.
4. **The live-medium profile** (`arch:iso`) is left alone here; ARM-2 adds its
   aarch64 counterpart.
5. **Test.** `check-arch-packages` resolves every profile for both
   architectures (`ARCH=x86_64` and `ARCH=aarch64`), and fails if an
   architecture-gated package reappears ungated.

**Acceptance:** every profile resolves on aarch64 to packages that exist in
Arch Linux ARM on the survey date; the x86_64 resolution is unchanged.

## ARM1-03: AUR pins and downloaded binaries on aarch64

1. **AUR pins** (`scripts/dwm-aur.sh`): `yay-bin` and `topgrade-bin` were
   reviewed for x86_64. For each, check that the pinned PKGBUILD lists
   `aarch64` in `arch=()` with its own checksummed `source_aarch64`. Where it
   does not, pin a commit that does, or build the non-`-bin` package from
   source on aarch64 (decided per package, written down in
   `docs/AUR-PACKAGES.md`).
2. **Downloaded tools** (`install-herdr`, `install-gearlever`,
   `lyona-appimage`, Topgrade's cargo path): each either supports aarch64
   (herdr already does), is gated off with a clear message, or is marked as a
   follow-up. AppImages are per-architecture; an x86_64 AppImage must never be
   offered on aarch64.
3. **Tests.** `test-dwm-aur.sh` checks the aarch64 sources of every pin are
   checksummed (it already reads `source_$arch`); each installer's test gains
   an aarch64 case.

**Acceptance:** `install.sh --print-plan`-style summaries name the right
artifact for aarch64, and nothing x86_64-only is downloaded on aarch64.

## ARM1-04: Code that assumes x86_64

Known places (from a 2026-10-11 search for `x86_64` and `uname -m`); the
sprint starts by repeating the search.

1. **System information** (`scripts/lyona_system_management/system_information.py`):
   the CPU model is read from `/proc/cpuinfo`'s `model name`, which ARM
   kernels do not print. Fall back to the device tree's model
   (`/sys/firmware/devicetree/base/model`, for the Pi), then SMBIOS
   (`/sys/class/dmi/id/product_name`, for UEFI machines), then the
   `CPU implementer`/`CPU part` pair. Tests with ARM fixtures.
2. **NVIDIA detection** is PCI-based and must find nothing on a Pi or a VM,
   without errors. GB10 detection is ARM-4's.
3. **Picom backend choice** (GLX on accelerated Intel/AMD, XRender otherwise):
   on aarch64 it chooses XRender unless the GPU is one Lyona has measured
   (ARM-3 measures `v3d`; ARM-4 NVIDIA). A missing GPU driver falls back as it
   does today.
4. **Settings features that assume a PC:** boot entries and firmware (GRUB or
   systemd-boot on UEFI), suspend and hibernate. Each is hidden or explained
   on a machine that lacks it, as `AGENTS.md` requires for unsupported
   hardware, without breaking the rest of Settings.
5. **The build.** `make clean all` with warnings enabled on aarch64 (GCC and
   Clang). C code has no x86 assumption known today; this proves it.

**Acceptance:** each place has a test that runs the aarch64 case, and the
x86_64 cases still pass.

## ARM1-05: aarch64 CI

1. Under A-9, add an aarch64 job to the manual **Full suite** workflow
   (`.github/workflows/full-suite.yml`): a GitHub `ubuntu-24.04-arm` runner,
   the suite inside an Arch Linux ARM container (bootstrapped from Arch Linux
   ARM's own `ArchLinuxARM-aarch64-latest.tar.gz`, with its checksum and
   signature checked).
2. Tests that need x86_64 (the x86_64 ISO builder, CachyOS, legacy NVIDIA)
   skip on aarch64 with exit 77, as other environment-gated tests do, and say
   why.
3. Record the first green run in the sprint's evidence. Move the job onto pull
   requests only after several consecutive green runs.

**Acceptance:** a green aarch64 Full suite run on the sprint branch.

## ARM1-06: Validate `install.sh` on Arch Linux ARM

1. **Machine:** an Arch Linux ARM virtual machine on Apple Silicon (UTM or
   Parallels), UEFI, `linux-aarch64` kernel, installed from Arch Linux ARM's
   generic tarball.
2. **Run** `install.sh` for the recommended and full profiles; log in through
   LightDM and through `startx`.
3. **Check:** the panel, launcher, overview (with Picom, then without),
   Settings (every pane opens; System Information names the CPU), audio,
   network, a reboot, `lyona-update check`, idle CPU and memory with the
   launcher closed.
4. **Record** in `docs/evidence/arm1-06-install-sh.md`, including what was
   not tested.

**Acceptance:** a working desktop on the VM with no manual step, and the
x86_64 Full suite still green.

---

## Not in this sprint

Any image, the Raspberry Pi, GB10 and N1X. `SPEC.md`'s contract changes only
as far as ARM1-01 says: the identity is accepted and marked experimental; no
target is claimed supported.
