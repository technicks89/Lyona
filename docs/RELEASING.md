# Release Checklist

Release artifacts are generated from the release build configuration. Do not
use `make native` for published binaries.

1. Update `VERSION` in `config.mk` and move the applicable `CHANGELOG.md`
   entries from Unreleased into that version.
2. Commit and push the release source. The helper refuses dirty worktrees,
   version mismatches, and commits that are unavailable on GitHub.
3. Run `scripts/run-tests`.
4. Run `scripts/run-tests make check-xvfb-runtime check-monitor-tags` in isolated X11.
5. Run `scripts/run-tests make check-arch-packages` on Arch Linux.
6. Run `scripts/run-tests make check-quickshell-qml check-quickshell-health-xvfb
   check-quickshell-settings-xvfb` when QML changed.
7. Run `scripts/run-tests mdbook build docs` when published documentation
   changed.
8. Run `scripts/run-tests make release-check` and confirm the artifact is named
   `release/lyona-VERSION.tar.gz`. When the release ships an installer
   image, build it per "Arch installer ISO" below and confirm it is named
   `lyona-VERSION-x86_64.iso` with a matching
   `/etc/lyona-iso-release`.
9. Record the tested Arch release, architectures, X11 environments, known
   limitations, and SHA-256 checksum in the release notes.
10. Tag the release only after all applicable `SPEC.md` acceptance criteria
    and required GitHub checks pass. The ISO workflow (see "Automated ISO
    builds and releases" below) creates the tag; run it only then.

`scripts/run-tests` creates an isolated directory below
`${DWM_TEST_TMP_ROOT:-$HOME/tmp}` and removes it on success, failure, or
interruption. Store
disposable VM disks and installer logs under a separately named directory in
that same root, then delete that exact directory after qualification. Do not
use `/tmp` for ISO or VM qualification.

lyona uses calendar versioning: `YYYY.MM`, or `YYYY.MM.PATCH` for a
second (or later) release in the same month. Before releasing, set `VERSION`
in `config.mk` to the version you're cutting (there is no automatic bump —
set it by hand each time).

### Pre-releases

A version may carry an `-alpha.N`, `-beta.N` or `-rc.N` suffix, for example
`2026.10.0-beta.1`. The suffix is part of the one `VERSION` in `config.mk`, so
it reaches the source archive, the compiled `dwm -v` string, the tag, and the
installer image together — there is no separate pre-release switch to forget.

`scripts/lyona-release` publishes a suffixed version to GitHub with
`--prerelease`, so it is never promoted to Latest. Only the three channel names
above are accepted, and the counter is required: `-beta` without a number is
rejected, as is any other word.

An ISO9660 volume identifier admits only `A-Z`, `0-9` and `_` and is capped at
32 characters, so the volume label drops the suffix punctuation:
`2026.10.0-beta.1` produces `LYONA_2026_10_0_BETA1`. The ISO filename and
`/etc/lyona-iso-release` keep the full version.

A pre-release is still a release: everything in the checklist above applies,
and step 9 must state plainly which parts are unqualified.

Release through the ISO workflow ("Automated ISO builds and releases" below).
It signs the source archive and the ISO before anything is published, which
`lyona-update` requires ("Signed releases" below); a release made by hand
cannot be signed. The workflow runs `scripts/lyona-release` as:

```sh
scripts/lyona-release --version v2026.10.0-beta.2 --iso lyona-2026.10.0-beta.2-x86_64.iso \
	--bundle BUNDLE --notes docs/RELEASE-NOTES-2026.10.0-beta.2.md --prerelease --skip-checks
```

`BUNDLE` is the signing step's bundle. The version must match `config.mk`; a
stable one has no suffix, such as `v2026.10.0`. Run by
hand, use `--dry-run` to see the plan; without `--bundle` it publishes a
release that `lyona-update` refuses.

The helper validates and hashes local artifacts before it creates a remote tag
or release. `--version` confirms the version already committed in `config.mk`;
it does not rewrite release source.

The release asset is a source archive (Sync Sprint 12 S12-19): the repository's
files under `lyona-VERSION/`, which `lyona-update` and `lyona-update-root` build
and install the way a checkout installs. `make release` takes git's file list,
so it runs in a checkout, and the release helper requires that checkout to be
clean.

