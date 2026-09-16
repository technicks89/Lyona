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
 * and this model re-reads only when told to, never per signal. Sync Phase 4
 * was the last read-only phase before the recovery journal (Sync Phase 5)
 * and confirmed mutation (Sync Phase 6, below).
 *
 * The helper is bounded (docs/SYNC-P2-UPDATE-SNAPSHOT.md), but this model is
 * the second line of defence: every record is re-validated against explicit
 * allowlists rather than passed through to the UI, a missing mandatory
 * record fails the whole snapshot instead of rendering a partial one, and a
 * snapshot without a trailing `complete\tsnapshot` is discarded whole.
 *
 * Sync Phase 6 (docs/SYNC-P6-UPDATE-EXECUTION.md) turns the journal into a
 * working execution owner: `active-operation`/`terminal-handoff` records
 * (from the helper's `build_managed_snapshot()`) report an in-progress or
 * unacknowledged-result operation so a Quickshell restart mid-update can
 * reattach via `watch-operation` rather than showing nothing.
 *
 * Sync Phase 7 (docs/SYNC-P7-OPERATION-SURFACE.md) adds the confirm/cancel
 * surface: `updateActionReason()`/`prepareUpdate()`/`confirmUpdate()`/
 * `discardUpdate()` own visible confirmation as a captured snapshot (the
 * generation, this model's own read counter, and the discovery cycle epoch
 * must all still match at confirm time, or the prompt invalidates itself
 * rather than dispatching a stale plan), and `operation` (a
 * `SystemOperationModel`) owns the actual process/journal-control lifecycle.
 * A `required` snapshot request (the operation model recovering evidence)
 * bypasses `settingsVisible` -- reusing `discoveryModel`'s existing
 * take/beforePublish/complete cycle, which already no-ops safely on a null
 * token when the pane is closed.
 */
Scope {
    id: root

    signal confirmationInvalidated()

    property bool settingsVisible: false
    property bool snapshotOwned: false
    property bool snapshotPending: false
    property bool requiredPending: false
    property bool snapshotRequired: false
    property bool snapshotAttempted: false
    property string snapshotState: "idle" // idle | loading | loaded | unavailable
    property string message: "System management has not been loaded"
    property string generation: ""
    property int requestGeneration: 0
    property var updateProvider: root.providerFallback("Update status has not been loaded")
    property var recoveryProvider: root.recoveryFallback("Recovery status has not been loaded")
    property var updateSummary: root.stateFallback("Update status has not been loaded")
    property var updateLastRefresh: root.stateFallback("Refresh history has not been loaded")
    property var updateRestart: root.stateFallback("Restart guidance has not been loaded")
    property var actions: []
    property var updates: []
    property var packageChanges: []
    property var nativeProviders: ({})
    property var nativeStates: ({})
    property var accounts: []
    property var repositories: []
    property var errors: []
    property var activeOperation: null
    property var terminalHandoff: null
    property var updateConfirmation: null
    property string confirmationMessage: ""
    property bool dispatchingUpdate: false

    readonly property bool busy: root.snapshotOwned
    readonly property int maxListRecords: 4096
    readonly property alias discovery: discoveryModel
    readonly property alias operation: operationModel
    readonly property string discoveryDetail: discoveryModel.detail

    readonly property var validStatus: ["available", "partial", "restricted", "unavailable", "unsupported"]
    readonly property var validActionStatus: ["available", "unavailable"]
    readonly property var validSeverity: ["unknown", "low", "enhancement", "normal", "bugfix", "important", "security", "critical"]
    readonly property var validInstallability: ["installable", "blocked"]
    readonly property var validRestart: ["none", "application", "session", "system", "security-session", "security-system", "unknown"]
    readonly property var validPlanAction: ["update", "install", "remove", "obsolete", "reinstall", "downgrade"]
    readonly property var validErrorCode: ["malformed", "timeout", "missing-provider", "permission-denied",
        "unsupported", "network", "repository", "conflict", "signature", "internal", "package", "canceled"]

    // Sync Phase 9 (docs/SYNC-P9-REGIONAL-MUTATION.md): protocol minor 1's
    // regional/accounts/printers/sources records. Four fixed owners, each
    // failing independently -- a malformed regional record must not blank
    // the accounts list, matching the helper's own per-owner build_native_
    // snapshot() isolation.
    readonly property var validNativeOwners: ["regional", "accounts", "printers", "sources"]
    readonly property var validNativeStateIds: ["timezone", "ntp-enabled", "ntp-synchronized",
        "locale", "accounts-count", "cups-service"]
    readonly property var validNativeActionIds: ["timezone-set", "ntp-set", "locale-set",
        "accounts-open", "password-open", "printers-open", "sources-open"]

    function nativeStateOwner(identifier) {
        if (identifier === "timezone" || identifier === "ntp-enabled"
                || identifier === "ntp-synchronized" || identifier === "locale") return "regional";
        if (identifier === "accounts-count") return "accounts";
        if (identifier === "cups-service") return "printers";
        return "";
    }

    function nativeActionOwner(actionId) {
        if (root.regionalActionKind(actionId).length > 0) return "regional";
        if (actionId === "accounts-open" || actionId === "password-open") return "accounts";
        if (actionId === "printers-open") return "printers";
        if (actionId === "sources-open") return "sources";
        return "";
    }

    function validNativeValue(identifier, status, value) {
        if (identifier === "accounts-count")
            return status === "available" ? /^(0|[1-9][0-9]*)$/.test(value) && Number(value) <= 256
                : value === "unknown";
        if (identifier === "cups-service")
            return status === "available" ? (value === "running" || value === "socket-ready" || value === "stopped")
                : value === "unknown";
        if (identifier === "ntp-enabled" || identifier === "ntp-synchronized")
            return status === "available" ? (value === "yes" || value === "no") : value === "unknown";
        // An explicit LANG= is readable unset configuration, not a malformed
        // regional provider. A replacement still requires its own fresh preview.
        if (identifier === "locale") return status === "available" || value === "unknown";
        return value.length > 0 && (status === "available" || value === "unknown");
    }

    function validOperationId(value) {
        return /^op-[0-9a-f]{32}$/.test(value);
    }

    function validOperationState(value) {
        return value === "pending" || value === "authorizing" || value === "running"
            || value === "cancel-requested";
    }

    function validPercent(value) {
        return value === "unknown" || (/^(0|[1-9][0-9]?)$/.test(value)) || value === "100";
    }

    function validGeneration(value) {
        return /^[0-9a-f]{64}$/.test(value);
    }

    function updateActionKind(actionId) {
        if (actionId === "updates-refresh") return "refresh";
        if (actionId === "updates-install-all") return "update";
        return "";
    }

    function regionalActionKind(actionId) {
        if (actionId === "timezone-set") return "timezone";
        if (actionId === "ntp-set") return "ntp";
        if (actionId === "locale-set") return "locale";
        return "";
    }

    function delegatedActionKind(actionId) {
        if (actionId === "accounts-open" || actionId === "password-open"
                || actionId === "printers-open" || actionId === "sources-open") return "delegate";
        return "";
    }

    // Kept as separate functions (mirroring the Python side's
    // JOURNAL_OPERATION_ACTION_KINDS entries) so an operation record can be
    // validated without assuming which family it belongs to.
    function operationActionKind(actionId) {
        const updateKind = root.updateActionKind(actionId);
        if (updateKind.length > 0) return updateKind;
        const regionalKind = root.regionalActionKind(actionId);
        if (regionalKind.length > 0) return regionalKind;
        return root.delegatedActionKind(actionId);
    }

    function updateActionReason(actionId) {
        if (actionId !== "updates-refresh" && actionId !== "updates-install-all")
            return "This update action is not supported.";
        if (!root.settingsVisible || root.dispatchingUpdate)
            return "Open System Settings to prepare an update action.";
        if (root.snapshotOwned || root.snapshotPending || root.requiredPending || !discoveryModel.fresh)
            return "Wait for fresh update discovery, or reload status to retry.";
        if (!root.validGeneration(root.generation) || root.recoveryProvider.status !== "available")
            return "Complete recovery evidence is required. Reload status to retry.";
        if (!operationModel.canStart)
            return "An operation or its recovery still owns the update workflow.";
        const action = root.actions.find(item => item.id === actionId);
        if (!action || action.status !== "available")
            return action && action.detail.length > 0 ? action.detail : "The provider did not offer this action.";
        if (actionId === "updates-install-all" && root.packageChanges.length === 0)
            return "No complete installable package-change preview is available.";
        return "";
    }

    // prepareUpdate()/confirmUpdate() capture the state the user is agreeing
    // to -- generation, this model's own read counter, and the discovery
    // cycle epoch -- rather than a flag. confirmUpdate() refuses to dispatch
    // unless all three still match, so a plan that changed underneath a
    // prompt the user has not yet acted on is never silently dispatched.
    function prepareUpdate(actionId) {
        const reason = root.updateActionReason(actionId);
        if (reason.length > 0) {
            root.confirmationMessage = reason;
            return false;
        }
        root.confirmationMessage = "";
        root.updateConfirmation = {
            actionId: actionId, generation: root.generation,
            requestGeneration: root.requestGeneration, epoch: discoveryModel.cycle.epoch,
            changes: actionId === "updates-install-all"
                ? JSON.parse(JSON.stringify(root.packageChanges)) : []
        };
        return true;
    }

    function discardUpdate() {
        root.updateConfirmation = null;
        root.confirmationMessage = "";
    }

    function confirmUpdate() {
        const pending = root.updateConfirmation;
        if (pending === null || root.dispatchingUpdate) return false;
        const reason = root.updateActionReason(pending.actionId);
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
        const started = operationModel.startUpdate(pending.actionId,
            pending.actionId === "updates-install-all" ? pending.generation : "");
        root.confirmationMessage = started ? "" : "Update state changed. Reload status and confirm again.";
        root.dispatchingUpdate = false;
        return started;
    }

    onConfirmationInvalidated: {
        if (root.updateConfirmation !== null)
            root.confirmationMessage = "Update state changed. Review a fresh preview and confirm again.";
        root.updateConfirmation = null;
    }

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
        root.nativeProviders = {};
        root.nativeStates = {};
        root.accounts = [];
        root.repositories = [];
        root.errors = [];
        root.activeOperation = null;
        root.terminalHandoff = null;
    }

    function openSettings() {
        root.settingsVisible = true;
        discoveryModel.open();
        root.refreshRecovery();
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.confirmationInvalidated();
        discoveryModel.close();
        root.snapshotPending = false;
        // A required fetch (recovering operation evidence) is not this
        // pane's to kill: it keeps running so operationModel can still
        // reattach to an in-progress or unacknowledged operation offscreen.
        if (!root.snapshotRequired && snapshotProcess.running) snapshotProcess.running = false;
    }

    function refresh() {
        if (!root.settingsVisible) return;
        discoveryModel.refresh();
        root.refreshRecovery();
    }

    // Drives operationModel's recovery snapshot the same way discoveryModel
    // drives the pane's own reads: reset the backoff, then ask again only if
    // the model was actually waiting on one (idle/observing/result states
    // already have everything they need and must not restart recovery).
    function refreshRecovery() {
        const requiredRecovery = operationModel.waitingSnapshot || operationModel.blocked
            || operationModel.state === "recovering";
        operationModel.resetRecovery();
        if (requiredRecovery) operationModel.requestSnapshot();
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
    // `required` (Sync Phase 7) is operationModel asking for recovery
    // evidence: it bypasses discoveryModel.canTake()'s settingsVisible tie,
    // but still hands discoveryModel.take() the request -- take() itself
    // returns null while the pane is closed, and a null token is a safe
    // no-op through beforePublish/complete (SystemDiscoveryCycle.js's
    // owns()), so the read still runs without joining the visible cycle.
    function requestSnapshot(required) {
        if (root.snapshotOwned || snapshotProcess.running) {
            root.snapshotPending = root.snapshotPending || !required;
            root.requiredPending = root.requiredPending || !!required;
            return;
        }
        required = required || root.requiredPending;
        if (!required && !discoveryModel.canTake()) return;
        root.snapshotPending = false;
        root.requiredPending = false;
        root.snapshotOwned = true;
        root.snapshotAttempted = false;
        root.snapshotRequired = required;
        root.requestGeneration++;
        root.confirmationInvalidated();
        snapshotProcess.cycleToken = discoveryModel.take();
        root.snapshotState = "loading";
        root.message = "Loading system update status...";
        snapshotProcess.command = Commands.checkedCommand(Commands.systemManagementCommand("snapshot", []));
        snapshotProcess.running = true;
    }

    // Cycle bookkeeping, plus handing the parsed operation state to
    // operationModel -- ownership and the next launch are handled
    // separately, gated on the process's real exit (see requestSnapshot).
    function finishSnapshot(successful) {
        discoveryModel.beforePublish(snapshotProcess.cycleToken);
        if (successful) operationModel.acceptSnapshot(root.activeOperation, root.terminalHandoff);
        else operationModel.snapshotFailed();
        discoveryModel.complete(snapshotProcess.cycleToken, successful);
        snapshotProcess.cycleToken = null;
        root.snapshotRequired = false;
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
        if (header.length !== 3 || header[0] !== "system-management-protocol" || header[1] !== "1"
                || (header[2] !== "0" && header[2] !== "1")) {
            root.resetToFallback("System management provider returned an unsupported protocol");
            return false;
        }
        const minor = Number(header[2]);
        if (lines[lines.length - 1] !== "complete\tsnapshot") {
            root.resetToFallback("System management provider returned a truncated snapshot");
            return false;
        }

        let generation = "";
        let updateProvider = null, recoveryProvider = null;
        let updateSummary = null, updateLastRefresh = null, updateRestart = null;
        let activeOperation = null, terminalHandoff = null;
        const actions = [];
        const updates = [];
        const packageChanges = [];
        const errors = [];
        const seenUpdateIds = {};
        const seenChangeIds = {};
        // Sync Phase 9: minor 1's four native owners each fail independently
        // -- a malformed/incomplete owner is marked invalid and falls back,
        // never rejecting the whole snapshot (the update domain above keeps
        // its existing all-or-nothing strictness, untouched).
        const nativeProviders = {};
        const nativeStates = {};
        const nativeActions = {};
        const nativeInvalid = {};
        const accountsList = [];
        const repositoriesList = [];
        const seenAccountIds = {};
        const seenRepositoryIds = {};

        for (let index = 1; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            const kind = fields[0];

            if (kind === "snapshot-generation") {
                if (fields.length !== 2 || !root.validGeneration(fields[1])) {
                    root.resetToFallback("System management provider returned a malformed generation");
                    return false;
                }
                generation = fields[1];
            } else if (kind === "provider") {
                if (minor === 1 && fields.length >= 2 && root.validNativeOwners.indexOf(fields[1]) >= 0) {
                    if (nativeProviders[fields[1]] !== undefined) {
                        root.resetToFallback("System management provider repeated a provider record");
                        return false;
                    }
                    if (fields.length !== 6 || root.validStatus.indexOf(fields[2]) < 0 || fields[3] !== "delegated") {
                        nativeInvalid[fields[1]] = true;
                        nativeProviders[fields[1]] = null;
                    } else nativeProviders[fields[1]] = { "status": fields[2], "class": fields[3],
                        "owner": fields[4], "detail": fields[5] };
                    continue;
                }
                if (fields.length !== 6 || root.validStatus.indexOf(fields[2]) < 0
                        || fields[3].length === 0 || fields[4].length === 0) {
                    root.resetToFallback("System management provider returned a malformed provider record");
                    return false;
                }
                const record = { "status": fields[2], "class": fields[3], "owner": fields[4], "detail": fields[5] };
                if (fields[1] === "updates") updateProvider = record;
                else if (fields[1] === "recovery") recoveryProvider = record;
            } else if (kind === "state") {
                const nativeOwner = fields.length >= 2 ? root.nativeStateOwner(fields[1]) : "";
                if (minor === 1 && nativeOwner.length > 0) {
                    if (nativeStates[fields[1]] !== undefined) {
                        root.resetToFallback("System management provider repeated a state record");
                        return false;
                    }
                    if (fields.length !== 5 || root.validStatus.indexOf(fields[2]) < 0
                            || !root.validNativeValue(fields[1], fields[2], fields[3])) {
                        nativeInvalid[nativeOwner] = true;
                        nativeStates[fields[1]] = null;
                    } else nativeStates[fields[1]] = { "status": fields[2], "value": fields[3], "detail": fields[4] };
                    continue;
                }
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
                const nativeOwner = fields.length >= 2 ? root.nativeActionOwner(fields[1]) : "";
                if (minor === 1 && nativeOwner.length > 0) {
                    if (nativeActions[fields[1]] !== undefined) {
                        root.resetToFallback("System management provider repeated an action record");
                        return false;
                    }
                    if (fields.length !== 7 || root.validActionStatus.indexOf(fields[2]) < 0
                            || fields[3] !== "delegated" || fields[4] !== nativeOwner) {
                        nativeInvalid[nativeOwner] = true;
                        nativeActions[fields[1]] = null;
                    } else nativeActions[fields[1]] = { "id": fields[1], "status": fields[2], "class": fields[3],
                        "owner": fields[4], "label": fields[5], "detail": fields[6] };
                    continue;
                }
                if (fields.length !== 7 || root.validActionStatus.indexOf(fields[2]) < 0) {
                    root.resetToFallback("System management provider returned a malformed action record");
                    return false;
                }
                actions.push({ "id": fields[1], "status": fields[2], "class": fields[3],
                    "owner": fields[4], "label": fields[5], "detail": fields[6] });
            } else if (kind === "account" || kind === "repository") {
                if (minor !== 1) {
                    root.resetToFallback("System management provider returned an inactive list owner");
                    return false;
                }
                const isAccount = kind === "account";
                const owner = isAccount ? "accounts" : "sources";
                const seen = isAccount ? seenAccountIds : seenRepositoryIds;
                if (fields.length < 2 || fields[1].length === 0) {
                    root.resetToFallback("System management provider returned a list without an identity");
                    return false;
                }
                if (seen[fields[1]] !== undefined) {
                    root.resetToFallback("System management provider repeated a list identity");
                    return false;
                }
                seen[fields[1]] = true;
                const list = isAccount ? accountsList : repositoriesList;
                if (list.length >= (isAccount ? 256 : root.maxListRecords)) {
                    nativeInvalid[owner] = true;
                    continue;
                }
                if (isAccount) {
                    if (fields.length !== 5 || (fields[2] !== "current" && fields[2] !== "other") || fields[4].length === 0) {
                        nativeInvalid[owner] = true;
                        continue;
                    }
                    accountsList.push({ "id": fields[1], "scope": fields[2], "displayName": fields[3], "loginName": fields[4] });
                } else {
                    if (fields.length !== 4 || (fields[2] !== "enabled" && fields[2] !== "disabled")) {
                        nativeInvalid[owner] = true;
                        continue;
                    }
                    repositoriesList.push({ "id": fields[1], "state": fields[2], "description": fields[3] });
                }
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
            } else if (kind === "active-operation") {
                if (activeOperation !== null || terminalHandoff !== null) {
                    root.resetToFallback("System management provider repeated snapshot operation state");
                    return false;
                }
                if (fields.length !== 8 || !root.validOperationId(fields[1])
                        || root.operationActionKind(fields[2]).length === 0
                        || root.operationActionKind(fields[2]) !== fields[3]
                        || !root.validOperationState(fields[4])
                        || !root.validPercent(fields[5])
                        || (fields[6] !== "yes" && fields[6] !== "no")) {
                    root.resetToFallback("System management provider returned an invalid active operation");
                    return false;
                }
                activeOperation = { "id": fields[1], "actionId": fields[2], "kind": fields[3],
                    "state": fields[4], "percent": fields[5], "cancelable": fields[6] === "yes",
                    "detail": fields[7] };
            } else if (kind === "terminal-handoff") {
                if (activeOperation !== null || terminalHandoff !== null) {
                    root.resetToFallback("System management provider repeated snapshot operation state");
                    return false;
                }
                if (fields.length !== 4 || !root.validOperationId(fields[1])
                        || root.operationActionKind(fields[2]).length === 0
                        || root.operationActionKind(fields[2]) !== fields[3]) {
                    root.resetToFallback("System management provider returned an invalid terminal handoff");
                    return false;
                }
                terminalHandoff = { "id": fields[1], "actionId": fields[2], "kind": fields[3] };
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

        let publishedProviders = {};
        let publishedStates = {};
        if (minor === 1) {
            for (let i = 0; i < root.validNativeOwners.length; i++) {
                if (nativeProviders[root.validNativeOwners[i]] === undefined) nativeInvalid[root.validNativeOwners[i]] = true;
            }
            for (let i = 0; i < root.validNativeStateIds.length; i++) {
                const identifier = root.validNativeStateIds[i];
                if (nativeStates[identifier] === undefined) nativeInvalid[root.nativeStateOwner(identifier)] = true;
            }
            for (let i = 0; i < root.validNativeActionIds.length; i++) {
                if (nativeActions[root.validNativeActionIds[i]] === undefined)
                    nativeInvalid[root.nativeActionOwner(root.validNativeActionIds[i])] = true;
            }
            if (!nativeInvalid.accounts) {
                const count = nativeStates["accounts-count"];
                const currentCount = accountsList.filter(function(item) { return item.scope === "current"; }).length;
                if ((count.status === "available" && Number(count.value) !== accountsList.length)
                        || (count.status !== "available" && count.status !== "partial" && accountsList.length > 0)
                        || currentCount > 1) nativeInvalid.accounts = true;
            }
            if (!nativeInvalid.sources && repositoriesList.length > 0
                    && nativeProviders.sources.status !== "available" && nativeProviders.sources.status !== "partial")
                nativeInvalid.sources = true;
            for (let i = 0; i < root.validNativeOwners.length; i++) {
                const owner = root.validNativeOwners[i];
                if (nativeInvalid[owner]) {
                    const detail = "System management provider returned malformed " + owner + " state";
                    publishedProviders[owner] = { "status": "partial", "class": "delegated", "owner": "", "detail": detail };
                    errors.push({ "capability": owner, "code": "malformed", "detail": detail });
                } else publishedProviders[owner] = nativeProviders[owner];
            }
            for (let i = 0; i < root.validNativeStateIds.length; i++) {
                const identifier = root.validNativeStateIds[i];
                const owner = root.nativeStateOwner(identifier);
                publishedStates[identifier] = nativeInvalid[owner]
                    ? { "status": "partial", "value": "unknown", "detail": publishedProviders[owner].detail }
                    : nativeStates[identifier];
            }
            for (let i = 0; i < root.validNativeActionIds.length; i++) {
                const actionId = root.validNativeActionIds[i];
                if (!nativeInvalid[root.nativeActionOwner(actionId)]) actions.push(nativeActions[actionId]);
            }
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
        root.nativeProviders = publishedProviders;
        root.nativeStates = publishedStates;
        root.accounts = minor === 1 && !nativeInvalid.accounts ? accountsList : [];
        root.repositories = minor === 1 && !nativeInvalid.sources ? repositoriesList : [];
        root.errors = errors;
        // A snapshot race can still name an identity operationModel already
        // acknowledged (its own control process exits before this read's
        // journal state settles) -- never resurrect it here.
        root.activeOperation = activeOperation !== null && operationModel.wasAcknowledged(activeOperation.id)
            ? null : activeOperation;
        root.terminalHandoff = terminalHandoff !== null && operationModel.wasAcknowledged(terminalHandoff.id)
            ? null : terminalHandoff;
        // A malformed native domain degrades only its own root.nativeProviders
        // entry (status "partial") -- root.snapshotState stays keyed to the
        // update domain's own success, matching every existing consumer
        // (e.g. SystemSettingsPane.qml's "No pending Arch updates" gate).
        root.snapshotState = "loaded";
        root.message = updates.length + " update" + (updates.length === 1 ? "" : "s") + " found";
        return true;
    }

    // Reads recovery evidence for an in-progress or unacknowledged operation
    // even before Settings is ever opened, so a Quickshell restart mid-update
    // can reattach on its own. Confirmed dispatch stays owned by root/UI --
    // this model only accepts fixed update commands (startUpdate).
    Component.onCompleted: Qt.callLater(function() { operationModel.requestSnapshot(); })

    SystemUpdateDiscovery {
        id: discoveryModel
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: root.confirmationInvalidated()
    }

    SystemOperationModel {
        id: operationModel
        onDiscoveryInvalidated: discoveryModel.invalidate()
        onSnapshotRequested: root.requestSnapshot(true)
        onAcknowledged: operationId => {
            if (root.terminalHandoff !== null && root.terminalHandoff.id === operationId)
                root.terminalHandoff = null;
            if (root.activeOperation !== null && root.activeOperation.id === operationId)
                root.activeOperation = null;
            discoveryModel.invalidate();
        }
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
                if (root.requiredPending) root.requestSnapshot(true);
                else if (root.snapshotPending && root.settingsVisible) root.requestSnapshot(false);
            });
        }
    }
}
