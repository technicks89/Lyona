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
 *
 * Sync Sprint 2 S2-05 (docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md), ported from
 * upstream's 177e3c3/b19fb90 (#286): "storage" (watch-mounts, a bare
 * mount-monitor-ready/mount-change stream with its own shorter deadlines) and
 * "security" (watch-units security, reusing the units-event/firewalld prefix)
 * join the four existing domains. Each launch now gets its own dynamically
 * created monitor object (generation/serial-stamped identity and callbacks),
 * so a stale timer, parser line, or exit signal from a retired Process can
 * never be mistaken for a replacement one's, even within one pane cycle.
 */
Scope {
    id: root

    // Only these fixed provider commands are selectable; no caller-supplied argv.
    property string domain: "updates"
    readonly property var definition: root.domainDefinition(root.domain)

    signal snapshotRequested()
    signal invalidated()
    signal ownerArrived()
    property bool externalUnresolved: false
    property string externalDetail: ""
    property var cycle: Cycle.create()
    property bool visible: false
    property int generation: 0
    property var monitor: null
    property int launchSequence: 0
    property bool monitorOwned: false
    property bool stopping: false
    property bool restartPending: false
    property bool ready: false
    property bool failed: false
    property bool unresolved: false
    property string phase: "idle"
    readonly property bool fresh: root.definition !== null && root.visible && root.ready && !root.failed && !root.unresolved && !root.externalUnresolved && root.phase === "idle"
    readonly property string detail: !root.visible ? "" : root.failed
        ? "Live " + root.domainLabel() + " monitoring is unavailable. Reload status to retry; readable state is preserved."
        : root.unresolved
        ? "The " + root.domainLabel() + " state changed during the settling read. Reload status to reconcile it; automatic rereads are paused."
        : !root.ready ? "Connecting to " + root.domainLabel() + " change notifications..." : root.externalDetail

    function domainDefinition(value) {
        if (value === "updates") return { action: "watch-updates", args: [], prefix: "update-event", label: "update" };
        if (value === "time") return { action: "watch-time", args: [], prefix: "time-event", label: "time" };
        if (value === "locale") return { action: "watch-regional", args: ["locale"], prefix: "regional-event", label: "locale" };
        if (value === "accounts") return { action: "watch-accounts", args: [], prefix: "accounts-event", label: "account" };
        if (value === "printers") return { action: "watch-units", args: ["printers"], prefix: "units-event", label: "printer" };
        if (value === "security") return { action: "watch-units", args: ["security"], prefix: "units-event", label: "firewalld" };
        if (value === "storage") return { action: "watch-mounts", args: [], prefix: "mount-change", label: "storage" };
        return null;
    }

    function domainLabel() { return root.definition === null ? "unsupported service" : root.definition.label; }

    onDomainChanged: {
        // Neither an old read token nor a failed-monitor fallback can certify
        // a replacement domain before its own subscription handshake.
        if (!root.visible) return;
        root.generation++;
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
        if (root.visible) { root.refresh(); return; }
        root.generation++;
        root.visible = true;
        Cycle.begin(root.cycle);
        root.publish();
        root.startMonitor();
    }

    function close() {
        root.generation++;
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
        if (!Cycle.owns(root.cycle, token)) return;
        Cycle.complete(root.cycle, token, successful);
        root.publish();
        // Process.runningChanged for the old snapshot follows its exit signal.
        const generation = root.generation;
        Qt.callLater(function() {
            if (root.visible && root.generation === generation) root.requestPending();
        });
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
        const identity = Object.freeze({ generation: root.generation, serial: ++root.launchSequence,
            storage: root.domain === "storage", prefix: selected.prefix });
        const owner = monitorComponent.createObject(root, { identity: identity,
            callbacks: root.monitorCallbacks(identity),
            command: Commands.systemManagementCommand(selected.action, selected.args) });
        if (owner === null) {
            root.failed = true;
            root.invalidated();
            root.requestPending();
            return;
        }
        root.monitor = owner;
        root.monitorOwned = true;
        owner.start();
    }

    // Capture primitives once per launch. Old parser, timer and exit deliveries
    // must not acquire the identity of a replacement Process, even in one pane cycle.
    function monitorCallbacks(identity) {
        const generation = identity.generation;
        const serial = identity.serial;
        return Object.freeze({
            line: line => root.event(line, generation, serial),
            setup: () => root.setupExpired(generation, serial),
            stop: () => root.stopExpired(generation, serial),
            finish: () => root.finished(serial)
        });
    }

    function ownsMonitor(serial) {
        return root.monitorOwned && root.monitor !== null
            && (serial === undefined || serial === root.monitor.identity.serial);
    }

    function stopMonitor() {
        root.ready = false;
        if (root.monitor !== null) root.monitor.stopSetup();
        if (!root.monitorOwned || root.stopping) return;
        root.stopping = true;
        root.monitor.stop();
    }

    function setupExpired(generation, serial) {
        if (root.ownsMonitor(serial) && root.visible && generation === root.generation
            && generation === root.monitor.identity.generation) root.failMonitor();
    }

    function stopExpired(generation, serial) {
        if (root.ownsMonitor(serial) && root.stopping && generation === root.monitor.identity.generation)
            root.monitor.signal(9);
    }

    function failMonitor() {
        if (!root.monitorOwned || root.stopping) return;
        root.failed = true;
        root.invalidated();
        root.stopMonitor();
        root.requestPending();
    }

    function event(line, generation, serial) {
        if (!root.ownsMonitor(serial) || root.stopping || !root.visible) return;
        if (generation === undefined) generation = root.monitor.identity.generation;
        if (generation !== root.generation) return;
        const readyLine = root.monitor.identity.storage ? "mount-monitor-ready" : root.monitor.identity.prefix + "\tready";
        if (line === readyLine && !root.ready) {
            root.monitor.stopSetup();
            root.ready = true;
            root.requestPending();
        } else if (root.monitor.identity.storage && root.ready && /^mount-change\t(mount|umount|move|remount)$/.test(line)) root.invalidate();
        else if (!root.monitor.identity.storage && line === root.monitor.identity.prefix + "\tchanged" && root.ready) root.invalidate();
        else if (root.domain === "time" && line === root.monitor.identity.prefix + "\towner-arrived" && root.ready) root.ownerArrived();
        else root.failMonitor();
    }

    function finished(serial) {
        if (!root.ownsMonitor(serial)) return;
        const retired = root.monitor;
        const retiredSerial = retired.identity.serial;
        const restart = root.restartPending;
        root.monitor = null;
        root.monitorOwned = false;
        root.restartPending = false;
        root.ready = false;
        retired.clearDeadlines();
        retired.destroy();
        if (!root.visible) return;
        if (restart) {
            const generation = root.generation;
            Qt.callLater(function() {
                if (root.visible && root.generation === generation
                    && root.launchSequence === retiredSerial && !root.monitorOwned) root.startMonitor();
            });
        } else {
            root.failed = true;
            root.invalidated();
            root.requestPending();
        }
    }

    Component {
        id: monitorComponent
        Scope {
            id: owner
            required property var identity
            required property var callbacks
            property alias command: process.command
            function start() { setupDeadline.restart(); process.running = true; }
            function stopSetup() { setupDeadline.stop(); }
            function stop() { setupDeadline.stop(); stopDeadline.restart(); process.signal(15); }
            function signal(number) { process.signal(number); }
            function clearDeadlines() { setupDeadline.stop(); stopDeadline.stop(); }
            // Both intervals are milliseconds, not geometry -- Theme.dp() does
            // not apply. Storage (watch-mounts) has no idle-poll fallback and
            // a bare readiness line, so it gets shorter deadlines than the
            // remaining watch-* domains.
            Timer {
                id: setupDeadline
                interval: owner.identity.storage ? 3000 : 12000
                repeat: false
                onTriggered: owner.callbacks.setup()
            }
            Timer {
                id: stopDeadline
                interval: owner.identity.storage ? 2000 : 1500
                repeat: false
                onTriggered: owner.callbacks.stop()
            }
            Process {
                id: process
                stdout: SplitParser { onRead: line => owner.callbacks.line(line) }
                // onRunningChanged alone covers every exit path (normal or
                // abnormal); a duplicate onExited handler here trips
                // quickshell-qmllint (QProcess::ExitStatus is not exposed to
                // it) for no behavioral benefit.
                onRunningChanged: { if (!running) owner.callbacks.finish(); }
            }
        }
    }
}
