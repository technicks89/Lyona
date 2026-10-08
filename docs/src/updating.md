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
and exits successfully. `unknown` with "Nothing has been published on the
CHANNEL channel yet" means the server answered but has no release there; see
[Channels](#channels). Nothing is written to disk by `check`.

`check_on_login=true` (the default) runs one check shortly after Quickshell
starts, jittered so a machine with several users logging in around the same
time does not all hit the update server at once. It never runs more than once
per session, and a `behind` result only surfaces a notification — it never
applies anything on its own.

## The panel's update icon

When updates are available, the panel shows an update icon with a count, left
of the Bluetooth icon. The count is the system packages and Flatpak apps waiting
to be updated, plus one when a new lyona release is out. Hover it for the details; click it to
open Settings -> System, where updates are run. The panel itself installs
nothing.

- **Packages are counted with `checkupdates`** (from `pacman-contrib`). It syncs
  a private copy of the package databases and never takes pacman's lock, so
  counting cannot interfere with a running `pacman`. Packages from the AUR are
  not counted.
- **Flatpak apps are counted with `flatpak remote-ls --updates`**, for the
  system and the user installation each. If one cannot be checked, Settings
  says which.
- **When it checks:**
  - a few minutes after you log in;
  - every 6 hours (choose 1, 3, 6, 12 or 24 in Settings -> System);
  - when NetworkManager reports that you are connected again;
  - when you press **Check for updates** in Settings -> System.

  One check runs at a time. After a successful check, a reconnect within 10
  minutes does not check again. The lyona release is re-checked this way only
  while `check_on_login` is `true`.
- **When it shows:** only while something can be updated, and not while an
  update is running (the progress icon shows then). Turn on "Show the panel
  icon when everything is up to date" in Settings -> System to keep it.
- **Its settings** are in `~/.config/lyona/update-indicator.conf`, private to
  you, written by `lyona-update-indicator`. Run `lyona-update-indicator check`
  to see what the panel would count.

## Updating in a terminal

Settings -> System -> **System packages and Flatpak** runs an update in your
own terminal, where you see the full plan and output and answer the tool's own
confirmation. Nothing is confirmed for you. This sits beside the PackageKit
preview further down the page (**System updates**); use whichever you prefer.
While a PackageKit update runs, **Update packages** is unavailable, so the two
never contend for the package database. lyona's own releases have their own
section, **lyona**, above.

- **Update packages** runs `yay -Syu` when `yay` is installed, so packages built
  from the AUR (such as the legacy NVIDIA drivers) update too, and
  `sudo pacman -Syu` otherwise.
- **Update Flatpak apps** runs `flatpak update --system`, then
  `flatpak update --user`. If one fails, the other still runs, and the result
  says which did not update. The system installation asks for authorization
  through Flatpak's own prompt.
- **The result** comes from the command, not from the window. Settings shows
  "Updated", "Not updated" with the exit status (declining the plan counts), or
  that the terminal closed before the update finished. The window stays open
  after the update until you press Enter. The panel count is read again when it
  closes.
- **Floating:** the terminal tiles. Turn on **Float the update terminal** to
  float it. That uses the window class `lyona-update-float`, which a new
  install's `window-rules.toml` floats. An existing file is never edited for
  you; if yours predates this, Settings shows the line to add inside its `rules`
  array:

  ```toml
  { class="lyona-update-float", isfloating=1 },
  ```

  Saving the file applies it through dwm's hot reload. Terminals other than
  Alacritty, kitty, st and xterm cannot be given the class, and always tile.

## Topgrade

A `recommended` or `full` install also has [Topgrade](https://github.com/topgrade-rs/topgrade).
Run `topgrade` in a terminal to update everything it finds in one go:
- system packages, through `yay` or `pacman`;
- Flatpak apps;
- cargo and rustup, when you have installed them;
- firmware;
- and more.

It is a separate path from Settings -> System:
- **Settings** previews package updates through PackageKit, or runs them in a
  terminal, and keeps the panel's update count current.
- **Topgrade** goes further than packages, with its own prompts. It does not
  update lyona itself out of the box; use `lyona-update` or Settings for that,
  or add it to Topgrade yourself (below).

The installed Topgrade is the AUR's `topgrade-bin` package, so `pacman -Syu`
does not upgrade it. Topgrade updates it itself, through `yay`, each time it
runs, as it does every other AUR package. To reinstall it, run
`install-topgrade --force`.

### Adding lyona to Topgrade

Topgrade runs your own commands as steps of its run, from the `[commands]`
section of its configuration file. lyona doesn't add one for you, because the
file is yours. To have `topgrade` update lyona too:

1. Open Topgrade's configuration. This creates it, at
   `~/.config/topgrade.toml`, the first time:

   ```sh
   topgrade --edit-config
   ```

2. Find the `[commands]` section (it is there, commented out), and add a line
   under it:

   ```toml
   [commands]
   "lyona" = 'if [ "$(lyona-update check --json | jq -r .state)" = behind ]; then lyona-update apply; fi'
   ```

   Use single quotes around the command, as above: it holds double quotes of
   its own.

3. Run `topgrade`. Its summary at the end lists **lyona** as a step of its
   own.

**What the command does.** `lyona-update apply` installs the newest release
every time it runs, even one you already have. So the command first asks
`lyona-update check` (see [Checking for updates](#checking-for-updates)) and
applies only when your install is `behind`:

| `check` says | The step |
| --- | --- |
| `behind` | runs `lyona-update apply`: the same update as in a terminal, with its backup and checks |
| `current` | does nothing |
| `offline` | does nothing; the next run tries again |
| `ahead`, `downgrade-offered` or `unknown` | does nothing; nothing older is ever installed from Topgrade |

**What to expect while it runs:**
- **Confirmation:** `apply` asks before it installs, in Topgrade's terminal.
  To skip that question, change `lyona-update apply` to
  `lyona-update apply --yes`.
- **Authorization:** installing the system files needs root. In a desktop
  session that is a polkit prompt; otherwise `sudo` asks for your password.
- **Your channel:** it follows the channel you chose (see [Channels](#channels)).
  On `preview`, Topgrade installs pre-releases too.
- **A failed update** shows as a failed step in Topgrade's summary, and leaves
  your install as it was, as described in
  [Applying an update](#applying-an-update).

**Your shell:** Topgrade runs the command with your login shell. The line
above works in bash and zsh. With fish, use this instead:

```toml
"lyona" = 'if test (lyona-update check --json | jq -r .state) = behind; lyona-update apply; end'
```

**To run only this step,** use `topgrade --only custom_commands`. This runs
every command in your `[commands]` section. **To stop** Topgrade updating
lyona, delete the line.

## Applying an update

```sh
lyona-update apply --version 2026.09.0
```

Nine steps, in this exact order, so an interruption at any point is always
recoverable:

1. Download the release tarball to `$XDG_STATE_HOME/lyona/updates/`.
2. Verify its SHA-256 against the published release digest, and its
   signature with `cosign`, **before** unpacking it.
3. Unpack it, and copy your `config.h` into the build: `~/.config/lyona/config.h`,
   or a checkout's `config.h` when run from one (see Configuration).
4. Build it, unprivileged, so a compile failure costs you nothing but time.
5. Back up the live install.
6. Install the system files through one confirmed privileged step
   (`lyona-update-root`, authenticated through polkit), then install the
   user-level files. The privileged step does not trust the unprivileged build:
   it makes its own root-owned copy of the tarball (read with your permissions),
   checks the digest and the signature again on that copy, against lyona's
   release workflow (fixed in the helper, not taken from the caller), then
   unpacks and rebuilds only that copy before backing up the system files and
   installing.

**What the checks prove.** The SHA-256 digest comes from the release page (or a
short-lived cache in `~/.cache/lyona/`), so a match proves the download is
intact. The signature proves it is genuine: from `2026.10.0-beta.2` on, each
release is signed by lyona's own release workflow on GitHub (decision D-31),
and `lyona-update` refuses one whose signature is missing or does not verify.
It needs `cosign`, which the install provides, and the network, for Sigstore's
trust root. The privileged step checks the signature again itself, so its
usual prompt ("Authentication is required to install a lyona system update")
only ever installs a signed release. A release from before signing, or an
offline file you vouch for with `--sha256`, is installed on its digest alone,
says so, and asks through a different prompt: "...install a lyona update whose
signature was NOT verified". Approve either only for an update you started, and
that one only for a file you checked yourself.
7. Verify every installed file matches what was staged.
8. Rewrite the provenance record (`/etc/lyona-release`,
   `$XDG_STATE_HOME/lyona/install.state`) — last, and only after step 7
   succeeds, so an interrupted update never claims success.
9. Restart Quickshell when it is safe to; report if dwm itself also needs a
   session restart.

Declining the privileged-step confirmation, or a build failure, leaves the
live install completely untouched and exits non-zero — never a half-applied
system.

Before it builds, an apply checks the packages the new release needs, from the
release's own package list. If one it requires is missing, it stops, changes
nothing, and prints the command to install it, for example
`sudo pacman -S --needed xdotool`. Run that, then update again; Settings shows the
same message. A missing desktop package (Picom, light-locker, ...) is only a
warning: the features that use it stay unavailable.

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
- `--file PATH` — install an already-downloaded tarball; still requires
  `--version`, and still verifies the checksum and the signature, which it
  downloads. Give the signature you downloaded with the tarball with
  `--bundle FILE` (the release's `lyona-<version>.sigstore.json`); it is
  needed for a version that is not the newest on your channel. Checking a
  signature still needs the network, for Sigstore's trust root.

  `--sha256 HASH` gives the checksum yourself: `HASH` is the 64-character
  hexadecimal value on the tarball's line in the release's
  `lyona-<version>-SHA256SUMS` (the first field). With `--bundle` too, both
  are checked. Given alone, for a machine with no network, the signature is
  not checked: you vouch for the file, and the install asks through the
  "NOT verified" prompt.

  ```sh
  lyona-update apply --file ~/lyona-2026.10.0.tar.gz --version 2026.10.0 \
      --sha256 HASH
  ```
- `--from-checkout DIR` — **removed.** The privileged step installs only
  releases it has verified itself. To install a local development checkout, run
  `sudo make install-system && make install-user` in it, or
  `scripts/dev-sync-install.sh`, where you type the command that runs as root.
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
except by `set-channel` itself. Settings -> System sets it too, under
**Channel**.

While lyona is in beta, every release is a pre-release, so the `stable`
channel has nothing to offer yet. A pre-release install (a version such as
`2026.10.0-beta.1`) is seeded on `preview` for that reason; one already on
`stable` gets `unknown` and "Nothing has been published on the stable channel
yet", with the command to switch:

```sh
lyona-update set-channel preview
```

`offline`, by contrast, means the release server could not be reached at all.

## Rolling back

```sh
lyona-update rollback --list
lyona-update rollback                          # the newest backup
lyona-update rollback --backup 20260828T153709Z-1472673
```

Every `apply` backs up the live install first, before writing anything, so
`rollback` always has something to restore to. A backup has two halves under the
same id: your own files (the managed Quickshell config, and in backups taken
before the S12-13 change the Lyona data directory) in
`~/.local/state/lyona/live-update-backups/<id>/`, and the system
files, which the privileged helper copies as root, just before installing, into
`/var/lib/lyona/backups/<id>/`, readable only by root. A rollback restores the
system files from that root-only copy and never from anything in your home
directory, so nothing another program running as you could have changed is ever
installed as root. The helper keeps the newest 5 system backups. Your own files
are restored whole: the backed-up Quickshell config, and the data directory when
the backup holds one, replace the current ones, so nothing a newer version added
is left behind. An older backup's data directory still holds that version's
session scripts and defaults, which the restored version needs; the next update
removes them again.

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
