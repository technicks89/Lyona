# #260: AppImages without the GNOME runtime

Issue `#260`. First merged from branch `appimage-handler` (PR #264, commits
`f36c557` "Appimage handler" and `af76db7` "CR Updates"); the follow-up from
the 2026-10-08 review is on `appimage-first-open` (see "Follow-up" below).
Written with the change; the code is in the diff, and this records the design
and the decisions behind it.

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

- **Open, the first time:** ask (see "Follow-up"), then move the file to `~/Applications` (a different file of the same name
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

## Follow-up: ask on the first open (2026-10-08 review)

The review found that one "Open" from a browser's download panel, a chat
attachment or Thunar ran a downloaded program with no question: the missing
exec bit, or Gear Lever's window, had been that question. Decision: ask on the
first open.

- **The question:** "Run NAME?" with **Add and run**, **Add only** and
  **Cancel**, the download host when the browser recorded it
  (`user.xdg.origin.url`, host only), the size, and "Only run programs you
  trust" first, since a notification shows three lines. In a terminal it asks
  there. Otherwise it is a critical notification (so Do Not Disturb does not
  hide a question the user just caused) with those buttons, through
  `notify-send -A`; closing it is Cancel. With no notification server that has
  buttons (no `actions` capability), it is added but never run.
- **The shell:** lyona's notification server did not support actions. It now
  does: up to three buttons (`NotificationActions.js`, never the `default`
  action), no timeout while a question is open, and the history keeps only
  the text. Other programs' actions get buttons too.
- **Cancel** leaves the file where it was, not executable; nothing is written.

Fixed with it, from the review and the #260 comment:

| Finding | Fix |
| --- | --- |
| Newline in the name wrote extra entry lines | Names with a control character or a backslash are refused ("rename it") |
| `Exec` escaped one level short | `exec_quote` matches `webapp-create`'s `desktop_exec_arg`: quote, then double every backslash |
| `My_App` and `My-App` shared an entry | `entry_id` adds `-2`, `-3` when another AppImage has the id; ids are at most 64 characters |
| Own `X-Lyona-AppImage` cut at 256 characters | Read back raw (`raw_key`); only values from inside an AppImage are cleaned |
| Double click raced two opens | `flock` on `$XDG_STATE_HOME/lyona/appimage.lock` around open and remove |
| Extraction unbounded | Root directories are never extracted, at most 8 candidates, `ulimit -f` per file, 20 s each, scratch under `$XDG_CACHE_HOME/lyona` |
| Icon removal by text prefix | Resolved directory compared |
| UTF-8 cut in half | `clean` truncates by character |
| Silent failure to start | Watched for 2 s; a failure is said, with the `fuse2` hint when `libfuse.so.2` is missing |
| `remove` deleted the only copy silently | To the trash (`gio trash`), and says what it did |
| `xdg-mime query` missed a user Gear Lever | `install.sh` reads the user's `mimeapps.list` first |
| Tests hidden under the Gear Lever target | `check-lyona-appimage`; a skip fails in CI |

## Validation

- `tests/test-lyona-appimage.sh` (fixtures built in the test; with the
  follow-up: each answer, no buttons, the terminal question, collisions, long
  paths, refused names, a `.desktop` directory, a failed start, remove),
  `tests/test-appimage-handler.sh`, `tests/qml/tst_notification_actions.qml`,
  `tests/test-quickshell-notifications.sh`, the updated
  `tests/test-install-gearlever.sh`, `tests/test-gearlever-first-login.sh`,
  `tests/test-seed-default-apps.sh`, `tests/test-install-step-timing.sh`.
- Real AppImages and a VM: `docs/evidence/260-appimages.md`.
