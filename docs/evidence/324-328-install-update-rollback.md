# #324 to #328: update, rollback and image install hardening, validated

Branch `install-update-rollback-324-328` at `e7055d5` (the CodeRabbit
follow-ups included), and the two fixes the VM run found (below).

## Suite

Each of the 152 steps of `make check` was run on its own through
`scripts/run-tests`, before the CodeRabbit follow-ups. Three steps failed
because their checks still expected the old code, not because of a fault:
`check-topgrade-install` (a second `sudo -k` in `install.sh`),
`check-aur-policy` (a logged `sudo -k` read as a `sudo pacman`) and
`check-live-medium-cleanup` (the old clean-up line). They were updated and
pass. The CodeRabbit follow-ups and the VM fixes were each tested with the
checks they touch. The root helper's tests ran as root in an
`archlinux:base-devel` container, which also checked the Makefile's legacy
removal as root: refused under a directory another user owns, done once that
directory is root's.

The suite was run again after the VM fixes (`8952fd8`): 150 of 152 passed,
none skipped, no process left behind. The two failures were real, and are
fixed: the rollback replaced `install.state` with a bare `mv -f`
(`check-shell-contracts` asks for `mv -fT`, so a directory there cannot take
it), and `check-install-summary` still looked for the yay `--noconfirm` line in
its form before the `sudo -n` change. Both checks pass.

## The VM (2026-10-10)

| | |
| --- | --- |
| Image | `lyona-2026.10.0-beta.6-x86_64.iso` built from `e7055d5` (archiso 91), SHA-256 `2f37c9e98b26dc676b69275b2b9bc3cb7fd73fba050723208ea05798f567de48` |
| VM | QEMU with KVM, q35, 4 GB, 4 CPUs (host AMD Ryzen 5 3600, x86-64-v3), OVMF (UEFI), `-vga std` 1280x800, virtio disk 40 GB, no NVIDIA |
| Install | the image wizard (us, btrfs, no encryption, America/New_York, US mirrors) |

### The image install (#328)

- **The timezone:** the wizard asks "Detect your timezone online? This sends
  your IP address to ipinfo.io or ipapi.co." before any lookup. No opened the
  list (New York chosen from it); Yes, through "Change an answer...", detected
  America/New_York and asked to confirm it.
- **The passwordless sudo rule:** after the install, neither
  `/etc/sudoers.d/90-lyona-install` nor its boot-time removal entry
  (`/etc/tmpfiles.d/lyona-install-sudoers.conf`) is left, and `sudo` asks for
  the password.
- **yay:** built and installed by the postinstall's own step (yay 13.0.1),
  before the passwordless rule.
- **CachyOS:** the live medium added only the baseline repository; the new
  system then moved to its level (`raise-level`): `[cachyos-v3]`,
  `[cachyos-core-v3]` and `[cachyos-extra-v3]` are configured, with the CachyOS
  pacman.
- **The layout record:** `/etc/lyona-release` names `PREFIX=/usr/local`,
  `MANPREFIX`, `DATADIR=/usr/share` and `XSESSIONSDIR`.

Install time, the steps the installer times, against the same VM installed from
the image before this branch (2026-10-09):

| Step | Before | Now |
| --- | --- | --- |
| Mirrors, CachyOS on the medium, archinstall | 1m 12s | 1m 11s |
| postinstall: CachyOS repositories | 1s | 38s |
| postinstall: yay | (in install.sh) | 12s |
| postinstall: install.sh | 56s | 48s |
| postinstall: the other steps | 21s | 18s |
| **Total** | **2m 30s** | **3m 07s** |

The 37 seconds are `raise-level`: its upgrade downloads again, as v3 builds,
the 184 base packages archinstall had just installed (337 MiB). A
baseline-level CPU skips it. yay's step is mostly moved time: its `base-devel`
and `git` came in `install.sh`'s package step before.

Kept as it is (decided with the maintainer, 2026-10-10): the 37 seconds are not
worth a live-medium partial upgrade to avoid.

### Updates and rollback (#324 to #327)

An update in the VM is a `make release` of the branch as `2026.10.0-beta.7`,
with a marker line added to `dwm-paths.sh` (installed in `PREFIX/lib/lyona`),
installed with `lyona-update apply --file`.

- **Update:** beta.7 installed; the marker is in `/usr/local/lib/lyona`. The
  system backup's manifest lists `lib/lyona`, `share/lyona`, the polkit actions
  and the 15 GTK themes. The download and build area was emptied after success.
- **Rollback:** a file added to `lib/lyona` after the update, then
  `lyona-update rollback`: beta.6 back, the marker and the added file gone, no
  `.lyona-restore-old` copy left; the status file says `operation rollback`.
- **An unverified downgrade:** a beta.6 tarball with `--sha256` while beta.7
  was installed was refused before any build or backup ("an older release is
  installed only with its signature checked"), and beta.7 stayed.
- **A signed downgrade:** Settings offered "Update to 2026.10.0-beta.5" (the
  preview channel's newest is older). The release was downloaded from GitHub,
  its signature verified, and the prompt was the new action, "install an OLDER
  lyona release"; approved, beta.5 installed, all three records agreeing.
- **config.h (#327):** a `config.h` including a file only the user can read
  built on the user's side, and failed in the root helper's build ("Permission
  denied"), which now runs as `nobody`; nothing was installed.
- **A cancelled prompt (#326):** an update started in the session (no
  terminal), its polkit prompt cancelled: `lyona-update` exited 4, the status
  file says `cancelled`, the popup says "Update cancelled: authorization was
  not given. Nothing was changed.", and Settings > System shows that line under
  "Update to". A successful rollback stays shown there while an update is
  available ("Rollback complete").

### Found and fixed in the VM

- **"Rolling back Lyona" over an update:** an update started after a rollback
  was titled as a rollback while it ran: the model took the operation only from
  a finished status. It now takes it from a running one too.
  `tests/qml/UpdateProgress.inc` covers it (it fails without the fix).
- **"Installed records disagree" after a rollback:** the rollback restored the
  system files and the user trees, not the account's install record
  (`install.state`), which the update had rewritten, so Settings called the
  rolled-back install damaged. The live backup keeps it now, and the rollback
  puts it back. In the VM, with both changes installed: an update and a
  rollback leave the records agreeing on beta.6.

### Seen, not changed here

- **A failed install's status reads "(authentication required)":** the
  outcome repeats the phase text, "Installing V (authentication required)
  (exit 1)", whatever failed (here the `config.h` build). It predates this
  branch (Phase 003).
- **A refused update leaves its download:** the area is emptied only after a
  successful update; the refused unverified downgrade left its staging
  directory and tarball (about 6 MB) until the next update.
- **A Quickshell crash on one restart:** Quickshell 0.3.2 (Qt 6.12) crashed once
  while shutting down for a restart (a segmentation fault in
  `QXcbWindow::hide()` during teardown); its crash dialog took the next
  keystrokes. Six more restarts, with and without the update popup showing, did
  not crash.

## Not tested

- Real hardware, a GPU-accelerated X server, an NVIDIA GPU, legacy BIOS, LUKS.
- A baseline-level CPU (where `raise-level` does nothing) and a v4 or Zen 4 CPU.
- A `PREFIX` other than `/usr/local` in a real install (the tests cover it).
