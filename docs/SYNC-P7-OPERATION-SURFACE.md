# Sync Phase 7 — the operation surface in Quickshell

Upstream: [`#235`](https://github.com/ChrisTitusTech/dwm-titus/pull/235)
(`01cf5e5f`), [`#236`](https://github.com/ChrisTitusTech/dwm-titus/pull/236)
(`a424a47b`), [`#239`](https://github.com/ChrisTitusTech/dwm-titus/pull/239)
(`96b632a5`), [`#240`](https://github.com/ChrisTitusTech/dwm-titus/pull/240)
(`66fb5356`), [`#241`](https://github.com/ChrisTitusTech/dwm-titus/pull/241)
(`65138a89`), [`#262`](https://github.com/ChrisTitusTech/dwm-titus/pull/262)
(`05b74e02`). Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 6](SYNC-P6-UPDATE-EXECUTION.md), and on
`docs/P6-UPDATE-SURFACE.md`'s Settings layout already existing — this is the
"Arch packages" confirm/cancel workflow built into the room that document
reserved beside its own "lyona" one, not a second one.

The click-to-install surface. After this phase Settings → System can refresh
metadata and install updates, with confirmation, live progress, cancellation
and recovery.

---

## Files

| File | Change |
| --- | --- |
| `config/quickshell/systemmanagement/SystemOperationProtocol.js` | **New**, ~197 lines — a pure stream parser |
| `config/quickshell/systemmanagement/SystemOperationModel.qml` | **New**, ~424 lines — process ownership over that parser |
| `config/quickshell/settings/SystemUpdateControls.qml` | **New**, ~215 lines — the confirmation UI |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | Confirmation state, action-reason logic |
| `config/quickshell/settings/SystemSettingsPane.qml` | Mount the controls; active/result cards; `reveal()` |
| `config/quickshell/shell.qml` | Operation state/result probes |

---

## 1. Parse bytes, not strings

`SystemOperationProtocol.js` is a `.pragma library` with no QML dependencies at
all. Its opening comment is the design:

```js
// A parser owns one stream. It never runs a command or acknowledges a journal.
// Feed cumulative StdioCollector.data (ArrayBuffer), not arbitrary QString
// chunks: a pipe read can split a UTF-8 character or a protocol record.
```

The parser carries `offset`, `remaining`, `codepoint` and `minimum` fields and
decodes UTF-8 itself, because a `SplitParser` over a `QString` cannot
distinguish "the record ended" from "the pipe read ended mid-character". For a
stream that authorises a package installation, that distinction matters.

> **Contrast with [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#3-systemproviderdiscoveryqml-is-generic-from-the-start).**
> The discovery monitor *does* use `SplitParser`, because its vocabulary is two
> fixed ASCII words. The operation stream carries package names and summaries.
> Use each where upstream uses it; the asymmetry is deliberate.

The parser also owns the **state machine**, and it is a whitelist of
transitions, not a set of forbidden ones:

```js
function transition(previous, next) {
    if (terminal(previous)) return false;
    // Same-state records update progress without inventing a new transition.
    if (previous === next) return true;
    if (previous === "pending") return ["authorizing", "running", "canceled", "failed", "interrupted"].indexOf(next) >= 0;
    if (previous === "authorizing") return ["running", "permission-denied", "canceled", "failed", "interrupted"].indexOf(next) >= 0;
    if (previous === "running") return ["cancel-requested", "succeeded", "failed", "interrupted"].indexOf(next) >= 0;
    ...
}
```

`running → permission-denied` is absent on purpose: authorization is decided
before execution starts. A stream claiming otherwise is malformed, and the
model must reject it rather than display it.

`actionKind()` and `owner()` mirror the helper's
`JOURNAL_OPERATION_ACTION_KINDS` map. When
[Phase 9](SYNC-P9-REGIONAL-MUTATION.md) adds regional actions it adds them in
both places; a mismatch is a bug the tests should catch.

## 2. Confirmation is a captured snapshot, not a flag

This is the most important QML in the phase and it must be ported precisely.
`prepareUpdate()` captures the state the user is agreeing to:

```qml
        root.updateConfirmation = {
            actionId: actionId, generation: root.generation,
            requestGeneration: root.requestGeneration, epoch: discoveryModel.cycle.epoch,
            changes: actionId === "updates-install-all"
                ? JSON.parse(JSON.stringify(root.packageChanges)) : []
        };
```

`confirmUpdate()` refuses to dispatch unless **all three** still match:

```qml
        if (reason.length > 0 || pending.generation !== root.generation
                || pending.requestGeneration !== root.requestGeneration
                || pending.epoch !== discoveryModel.cycle.epoch) {
            root.confirmationInvalidated();
            return false;
        }
        // Capture the fixed arguments and claim dispatch before clearing the
        // prompt: reentrant UI callbacks must not dispatch another origin.
        root.dispatchingUpdate = true;
        root.updateConfirmation = null;
```

- `generation` — the helper's SHA-256 of the plan. Changes if the plan changed.
- `requestGeneration` — the model's own read counter. Changes if the snapshot
  was replaced even with an identical plan.
- `epoch` — the [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#2-the-cycle-state-machine-is-the-interesting-part)
  discovery cycle epoch. Changes if a monitor restarted, so a stale
  subscription cannot certify a fresh plan.

The `deep copy` of `packageChanges` is not defensive style — it is what the
confirmation dialog displays, and it must be the list the user actually saw
even after the model has moved on.

Ordering matters too: `dispatchingUpdate` is set and the prompt cleared
**before** `startUpdate()`, so a re-entrant activation from the UI cannot
dispatch a second origin. Port the ordering and the comment.

`updateActionReason()` is the single source of "why can't I click this",
returning a user-facing string rather than a boolean. Every disabled control
in `SystemUpdateControls.qml` shows it. Preserve that pattern — it is the
difference between a greyed-out button and an explanation.

## 3. `SystemOperationModel.qml`

Owns one child process at a time, running
`Commands.systemManagementCommand(action, args)` under
`Commands.terminatingCheckedCommand(...)` (from
[Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#3-commandsqml)), feeding
`StdioCollector.data` into the parser.

Rules to carry:

- `canStart` is false while any operation, unacknowledged result, or recovery
  ambiguity exists. It mirrors the helper's admission check but never replaces
  it — the helper re-checks at dispatch
  ([Phase 6 §4](SYNC-P6-UPDATE-EXECUTION.md#4-recovery)).
- Cancellation always passes the **exact observed operation ID**, never "the
  current one".
- `#236` (`a424a47b`) recovers an operation the shell did not start — a
  Quickshell restart mid-update reattaches via `watch-operation` rather than
  showing nothing. This is why [Phase 5](SYNC-P5-OPERATION-JOURNAL.md) exists;
  make sure the test exercises it.
- `#262` (`05b74e02`) restricts origins to a fixed internal set. QML may not
  construct an arbitrary action; it selects one of a closed list. This matches
  Lyona's own standing rule in
  [`SETTINGS-PLATFORM.md`](SETTINGS-PLATFORM.md#helper-protocol): *"QML cannot
  supply command strings, executables, arbitrary paths, or elevation flags."*

## 4. `SystemUpdateControls.qml` and the pane

A component mounted inside `SystemSettingsPane.qml`, above the status grid:

```diff
         SectionLabel { label: "System updates" }
 
+        SystemUpdateControls {
+            model: root.systemManagementModel
+            onRevealRequested: target => root.reveal(target)
+        }
+
```

`reveal()` scrolls a target into view — added to the pane in `#240` because a
confirmation prompt that appears below the fold is a confirmation nobody read:

```diff
+    function reveal(target) {
+        const position = target.mapToItem(content, 0, 0);
+        if (position.y < root.contentY) root.scrollTo(position.y);
+        else if (position.y + target.height > root.contentY + root.height)
+            root.scrollTo(position.y + target.height - root.height);
+    }
```

Two `StatusCard`s replace the single active-operation card from
[Phase 3](SYNC-P3-SYSTEM-PANE.md): one for the live operation, one for the
verified result, which persists until acknowledged.

**Lyona adaptations:**

- Reuse `core/StatusCard.qml` and `controls/ShellButton.qml`. Phase 9 of the
  earlier sync work already extended `ShellButton` with primary/pending states
  for the display Apply button (see
  [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#recommended-execution-order)); the
  confirm/cancel pair here should use the same states rather than adding new
  ones.
- Every constant through `Theme.dp()`.
- The pane caption from [Phase 3](SYNC-P3-SYSTEM-PANE.md) is now false and must
  be replaced:

```diff
-            text: "This pane reads update and recovery state only. Metadata refresh, "
-                + "update installation, and cancellation require a separate confirmed "
-                + "operation workflow."
+            text: "Reload status reads update and recovery state. Metadata refresh and "
+                + "update installation require visible confirmation. PackageKit owns "
+                + "authorization and safe cancellation."
```

- Confirmation must use Lyona's existing confirmation idiom from the power and
  session actions rather than inventing a dialog — the same instruction
  [`P6-UPDATE-SURFACE.md`](P6-UPDATE-SURFACE.md) gives for `lyona-update`.
  Both features confirm in the same pane; they must not look different.

## 5. `shell.qml` probes

```qml
        function systemManagementOperationState(): string {
            return systemManagementModel.operation.state;
        }

        function systemManagementOperationResult(): string {
            const result = systemManagementModel.operation.result;
            return result === null ? "" : result.actionId + ":" + result.state;
        }
```

---

## Verification

```bash
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-quickshell-system-management
scripts/run-tests make check-quickshell-settings-xvfb
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
```

`SystemOperationProtocol.js` is a pure library — test it directly with
malformed, truncated, split-mid-codepoint and illegal-transition streams.
Upstream's `tests/qml/SystemOperationParser.qml` harness is the model.

Manual, on a **disposable** CachyOS VM:

- Refresh metadata from the pane. Progress appears, the result card appears,
  and the next action is blocked until the result is acknowledged.
- Install updates: the confirmation lists the exact package changes, and the
  list matches `pacman -Qu` plus dependencies.
- **Confirm, then invalidate.** Open the confirmation, and in a terminal run
  `pkcon refresh` (or install a package) before clicking confirm. The prompt
  must invalidate with "Update state changed. Review a fresh preview and
  confirm again." — **not** install the stale set. This is the phase's central
  claim.
- Cancel a running install from the pane. It reaches `canceled`.
- Kill Quickshell mid-install and restart it. The pane reattaches to the
  running operation and reports its real result.
- Deny the polkit prompt. State stays readable, the operation reaches
  `permission-denied`, and retry is possible — `SETTINGS-PLATFORM.md`'s
  `permission-denied` state contract.
- Confirmation prompt below the fold: it scrolls into view.
- Keyboard-only: reach and activate confirm and cancel with visible focus.
- Closed-CPU baseline once more, with the pane open and idle.

## Closes

Phase 6's `ROADMAP.md` exit criteria *"Every privileged action is allowlisted,
confirmed, auditable, and cancelable"* and *"Read-only status remains available
when authorization is denied"*, for the update half. The regional half is
[Phase 9](SYNC-P9-REGIONAL-MUTATION.md), and it needs a documented contract
exception.
