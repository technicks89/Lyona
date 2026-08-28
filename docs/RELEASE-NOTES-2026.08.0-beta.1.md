# lyona 2026.08.0-beta.1

First beta of the Arch Linux line, and the first release on calendar
versioning. This is a **pre-release**: it is published to GitHub with
`--prerelease` and is not promoted to Latest.

The previous line ended at `0.1.0`. That version reset the project from the
0.6.x Fedora-based numbering when the distribution target moved to Arch;
this release moves the same line onto `YYYY.MM.PATCH` calendar versions.
Changelog entries below `0.1.0` describe the superseded Fedora-based project
and are retained for history.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.08.0-beta.1.tar.gz` |
| Installer image | `lyona-2026.08.0-beta.1-x86_64.iso` |
| Checksums | `lyona-2026.08.0-beta.1-SHA256SUMS` |

The installer image carries `iso_label=LYONA_2026_08_0_BETA1` — an ISO9660
volume identifier cannot hold the suffix punctuation, so the label drops it
while the filename and `/etc/lyona-iso-release` keep the full version. That
file records the version, volume label, source commit, and build date on the
live medium. Quote it when reporting a problem with an image.

`scripts/lyona-release` writes the SHA-256 sums at publish time from the
artifacts it uploads. Record them here once the release is cut; do not copy
checksums from a local build, because the published archive is rebuilt from
the tagged commit.

## What is in this beta

### Arch Linux conversion

The distribution target moved from Fedora to Arch Linux in full: the
installer, dependency map, and diagnostics use `pacman` and Arch package
names, and the Fedora Kickstart/RPM Fusion/COPR image path is replaced by an
archiso-based install medium. Arch Linux is the sole supported platform.
Project branding moved to `technicks89`/`technicks89.com`, and the project was
renamed from `dwm-titus` to `lyona`. **There is no migration path from an
existing `dwm-titus` install** — reinstall onto the new paths.

### Display scaling without a logout

A DPI change now applies to the running session rather than only to
applications started afterwards. `dwm-settings-display dpi-set` persists
`Xft.dpi`, merges it into the running resource database, publishes it over
XSETTINGS, sets the X server's reported DPI, and writes a runtime record the
managed shell watches. dwm rescales its border width and snap distance; the
Quickshell panel, popups, Control Center, launcher, and Settings window scale
their metrics from the active DPI. A 96 DPI session renders as before.

Rescaling applications that are *already open* requires `xsettingsd`, which
joins the X11 dependency set along with `xorg-xrdb`. Without `xsettingsd` a
scale change still reaches the desktop immediately and reaches each
application as it restarts.

### Window stacking

Floating windows stay above the tiling layout. Previously every visible tiled
client was stacked directly beneath the bar — the top of the window stack — so
any floating window that was not the selected one was buried as soon as focus
moved to a tiled client. Tiled clients now also restack correctly on a monitor
that has not adopted a panel.

### Other changes

- The shipped default theme is Tokyo Night rather than Nord.
- `multilib` is enabled on the ISO, so the Arch gaming packages the full
  profile advertises are installed instead of skipped.
- Super+A prefers an installed ChatGPT desktop application, falling back to
  the web app.

See `CHANGELOG.md` for the complete list.

## Installing from the image

1. Write `lyona-2026.08.0-beta.1-x86_64.iso` to a USB stick and boot it. The
   medium auto-logs into a root shell on tty1.
2. Complete a base Arch install to `/mnt`, for example with `archinstall`,
   including a regular user account.
3. Run `/root/lyona-postinstall.sh` from that shell. It copies the checkout
   into the new system, runs `install.sh --profile core` as the created user,
   and enables LightDM and the graphical target.
4. Remove the medium and reboot.

Existing installs can update in place with `install.sh`; the image is only
needed for new systems.

## Qualification status

Fill this section in before publishing. It must state the Arch release tested
against, the architectures and X11 environments exercised, and the SHA-256 of
each artifact. Do not describe an environment that was not actually used.

**The installer image has not been boot-tested on real hardware or in a VM.**
`tests/test-arch-iso-builder.sh` verifies the package manifest, the
postinstall script, and that the release version reaches the ISO filename,
volume label, `iso_application`, and on-medium stamp — it does not verify that
the image boots or that the install completes.

Before treating this image as qualified, boot it in a KVM virtual machine,
complete the install flow above, and confirm LightDM, dwm, and the managed
Quickshell shell come up on the installed system. Record the source ISO
checksum, firmware mode, architecture, package-resolution result, and
first-boot result.

Verified so far, on the build host only:

- `make release-check` — reproducible source archive, byte-identical across
  two builds.
- `make check-archiso` — archiso profile structure and version stamping,
  including the pre-release volume label.
- `make check-release-helper` — release preflight and remote-write ordering.
- `make check-shell` — shellcheck across the shipped scripts.

## Known limitations

- **The display-scaling and window-stacking changes above have not been
  exercised on a live session.** They compile and pass the repository's
  static and structural checks; nothing here confirms the panel rescales,
  that GTK and Qt clients follow XSETTINGS on this hardware, or that the
  stacking order is correct on a real X server. Treat both as the beta's
  primary test targets.
- The archiso build path is best-effort and has been exercised only through
  its structural tests and a staged (`--profile-only`) profile.
- The image must be built on an Arch host with the `archiso` package
  installed; `mkarchiso` requires root.
- Package availability can be validated in a container, but that does not
  substitute for the boot and first-session qualification above.
- `xrandr --dpi` is not reversed by `dpi-reset`; the X server keeps its
  reported DPI until the next session. The resource and XSETTINGS values are
  both cleared.

## Reporting problems

Include `/etc/lyona-iso-release` from the medium when the report concerns an
image, and the output of `scripts/dwm-diagnostics` when it concerns an
installed session.
