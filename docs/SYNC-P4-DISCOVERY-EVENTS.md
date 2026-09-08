# Sync Phase 4 — live discovery monitoring

Upstream: [`#237`](https://github.com/ChrisTitusTech/dwm-titus/pull/237)
(`e47a1f08`), [`#238`](https://github.com/ChrisTitusTech/dwm-titus/pull/238)
(`a30f5fed`), [`#260`](https://github.com/ChrisTitusTech/dwm-titus/pull/260)
(`a6d65c08`). Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 3](SYNC-P3-SYSTEM-PANE.md).

Replaces "click Reload status and hope" with a bounded subscription: while the
System pane is open, the helper watches PackageKit's manager signals and tells
the shell when to re-read. **The last read-only phase** — everything after
this either writes a journal or mutates the system.

---

## Files

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | `UpdateEventMonitor`, `watch_update_events()`, the `watch-updates` command |
| `config/quickshell/systemmanagement/SystemDiscoveryCycle.js` | **New**, 71 lines — the pure state machine |
| `config/quickshell/systemmanagement/SystemProviderDiscovery.qml` | **New**, ~198 lines — process lifecycle over that machine |
| `config/quickshell/systemmanagement/SystemUpdateDiscovery.qml` | **New**, 3 lines |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | Own a `SystemUpdateDiscovery`, coalesce reads |
| `config/quickshell/settings/SystemSettingsPane.qml` | Surface `discoveryDetail` |
| `config/quickshell/shell.qml` | `systemManagementDiscoveryStatus()` probe |

---

## 1. The event stream is a child process, not a daemon

This is the part that earlier notes got wrong and it is worth stating plainly:
`dwm-system-management watch-updates` is an **ordinary child of Quickshell's
`Process`**. It writes two record kinds on stdout and nothing else:

```text
update-event<TAB>ready
update-event<TAB>changed
```

It exits on `SIGTERM`. There is no resident daemon, no socket, no bus name
owned by Lyona, and no state that survives the pane being closed. The pattern
is the same one Lyona already uses for `dwm-settings-appearance`'s inventory
watch and `dwm-settings-display watch` — which is why
`config/quickshell/core/WatchedProcess.qml` exists.

What it does internally (`UpdateEventMonitor`, `:8044`) is subscribe to
PackageKit's manager signals on the system bus through `Gio`, with:

- a **bounded setup deadline** — it must emit `ready` or die;
- `NameOwnerChanged` tracking, so a PackageKit restart is a `changed`, not a
  silent stall;
- a `dirty` flag, so a change arriving *before* `ready` is not lost;
- an explicit sender check against the well-known name rather than trusting
  GDBus's implicit name cache, whose lookup failures cannot be observed.

Under **Option C** ([Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#the-three-options))
this whole phase changes shape: without PackageKit there is no signal to
subscribe to, and the honest replacement is an `inotify` watch on
`/var/lib/pacman/local` plus the `checkupdates` database copy. That is a
different mechanism with different latency and it must be documented as such
rather than presented as equivalent.

## 2. The cycle state machine is the interesting part

`SystemDiscoveryCycle.js` is 71 lines of **pure functions over a plain
object** — deliberately no QML properties and no signals inside it, so the
completion handoff cannot re-enter:

```js
// Serialized state only: no QML property signals inside the completion handoff.
function create() {
    return { epoch: 0, enabled: false, phase: "idle", dirty: false,
        unresolved: false, forceSettle: false, settlingDirty: false };
}
```

The phases are `idle`, `initial-pending`, `initial-active`,
`initial-completing`, `settling-pending`, `settling-active`,
`settling-completing`, `blocked`. The reason for two rounds rather than one:

- A `changed` during an **initial** read schedules exactly one **settling**
  read, because the read that was in flight may have observed a half-applied
  transaction.
- A `changed` during the **settling** read sets `unresolved` and moves to
  `blocked` — it does **not** schedule a third automatic read. An update
  transaction emits many signals; unbounded rescheduling would turn a
  `pacman -Syu` into a re-read storm.
- `blocked` surfaces as an explicit user-visible message rather than silent
  staleness:

```qml
    readonly property string detail: !root.visible ? "" : root.failed
        ? "Live " + root.domainLabel() + " monitoring is unavailable. Reload status to retry; readable state is preserved."
        : root.unresolved
        ? "The " + root.domainLabel() + " state changed during the settling read. Reload status to reconcile it; automatic rereads are paused."
        : !root.ready ? "Connecting to " + root.domainLabel() + " change notifications..." : ""
```

That is the whole design in one property: **a monitor that cannot keep up says
so, and readable state is preserved.** Port it verbatim; the wording is part
of the contract.

`epoch` guards completion: a snapshot that finishes after its cycle was closed
or the domain changed is discarded rather than published, because `owns()`
compares the token's epoch.

## 3. `SystemProviderDiscovery.qml` is generic from the start

`a6d65c08` (`#260`) refactored five near-identical monitors into one
parameterised component. **Port the refactored form directly** — writing the
update-only version first and refactoring later would be re-doing upstream's
own mistake:

```qml
    // Only these fixed provider commands are selectable; no caller-supplied argv.
    property string domain: "updates"

    function domainDefinition(value) {
        if (value === "updates") return { action: "watch-updates", args: [], prefix: "update-event", label: "update" };
        if (value === "time") return { action: "watch-regional", args: ["time"], prefix: "regional-event", label: "time" };
        if (value === "locale") return { action: "watch-regional", args: ["locale"], prefix: "regional-event", label: "locale" };
        if (value === "accounts") return { action: "watch-accounts", args: [], prefix: "accounts-event", label: "account" };
        if (value === "printers") return { action: "watch-units", args: ["printers"], prefix: "units-event", label: "printer" };
        return null;
    }
```

Only the `updates` domain has a helper behind it at this boundary; the other
four arrive in [Phase 9](SYNC-P9-REGIONAL-MUTATION.md). An unknown domain sets
`failed`, which is the correct behaviour for both cases.

`SystemUpdateDiscovery.qml` is the whole of the specialisation:

```qml
SystemProviderDiscovery {
    domain: "updates"
}
```

The process lifecycle around it is strict and must be ported exactly:

```qml
    Timer { id: setupDeadline; interval: 12000; repeat: false; onTriggered: root.failMonitor() }
    Timer { id: stopDeadline; interval: 1500; repeat: false; onTriggered: monitor.signal(9) }
    Process {
        id: monitor
        property string eventPrefix: ""
        stdout: SplitParser { onRead: line => root.event(line) }
        onExited: root.finished()
        onRunningChanged: { if (!running && root.monitorOwned) root.finished(); }
    }
```

- 12 s to produce `ready`, or the monitor is failed and the pane says so.
- `SIGTERM` on close, then `SIGKILL` after 1.5 s. Nothing is orphaned.
- **Any line that is not exactly `<prefix>\tready` or `<prefix>\tchanged`
  fails the monitor.** Unknown records are not ignored here — this stream is
  two words wide and anything else means the helper is not what it claims.
- `restartPending` handles a domain change while a stop is in flight, so a new
  subscription cannot inherit the old monitor's `ready`.

**Lyona adaptation.** `monitor.command` must come from
`Commands.systemManagementCommand(action, args)` wrapped in
`Commands.terminatingCheckedCommand(...)` — the variant added in
[Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#3-commandsqml) precisely so a
long-running helper receives the close signal instead of being orphaned.
Wrap both `Timer` intervals' pixel-free constants as-is (they are
milliseconds, not geometry — `Theme.dp()` does not apply).

## 4. Coalescing in the model

`SystemManagementModel` owns the discovery object and gates reads through it
rather than launching a snapshot per signal:

```qml
    readonly property alias discovery: discoveryModel
    readonly property string discoveryDetail: discoveryModel.detail
```

`openSettings()` calls `discoveryModel.open()`; `closeSettings()` calls
`close()`, which stops the monitor. `take()` / `beforePublish()` /
`complete(token, successful)` bracket every snapshot so a late result cannot
publish over a newer one.

Surface `discoveryDetail` in the pane as a warning line, and add the probe:

```qml
        function systemManagementDiscoveryStatus(): string {
            const discovery = systemManagementModel.discovery;
            return discovery.phase + ":" + (discovery.ready ? "ready"
                : discovery.failed ? "failed" : "inactive");
        }
```

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-quickshell-system-management
scripts/run-tests make check-quickshell-qml
```

The cycle machine is pure and deterministic — test it directly rather than
only through the UI. Upstream's `tests/qml/SystemProviderDiscovery.qml`
harness is the model for this and is worth porting in full.

Manual, on a real CachyOS install:

- Open Settings → System, then in a terminal run
  `pkcon refresh` (or install a package). The pane re-reads without a click.
- Restart PackageKit (`systemctl restart packagekit`) with the pane open. The
  monitor recovers via `NameOwnerChanged`; it does not stall silently.
- Run a full `pacman -Syu` with the pane open. Confirm the pane reaches
  `blocked` with the "changed during the settling read" message rather than
  launching a read per signal. **This is the point of the phase** — verify it
  by watching process count, not just the UI.
- **Closed-CPU baseline again.** The monitor is a blocked `GLib.MainLoop`; a
  measurable idle delta means it is spinning.
- Close the pane. `pgrep -f 'dwm-system-management watch-updates'` returns
  nothing.
- Kill the monitor externally (`pkill -f watch-updates`) with the pane open:
  `failed` is set, the message appears, and previously read state is still
  displayed.

## Closes

Completes the read-only half of Phase 6's system-update scope. **This is the
decision point** — see
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#the-decision-point-after-phase-4) before
starting [Phase 5](SYNC-P5-OPERATION-JOURNAL.md).
