# Sync Sprint 15 -- Update discovery in the panel, and the login keyring

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). From a review (2026-10-02) of
two upstream pull requests in `ChrisTitusTech/dwm-titus`:

- **`#365`** "fix: require GNOME Keyring PAM and repair missing dependencies"
  (open, +240/-26).
- **`#363`** "feat: integrate dwm-update-center" (merged 2026-10-01,
  +9176/-98, 37 commits).

**Status:** started 2026-10-02; S15-01 on branch `s15-01-keyring`; D-24 to
D-26 decided 2026-10-02. GitHub: milestone "Sync Sprint 15 - Update discovery
and the login keyring", issues `#214` to `#218`.

| Item | Issue | Kind | Gate |
| --- | --- | --- | --- |
| [S15-01](#s15-01-the-login-keyring-is-required-and-diagnosed) | `#214` | Fix | none (D-24 decided) |
| [S15-02](#s15-02-an-updates-available-indicator-in-the-panel) | `#215` | Feature | none (D-25 decided) |
| [S15-03](#s15-03-flatpak-updates) | `#216` | Feature | S15-02 |
| [S15-04](#s15-04-system-updates-in-a-terminal) | `#217` | Feature | none (D-26 decided) |
| [S15-05](#s15-05-validate-in-a-live-session) | `#218` | Validation | S15-01 to S15-04, live session |

---

## Review result

### `#365`: not done in Lyona; applies, adapted to Arch

What upstream fixes: `gnome-keyring` and `gnome-keyring-pam` were optional
(`desktop-optional`). A password login could leave the login keyring locked,
nothing reported it, and updates never installed the pair.

Lyona has the same gap:

- **The dependency map:** `gnome-keyring` is only in `arch:desktop-optional`
  (`scripts/dwm-packages.sh`). Only the `full` profile installs it, which the
  live medium uses (`lyona-postinstall.sh` runs `install.sh --profile full`).
  An existing-system install with the `recommended` or `minimal` profile goes
  without it.
- **Diagnostics:** `dwm-diagnostics` checks no keyring package. System Health
  reads its rows (`dwm-system-health` runs `dwm-diagnostics --format
  health-tsv`), so it shows nothing either.
- **Updates:** `lyona-update`'s `check_release_packages` checks only `build`,
  `x11`, `runtime-required` and `desktop`. A missing keyring is never mentioned.

What differs on Arch:

- **No separate PAM package.** `pam_gnome_keyring.so` ships inside
  `gnome-keyring` (`/usr/lib/security/pam_gnome_keyring.so`). Upstream's pair is
  one package here.
- **LightDM's PAM stack already loads it.** Arch's `lightdm` package ships
  `/etc/pam.d/lightdm` with `-auth optional pam_gnome_keyring.so` and
  `-session optional pam_gnome_keyring.so auto_start`. The leading `-` makes
  both lines no-ops while the module is missing. So installing the package is
  enough; no PAM file needs changing. (Checked on lightdm 1:1.33.1-1.1.)
- **`startx` has no display-manager PAM stack.** `/etc/pam.d/login` on Arch does
  not load the module. A `startx` session keeps the keyring locked until the
  first application asks for it. That is documented, not changed: editing
  `/etc/pam.d/login` is security policy the installer must not alter silently
  (AGENTS.md).
- **Updates never install packages.** Upstream's `dev-sync-install.sh` installs
  the pair with `dnf`. Lyona's `lyona-update` refuses an update that needs a
  missing required package and prints the `pacman -S` line (S12-11, decided
  with the maintainer). It warns, and does not refuse, for a missing `desktop`
  package. D-24 put the keyring in `desktop`, so an update warns.

N/A: the Fedora RPM checks and the `dnf` repair in `dev-sync-install.sh`; the
three X11 fixture edits, which copy the map for a `dwm-diagnostics` that sources
it. Lyona's fixtures stage helpers with `stage_helpers`, which S15-01 extends
only if `dwm-diagnostics` starts sourcing the map.

### `#363`: mostly done or declined; four ideas apply

D-8 (2026-09-16) declined upstream's git-`main` desktop updater (`#318` to
`#323`). It ported four UX ideas onto `lyona-update` and `UpdateModel.qml`
instead. `#363` builds an Update Center on top of that declined updater.

**Already in Lyona:**

| `#363` | Lyona |
| --- | --- |
| Desktop updates with a progress window that survives a shell restart | `lyona-update` (verified release tarballs), `config/quickshell/system/UpdateProgressWindow.qml` (D-8) |
| Panel indicator while an update runs | `updatePill` in `config/quickshell/panel/DwmPanel.qml`, shown while `lyona-update` runs and briefly after (D-8) |
| Bounded log viewer, completion notification | `UpdateLogView.qml`, `UpdateModel.qml` (D-8) |
| System package update discovery | Settings > System, `SystemUpdateDiscovery.qml` and `SystemUpdateControls.qml`, through PackageKit's alpm backend, with a preview and confirmation (Sprint 1) |
| Interrupted or unprovable results stay unknown, never claimed as success | `SystemUpdateControls.qml` ("Verifying the update result..."), the `lyona-update` status file |

**Declined, N/A on Arch or under D-8:**

- Fedora: the DNF5 provider, the PackageKit-to-DNF handoff and its legacy
  recovery, the Fedora 44 podman runner (`scripts/run-tests-podman`,
  `tests/containers/fedora-44/`).
- mise: Lyona does not install or manage mise.
- The git-`main` desktop worker's authorization reuse (sudo probe, polkit
  fallback), recovery reattach, and `dwm-desktop-update`/`-root` changes. These
  are the mechanism D-8 declined.
- `dwm-migrate-update-center-window-rule`: it migrates rules for upstream's own
  Update Center window. S15-04 adds no terminal rule; if one is ever
  needed, it follows Lyona's own rule (a default in `config/window-rules.toml`,
  never a rewrite of the user's file without a backup).

**Not in Lyona, and applicable:**

1. **An "updates available" indicator.** Lyona's panel pill shows only while an
   update runs. Nothing tells the user that updates exist until they open
   Settings > System. Upstream adds an icon beside the clock, a popup listing
   each provider's pending updates, and a "hide when current" preference
   (S15-02).
2. **Checking on a schedule and on reconnect.** Lyona checks when Settings
   opens. Upstream checks at a configured interval (remote repositories have no
   change signal, so sampling is the documented fallback that AGENTS.md
   allows), and again when NetworkManager reports a connection (S15-02).
3. **Flatpak updates.** Lyona installs Flatpak and Flathub
   (`dwm-flatpak-setup`, Sprint 5 S5-02), but no surface lists or applies
   Flatpak updates. Upstream updates the system and user scopes separately and
   keeps evidence when only one completes (S15-03).
4. **Updates in a terminal.** Upstream found that a PackageKit update looked
   stuck while it ran in the background, and moved its package updates to the
   native tool in a terminal: the full plan, download progress, scriptlet
   output and the tool's own confirmation, with no automatic yes. The terminal
   tiles or floats by a saved preference (S15-04).

   On Arch this has a second reason: PackageKit cannot update a foreign
   package. The legacy NVIDIA drivers that Sprint 14 builds from the AUR are
   foreign packages, which `pacman -Syu` and PackageKit both leave alone. The
   user is told to run `yay`.

---

## Decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| **D-24** | Where does `gnome-keyring` go: `runtime-required` (as upstream; `lyona-update` then refuses until it is installed), `desktop` (recommended; `lyona-update` warns), or stays optional with only a diagnostic? | **Decided (2026-10-02), asked of the user directly:** `desktop`. Every recommended and full install gets it, diagnostics flag it, and an update only warns. |
| **D-25** | Where do pending updates show: a panel icon that opens a popup listing the providers (as upstream), a panel icon that opens Settings > System, or Settings only (as now)? | **Decided (2026-10-02), asked of the user directly:** a panel icon that opens Settings > System. Settings stays the one update surface. |
| **D-26** | How do system package updates run: keep PackageKit with its preview (as now), `pacman -Syu` in a terminal (as upstream), or both, with the terminal also updating foreign packages through `yay` when it is installed? | **Decided (2026-10-02), asked of the user directly:** both. PackageKit's preview stays; "Update in a terminal" is added, using `yay -Syu` when `yay` is installed. |

---

## Implemented

- **S15-01 (2026-10-02, branch `s15-01-keyring`):**
  - **The map:** `arch:keyring` (`gnome-keyring`), included by `arch:desktop`,
    and removed from `arch:desktop-optional`. `archiso/packages.x86_64` gains
    `gnome-keyring`, as the sync test requires.
  - **Diagnostics:** `check_keyring` in `scripts/dwm-diagnostics` checks each
    package with `pacman -T`. Installed is `ok`; a missing package, no `pacman`,
    or a failed query is a degraded `warn` row,
    `dependency-package-gnome-keyring`. System Health shows it through
    `health-tsv`. `dwm-diagnostics` sources the map through `$lyona_lib`, so
    `stage_helpers` stages it with no fixture change.
  - **Updates:** no change. `lyona-update`'s `desktop` check already warns.
  - **Tests:** `test-dwm-diagnostics.sh` (installed, missing, a failed query,
    both formats, through a stub `pacman`; removing the check fails it),
    `test-arch-packages.sh` (in `desktop`, out of `desktop-optional`, listed
    once in `full`), `test-quickshell-health-xvfb.sh` (the staged backend
    reports the row).
  - **Docs:** SPEC.md 5.8, `docs/src/dependencies.md`, `docs/src/install.md`,
    `CHANGELOG.md`.
  - **Not tested:** a real LightDM password login unlocking the keyring, which
    S15-05 covers.

## S15-01: The login keyring is required and diagnosed

From `#365`. Decided by D-24.

- **The map:** move `gnome-keyring` out of `arch:desktop-optional` into the
  `arch:desktop` (D-24), through a new `arch:keyring` profile that `desktop` includes
  (as upstream's `fedora:keyring`). One package; no `-pam` package exists on
  Arch.
- **The ISO list:** `archiso/packages.x86_64` stays in sync with the map
  (`tests/test-arch-iso-builder.sh` checks it). The sync covers `desktop`, so
  `gnome-keyring` joins the list.
- **Diagnostics:** `dwm-diagnostics` checks each package in `arch:keyring`
  with `pacman -T` (a machine interface; no output parsing). A missing one is a
  row named `dependency-package-gnome-keyring` with "Install gnome-keyring for
  secret storage and the keyring unlock at password login; then log out and
  back in". It is an `optional_missing` row, a warning, to match `desktop`. System Health
  shows it through the existing `health-tsv` path.
- **The map's location:** `dwm-diagnostics` finds `dwm-packages.sh` the way
  the other shared libraries are found (`${BASH_SOURCE[0]%/*}`, then
  `PREFIX/lib/lyona`; D-16). `stage_helpers` stages it for the X11 fixtures
  that run System Health.
- **Updates:** `lyona-update`'s `check_release_packages` covers it through the
  `desktop` group, which warns and does not refuse. No new code.
- **Docs:** SPEC.md (the dependency section), `docs/src/dependencies.md`,
  `docs/src/install.md` (the keyring moves out of "optional extras"),
  `CHANGELOG.md`. The `startx` note: the keyring unlocks at login only through a
  display manager whose PAM stack loads `pam_gnome_keyring`, which Arch's
  `lightdm`, `sddm` and `gdm` do.
- **Tests:** the map test (the package is in the chosen group and no longer in
  `desktop-optional`); `test-dwm-diagnostics.sh` (an installed and a missing
  keyring, through a stub `pacman`); the Health X11 fixture asserts the row.

## S15-02: An updates-available indicator in the panel

From `#363`. Decided by D-25.

- **What it shows:** a count per provider: system packages (the existing
  read-only discovery), the Lyona release (`lyona-update check`), and Flatpak
  (S15-03). It is hidden when everything is current, unless the user turns on
  "show when current".
- **When it checks:**
  - at login, after a delay so the first paint is not slowed;
  - at an interval the user sets (default 6 hours, minimum 1 hour). Remote
    repositories have no change signal; this is the sampled fallback AGENTS.md
    allows. One check runs at a time; a check never overlaps the last;
  - when NetworkManager reports a new connection, through its D-Bus signal
    (event-driven, no polling). An unavailable NetworkManager does not stop
    the interval checks;
  - by hand, from Settings only.
- **Where a click goes:** Settings > System (D-25). The panel has no update
  controls of its own.
- **Cost:** no resident hidden model; the check is a bounded `Process`. Closed
  popup idle CPU is measured, as AGENTS.md requires.
- **Docs:** SPEC.md (the update surface), `docs/src/` (the user guide),
  `CHANGELOG.md`.
- **Tests:** model tests for the counts, the hidden state and overlapping
  checks; an Xvfb test that the icon appears, hides and opens the chosen
  surface.

## S15-03: Flatpak updates

From `#363`. Gate: S15-02 (its provider list).

- **Discovery:** `flatpak remote-ls --updates --columns=application,branch`
  per scope, `--system` and `--user` (a column interface, not human output).
  Flatpak missing is "unavailable", never an error.
- **Applying:** `flatpak update --system` and `flatpak update --user`, run
  separately in a terminal (S15-04's terminal helper). One scope failing
  leaves the other's result, and says which scope did not finish.
- **Privilege:** none from Lyona. A system-scope update uses Flatpak's own
  polkit authorization.
- **Tests:** a stub `flatpak` for no updates, updates in one scope, both, a
  failure in one, and Flatpak missing.

## S15-04: System updates in a terminal

From `#363`. Decided by D-26.

- **The command:** `pacman -Syu` through `sudo` in a terminal, with pacman's
  own plan and confirmation (never `--noconfirm`). If `yay` is installed,
  `yay -Syu` instead (D-26), so foreign packages (the Sprint 14 legacy
  drivers) update too.
- **The terminal:** the user's terminal through `dwm-terminal`. It holds open
  after the command ends ("press a key to close"), so the result can be read.
  It tiles by default, or floats if the user saves "Float update terminal".
  That preference goes in the user's runtime TOML under
  `${XDG_CONFIG_HOME:-$HOME/.config}/lyona/`. It never changes an existing
  window rule.
- **The result:** the exit status is reported and never read as success when
  the terminal closed early. A declined confirmation is "not updated".
- **What stays:** PackageKit's preview path, beside the terminal action (D-26). The
  privileged helper gains nothing: `sudo` in the user's terminal is the
  authorization, as for any command the user runs.
- **Docs:** SPEC.md, the user guide, and `docs/AUR-PACKAGES.md` (an AUR-built
  driver can now be updated from Settings when `yay` is installed),
  `CHANGELOG.md`.
- **Tests:** a stub terminal and stub `pacman`/`yay`: the command line, no
  `--noconfirm`, success, failure, a declined plan, an early close, and
  `yay` missing.

## S15-05: Validate in a live session

Gate: S15-01 to S15-04, a live X11 session.

- A `recommended` install on a clean Arch VM gets `gnome-keyring`. After a
  LightDM password login, the login keyring is unlocked
  (`secret-tool` stores and reads a value without a prompt).
- Removing `gnome-keyring` shows the Health row; reinstalling clears it.
- The panel icon appears with a pending update and hides once current. A
  reconnect triggers a check. Closed-popup idle CPU is near zero.
- A real `pacman -Syu` and a Flatpak update run in the terminal in both window
  modes. A declined plan reports "not updated".
- Record what was not tested (hardware, other display managers) in
  `docs/evidence/s15-05-updates-and-keyring.md`.
