import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

/*
 * Bounded, read-only Arch update snapshot from dwm-system-management.
 *
 * Sync Phase 3 (docs/SYNC-P3-SYSTEM-PANE.md) added the on-demand `snapshot`
 * fetch, gated by settingsVisible the same way every other Settings-only
 * model in this shell already is -- never polled, and closing the section
 * stops any fetch this model owns. Sync Phase 4
 * (docs/SYNC-P4-DISCOVERY-EVENTS.md) replaces "click Reload and hope" with
 * a bounded live subscription (SystemUpdateDiscovery) that coalesces reads:
 * while the pane is open, the helper watches PackageKit's manager signals
 * and this model re-reads only when told to, never per signal. This is the
 * last read-only Sync Phase -- mutation and the recovery journal are later.
 *
 * The helper is bounded (docs/SYNC-P2-UPDATE-SNAPSHOT.md), but this model is
 * the second line of defence: every record is re-validated against explicit
 * allowlists rather than passed through to the UI, a missing mandatory
 * record fails the whole snapshot instead of rendering a partial one, and a
 * snapshot without a trailing `complete\tsnapshot` is discarded whole.
 */
Scope {
    id: root

    property bool settingsVisible: false
    property bool snapshotOwned: false
    property bool snapshotPending: false
    property bool snapshotAttempted: false
    property string snapshotState: "idle" // idle | loading | loaded | unavailable
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

    readonly property bool busy: root.snapshotOwned
    readonly property int maxListRecords: 4096
    readonly property alias discovery: discoveryModel
    readonly property string discoveryDetail: discoveryModel.detail

    readonly property var validStatus: ["available", "partial", "restricted", "unavailable", "unsupported"]
    readonly property var validActionStatus: ["available", "unavailable"]
    readonly property var validSeverity: ["unknown", "low", "enhancement", "normal", "bugfix", "important", "security", "critical"]
    readonly property var validInstallability: ["installable", "blocked"]
    readonly property var validRestart: ["none", "application", "session", "system", "security-session", "security-system", "unknown"]
    readonly property var validPlanAction: ["update", "install", "remove", "obsolete", "reinstall", "downgrade"]
    readonly property var validErrorCode: ["malformed", "timeout", "missing-provider", "permission-denied",
        "unsupported", "network", "repository", "conflict", "signature", "internal", "package", "canceled"]

    function providerFallback(detail) {
        return { "status": "unavailable", "class": "delegated", "owner": "", "detail": detail };
    }

    function recoveryFallback(detail) {
        return { "status": "unsupported", "class": "user-session", "owner": "dwm-system-management", "detail": detail };
    }

    function stateFallback(detail) {
        return { "status": "unavailable", "value": "unknown", "detail": detail };
    }

    function resetToFallback(reason) {
        root.snapshotState = "unavailable";
        root.message = reason;
        root.generation = "";
        root.updateProvider = root.providerFallback(reason);
        root.recoveryProvider = root.recoveryFallback(reason);
        root.updateSummary = root.stateFallback(reason);
        root.updateLastRefresh = root.stateFallback(reason);
        root.updateRestart = root.stateFallback(reason);
        root.actions = [];
        root.updates = [];
        root.packageChanges = [];
        root.errors = [];
    }

    function openSettings() {
        root.settingsVisible = true;
        discoveryModel.open();
    }

    function closeSettings() {
        root.settingsVisible = false;
        discoveryModel.close();
        root.snapshotPending = false;
        if (snapshotProcess.running) snapshotProcess.running = false;
    }

    function refresh() {
        if (!root.settingsVisible) return;
        discoveryModel.refresh();
    }

    // The single entry point for starting a fetch, regardless of whether the
    // trigger was a user-initiated refresh or a live discovery signal: only
    // one snapshotProcess runs at a time, and every launch is bracketed by
    // discoveryModel.take()/beforePublish()/complete() so a signal arriving
    // mid-read schedules exactly one follow-up settling read rather than a
    // read per signal.
    //
    // Guarded on snapshotProcess.running as well as snapshotOwned:
    // StdioCollector.onStreamFinished fires before Quickshell.Io.Process
    // updates `running` to false, and Qt.callLater does not guarantee it
    // runs after that transition either. A queued relaunch (or any other
    // caller) can therefore reach this function while the previous process
    // has not actually exited yet -- reassigning `running` to `true` while
    // it is already `true` is a no-op, silently dropping the new read. Both
    // snapshotOwned and the relaunch itself are cleared/scheduled only from
    // onRunningChanged's real not-running transition below, never from
    // finishSnapshot, so this guard should never trip in practice; it stays
    // as the actual authority a caller cannot get out of sync with.
    function requestSnapshot() {
        if (root.snapshotOwned || snapshotProcess.running) {
            root.snapshotPending = true;
            return;
        }
        if (!discoveryModel.canTake()) return;
        root.snapshotPending = false;
        root.snapshotOwned = true;
        root.snapshotAttempted = false;
        snapshotProcess.cycleToken = discoveryModel.take();
        root.snapshotState = "loading";
        root.message = "Loading system update status...";
        snapshotProcess.command = Commands.checkedCommand(Commands.systemManagementCommand("snapshot", []));
        snapshotProcess.running = true;
    }

    // Cycle bookkeeping only -- ownership and the next launch are handled
    // separately, gated on the process's real exit (see requestSnapshot).
    function finishSnapshot(successful) {
        discoveryModel.beforePublish(snapshotProcess.cycleToken);
        discoveryModel.complete(snapshotProcess.cycleToken, successful);
        snapshotProcess.cycleToken = null;
    }

    function parseSnapshot(text) {
        root.snapshotAttempted = true;

        const lines = text.length > 0 ? text.split("\n") : [];
        while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();

        if (lines.length === 0) {
            root.resetToFallback("System management provider returned no data");
            return false;
        }

        const header = lines[0].split("\t");
        if (header.length !== 3 || header[0] !== "system-management-protocol" || header[1] !== "1") {
            root.resetToFallback("System management provider returned an unsupported protocol");
            return false;
        }
        if (lines[lines.length - 1] !== "complete\tsnapshot") {
            root.resetToFallback("System management provider returned a truncated snapshot");
            return false;
        }

        let generation = "";
        let updateProvider = null, recoveryProvider = null;
        let updateSummary = null, updateLastRefresh = null, updateRestart = null;
        const actions = [];
        const updates = [];
        const packageChanges = [];
        const errors = [];
        const seenUpdateIds = {};
        const seenChangeIds = {};

        for (let index = 1; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            const kind = fields[0];

            if (kind === "snapshot-generation") {
                if (fields.length !== 2 || !/^[0-9a-f]{64}$/.test(fields[1])) {
                    root.resetToFallback("System management provider returned a malformed generation");
                    return false;
                }
                generation = fields[1];
            } else if (kind === "provider") {
                if (fields.length !== 6 || root.validStatus.indexOf(fields[2]) < 0
                        || fields[3].length === 0 || fields[4].length === 0) {
                    root.resetToFallback("System management provider returned a malformed provider record");
                    return false;
                }
                const record = { "status": fields[2], "class": fields[3], "owner": fields[4], "detail": fields[5] };
                if (fields[1] === "updates") updateProvider = record;
                else if (fields[1] === "recovery") recoveryProvider = record;
            } else if (kind === "state") {
                if (fields.length !== 5 || root.validStatus.indexOf(fields[2]) < 0) {
                    root.resetToFallback("System management provider returned a malformed state record");
                    return false;
                }
                let valueOk = true;
                if (fields[1] === "update-restart") valueOk = root.validRestart.indexOf(fields[3]) >= 0;
                else if (fields[1] === "update-summary" || fields[1] === "update-last-refresh")
                    valueOk = fields[3] === "unknown" || /^[0-9]+$/.test(fields[3]);
                if (!valueOk) {
                    root.resetToFallback("System management provider returned a malformed state value");
                    return false;
                }
                const record = { "status": fields[2], "value": fields[3], "detail": fields[4] };
                if (fields[1] === "update-summary") updateSummary = record;
                else if (fields[1] === "update-last-refresh") updateLastRefresh = record;
                else if (fields[1] === "update-restart") updateRestart = record;
            } else if (kind === "action") {
                if (fields.length !== 7 || root.validActionStatus.indexOf(fields[2]) < 0) {
                    root.resetToFallback("System management provider returned a malformed action record");
                    return false;
                }
                actions.push({ "id": fields[1], "status": fields[2], "class": fields[3],
                    "owner": fields[4], "label": fields[5], "detail": fields[6] });
            } else if (kind === "update") {
                if (fields.length !== 7 || root.validSeverity.indexOf(fields[2]) < 0
                        || root.validInstallability.indexOf(fields[3]) < 0
                        || fields[1].length === 0 || seenUpdateIds[fields[1]]) {
                    root.resetToFallback("System management provider returned a malformed update record");
                    return false;
                }
                if (updates.length >= root.maxListRecords) {
                    root.resetToFallback("System management provider returned too many update records");
                    return false;
                }
                seenUpdateIds[fields[1]] = true;
                updates.push({ "packageId": fields[1], "severity": fields[2], "installability": fields[3],
                    "name": fields[4], "version": fields[5], "summary": fields[6] });
            } else if (kind === "package-change") {
                if (fields.length !== 6 || root.validPlanAction.indexOf(fields[2]) < 0
                        || fields[1].length === 0 || seenChangeIds[fields[1]]) {
                    root.resetToFallback("System management provider returned a malformed package-change record");
                    return false;
                }
                if (packageChanges.length >= root.maxListRecords) {
                    root.resetToFallback("System management provider returned too many package-change records");
                    return false;
                }
                seenChangeIds[fields[1]] = true;
                packageChanges.push({ "packageId": fields[1], "action": fields[2], "name": fields[3],
                    "version": fields[4], "summary": fields[5] });
            } else if (kind === "error") {
                if (fields.length !== 4 || root.validErrorCode.indexOf(fields[2]) < 0) {
                    root.resetToFallback("System management provider returned a malformed error record");
                    return false;
                }
                errors.push({ "capability": fields[1], "code": fields[2], "detail": fields[3] });
            }
            // Unknown record kinds are ignored: a later Sync Phase's protocol
            // minor adds new record types this model does not parse yet.
        }

        if (updateProvider === null || recoveryProvider === null || updateSummary === null
                || updateLastRefresh === null || updateRestart === null) {
            root.resetToFallback("System management provider omitted a mandatory record");
            return false;
        }
        const actionIds = actions.map(function(action) { return action.id; });
        if (actionIds.indexOf("updates-refresh") < 0 || actionIds.indexOf("updates-install-all") < 0
                || actionIds.indexOf("updates-cancel") < 0) {
            root.resetToFallback("System management provider omitted a mandatory action");
            return false;
        }

        root.generation = generation;
        root.updateProvider = updateProvider;
        root.recoveryProvider = recoveryProvider;
        root.updateSummary = updateSummary;
        root.updateLastRefresh = updateLastRefresh;
        root.updateRestart = updateRestart;
        root.actions = actions;
        root.updates = updates;
        root.packageChanges = packageChanges;
        root.errors = errors;
        root.snapshotState = "loaded";
        root.message = updates.length + " update" + (updates.length === 1 ? "" : "s") + " found";
        return true;
    }

    SystemUpdateDiscovery {
        id: discoveryModel
        onSnapshotRequested: root.requestSnapshot()
    }

    Process {
        id: snapshotProcess
        property var cycleToken: null
        running: false
        stdout: StdioCollector { onStreamFinished: root.finishSnapshot(root.parseSnapshot(this.text)) }
        stderr: StdioCollector { id: snapshotError }
        onRunningChanged: if (!running) {
            if (!root.snapshotAttempted) {
                root.resetToFallback(snapshotError.text.trim().length > 0
                    ? snapshotError.text.trim() : "System management provider did not return a result");
                root.finishSnapshot(false);
            }
            // The process is now confirmed exited -- only here is it safe to
            // free ownership and consider relaunching. Queueing the relaunch
            // still matters (this handler runs inside the same exit
            // notification a fresh Process.running assignment would race
            // against), but gating it behind a real `!running` observation
            // (rather than firing from finishSnapshot's onStreamFinished,
            // which can run first) is what actually closes the race.
            root.snapshotOwned = false;
            Qt.callLater(function() {
                if (root.snapshotPending && root.settingsVisible) root.requestSnapshot();
            });
        }
    }
}