`make release-check`:

- builds the archive twice and checks the bytes are identical;
- checks for the build files and sources (`Makefile`, `config.mk`,
  `config.def.h`, the C sources and the scripts);
- checks that nothing is built or local: no binaries, no `config.h`, no
  objects, no `.git` or `release/`;
- extracts the archive alone and builds it.

## Arch installer ISO

The ISO carries the same version as the rest of the project: one `VERSION` in
`config.mk` drives the source archive, the compiled `dwm -v` string, and the
installer image. Bump `config.mk` before building the image, not after.

Build the installer image on an Arch host with the `archiso` package
installed:

```sh
sudo scripts/build-lyona-arch-iso.sh --output release/
```

This layers `archiso/packages.x86_64`, `archiso/pacman.conf`, and this
checkout onto the system's archiso `releng` profile, then runs `mkarchiso`.
The build reads `VERSION` from `config.mk` — `--version` overrides it for test
images — and produces:

| Artifact | Value at 2026.10.0 | Value at 2026.10.0-beta.1 |
| --- | --- | --- |
| ISO filename | `lyona-2026.10.0-x86_64.iso` | `lyona-2026.10.0-beta.1-x86_64.iso` |
| Volume label (`iso_label`) | `LYONA_2026_10_0` | `LYONA_2026_10_0_BETA1` |
| `iso_application` | `lyona 2026.10.0 Arch Linux install medium` | `lyona 2026.10.0-beta.1 Arch Linux install medium` |
| On-medium stamp | `/etc/lyona-iso-release` | `/etc/lyona-iso-release` |

`/etc/lyona-iso-release` records `LYONA_ISO_VERSION`,
`LYONA_ISO_LABEL`, `LYONA_ISO_COMMIT`, and `LYONA_ISO_BUILD_DATE`,
so a booted medium identifies exactly which build it came from. Report the
version from that file in qualification notes and bug reports.

Use `--profile-only` to stage and inspect the branded archiso profile without
root or `mkarchiso`; `tests/test-arch-iso-builder.sh` uses that path to verify
the version reaches every field above. Set `LYONA_RELENG_DIR` if the
`releng` profile is not at `/usr/share/archiso/configs/releng`.

The build produces an ISO on Arch Linux (the release workflow builds one for
every release). **VM qualification, 2026-10-03:** images built on the
maintainer's host were installed in a QEMU/KVM virtual machine three times,
each run finding faults fixed before the next (`CHANGELOG.md`,
`2026.10.0-beta.2`). The last run:
- **Image:** `lyona-2026.10.0-beta.1-x86_64.iso` built at the pre-`beta.2`
  commit of this work, SHA-256
  `19341b4cbb95cfe58a90b77de90660e277b27bb2a3418915f5fb15e1a3f17beb`,
  `archiso` 91-1, Arch with the CachyOS repositories.
- **Machine:** x86_64, UEFI (OVMF), a standard VGA adapter, no NVIDIA GPU,
  4 GiB, a 30 GiB virtio disk, btrfs, no encryption.
- **Result:** packages resolved and the wizard completed with no manual
  help; the installed system booted to LightDM, and dwm and the managed
  shell came up (the launcher, the power menu).

**Still untested:** real hardware, NVIDIA and legacy NVIDIA drivers, LUKS,
ext4, the manual `archinstall` fallback, an image built by the release
workflow, and `lyona-update` from one release to the next. Do not treat a
release as qualified on hardware until it has been.

### Signed releases

The release workflow signs what users install, the ISO and the source archive,
from `2026.10.0-beta.2` on (decision D-31, reversing D-14). It records one
build-provenance attestation for both, signed keylessly through Sigstore with
the run's GitHub identity. There is no signing key to keep or rotate: the
signature names the repository, the workflow file, the branch (`main`) and the
commit it was built from.

The files are signed before anything is published. `scripts/lyona-release
--bundle` then publishes the signature as `lyona-VERSION.sigstore.json`, and
refuses a bundle that does not name the digests of the archive and the ISO it
uploads; the archive is reproducible, so its rebuild is the file that was
signed. The attestation is also kept in the repository's attestation store.

