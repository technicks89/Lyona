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
    and required GitHub checks pass.

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
`2026.08.0-beta.1`. The suffix is part of the one `VERSION` in `config.mk`, so
it reaches the source archive, the compiled `dwm -v` string, the tag, and the
installer image together — there is no separate pre-release switch to forget.

`scripts/lyona-release` publishes a suffixed version to GitHub with
`--prerelease`, so it is never promoted to Latest. Only the three channel names
above are accepted, and the counter is required: `-beta` without a number is
rejected, as is any other word.

An ISO9660 volume identifier admits only `A-Z`, `0-9` and `_` and is capped at
32 characters, so the volume label drops the suffix punctuation:
`2026.08.0-beta.1` produces `LYONA_2026_08_0_BETA1`. The ISO filename and
`/etc/lyona-iso-release` keep the full version.

A pre-release is still a release: everything in the checklist above applies,
and step 9 must state plainly which parts are unqualified.

To create the GitHub release:

```sh
scripts/lyona-release --version v2026.08.0 --iso ~/Downloads/lyona.iso --notes RELEASE_NOTES.md
```

For a pre-release, pass the suffixed version — it must match `config.mk`:

```sh
scripts/lyona-release --version v2026.08.0-beta.1 \
	--iso release/lyona-2026.08.0-beta.1-x86_64.iso \
	--notes docs/RELEASE-NOTES-2026.08.0-beta.1.md
```

The helper validates and hashes local artifacts before it creates a remote tag
or release. `--version` confirms the version already committed in `config.mk`;
it does not rewrite release source.

`make release-check` builds the archive twice and verifies identical bytes,
the generated desktop-session path, required archive entries, and the absence
of `config.h` and object files.

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

| Artifact | Value at 2026.08.0 | Value at 2026.08.0-beta.1 |
| --- | --- | --- |
| ISO filename | `lyona-2026.08.0-x86_64.iso` | `lyona-2026.08.0-beta.1-x86_64.iso` |
| Volume label (`iso_label`) | `LYONA_2026_08_0` | `LYONA_2026_08_0_BETA1` |
| `iso_application` | `lyona 2026.08.0 Arch Linux install medium` | `lyona 2026.08.0-beta.1 Arch Linux install medium` |
| On-medium stamp | `/etc/lyona-iso-release` | `/etc/lyona-iso-release` |

`/etc/lyona-iso-release` records `LYONA_ISO_VERSION`,
`LYONA_ISO_LABEL`, `LYONA_ISO_COMMIT`, and `LYONA_ISO_BUILD_DATE`,
so a booted medium identifies exactly which build it came from. Report the
version from that file in qualification notes and bug reports.

Use `--profile-only` to stage and inspect the branded archiso profile without
root or `mkarchiso`; `tests/test-arch-iso-builder.sh` uses that path to verify
the version reaches every field above. Set `LYONA_RELENG_DIR` if the
`releng` profile is not at `/usr/share/archiso/configs/releng`.

This build has been verified to produce a bootable ISO on Arch Linux, but
**it has not been boot-tested end-to-end on real hardware or in a VM** — do
not treat it as release-qualified until it has been.

### Using the ISO

**Requires UEFI.** The wizard installs systemd-boot, which cannot boot
BIOS/legacy systems — see the manual fallback below if you're on BIOS.

Booting the image auto-logs into a root shell on tty1 (standard archiso
behavior) and **automatically launches `lyona-install`** — no command to
type. (A `/root/.lyona-install-done` sentinel, written once the base
install succeeds, stops it from relaunching and re-wiping the disk on a
later tty1 relogin; re-run `lyona-install` by hand if you ever want to.)

It's a short, opinionated wizard styled after linutil's `server-setup.sh`
(arrow-key `select_option` menus, a redrawn banner between steps), not
`archinstall`'s own menu system: a `gum`-drawn LYONA wordmark banner,
then keyboard layout, target disk, username/password,
hostname, timezone (auto-detected and confirmed), and, only if an NVIDIA GPU
is detected, a driver choice (default: open-source nouveau — the standard
image never auto-installs proprietary drivers, per SPEC.md). There is no
desktop-environment or package picker; this always installs lyona.
After a final "type yes to wipe `$DISK`" confirmation, it generates an
`archinstall` JSON config (single btrfs root + ESP, systemd-boot, zram
swap, NetworkManager) and runs `archinstall --config ... --creds ...
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
driver, NetworkManager, and low-memory swap (`LYONA_NVIDIA_DRIVER=1` for
the same NVIDIA opt-in), before installing the lyona package profile
itself.

Install the image in a KVM virtual machine before treating it as
release-qualified. Boot the live medium, run `lyona-install` to
completion, reboot from the installed virtual disk, and verify LightDM, dwm,
and the managed Quickshell shell. Record the source ISO checksum, firmware
mode, architecture, package-resolution result, first-boot result, and
untested hardware. A container can validate package availability, but it
cannot replace the required boot and first-session VM qualification.

### Automated ISO builds (CI)

`.github/workflows/build-iso.yml` runs the same build script in a privileged
`archlinux:base-devel` container. It is manually triggered (never on tag
push) — run it from the Actions tab or:

```sh
gh workflow run build-iso.yml -f tag=v2026.08.0
```

`tag` must be an existing release tag (i.e. `scripts/lyona-release` has
already run for that version). The workflow builds the ISO, uploads it as a
workflow artifact, and attaches it plus a `SHA256SUMS` file to that tag's
GitHub release as a **pre-release** — GitHub only shows the newest
non-prerelease as "Latest", so this never displaces the current qualified
release. After boot-qualifying the ISO in a VM as above, promote it:

```sh
gh release edit v2026.08.0 --prerelease=false --latest
```
