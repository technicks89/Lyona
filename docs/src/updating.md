# Updating and Rollback

lyona updates itself in place from release tarballs, either through
Settings -> System or from a terminal with `lyona-update`. Both paths use the
same helper, so anything you can do from Settings you can also do from a
terminal — including the one thing Settings cannot help with: recovering a
machine whose desktop will not start.

## Checking for updates

```sh
lyona-update check
```

Reports the installed version, the version available on your configured
channel, and one of `current`, `behind`, `ahead`, `downgrade-offered`,
`unknown`, or `offline`. `offline` is a normal outcome, not an error: if the
update server cannot be reached, `check` still reports the installed version
and exits successfully. Nothing is written to disk by `check`.

`check_on_login=true` (the default) runs one check shortly after Quickshell
starts, jittered so a machine with several users logging in around the same
time does not all hit the update server at once. It never runs more than once
per session, and a `behind` result only surfaces a notification — it never
applies anything on its own.

## Applying an update

```sh
lyona-update apply --version 2026.09.0
```

Nine steps, in this exact order, so an interruption at any point is always
recoverable:

1. Download the release tarball to `$XDG_STATE_HOME/lyona/updates/`.
2. Verify its SHA-256 against the published release digest **before**
   unpacking it.
3. Unpack it, and copy your `config.h` into the build: `~/.config/lyona/config.h`,
   or a checkout's `config.h` when run from one (see Configuration).
4. Build it, unprivileged, so a compile failure costs you nothing but time.
5. Back up the live install.
6. Install the system files through one confirmed privileged step
   (`lyona-update-root`, authenticated through polkit), then install the
   user-level files. The privileged step does not trust the unprivileged build:
   it makes its own root-owned copy of the tarball (read with your permissions),
   checks the digest again on that copy, then unpacks and rebuilds only that copy
   before backing up the system files and installing.

**What the digest proves.** The SHA-256 digest comes from the release page (or a
short-lived cache in `~/.cache/lyona/`), fetched by the unprivileged side, so a
match proves the download is intact, not that the release is genuine. Releases
are not signed yet (decision D-14), so the administrator password prompt in step
6 is the real boundary: approve it only for an update you started.
7. Verify every installed file matches what was staged.
8. Rewrite the provenance record (`/etc/lyona-release`,
   `$XDG_STATE_HOME/lyona/install.state`) — last, and only after step 7
   succeeds, so an interrupted update never claims success.
9. Restart Quickshell when it is safe to; report if dwm itself also needs a
   session restart.

Declining the privileged-step confirmation, or a build failure, leaves the
live install completely untouched and exits non-zero — never a half-applied
system.

### Watching an update

An apply takes a few minutes and restarts Quickshell part way through, so the
progress is shown outside Settings and survives that restart:

- A **progress popup** appears under the panel while an update runs, showing
  the current step (downloading, verifying, building, installing, restarting).
  **Hide** tucks it away without stopping anything.
- A **panel indicator** appears next to the battery while an update runs and
  stays after it ends until you dismiss it; a successful update dismisses
  itself after 20 seconds, a failed one never does. Click it to bring the popup
  back. When the shell restarts mid-update, both reappear on their own, still
  in progress or showing how it ended. A shell that starts up more than ten
  minutes after an update ended does not show it, and neither does one left
  "in progress" for over an hour by a crash.
- A **notification** reports how an update or rollback ended. A failure is
  critical and names the log; declining the confirmation prompt is not
  treated as a failure and sends nothing.
- **View log** in the popup, or **View update log** under Settings -> System,
  shows the last 64 KiB of `$XDG_STATE_HOME/lyona/update.log`. Each apply or
  rollback starts a fresh log holding its full output (build output included),
  readable only by you; a dry run leaves the previous log alone.

The whole apply asks you to authenticate once: the installation of system files
is a single privileged step, and a step that ran and failed is never retried
through a second prompt.

Useful flags:

- `--allow-downgrade` — required to install a version older than what is
  installed.
- `--dry-run` — builds and reports exactly what would be written, without
  installing anything.
- `--file PATH` — install an already-downloaded tarball (for an offline
  machine); still requires `--version` and still verifies the checksum.
- `--from-checkout DIR` — install directly from a local development checkout
  instead of a published release. This carries the same trust level as
  running `sudo make install-system` from that checkout yourself.
- `--yes` — skip the interactive confirmation prompt (Settings always passes
  this, since it shows its own confirmation first).

## Channels

```sh
lyona-update set-channel stable   # or: preview
```

`stable` tracks GitHub's Latest release. `preview` tracks the newest
published release including pre-releases, which are not release-qualified —
see [Releasing](https://github.com/technicks89/Lyona/blob/main/docs/RELEASING.md)
for what that means in practice. The channel is stored in
`~/.config/lyona/update.conf`, seeded on first use and never overwritten
except by `set-channel` itself.

## Rolling back

```sh
lyona-update rollback --list
lyona-update rollback                          # the newest backup
lyona-update rollback --backup 20260828T153709Z-1472673
```

Every `apply` backs up the live install first, before writing anything, so
`rollback` always has something to restore to. A backup has two halves under the
same id: your own files (the managed Quickshell config and the Lyona data
directory) in `~/.local/state/lyona/live-update-backups/<id>/`, and the system
files, which the privileged helper copies as root, just before installing, into
`/var/lib/lyona/backups/<id>/`, readable only by root. A rollback restores the
system files from that root-only copy and never from anything in your home
directory, so nothing another program running as you could have changed is ever
installed as root. The helper keeps the newest 5 system backups.

It refuses to restore a backup whose checksums do not match, or one taken against
a different install environment (prefix, config, or data directory) than the one
it would be restored into — it will not guess. A backup taken before system
backups moved to `/var/lib/lyona/backups` has no system half, and `rollback`
refuses it rather than restore only your own files.

## Rolling back from a TTY when the desktop will not start

**This is the case that matters most, and it is why `rollback` is built the
way it is.** If an update leaves you without a working session, you are at a
text console, not a desktop — so `rollback` does not depend on Quickshell,
D-Bus, or a running polkit agent. It authenticates with `sudo` directly when
no graphical polkit agent is reachable.

1. Log in at the TTY (<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F2</kbd> through
   <kbd>F6</kbd> if X is stuck on the active console).
2. List what is available to restore:

   ```sh
   lyona-update rollback --list
   ```

3. Restore the newest backup (or name one from the list):

   ```sh
   lyona-update rollback
   ```

4. When it finishes, start the session again:

   ```sh
   startx
   ```

   or log in normally if you use a display manager.

If `rollback` itself reports a checksum or environment mismatch, do not
force past it — that check exists specifically to stop a restore from making
things worse. Open an issue with the exact message instead.