`lyona-update` checks the signature with `cosign` before it unpacks a release,
and refuses one that does not verify or has no bundle. To check a download by
hand, with `cosign`:

```sh
cosign verify-blob-attestation --bundle lyona-VERSION.sigstore.json \
	--type https://slsa.dev/provenance/v1 \
	--certificate-oidc-issuer https://token.actions.githubusercontent.com \
	--certificate-identity https://github.com/technicks89/Lyona/.github/workflows/build-iso.yml@refs/heads/main \
	lyona-VERSION-x86_64.iso
```

Or, logged in to the GitHub CLI: `gh attestation verify FILE --repo
technicks89/Lyona`. Either succeeds only for a file this repository's workflow
built. A release made by hand with `scripts/lyona-release` and no `--bundle` is
not signed, and `lyona-update` refuses it: publish through the workflow.

### Using the ISO

**Requires UEFI.** The wizard installs systemd-boot, which cannot boot
BIOS/legacy systems — see the manual fallback below if you're on BIOS.

Booting the image auto-logs into a root shell on tty1 (standard archiso
behavior) and **automatically launches `lyona-install`** — no command to
type. (A `/root/.lyona-install-done` sentinel, written once the base
install succeeds, stops it from relaunching and re-wiping the disk on a
later tty1 relogin; re-run `lyona-install` by hand if you ever want to.)

It's a short, opinionated wizard drawn with `gum`, not `archinstall`'s own
menu system: a LYONA wordmark banner, then keyboard layout, target disk, btrfs
or ext4 (each with optional LUKS encryption), username/password, hostname,
timezone (auto-detected and confirmed), and, only if an NVIDIA GPU is detected,
a driver choice. There is one image for every GPU (SPEC.md).

- **A supported card:** on a Turing (GTX 16xx, RTX 20xx) or newer GPU, the
  choice recommends the proprietary driver, with open-source nouveau as the
  alternative. The driver is `nvidia-open`, or `nvidia-open-dkms` with any
  other kernel.
- **An older card (Sync Sprint 14):** a Maxwell, Pascal or Volta card (GTX
  750 to GTX 10xx) is offered the legacy 580xx driver, and a Kepler card (GTX
  600 and 700) the 470xx one.
  - The device ID decides, through `config/nvidia-legacy-gpus.tsv`, generated
    from NVIDIA's own table by `scripts/lyona-nvidia-gpu-table`.
  - The driver comes from the CachyOS repository when the medium added it, and
    is otherwise built from a pinned AUR PKGBUILD (`docs/AUR-PACKAGES.md`).
  - An AUR-built driver is not updated by `pacman -Syu`; the user updates it
    with `yay`, and the install's closing message says so.
- **A card no packaged driver supports** (Fermi and older) keeps nouveau
  without a prompt, and the summary says why.
- **Not yet hardware-tested:** the legacy driver path has been tested only
  against a stub chroot (S14-04).

There is no
desktop-environment or package picker; this always installs lyona.
After a summary and a final "Wipe `$DISK` and install" confirmation, it
generates an `archinstall` JSON config (an ESP and a root of the chosen
filesystem, encrypted when chosen; systemd-boot, zram swap, NetworkManager)
and runs `archinstall --config ... --creds ...
--silent` fully unattended — no menus to navigate. Once that completes, it
automatically runs `lyona-postinstall.sh` to finish the lyona
install.

The `archinstall` JSON schema is version-sensitive and was validated by
running real installs against loop devices, not just archinstall's own
bundled `examples/config-sample.json` (which is stale/wrong for 4.4 in
several fields). If this profile bumps the archinstall package version,
re-validate the schema in `archiso/airootfs/root/lyona-install.sh`
before trusting it again.

