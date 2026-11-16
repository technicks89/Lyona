# ARM5-02: updates on aarch64

ARM Sprint 5 item ARM5-02 (Lyona-ARM issue #19, then Lyona #490). Run
2026-11-15, from `v2026.11.0-beta.1` (db24732) to `v2026.11.0-beta.2`
(ecc0f48), the first two releases that carry the aarch64 images. The
maintainer ran each step at the machine; the checks were made over SSH.

**Acceptance** (an update and a rollback pass on both targets): **met**, with
the generic image on hardware instead of a VM (see "Not tested").

## The targets

| | Generic image | Raspberry Pi image |
| --- | --- | --- |
| Machine | Dell XPS 13 9345 (Snapdragon X Elite), the ARM6-06 machine ([evidence](arm6-06-xps13-9345.md)) | Raspberry Pi 4 |
| Address | 10.0.1.154 | 10.0.1.213 |
| Kernel | `7.3.4-1-aarch64-ARCH` | `6.18.62-1-rpi` |
| Installed from | the beta.1 generic image | the beta.1 Pi image |
| Channel | `preview` (`/etc/lyona/update.conf`; `check_on_login=true`, `auto_apply=false`, `keep_backups=5`) | same |
| Quickshell | 0.3.2-1 | 0.3.2-1 |

## The run

Times are EST (UTC−5) as each machine logged them; backup IDs are UTC.

| Step | XPS 13 (.154) | Pi 4 (.213) |
| --- | --- | --- |
| 1. `check` on beta.1 | beta.2 offered (`state behind`) | same |
| 2. `apply` to beta.2 | 19:15:07, from Settings > System; backup `20261116T001440Z-9156` (beta.1) | 19:16:57, from a terminal; backup `20261116T001603Z-16971` (beta.1) |
| 3. After a reboot | beta.2 @ ecc0f48, `state current`; dwm, Quickshell, light-locker, picom running; no failed unit | same, without picom (the Pi's session runs none, before and after) |
| 4. `rollback --yes` | 19:23:17 (`restore-system 20261116T001440Z-9156` through pkexec), "Rollback complete / succeeded" | 19:24:19 (`restore-system 20261116T001603Z-16971`), same |
| 5. Log out and in | beta.1 @ db24732, `state behind`; session started 19:25:42, all four processes running, locker inactive | session started 19:32:55 (after the package updates below, which needed a second login), dwm, Quickshell and light-locker running |
| 6. `apply --yes` again | 00:29Z; backup `20261116T002909Z-42474`; "All managed files match the checkout" | 00:35Z; backup `20261116T003437Z-7960`; same |
| 7. Log out and in | beta.2, `state current`; session 19:29:45; `dwm-blank-watch` once (main + reader, `:0` lock) | beta.2, `state current`; session 19:35:56; `dwm-blank-watch` once (main + reader, `:0` lock) |

What the rollback did, on both:

- It removed the seven files beta.2 added: `dwm-layout-settings`,
  `dwm-clipboard-history`, `dwm-blank-watch`, `dwm-settings-fingerprint`,
  `libexec/lyona/dwm-settings-fingerprint-root`,
  `libexec/lyona/lyona-fingerprint-pam` and
  `com.lyona.fingerprint.policy`.
- The beta.1 `dwm` differs from beta.2's, so the rollback (and each apply)
  left Quickshell running and printed
  `SESSION RESTART REQUIRED: log out and back in to activate /usr/local/bin/dwm`,
  as `runtime_verify` is meant to. No reboot was needed; a logout was.

## The release notes' rollback caveats

- **Fingerprint PAM lines** (XPS 13, which had fingerprint on for polkit and
  `sudo`): after the rollback, the `# lyona-fingerprint` marker and the
  `-auth sufficient pam_fprintd.so timeout=10 max-tries=3` line stayed in
  `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1`, as the notes say. They are
  harmless on beta.1 (`pam_fprintd.so` is still installed, and `-auth` skips a
  missing module), but beta.1 has no Settings > Fingerprint to remove them.
  After the update back, `dwm-settings-fingerprint status` showed the reader
  available and polkit and `sudo` still on. The Pi has no reader, and no PAM
  file changed.
- **`panel-widgets.conf` 1.1**: neither machine has
  `~/.config/lyona/panel-widgets.conf`, so this caveat was not exercised.

## Package updates

| | XPS 13 (.154) | Pi 4 (.213) |
| --- | --- | --- |
| `pacman -Syu` | 19:16:58 (openssh, qt6-base 6.12.0-5, sdl3, udisks2, …), run by Topgrade | 19:23:57–19:27:19 (qt6-base 6.12.0-5, …), run by Topgrade |
| Topgrade | 19:16–19:18: `pacman -Syu`, then the AUR (`topgrade-bin` 17.16.0-1, `yay-bin` 13.1.0-1) | 19:22–19:31: `pacman -Syu` through `sudo`, then the AUR (`topgrade-bin`, `yay-bin`), then `flatpak update --system` |
| Settings > System updates pane | opened after Topgrade; its check ran and found everything current (the maintainer's report) | same |

Both against Arch Linux ARM's repositories; Topgrade is the one ARM1-03 kept.
Topgrade (which the maintainer uses for updates) had already run on both, so
the pane had nothing to install. Opening the pane only checks; that leaves no record in the journal or
`pacman.log`, so the pane rows rest on the maintainer's report. No update was
installed from the pane: neither journal has its pkexec `pacman -Syu --needed`.

## Found on the way

- **The Pi's rollback ran during a package upgrade.** The rollback at 19:24:19
  fell inside Topgrade's `pacman -Syu` (19:23:57 to 19:27:19, which replaced
  `qt6-base`). It succeeded and the beta.1 session started normally once
  pacman had finished, but it is a weaker data point than the XPS 13's
  rollback, which ran on an idle system (added 2026-11-15, #519).

- **A login during `pacman -Syu` starts no Quickshell (Pi).** The maintainer
  logged in at 19:26:44 while pacman was replacing `qt6-base` (upgraded
  19:26:49). `dwm-quickshell-version-check` got no output from
  `quickshell --version` and the session logged
  `unable to determine the Quickshell version` and
  `lyona: compatible Quickshell 0.3.0 or newer is required`; dwm and the locker
  ran, Quickshell did not. Logging in again after pacman finished started it.
  Not a release defect: Qt was half-replaced. Not filed.
- **`jq: parse error: Invalid numeric literal at line 1, column 3`** in
  `~/.xsession-errors` at every login, on both machines and both releases.
  Before Quickshell is running, `quickshell list --path … --json` prints the
  plain text `No running instances for "…"` rather than JSON, and
  `quickshell_instance_pids` (`scripts/dwm-quickshell-lifecycle.sh`) pipes it
  to jq. Reproduced on the Pi with a config path that has no instance. Only
  noise: the function finds no PID either way. Not filed yet.

## Not tested

- **A VM.** The plan names the generic image's VM; the generic image was run
  on the XPS 13 instead, on hardware. No QEMU/KVM, UTM or libvirt guest was
  updated.
- An install from the Settings > System updates pane (it was opened and
  checked on both, and found nothing to install after Topgrade).
- The `panel-widgets.conf` 1.1 caveat (no such file on either machine).
- A rollback with `--backup` naming an older backup, and `lyona-update` from a
  bare TTY (each rollback and apply was run in the desktop session).
- Any other Pi model than the Pi 4.
