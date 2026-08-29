# UPDATE-003 — Update Surfaces in Settings and Control Center

Third boundary of the Phase 6 update path. Architecture and rationale:
[`P6-UPDATE-OVERVIEW.md`](P6-UPDATE-OVERVIEW.md). Depends on
[`UPDATE-001`](P6-UPDATE-PROVENANCE.md) and
[`UPDATE-002`](P6-UPDATE-HELPER.md).

## Context

With `lyona-update` in place the desktop can be updated from a terminal. Most
users will never open one. This boundary puts the same capability behind the
Settings surface, using the model/helper pattern the shell already uses
everywhere else — a root model over a versioned helper protocol, with
per-capability status and safe degradation.

Deliberately excluded: unattended updates, and Arch package updates. Both are
separate Phase 6 decisions (see *Out of scope*).

---

## 1. `config/quickshell/system/UpdateModel.qml`

One root model, instantiated once in `shell.qml`, shared by the Settings pane
and the Control Center. Same shape as `PanelSettingsModel` and
`AppearanceModel`.

State:

```
providerState   idle | available | offline | unknown | unavailable
providerDetail  human-readable status line
installedVersion, installedCommit, installedSource
availableVersion, availableDate, availableNotesUrl
updateState     current | behind | ahead | unknown | offline
busy            an action is in flight
phase           idle | checking | downloading | verifying | building | installing | verifying-install | restarting
progressDetail  the current step, verbatim from the helper
message, actionSucceeded
consistent      from lyona-version; false means a damaged install
```

Actions: `check()`, `apply(version)`, `rollback(backupId)`, `refreshBackups()`.

Two things this model must get right, both of which differ from every existing
model in the tree:

**Long-running, staged progress.** An apply takes minutes and passes through
distinct phases. The helper emits one progress record per phase to stdout; the
model parses and republishes it. No spinner-only UI — the user must be able to
see that it is building rather than hung.

**Survival of its own update.** An apply restarts Quickshell (step 9 of
`apply`), so the model is destroyed mid-action by design. It therefore cannot
hold the operation's state only in memory. The helper owns a status file at
`$XDG_STATE_HOME/lyona/update.status`; the model reads it on
`Component.onCompleted` and reports the outcome of an update that completed
across its own restart. Without this, every successful update looks like a crash
to the UI.

Refresh is event-driven from a `FileView` watch on the status file, matching the
`PanelSettingsModel` pattern — no polling.

Command wiring in `config/quickshell/core/Commands.qml`:

```qml
    function updateCommand(action, args) {
        return helperCommand("lyona-update", action, args, true);
    }

    function versionCommand(action, args) {
        return helperCommand("lyona-version", action, args, true);
    }
```

---

## 2. Settings → a new "System" section

A tenth section in `SettingsModel`'s section list, after `appearance`. New pane
`config/quickshell/settings/SystemSettingsPane.qml`, following
`AppearanceSettingsPane` in structure.

Contents, top to bottom:

- **Installed version card** — `StatusCard` with version, commit (short),
  install source and date. `statusState` is `error` when
  `consistent` is false, with the detail naming which of system/user/binary
  disagrees. A damaged install is the single most important thing this pane can
  tell a user, so it is first and it is loud.
- **Update status** — current/behind/offline, the available version and its
  release date, and a link to the release notes.
- **Check for updates** — `ShellButton`, disabled while `busy`.
- **Update now** — `ShellButton`, visible only when `updateState` is `behind`.
  Requires an explicit confirmation step showing the target version before it
  calls `apply()`; reuse the confirmation idiom already used for destructive
  power and session actions rather than inventing a new dialog.
- **Progress** — while `busy`, the phase and `progressDetail`, plus the plain
  statement that Quickshell will restart and a session restart may be needed.
- **Channel** — stable/preview selector, writing `update.conf` through the
  helper. `preview` carries an inline warning that pre-releases are not
  release-qualified (`docs/RELEASING.md`).
- **Backups and rollback** — the list from `lyona-update backups`, each with
  version and date, and a confirmed `Roll back` action.

The privileged step still authenticates through polkit exactly as in
UPDATE-002. The pane never runs anything as root itself; it invokes the same
unprivileged helper a terminal user would.

### Capability registration

Add an `updates` capability to `dwm-settings-provider` so the section appears
in `capabilitiesForSection` with proper status attribution, and add a row to
`docs/SETTINGS-CAPABILITIES.md` in the operations table — owner
`lyona-update` / `lyona-version`, class user-session + one confirmed privileged
step, with the degradation contract.

---

