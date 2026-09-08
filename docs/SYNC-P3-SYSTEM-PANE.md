# Sync Phase 3 — update model and the System Settings pane

Upstream: [`#209`](https://github.com/ChrisTitusTech/dwm-titus/pull/209)
(`27ab809a`) and [`#210`](https://github.com/ChrisTitusTech/dwm-titus/pull/210)
(`4ebb339d`). Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 2](SYNC-P2-UPDATE-SNAPSHOT.md) — nothing here has a data
source until the snapshot exists — and on Lyona's own `UPDATE-001…003`
(`docs/P6-UPDATE-*.md`, `lyona-update`) having landed first: **this "Arch
packages" group is the room `P6-UPDATE-SURFACE.md` already reserved beside
its own "lyona" group**, not a new pane. Build it into that existing layout,
not alongside it.

First user-visible behaviour of the whole port: Settings → System stops being
a generic capability list and becomes a real read-only update status pane.

---

## Files

| File | Change |
| --- | --- |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | **New**, ~590 lines at this boundary |
| `config/quickshell/settings/SystemSettingsPane.qml` | **New**, ~391 lines at this boundary |
| `config/quickshell/settings/SettingsModel.qml` | `systemManagementModel` property, open/close/refresh wiring |
| `config/quickshell/settings/SettingsWindow.qml` | Render the pane; exclude `system` from the generic fallback |
| `config/quickshell/shell.qml` | Instantiate the root model; IPC probes |
| `tests/test-quickshell-system-management.sh` | **New** parser/lifecycle test |
| `tests/test-quickshell-system-management-xvfb.sh` | **New** nested-X11 test |

---

## 1. The section already exists

Unlike every other pane in this port, Lyona does **not** need a new Settings
section. `SettingsModel.qml:108` already carries:

```qml
        { "id": "system", "label": "System", "description": "Health and administration" }
```

It is the ninth section and it currently renders through
`SettingsWindow.qml`'s generic `capabilityList`, whose `visible` expression
excludes every section that has a real pane. This phase adds `system` to that
exclusion list and mounts a pane instead — the same shape upstream used:

```diff
+                            SystemSettingsPane {
+                                Layout.fillWidth: true
+                                Layout.fillHeight: true
+                                visible: root.settingsModel.selectedSectionId === "system"
+                                systemManagementModel: root.systemManagementModel
+                                capabilities: root.settingsModel.capabilitiesForSection("system")
+                            }
+
                             ListView {
                                 id: capabilityList
```

```diff
                                     && root.settingsModel.selectedSectionId !== "appearance"
+                                    && root.settingsModel.selectedSectionId !== "system"
```

```diff
     required property var panelSettingsModel
+    required property var systemManagementModel
```

> The pane must **coexist** with the `system health` and `system
> authorization` capability rows that `dwm-settings-provider` already emits
> (`scripts/dwm-settings-provider:682-698`), not replace them. Upstream's pane
> takes a `capabilities` property for exactly this reason. It must also leave
> room for `lyona-update`'s own section — see
> [`P6-UPDATE-SURFACE.md`](P6-UPDATE-SURFACE.md), which builds a Lyona-version
> group in the same pane. Whichever lands first owns the pane file; the second
> adds a section to it.

## 2. Lifecycle: the pane owns the snapshot, and closing it stops the work

`SettingsModel.qml` gains the open/close pairing every other model already
uses. Upstream's hunk, adapted to Lyona's `selectSection`:

```diff
     property var panelSettingsModel: null
+    property var systemManagementModel: null
```
```diff
+        if (root.systemManagementModel) {
+            const wantSystem = id === "system" && root.visible;
+            if (wantSystem && !root.systemManagementModel.settingsVisible)
+                root.systemManagementModel.openSettings();
+            else if (!wantSystem && root.systemManagementModel.settingsVisible)
+                root.systemManagementModel.closeSettings();
+        }
```
```diff
+        if (root.visible && root.selectedSectionId === "system" && root.systemManagementModel)
+            root.systemManagementModel.refresh();
```

This is the same contract `SETTINGS-PLATFORM.md` states for every section:
*"Closing a section must stop watches and child processes that exist only for
that section."* The snapshot is **on demand**, never polled — which the
closed-CPU baseline in Verification exists to prove.

## 3. `SystemManagementModel.qml`

A `Scope` root model instantiated once in `shell.qml`, shared by Settings and
(later) the Control Center — the same shape as Lyona's `AppearanceModel` and
`PanelSettingsModel`. At this boundary it holds:

```qml
    property bool settingsVisible: false
    property string snapshotState: "idle"
    property string message: "System management has not been loaded"
    property string generation: ""
    property var updateProvider: root.providerFallback("Update status has not been loaded")
    property var recoveryProvider: root.recoveryFallback("Recovery status has not been loaded")
    property var updateSummary: root.stateFallback("Update status has not been loaded")
    property var updateLastRefresh: root.stateFallback("Refresh history has not been loaded")
    property var updateRestart: root.stateFallback("Restart guidance has not been loaded")
    property var actions: []
    property var updates: []
    property var packageChanges: []
    property var errors: []
    readonly property bool busy: snapshotOwned
```

Later phases add `nativeProviders` / `nativeStates` / `accounts` /
`repositories` ([Phase 8](SYNC-P8-REGIONAL-READERS.md)), the `operation` and
`discovery` aliases ([Phases 4](SYNC-P4-DISCOVERY-EVENTS.md) and
[7](SYNC-P7-OPERATION-SURFACE.md)), and the confirmation state
([Phase 7](SYNC-P7-OPERATION-SURFACE.md)). Structure the file so those arrive
as additions.

**Parser rules that must not be softened.** The model validates the snapshot
rather than trusting it — the helper is bounded, but the model is the second
line of defence and the tests target it directly:

- A missing or unsupported `system-management-protocol` record is a **provider
  failure**, not an empty result. This is already Lyona's stated rule in
  [`SETTINGS-PLATFORM.md`](SETTINGS-PLATFORM.md#helper-protocol).
- A snapshot without a trailing `complete<TAB>snapshot` is discarded whole. A
  truncated read must never present as a shorter update list.
- Every mandatory provider/state/action ID for the advertised protocol minor
  must be present, even when its source is absent — enforced against the
  minor table in [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#1-the-contract-document).
- List identity, count and byte limits are re-checked model-side.
- Enum values are validated by explicit allowlists (`validProviderStatus`,
  `validErrorCode`, `validSeverity`, `validRestart`, `validPlanAction`), not
  by passing strings through to the UI.

**Lyona adaptations:**

- Launch through `Commands.systemManagementCommand("snapshot", [])` wrapped in
  `Commands.checkedCommand(...)` — the plain one, so a nonzero exit can never
  be parsed as a result. The `terminatingCheckedCommand` variant added in
  [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#3-commandsqml) is for the
  long-running `watch-*` children in [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md),
  not for this.
- Reuse `config/quickshell/core/WatchedProcess.qml` wherever upstream inlines
  a `Process` + settle-timer + restart-timer trio. This is the standing rule
  in [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#lyona-only-assets-the-port-must-reuse-rather-than-duplicate).

## 4. `SystemSettingsPane.qml`

A `Flickable` with keyboard paging, following `AppearanceSettingsPane`'s
structure. Reuse `config/quickshell/core/StatusCard.qml` — upstream repeats an
inline `component StatusCard` in each pane and Lyona already has the shared
one. Wrap every pixel constant in `Theme.dp(...)`; Lyona scales the whole
shell and upstream does not.

Contents at this boundary, top to bottom:

1. Section header and a **Reload status** `ShellButton`, disabled while
   `busy`, with `objectName: "reloadSystemStatus"` for the xvfb test.
2. Provider/recovery status line.
3. `SectionLabel { label: "System updates" }` — upstream says "Fedora
   updates"; Lyona's provider is PackageKit over alpm and the label must say
   so honestly, not name a distribution.
4. A `GridLayout` of `StatusCard`s: update summary, last refresh, restart
   guidance. One column below 720 px, three above.
5. The pending-update list and the package-change preview list.
6. The existing `capabilities` rows (`system health`, `system authorization`).
7. A caption stating plainly what the pane can and cannot do. At this
   boundary that is read-only, and the text must say so:

```qml
            text: "This pane reads update and recovery state only. Metadata refresh, "
                + "update installation, and cancellation require a separate confirmed "
                + "operation workflow."
```

[Phase 7](SYNC-P7-OPERATION-SURFACE.md) replaces that caption when the
mutation path becomes real. Do not ship the later wording early.

## 5. `shell.qml`

Instantiate the model once and pass it down. Add the IPC probes the xvfb test
drives — upstream's set at this boundary, plus the ones `#231`/`#236` added
later, which are cheap to include now:

```qml
        function systemManagementUpdateCount(): int {
            return systemManagementModel.updates.length;
        }

        function systemManagementPackageChangeCount(): int {
            return systemManagementModel.packageChanges.length;
        }

        function systemManagementSnapshotState(): string {
            return systemManagementModel.snapshotState;
        }

        function systemManagementRestartState(): string {
            return systemManagementModel.updateRestart.status + ":" + systemManagementModel.updateRestart.value;
        }
```

---

## Verification

```bash
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-quickshell-system-management
scripts/run-tests make check-quickshell-settings-xvfb
scripts/run-tests make check-settings
```

Manual, on a real CachyOS install:

- Open Settings → System with updates pending, and with none. Both render;
  neither shows a spinner that never resolves.
- With `packagekit` uninstalled: the pane explains the missing provider and
  the other Settings sections stay usable. Provider failures isolate — that is
  the `SETTINGS-PLATFORM.md` `failure` state contract.
- **Closed-CPU baseline.** 30 seconds with Settings closed versus 30 seconds
  with the System pane open. The snapshot is on demand; a nonzero steady-state
  delta means something is polling. Mean Quickshell CPU delta must be within
  0.5 percentage points of one CPU, matching `TASKS.md`'s `P5-VALIDATE`
  threshold.
- Close the pane and confirm no `dwm-system-management` process survives.

## Closes

The first real content for Phase 6's `SYSTEM-001` "read-only status remains
available when authorization is denied" exit criterion in `ROADMAP.md`.
