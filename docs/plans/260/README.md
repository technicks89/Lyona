# #260: AppImages without the GNOME runtime

Issue `#260`. Branch `appimage-handler`, one commit: "Open AppImages with
lyona-appimage; Gear Lever opt-in (#260)". Written with the change; the code is
in the diff, and this records the design and the decisions behind it.

## Why

Measured for #250 (`docs/evidence/250-install-step-timing.md`, B4): Gear Lever
cost every recommended install 602 MB of downloads and 1.7 GB on disk (the GNOME
and GL Flatpak runtimes), plus 31 s on an existing system or a job at first
login. And classic AppImages could not run at all: nothing installed `fuse2`
(`libfuse.so.2`); lyona only had Flatpak's `fuse3`.

## What changed

| Piece | What |
| --- | --- |
| `scripts/lyona-appimage` (new, a command) | `open FILE`, `remove NAME`, `list` |
| `lyona-appimage.desktop` (new) | The handler, hidden (`NoDisplay`), for `application/vnd.appimage`, installed to `DATADIR/applications` |
| `scripts/dwm-packages.sh` | A new `appimage` group, `fuse2` and `squashfs-tools`, in `desktop` |
| `install.sh` | `configure_appimage_handler` after the defaults are seeded; Gear Lever only with `--with-gearlever`; a leftover first-login marker cleared without it; the summary says both |
| `scripts/install-gearlever` | Takes AppImages over from `lyona-appimage.desktop` (asking for Gear Lever is asking for that), never from a handler the user chose |
| `Makefile` | The command and the desktop entry, in install, uninstall and the install manifest; the new test in `check-gearlever-install` |

## How lyona-appimage reads an AppImage without running it

A type-2 AppImage is an ELF runtime followed by a squashfs image. The image
starts where the ELF ends: the end of its section header table
(`e_shoff + e_shentsize * e_shnum`), read with `od`. The squashfs magic `hsqs`
must be there. `unsquashfs -l -o OFFSET` lists the image's root, and
`unsquashfs -follow -o OFFSET` extracts the root `.desktop` (often a symlink into
`usr/share/applications`) and the icon the entry names (`NAME.png`, `NAME.svg`,
else `.DirIcon`).

Nothing from the file is trusted:

- An extracted file must resolve inside the scratch directory: a symlink in the
  image that leads to a host file is refused (tested with one that points at a
  file outside).
- The entry is at most 64 KiB and the icon 2 MiB; an icon must be a PNG (by its
  magic) or an SVG.
- Only these keys are kept, without control characters and at most 256
  characters: `Name`, `Comment`, `Categories`, `Terminal`, `StartupWMClass`, and
  the first `%f`, `%F`, `%u` or `%U` of `Exec`. `Exec` itself is rewritten to the
  file in `~/Applications`, quoted by the desktop entry rules. `MimeType` is not
  kept: an AppImage does not register handlers through lyona.

Only `open` runs the AppImage, and only after integrating it, detached with
`setsid`.

## The rules

- **Open:** move the file to `~/Applications` (a different file of the same name
  is kept beside it, `-2`), `chmod u+x`, write
  `~/.local/share/applications/lyona-appimage-SLUG.desktop` and the icon under
  `~/.local/share/lyona/appimage-icons/`, refresh the desktop database, notify
  "Added NAME to the launcher" once, start it.
- **Open again**, or an identical copy downloaded again: nothing added, it starts.
- **No entry or icon inside:** named after the file, the generic
  `application-x-executable` icon.
- **Remove NAME:** by launcher name (any case), file name or path. Removes only
  what it added: the file if it is in `~/Applications`, the icon if it is in its
  icon directory, and the entry. A name two AppImages share is refused, listing
  their file names (found with two real `appimagetool` builds, both named
  "appimagetool").
- **Not an AppImage it can read** (not ELF, no squashfs after the ELF, or type
  1): refused, said on stderr and as a notification, nothing moved.

## Decisions

- **Default handler only when none is set:** an existing Gear Lever, or a
  handler the user chose, stays. Set after `seed-default-apps.sh`, which only
  writes to an account with no MIME preferences yet.
- **An installed Gear Lever is never removed.** Without `--with-gearlever`, only
  a pending first-login marker an earlier install left is cleared.
- **The first-login path stays** for `--with-gearlever` in an image install
  (Flatpak cannot install for the user in the installer's chroot).
- **Not in scope:** updates of AppImages (Gear Lever's), an AppImage catalogue,
  type-1 AppImages.

## Validation

- `tests/test-lyona-appimage.sh` (fixtures built in the test), the updated
  `tests/test-install-gearlever.sh`, `tests/test-gearlever-first-login.sh`,
  `tests/test-seed-default-apps.sh`, `tests/test-install-step-timing.sh`.
- Real AppImages and a VM: `docs/evidence/260-appimages.md`.
