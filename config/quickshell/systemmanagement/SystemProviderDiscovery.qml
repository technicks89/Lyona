import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemDiscoveryCycle.js" as Cycle

/*
 * Generic lifecycle over a fixed set of bounded `watch-*` event streams.
 * Sync Phase 4 (docs/SYNC-P4-DISCOVERY-EVENTS.md), ported from upstream's
 * `a6d65c08` (#260) refactor -- the generic form is ported directly rather
 * than writing an updates-only version and refactoring later. Only the
 * "updates" domain has a helper behind it at this boundary (SystemUpdateDiscovery);
 * the other four are Sync Phase 9.
 */
Scope {
    id: root

    // Only these fixed provider commands are selectable; no caller-supplied argv.
    property string domain: "updates"
    readonly property var definition: root.domainDefinition(root.domain)

    signal snapshotRequested()
    signal invalidated()
    property var cycle: Cycle.create()
    property bool visible: false
    property bool monitorOwned: false
    property bool stopping: false
    property bool restartPending: false
    property bool ready: false
    property bool failed: false
    property bool unresolved: false
    property string phase: "idle"
    readonly property bool fresh: root.definition !== null && root.visible && root.ready && !root.failed && !root.unresolved && root.phase === "idle"
    readonly property string detail: !root.visible ? "" : root.failed
        ? "Live " + root.domainLabel() + " monitoring is unavailable. Reload status to retry; readable state is preserved."
        : root.unresolved
        ? "The " + root.domainLabel() + " state changed during the settling read. Reload status to reconcile it; automatic rereads are paused."
        : !root.ready ? "Connecting to " + root.domainLabel() + " change notifications..." : ""

    function domainDefinition(value) {
        if (value === "updates") return { action: "watch-updates", args: [], prefix: "update-event", label: "update" };
        if (value === "time") return { action: "watch-regional", args: ["time"], prefix: "regional-event", label: "time" };
        if (value === "locale") return { action: "watch-regional", args: ["locale"], prefix: "regional-event", label: "locale" };
        if (value === "accounts") return { action: "watch-accounts", args: [], prefix: "accounts-event", label: "account" };
        if (value === "printers") return { action: "watch-units", args: ["printers"], prefix: "units-event", label: "printer" };
        return null;
    }

    function domainLabel() { return root.definition === null ? "unsupported service" : root.definition.label; }

    onDomainChanged: {
        // Neither an old read token nor a failed-monitor fallback can certify
        // a replacement domain before its own subscription handshake.
        if (!root.visible) return;
        root.ready = false;
        root.failed = false;
        Cycle.begin(root.cycle);
        root.publish();
        root.invalidated();
        root.stopMonitor();
        root.startMonitor();
    }

    function publish() {
        root.unresolved = root.cycle.unresolved;
        root.phase = root.cycle.phase;
    }

    function requestPending() {
        if (root.visible && (root.ready || root.failed) && Cycle.pending(root.cycle))
            root.snapshotRequested();
    }

    function open() {
        root.visible = true;
        Cycle.begin(root.cycle);
        root.publish();
        root.startMonitor();
    }

    function close() {
        root.visible = false;
        root.restartPending = false;
        Cycle.close(root.cycle);
        root.publish();
        root.stopMonitor();
    }

    function refresh() {
        if (!root.visible) return;
        Cycle.begin(root.cycle);
        root.publish();
        if (!root.monitorOwned || root.stopping) root.startMonitor();
        root.requestPending();
    }

    function invalidate() {
        Cycle.invalidate(root.cycle);
        root.publish();
        root.invalidated();
        root.requestPending();
    }

    function canTake() {
        return root.visible && (root.ready || root.failed) && Cycle.pending(root.cycle);
    }

    function take() {
        if (!root.canTake()) return null;
        const token = Cycle.take(root.cycle);
        root.publish();
        return token;
    }

    function beforePublish(token) { Cycle.beforePublish(root.cycle, token); }

    function complete(token, successful) {
        Cycle.complete(root.cycle, token, successful);
        root.publish();
        // Process.runningChanged for the old snapshot follows its exit signal.
        Qt.callLater(root.requestPending);
    }

    function startMonitor() {
        if (!root.visible) return;
        if (root.monitorOwned) {
            if (root.stopping) {
                root.restartPending = true;
                // A new explicit cycle must wait for replacement subscriptions,
                // not consume the previous monitor's failed-read fallback.
                root.ready = false;
                root.failed = false;
            }
            return;
        }
        root.restartPending = false;
        root.ready = false;
        root.failed = false;
        root.stopping = false;
        const selected = root.domainDefinition(root.domain);
        if (selected === null) {
            root.failed = true;
            root.invalidated();
            root.requestPending();
            return;
        }
        // Deliberately NOT wrapped in checkedCommand or terminatingCheckedCommand:
        // both buffer the wrapped command's stdout to a temp file and only
        // `cat` it once the child exits, which is correct for a bounded
        // one-shot read but defeats live streaming entirely -- ready/changed
        // would only ever arrive as one batch at shutdown. helperCommand's
        // own script chain runs the real helper via `exec`, so this Process's
        // PID already *is* the helper (no intermediate command-substitution
        // fork to orphan), and monitor.signal() below reaches it directly.
        // See docs/SYNC-P4-DISCOVERY-EVENTS.md's "Correction, found during
        // implementation" note -- the doc's own terminatingCheckedCommand
        // instruction was wrong for this streaming case.
        monitor.command = Commands.systemManagementCommand(selected.action, selected.args);
        monitor.eventPrefix = selected.prefix;
        root.monitorOwned = true;
        setupDeadline.restart();
        monitor.running = true;
    }

    function stopMonitor() {
        root.ready = false;
        setupDeadline.stop();
        if (!root.monitorOwned || root.stopping) return;
        root.stopping = true;
        monitor.signal(15);
        stopDeadline.restart();
    }

    function failMonitor() {
        if (!root.monitorOwned || root.stopping) return;
        root.failed = true;
        root.invalidated();
        root.stopMonitor();
        root.requestPending();
    }

    function event(line) {
        if (!root.monitorOwned || root.stopping || !root.visible) return;
        if (line === monitor.eventPrefix + "\tready" && !root.ready) {
            setupDeadline.stop();
            root.ready = true;
            root.requestPending();
        } else if (line === monitor.eventPrefix + "\tchanged" && root.ready) root.invalidate();
        else root.failMonitor();
    }

    function finished() {
        if (!root.monitorOwned) return;
        const restart = root.restartPending;
        root.monitorOwned = false;
        root.ready = false;
        setupDeadline.stop();
        stopDeadline.stop();
        if (!root.visible) return;
        if (restart) Qt.callLater(root.startMonitor);
        else {
            root.failed = true;
            root.invalidated();
            root.requestPending();
        }
    }

    // Both intervals are milliseconds, not geometry -- Theme.dp() does not apply.
    Timer { id: setupDeadline; interval: 12000; repeat: false; onTriggered: root.failMonitor() }
    Timer { id: stopDeadline; interval: 1500; repeat: false; onTriggered: monitor.signal(9) }
    Process {
        id: monitor
        property string eventPrefix: ""
        stdout: SplitParser { onRead: line => root.event(line) }
        // onRunningChanged alone covers every exit path (normal or abnormal)
        // finished() is idempotent (guarded on monitorOwned), so this single
        // handler is enough -- a duplicate onExited handler here trips
        // quickshell-qmllint (QProcess::ExitStatus is not exposed to it) for
        // no behavioral benefit.
        onRunningChanged: { if (!running && root.monitorOwned) root.finished(); }
    }
}