## 3. Control Center

A single line on the overview page: the installed version, and — only when
`updateState` is `behind` — one row reading `Update available: <version>` that
navigates to Settings → System.

No apply action in the Control Center. It is a quick-access surface; a
multi-minute privileged operation that restarts the shell does not belong
behind a one-click row next to the volume slider.

---

## 4. Login-time check

When `check_on_login=true` (the `update.conf` default from UPDATE-002), run one
`lyona-update check` shortly after session start, jittered, and surface a
notification through the existing notification model when the result is
`behind`. The notification opens Settings → System; it never applies anything.

Constraints: one check per session, never blocking session startup, silent on
`offline`, and honouring `check_on_login=false` absolutely. An update prompt on
every login for a user who has said no is the fastest way to make people
disable the whole feature.

---

## Out of scope for this boundary

- **Unattended/automatic updates.** `auto_apply` remains rejected. Making a
  desktop rebuild and reinstall itself without the user watching needs its own
  specification and its own failure story.
- **Arch package updates** (`pacman -Syu`). Phase 6 wants this, but it is a
  different risk profile, authorisation story and failure mode. The System
  section is laid out so an "Arch packages" group can be added beside "lyona"
  later without rework.
- **Rollback from within a broken session.** If the desktop will not start there
  is no UI to click; the TTY path in UPDATE-002 is the answer, and the
  documentation must say so plainly.

---

## Tests

### New: `tests/test-quickshell-update-model.sh`

Static and stubbed-helper assertions, following `tests/lib.sh` conventions:

- `shell.qml` instantiates `UpdateModel` exactly once and passes it to both
  `SettingsWindow` and `ControlCenterWindow`.
- Protocol parsing: well-formed `check` output populates every field; a
  malformed record leaves the model in `unavailable` with defaults, never
  half-populated.
- `offline` renders as an informational state, not an error.
- `consistent=false` drives the error styling on the version card.
- Actions are inert while `busy`.
- `Commands.qml` defines `updateCommand` and `versionCommand`.

### Extend: `tests/test-quickshell-settings-xvfb.sh`

With a stubbed `lyona-update` in the managed script dir:

- The System section appears and reaches a non-`idle` state.
- IPC probes `updateState()`, `updateInstalledVersion()`,
  `updateAvailableVersion()`, `updateConsistent()` return the stubbed values.
- A stubbed `behind` result makes the Update action visible; `current` hides it.
- Driving `apply` through a stub that emits each phase in turn moves `phase`
  through `downloading` → `verifying` → `building` → `installing`.
- A stub that writes `update.status` and exits, followed by a model reload,
  reports the completed outcome — the survives-its-own-restart case.

### Extend: `tests/test-quickshell-controlcenter.sh`

The update row appears only when `behind`, and navigates rather than acting.

### `Makefile`

`check-quickshell-update-model:` target, added to `check:` and `.PHONY`.

---

## Documentation

- `docs/src/settings.md` — a System section covering version, channel, updating
  and rollback.
- `docs/src/control-center.md` — the version line and update indicator.
- **`docs/src/updating.md`** — a new user-facing page, added to
  `docs/src/SUMMARY.md`: how to check, how to update, what a session restart
  means, how to roll back, and — prominently — **how to roll back from a TTY
  when the desktop will not start**. That last section is the one people will
  search for at their worst moment; it should be findable without a working GUI,
  so mirror it in `README.md` under Troubleshooting.
- `CHANGELOG.md` — one `### Added` entry covering the user-visible surface.

---

## Verification

```bash
scripts/run-tests make check-quickshell-update-model
scripts/run-tests make check-quickshell-controlcenter check-quickshell-qml
scripts/run-tests env DWM_SETTINGS_POWER_CPU_SECONDS=0 tests/test-quickshell-settings-xvfb.sh
scripts/run-tests make check
```

On a disposable Arch VM with two real published releases:

1. Install release N. Settings → System shows N, source, date, `consistent`.
2. Check for updates → N+1 offered with its release date and notes link.
3. Update now → confirmation names N+1; progress advances through its phases;
   Quickshell restarts; on return the pane reports the completed update at N+1
   rather than an error.
4. Log out and back in where a session restart was reported; version card
   confirms N+1 and `consistent`.
5. Roll back through the pane → confirmation, restore, N reported.
6. Set `check_on_login=false`, log in, confirm no notification and no network
   call.
7. Disconnect the network → the pane reports offline without an error card, and
   the installed version is still shown.
8. Corrupt the user provenance record → the version card shows the error state
   and names the disagreeing records.
