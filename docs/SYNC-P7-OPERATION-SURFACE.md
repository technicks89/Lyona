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
| `scripts/dwm-system-management` | `build_snapshot()`/`build_managed_snapshot()` thread `mutation_blocker`/`mutation_failure` so `updates-refresh`/`updates-install-all` can actually report `available` |

> **Gap found during Sync Phase 8 and fixed on `sync-p7-mutation-fix-v2`.**
> This file's own commit citation (`#241`, `65138a89` is the *QML* SHA for
> this phase; `#241`'s *Python* changes to `scripts/dwm-system-management`
> were never diffed or ported) was missed entirely during the original Sync
> Phase 7 work — only the QML side was fetched and ported. The practical
> effect: `build_snapshot()` unconditionally emitted `updates-refresh`/
> `updates-install-all` as `unavailable`, so every confirm/cancel control this
> phase adds was permanently disabled against a real backend from the moment
> Sync Phase 7 merged (`44b0a39`, PR #30) until this fix. Ported PR #241's
> `mutation_blocker`/`mutation_failure` threading verbatim, preserving Lyona's
> own `_restart_heuristic_hint()` (Arch-only, not in upstream) and updating
> the stale pre-Phase-6 provider-detail text that still referenced
> `lyona-update`. Also ported PR #241's test rewrite: `test_cli_initializes_
> only_its_fixed_journal_and_keeps_actions_disabled` renamed to `..._and_
> offers_safe_refresh` plus six new `RecoverySnapshotTests` cases covering
> every origin-blocking path (unsafe backend, failed/unsupported plan, failed
> discovery, incomplete recovery, malformed inventory, existing owner/handoff)
> — 314 → 321 tests, all passing. See `TASKS.md`'s "Sync Phase 7 follow-up"
> entry for the full verification record.

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
`Commands.systemManagementCommand(action, args)` directly, feeding
`StdioCollector.data` into the parser.

> **Correction, found during implementation.** This section originally said
> the watch/ack commands run under `Commands.terminatingCheckedCommand(...)`
> (from [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#3-commandsqml)). They do
> not, and must not: `terminatingCheckedCommand` (like `checkedCommand`)
> buffers the wrapped command's stdout to a temp file and only `cat`s it once
> the child exits — correct for the bounded one-shot `snapshot` read, but it
> would defeat `watch-operation`'s live streaming entirely, turning every
> progress record into one batch delivered at exit. This is the exact same
> mistake [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#3-systemproviderdiscoveryqml-is-generic-from-the-start)
> already found and corrected for `watch-updates`/`watch-regional`/etc.; the
> ported `SystemOperationModel.qml` (upstream does not wrap these either)
> follows the same rule.

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

  > **Deferred to [Phase 9](SYNC-P9-REGIONAL-MUTATION.md).** `#262`'s own diff
  > is a "native origins" adaptation spanning the regional/delegated action
  > machinery ([Phase 8](SYNC-P8-REGIONAL-READERS.md)/[Phase 9](SYNC-P9-REGIONAL-MUTATION.md))
  > that does not exist in Lyona yet, so the commit itself is not ported here.
  > The security property it is cited for above already holds without it:
  > `startUpdate(action, generation)` only accepts the two literal strings
  > `"updates-refresh"`/`"updates-install-all"` (see its guard clause) — QML
  > has no path to construct or pass through an arbitrary action string for
  > the update domain this phase covers. Re-check this note when Phase 9 adds
  > regional/delegated origins, the same way [Phase 6](SYNC-P6-UPDATE-EXECUTION.md)'s
  > `#232`/E7 exclusion was inherited rather than re-litigated.

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

> **Gap found during implementation.** This `scrollTo()` call assumes prior
> keyboard-scroll scaffolding (a `Keys.onPressed` line/page-step handler and a
> `scrollTo()` helper) that upstream's `SystemSettingsPane.qml` already had
> from an earlier phase. Lyona's pane never ported that scaffolding — it is
> a plain `Flickable` with no `scrollTo()` — so `reveal()` here sets
> `root.contentY` directly instead of calling a helper that does not exist:
>
> ```qml
> function reveal(target) {
>     const position = target.mapToItem(content, 0, 0);
>     if (position.y < root.contentY)
>         root.contentY = Math.max(0, position.y);
>     else if (position.y + target.height > root.contentY + root.height)
>         root.contentY = Math.min(Math.max(0, root.contentHeight - root.height),
>             position.y + target.height - root.height);
> }
> ```
>
> The behavior (scroll the minimum distance to bring `target` on screen) is
> the same; only the mechanism differs. Porting the keyboard line/page-step
> handler itself is out of scope here — it was never part of any prior Lyona
> sync phase and this phase's upstream diff does not touch it either.

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
scripts/run-tests make check-quickshell-system-management-xvfb
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
```

`SystemOperationProtocol.js` is a pure library — test it directly with
malformed, truncated, split-mid-codepoint and illegal-transition streams.
Upstream's `tests/qml/SystemOperationParser.qml` harness is the model.

> **Known automated-coverage gap.** `tests/qml/SystemOperationParser.qml` was
> not ported in this pass — deferred, not forgotten. Separately,
> `tests/test-quickshell-system-management-xvfb.sh`'s stub `dwm-system-management`
> reports `recovery\tunsupported` and both update actions `unavailable` (it
> predates this phase and was built for read-only assertions), so it proves
> `SystemOperationModel`/`SystemUpdateControls` mount and settle to their idle
> defaults against a real Quickshell process (added assertions:
> `systemManagementOperationState` is `idle`, `systemManagementOperationResult`
> is empty) but cannot exercise a live confirm → dispatch → watch → cancel →
> ack cycle — that needs a PackageKit-transaction-capable stub (handling
> `updates-refresh`, `updates-install-all`, `watch-operation`, `ack-operation`,
> `updates-cancel`) comparable in complexity to `tests/test-system-management.py`'s
> own fixtures. Both gaps are left for whoever picks this up next; the manual
> VM checklist below is the only coverage of the live cycle until then.

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
