# lyona 0.1.0

First release of lyona as an Arch Linux distribution.

The project version was reset from the 0.6.x Fedora-based line to `0.1.0`.
The Arch conversion replaces the Fedora Kickstart install path with an
archiso-based installer image, so it starts a new version line rather than
continuing the old one. Changelog entries below `0.1.0` describe the
superseded Fedora-based project and are retained for history.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-0.1.0.tar.gz` |
| Installer image | `lyona-0.1.0-x86_64.iso` |
| Checksums | `lyona-0.1.0-SHA256SUMS` |

The installer image carries `iso_label=LYONA_0_1_0` and records its
version, volume label, source commit, and build date in
`/etc/lyona-iso-release` on the live medium. Quote that file when
reporting a problem with an image.

## Installing from the image

1. Write `lyona-0.1.0-x86_64.iso` to a USB stick and boot it. The medium
   auto-logs into a root shell on tty1.
2. Complete a base Arch install to `/mnt`, for example with `archinstall`,
   including a regular user account.
3. Run `/root/lyona-postinstall.sh` from that shell. It copies the
   checkout into the new system, runs `install.sh --profile core` as the
   created user, and enables LightDM and the graphical target.
4. Remove the medium and reboot.

Existing installs can update in place with `install.sh` instead; the image is
only needed for new systems.

## Qualification status

**The installer image has not been boot-tested on real hardware or in a VM.**
`tests/test-arch-iso-builder.sh` verifies the package manifest, the
postinstall script, and that the release version reaches the ISO filename,
volume label, `iso_application`, and on-medium stamp — it does not verify that
the image boots or that the install completes.

Before treating this image as release-qualified, boot it in a KVM virtual
machine, complete the install flow above, and confirm LightDM, dwm, and the
managed Quickshell shell come up on the installed system. Record the source
ISO checksum, firmware mode, architecture, package-resolution result, and
first-boot result.

## Known limitations

- The archiso build path is best-effort and has been exercised only through
  its structural tests and a staged (`--profile-only`) profile.
- The image must be built on an Arch host with the `archiso` package
  installed; `mkarchiso` requires root.
- Package availability can be validated in a container, but that does not
  substitute for the boot and first-session qualification above.
