# Sync Sprint 14 -- Older NVIDIA GPUs, with an AUR exception

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). It builds on Sprint 12 S12-15,
which moved the live medium's NVIDIA option to `nvidia-open` once Arch dropped
`nvidia` and `nvidia-dkms`.

**Status:** S14-01 to S14-03 implemented 2026-10-02, on one branch
(`s14-legacy-nvidia`). S14-04 needs real hardware and has not run
(`docs/evidence/s14-04-legacy-nvidia.md`). GitHub: milestone "Sync Sprint 14 -
Older NVIDIA GPUs", issues `#201` to `#204`.

| Item | Issue | Kind | Gate |
| --- | --- | --- | --- |
| [S14-01](#s14-01-the-aur-exception-written-down-and-enforced-narrowly) | `#201` | Policy, test | none |
| [S14-02](#s14-02-tell-which-driver-branch-a-card-needs) | `#202` | Feature | none |
| [S14-03](#s14-03-install-the-legacy-driver-from-the-live-medium) | `#203` | Feature | none (D-22, D-23 decided) |
| [S14-04](#s14-04-validate-on-real-legacy-hardware) | `#204` | Validation | S14-03, hardware |

---

## Why

Arch's NVIDIA driver is now `nvidia-open` or `nvidia-open-dkms`, which needs a
Turing (GTX 16xx, RTX 20xx) or newer GPU. Older cards have no driver in `core`,
`extra` or `multilib`. Since S12-15, the live medium's NVIDIA option installs
`nvidia-open` on Turing and newer cards only. On an older card, a device-ID
cutoff (`nvidia_open_supported`: below `0x1e00`) keeps nouveau and says why.
S14-02's table replaces that cutoff.

The maintained drivers for those cards are in the AUR. Checked 2026-10-01
through the AUR RPC:

| Branch | AUR packages | Last updated | Cards |
| --- | --- | --- | --- |
| 580xx | `nvidia-580xx-dkms`, `nvidia-580xx-utils`, `lib32-nvidia-580xx-utils`, `opencl-nvidia-580xx`, `nvidia-580xx-settings` | 2026-09-26 | Maxwell, Pascal, Volta (GTX 750 to GTX 10xx, Titan V) |
| 470xx | `nvidia-470xx-dkms`, `nvidia-470xx-utils`, `lib32-nvidia-470xx-utils` | 2026-09-01 | Kepler (GTX 600 and 700 series) |
| 390xx | `nvidia-390xx-dkms`, `nvidia-390xx-utils` | 2026-08-29 | Fermi (GTX 400 and 500 series) |

The CachyOS repository, which the postinstall already adds for its kernels,
ships prebuilt 580xx and 470xx packages under the same names
(`cachyos/nvidia-580xx-dkms 580.178.04-1` and
`cachyos/nvidia-470xx-dkms 470.256.02-20` on 2026-10-01). Under D-22 those
come first, and the AUR is used only when the CachyOS repository is unavailable.

## The exception

Today's rule (`docs/AUR-PACKAGES.md`, enforced by `tests/test-no-aur.sh`): an AUR
helper stays installed for the user, but no package Lyona installs depends on
the AUR.

The exception is this sprint's only change to that rule:

- **What:** the legacy NVIDIA driver packages of the 580xx and 470xx branches (D-23), and
  nothing else.
- **When:** only after the user picks the NVIDIA option, and only on a card that
  S14-02 identifies as needing that branch.
- **Where:** only the live medium's postinstall, through one function.
- **How:** from a PKGBUILD commit that has been reviewed and pinned, like
  `install.sh`'s `yay-bin`. It is built as the new user, never as root, and never
  through `yay`. Under D-22, it applies only when the CachyOS repository is
  unavailable; with it, the prebuilt package is installed with `pacman`.

The standard path doesn't change: Turing and newer cards, AMD and Intel use the
official repositories only.

---

## Decisions

| ID | Question | Blocks | Recommendation | Status |
| --- | --- | --- | --- | --- |
| **D-22** | Where does the legacy driver come from? (a) The CachyOS repository's prebuilt package when the postinstall added that repository, else the AUR. (b) Always the AUR. (c) `yay`, unpinned | S14-03 | **(a).** The CachyOS repository is already trusted by the install for its kernels, and its packages are signed and prebuilt. The AUR is the fallback for when adding the repository failed, from pinned commits built with `makepkg` as the new user | **Decided (2026-10-01), asked of the user directly:** the CachyOS repository when it is available, the AUR otherwise |
| **D-23** | Which branches? | S14-02, S14-03 | **580xx and 470xx.** Both are maintained and in the CachyOS repository. 390xx (Fermi, 2010-2012) has no Vulkan, needs Xorg ABI patches, and is only in the AUR; those cards stay on nouveau | **Decided (2026-10-01), asked of the user directly:** as recommended, 580xx and 470xx; 390xx is out |

---

## Implemented (2026-10-02)

Where it differs from the items below:

- **S14-01:**
  - The exception is written down in `docs/AUR-PACKAGES.md`, with the
    packages, the AUR bases, the pinned commits and what was reviewed at each.
    `docs/src/dependencies.md`, `docs/src/install.md`, `docs/RELEASING.md` and
    SPEC.md 5.11 match.
  - `tests/test-no-aur.sh` allows AUR access and `makepkg` only inside
    `install_legacy_nvidia_driver`, found by its `name() {` to `}` span; comment
    lines never count.
  - It skips the two legacy profiles in the official-repository check, and
    requires each of their packages to be built by a pinned base.
  - The three planned mutations each fail it: `makepkg` in another function,
    an AUR package in another profile, and a removed pin.
- **S14-02:**
  - **The table's source:** NVIDIA's `supportedchips.html`, which Arch's
    `nvidia-utils` installs. It has the same data as `supported-gpus.json` (a
    `devid` row per device, in a current section and one section per legacy
    branch), and needs no `.run` download.
  - **The generator and table:** `scripts/lyona-nvidia-gpu-table` (not
    installed) wrote `config/nvidia-legacy-gpus.tsv` from nvidia-utils
    615.71.09-1, with its checksum in the header. It has 879 legacy devices:
    162 are 580xx, 117 are 470xx, and 600 have no packaged driver.
  - **Unlisted devices:** an unlisted ID is `open`, unless it is below
    `0x1e00`, the S12-15 cutoff kept as the fallback. No current device is
    below it, so the two agree.
  - **The reader:** `lyona_nvidia_branch` and `nvidia_gpu_branch` live in
    `archiso/airootfs/root/lyona-nvidia.sh` and replace `nvidia_open_supported`.
  - **The tests** are in `test-arch-iso-builder.sh`: Turing, Ada, Pascal,
    Volta, Maxwell, Kepler and Fermi cards, two cards, and no ID.
- **S14-03:**
  - **Profiles:** `arch:gpu-nvidia-580xx` and `arch:gpu-nvidia-470xx`.
  - **The function:** `install_legacy_nvidia_driver` does as planned, and
    installs `base-devel` and `git` as dependencies first.
  - **The prompt:** the installer recommends "nvidia 580xx (proprietary legacy
    driver, recommended)" on such a card, and its summary says where the driver
    comes from.
  - **The closing message** says to update an AUR-built driver with `yay`.
  - **`tests/test-legacy-nvidia.sh`** runs the real functions against a stub
    chroot. It covers the CachyOS path, the CachyOS failure falling back to the
    AUR, the build (dependencies, user, packages, clean-up), a failed build,
    the 470xx pin, and the dispatch for each kind of card. A mutation that runs
    `makepkg` as root fails it.
  - **Not done:** the `-lib32` profiles. Gaming, and so `multilib`, is not
    enabled at install time, so nothing would install them.
- **S14-04:** not run; it needs Pascal and Kepler hardware.
- **The full suite (`scripts/run-tests`) passed end to end** on this branch,
  2026-10-02.

## S14-01: The AUR exception, written down and enforced narrowly

1. **Docs.** Add an "Exception: legacy NVIDIA drivers" section to
   `docs/AUR-PACKAGES.md` with the rule above, the packages, and the pinned
   commits. Update the "Repositories and the AUR" section of
   `docs/src/dependencies.md` and the AUR helper paragraph of
   `docs/src/install.md`, which both say "nothing depends on the AUR". The live
   medium's section of `docs/RELEASING.md` says which cards get which driver.
2. **SPEC.md.** Section 5.11 says the NVIDIA opt-in "may install the documented
   NVIDIA driver packages". It now names where they come from for older cards.
   This is an intentional requirement change, made in the same change as the
   docs.
3. **The guard.** `tests/test-no-aur.sh` keeps failing on any other AUR use. It
   gets an allowlist with exactly one entry, and nothing that matches by pattern:

   ```bash
   # The one AUR exception (Sync Sprint 14, docs/AUR-PACKAGES.md): the legacy
   # NVIDIA drivers, built from pinned PKGBUILDs by install_legacy_nvidia_driver.
   aur_exception_file=$repo/archiso/airootfs/root/lyona-postinstall.sh
   aur_exception_function=install_legacy_nvidia_driver
   ```

   - Section 1 allows `aur.archlinux.org` and `makepkg` only inside that
     function, found by its `name() {` to `}` span.
   - Section 2 skips the legacy profiles (`arch:gpu-nvidia-580xx*`,
     `arch:gpu-nvidia-470xx*`) in the official-repository check. It requires
     instead that each package in them has a pinned commit in the postinstall's
     pin table.
   - Section 2 still fails for every other profile, and for any profile that has
     a package outside the official repositories but no pin.
4. **Test.** Mutation checks in scratch copies:
   - `makepkg` in another function fails;
   - an AUR package in another profile fails;
   - removing a pin fails.

## S14-02: Tell which driver branch a card needs

Today the postinstall only greps `lspci` for "NVIDIA" or "GeForce". It needs the
PCI device ID, and a table that maps the ID to a branch.

- **Read the ID through a machine interface:** `lspci -n -mm -d 10de::0300`
  (VGA) and `-d 10de::0302` (3D) give the vendor and device as hex fields,
  with no human text to parse.
- **The table.** NVIDIA publishes `supported-gpus.json` (device ID, name,
  `legacybranch`) inside its `.run` installer, but Arch's `nvidia-utils` doesn't
  install it (only `supportedchips.html`). So:
  - a generator, `scripts/lyona-nvidia-gpu-table`, reads that JSON from a pinned
    driver version and writes `config/nvidia-legacy-gpus.tsv`, with lines like
    `1c03<TAB>580xx`;
  - the generated table is checked in, with its source version and checksum in
    its header;
  - a device that is absent from the table, or marked current, gets
    `nvidia-open`.
- **One reader:** `lyona_nvidia_branch DEVICE-ID` in a small sourced library
  prints `open`, `580xx`, `470xx` or `unsupported`.
- **Test:** `tests/test-nvidia-branch.sh` with a fake `lspci`:
  - one ID per branch;
  - an unknown ID;
  - two GPUs (the first discrete NVIDIA card wins, the same as today);
  - a 390xx card, which gets `unsupported` and stays on nouveau with a message.

## S14-03: Install the legacy driver from the live medium

1. **Profiles** in `scripts/dwm-packages.sh`, for 580xx and 470xx (D-23), with
   the 470xx profiles mirroring the 580xx ones:
   - `arch:gpu-nvidia-580xx`: `nvidia-580xx-dkms nvidia-580xx-utils`;
   - `arch:gpu-nvidia-580xx-lib32`: `lib32-nvidia-580xx-utils`, only when the
     gaming profile enabled `multilib`.

   The legacy branches are DKMS-only, so the kernel `-headers` are always
   added, from `installed_kernels`, as the `nvidia-open-dkms` path does now.
2. **`install_nvidia_driver`** asks `lyona_nvidia_branch`:
   - `open`: the current path;
   - `580xx` or `470xx`: the new `install_legacy_nvidia_driver`;
   - `unsupported`: nouveau, with a message that names the card and why.
3. **`install_legacy_nvidia_driver`**, per D-22:
   - When `$CACHYOS_MARKER` exists, `pacman -S` the profile from the CachyOS
     repository, named explicitly (`cachyos/nvidia-580xx-dkms`).
   - **Otherwise:**
     - clone each pinned PKGBUILD commit into a temporary directory owned by the
       new user, inside the chroot;
     - install the PKGBUILD's `depends` and `makedepends` as root with
       `pacman -S --asdeps`, read from `makepkg --printsrcinfo`. `--syncdeps`
       would call `sudo pacman` as the user, which can't authenticate in the
       chroot;
     - run `makepkg --noconfirm` there, as that user, through `runuser -u`;
     - install the built packages with `pacman -U`, as root;
     - remove the directory.
   - On any failure, nothing is half-installed: the step reports the failure,
     leaves nouveau in place, and the rest of the install goes on, as the
     NetworkManager step does.
4. **The installer prompt** (`lyona-install.sh`, `ask_nvidia`) names the driver
   it will install for the detected card: "nvidia-open", "nvidia 580xx (from
   CachyOS)", "nvidia 580xx (built from the AUR)", or "no proprietary driver
   supports this card".
5. **Updates.** The built packages are foreign packages: `pacman -Syu` won't
   update them, and the user's `yay` will. Say so in the install summary and
   in `docs/RELEASING.md`. Installs from the CachyOS repository update with
   `pacman` as usual.
6. **Tests:**
   - `test-arch-iso-builder.sh` extends S12-15's check to the new profiles;
   - a postinstall test with stub `arch-chroot`, `runuser`, `makepkg`, `git` and
     `pacman` checks each branch's commands, the CachyOS-first order, that
     `makepkg` never runs as root, and the failure path.

## S14-04: Validate on real legacy hardware

A VM can't stand in: there is no emulated NVIDIA GPU. Install from the medium on
at least one Pascal card (580xx) and one Kepler card (470xx). Check each
install for:

- the driver is in use (`nvidia-smi` runs, and `lsmod` lists `nvidia`, not
  `nouveau`);
- the session reaches the desktop, with Picom on;
- the driver still works after a kernel update (DKMS rebuild);
- with the CachyOS repository and without it (the AUR build).

Record the results in `docs/evidence/s14-04-legacy-nvidia.md`. Until this is
done, the docs describe the legacy path as untested on hardware (SPEC.md
section 9.4).

## Not in scope

- `install.sh` on an existing Arch system. It installs no GPU drivers today,
  and its users already have one.
- The 390xx branch (D-23): Fermi cards stay on nouveau.
- `nvidia-580xx-settings` and the other optional packages.