**Manual fallback** (BIOS systems, or custom partitioning): boot the ISO,
run `archinstall` yourself, then run `/root/lyona-postinstall.sh`
directly — it only requires a mounted target at `/mnt` with a regular user
already created, and works the same whether `lyona-install` or a manual
`archinstall` run got you there. It also handles CPU microcode, a GPU
driver, NetworkManager, and low-memory swap (`LYONA_NVIDIA_DRIVER=1` installs
the proprietary NVIDIA driver, which the wizard would have recommended),
before installing the lyona package profile
itself. Once that is done, and its temporary passwordless `sudo` rule is
removed, it builds Topgrade as the new user (Sync Sprint 15 S15-06): rustup is
installed, and the newest Topgrade is built with cargo. This adds a few minutes
and some network use to every install. A failure is reported, and the user can
run `install-topgrade` after logging in.

Install the image in a KVM virtual machine before treating it as
release-qualified. Boot the live medium, run `lyona-install` to
completion, reboot from the installed virtual disk, and verify LightDM, dwm,
and the managed Quickshell shell. Record the source ISO checksum, firmware
mode, architecture, package-resolution result, first-boot result, and
untested hardware. A container can validate package availability, but it
cannot replace the required boot and first-session VM qualification.

### Automated ISO builds and releases (CI)

`.github/workflows/build-iso.yml` builds the ISO in a privileged
`archlinux:base-devel` container, then creates the tag and the release. It is
run by hand, from the Actions tab or:

```sh
gh workflow run build-iso.yml -f channel=main
gh workflow run build-iso.yml -f channel=beta -f notes=docs/RELEASE-NOTES-2026.10.0-beta.1.md
```

It asks for the channel:
- **beta:** `VERSION` in `config.mk` must have an `-alpha.N`, `-beta.N` or
  `-rc.N` suffix.
- **main:** `VERSION` must be a plain `YYYY.MM.PATCH`.

A mismatch fails in seconds, before anything is built. So commit the new
`VERSION` (and `CHANGELOG.md`) first, and push it.

What it does:
- **The ISO:** builds it, and keeps it and its `SHA256SUMS` as a workflow
  artifact.
- **The tag and the release:** only once the ISO has built, it runs
  `scripts/lyona-release` with `--prerelease`. That creates `vVERSION` at the
  run's commit, with the source archive `lyona-update` installs from, the ISO,
  and a `SHA256SUMS` of both. `notes` is an optional release notes file in the
  repository.
- **Every release starts as a pre-release.** A beta stays one. A main release
  stays one until you promote it, once its ISO has passed the VM
  qualification above.
- **Reruns:** rerunning for a `VERSION` already tagged at the same commit
  replaces the release's assets. A `VERSION` tagged at another commit is
  refused; bump `VERSION` to release again.

#### Who can release, and the release token

Only the repository's **admins and maintainers** can run either release
workflow. Each starts with an `authorize` job, which asks GitHub for the role of
whoever started the run and refuses anything but `admin` or `maintain`. It
follows the collaborator list as it changes.

The tag needs an admin's token. The "Lock Tags" ruleset lets only admins
create, move or delete tags, and the workflow's own `GITHUB_TOKEN` is not an
admin. On a personal repository the ruleset's bypass list cannot name GitHub
Actions. So the release step uses `RELEASE_TOKEN`: an admin's fine-grained
personal access token, kept as a secret of the `release` environment.
`build-iso.yml` fails before building anything when that secret is missing.

To set it up, once, and again when the token expires:

1. **Create the token** (GitHub -> Settings -> Developer settings -> Personal
   access tokens -> Fine-grained tokens):
   - Repository access: only `technicks89/Lyona`.
   - Repository permissions: Contents, read and write. Nothing else.
   - Expiration: your choice; note the date.
2. **The environment:** Settings -> Environments -> `release`, with deployment
   branches limited to `main`. A run from any other branch cannot use it.
3. **Store the token** in that environment, not as a repository secret:

   ```sh
   gh secret set RELEASE_TOKEN --env release
   ```

Maintainers can run the release, and it uses the token, but cannot read it.
Only admins can change the environment or its secret.

To promote a qualified main release, run `.github/workflows/promote-releases.yml`
by hand with its tag:

```sh
gh workflow run promote-releases.yml -f tag=v2026.10.0
```

It makes the release a normal one, and the latest unless a newer stable release
already is. It refuses a beta tag, a tag with no release, and a draft, and does
nothing for a release that is already normal. Nothing promotes a release
automatically.
