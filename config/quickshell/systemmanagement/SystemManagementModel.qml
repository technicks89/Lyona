import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemInformationProtocol.js" as Information

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

    readonly property bool initialLoading: root.settingsVisible && (!root.discoveryReady()
        || root.snapshotOwned || root.snapshotPending || root.requiredPending)

    signal confirmationInvalidated()
    signal healthOpened()
    property var healthModel: null
    property var targetScreen: null

    property bool settingsVisible: false
    property bool snapshotOwned: false
    property bool snapshotPending: false
    property bool requiredPending: false
    property bool snapshotRequired: false
    property bool snapshotAttempted: false
    // #261: true only while openSettings()/refresh() are looping over the
    // five discovery models -- requestSnapshot() defers to the pending
    // flags during that window so one batch of open/refresh signals results
    // in at most one fetch, not up to five.
    property bool discoveryBatch: false
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
    property var filesystems: []
    property bool filesystemsRetained: false
    property var errors: []
    property var activeOperation: null
    property var terminalHandoff: null
    property var updateConfirmation: null
    property string confirmationMessage: ""
    property bool dispatchingUpdate: false
    // Sync Sprint 1 S1-04 (#266): delegated actions (accounts-open/
    // password-open/printers-open/sources-open) now get their own visible
    // confirmation step, matching regional mutations rather than launching
    // immediately -- nativeConfirmation is { actionId, generation,
    // requestGeneration, epoch } captured at prepareDelegate() time and
    // rechecked at confirmDelegate() time, the same "captured plan, not a
    // flag" shape regionalModel's own confirmation ticket uses.
    property var nativeConfirmation: null
    property string nativeConfirmationMessage: ""
    property bool dispatchingNative: false

    readonly property bool busy: root.snapshotOwned
    readonly property int maxListRecords: 4096
    readonly property alias discovery: discoveryModel
    // #261: the four native domains each get their own SystemProviderDiscovery
    // instance -- domainDefinition() already supports all five ("updates" via
    // discoveryModel/SystemUpdateDiscovery, these four via the generic form).
    readonly property alias timeDiscovery: timeDiscoveryModel
    readonly property alias localeDiscovery: localeDiscoveryModel
    readonly property alias accountDiscovery: accountDiscoveryModel
    readonly property alias printerDiscovery: printerDiscoveryModel
    readonly property alias storageDiscovery: storageDiscoveryModel
    readonly property alias securityDiscovery: securityDiscoveryModel
    readonly property alias regional: regionalModel
    readonly property alias timeReconciliation: timeReconciliationModel
    readonly property alias operation: operationModel
    readonly property string discoveryDetail: discoveryModel.detail

    // Sync Sprint 2 S2-05 (#286): confirms opening the existing dwm-system-health
    // view -- the action itself is only ever offered when the helper's own
    // "health-open" record reports available, so this never has to duplicate
    // that decision, only route it.
    function openHealth() {
        const action = root.actions.find(item => item.id === "health-open");
        if (!root.settingsVisible || root.healthModel === null || !action || action.status !== "available") return false;
        root.healthModel.openOnScreen(root.targetScreen);
        root.healthOpened();
        return true;
    }

    // #261: every open discovery model, updates first (its own alias stays
    // the "primary" one existing callers keep using directly).
    function discoveryModels() {
        return [discoveryModel, timeDiscoveryModel, localeDiscoveryModel,
            accountDiscoveryModel, printerDiscoveryModel, storageDiscoveryModel, securityDiscoveryModel];
    }

    // True only once every domain has a subscription handshake (ready) or a
    // settled failure (failed) -- an optional background snapshot must not
    // fire while any domain is still connecting, or it would certify staler
    // native state as fresh before that domain's own monitor caught up.
    function discoveryReady() {
        return root.settingsVisible && root.discoveryModels().every(
            model => model.visible && (model.ready || model.failed));
    }

    // #262: maps one dispatched/watched/acknowledged action to the one
    // discovery domain it actually changed. operationModel.discoveryInvalidated
    // carries the actionId; a regional/delegated action must not go stale by
    // only ever invalidating the (unrelated) update discovery model.
    function invalidateActionDiscovery(action) {
        if (action === "timezone-set" || action === "ntp-set") timeDiscoveryModel.invalidate();
        else if (action === "locale-set") localeDiscoveryModel.invalidate();
        else if (action === "accounts-open" || action === "password-open") accountDiscoveryModel.invalidate();
        else if (action === "printers-open") printerDiscoveryModel.invalidate();
        else if (action === "sources-open" || action === "updates-refresh" || action === "updates-install-all")
            discoveryModel.invalidate();
    }

    // Maps one native state identifier to the discovery model whose
    // watch-* stream actually keeps it fresh, so nativeStateView() can
    // degrade a stale read without waiting on a full reload.
    function stateDiscovery(identifier) {
        if (identifier === "timezone" || identifier === "ntp-enabled" || identifier === "ntp-synchronized")
            return timeDiscoveryModel;
        if (identifier === "locale") return localeDiscoveryModel;
        if (identifier === "accounts-count") return accountDiscoveryModel;
        if (identifier === "cups-service") return printerDiscoveryModel;
        if (identifier === "filesystem-summary") return storageDiscoveryModel;
        if (identifier === "firewalld") return securityDiscoveryModel;
        return null;
    }

    // A parsed native state/provider record is only as fresh as its own
    // discovery monitor -- these two wrap root.nativeStates/root.nativeProviders
    // with that monitor's current health, appending its detail rather than
    // replacing the helper's own.
    function nativeStateView(identifier) {
        const state = root.nativeStates[identifier] || root.stateFallback("This state is unavailable");
        const monitor = root.stateDiscovery(identifier);
        if (!root.settingsVisible || monitor === null) return state;
        return { "status": state.status === "available" && (monitor.failed || monitor.unresolved || monitor.externalUnresolved) ? "partial" : state.status,
            "value": state.value, "detail": [state.detail, monitor.detail].filter(value => value.length > 0).join(" ") };
    }

    function nativeProviderView(owner) {
        const provider = root.nativeProviders[owner] || root.providerFallback("This provider is unavailable");
        const monitors = owner === "regional" ? [timeDiscoveryModel, localeDiscoveryModel]
            : owner === "accounts" ? [accountDiscoveryModel] : owner === "printers" ? [printerDiscoveryModel]
            : owner === "sources" ? [discoveryModel] : owner === "storage" ? [storageDiscoveryModel]
            : owner === "security" ? [securityDiscoveryModel] : [];
        if (!root.settingsVisible) return provider;
        return { "status": provider.status === "available" && monitors.some(model => model.failed || model.unresolved || model.externalUnresolved)
                ? "partial" : provider.status,
            "class": provider["class"], "owner": provider.owner,
            "detail": [provider.detail].concat(monitors.map(model => model.detail)).filter(value => value.length > 0).join(" ") };
    }

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
        return Information.owner(identifier);
    }

    function nativeActionOwner(actionId) {
        if (root.regionalActionKind(actionId).length > 0) return "regional";
        if (actionId === "accounts-open" || actionId === "password-open") return "accounts";
        if (actionId === "printers-open") return "printers";
        if (actionId === "sources-open") return "sources";
        if (actionId === "health-open") return "diagnostics";
        return "";
    }

    function validNativeValue(identifier, status, value) {
        if (Information.owner(identifier).length > 0) return Information.validValue(identifier, status, value);
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
        if (!root.settingsVisible)
            return "Open System Settings to prepare an update action.";
        // #266/S1-05 (#268): a native (delegated or regional) confirmation
        // already in flight must block starting an update one, the same as
        // the reverse direction delegateActionReason()/regionalModel's own
        // actionReason() already enforce -- this symmetric half was missed
        // when S1-04 ported #266's delegated confirmation.
        if (root.dispatchingUpdate || root.dispatchingNative || root.nativeConfirmation !== null
                || regionalModel.ownsPreparation() || regionalModel.confirmation !== null)
            return "Finish or dismiss the current confirmation first.";
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
        // #266/S1-05 (#268): discoveryModel/operationModel signals already
        // invalidate the update confirmation above; extend the same handler
        // rather than add a second signal, since all three (update,
        // delegated, regional) share one invalidation source.
        // invalidateNativeConfirmation("") was itself missed when S1-04
        // ported #266 -- a pending delegate confirmation did not clear when
        // the update one did.
        root.invalidateNativeConfirmation("");
        regionalModel.invalidate("");
    }

    // Sync Sprint 1 S1-04 (#266): delegated actions (accounts-open/
    // password-open/printers-open/sources-open) have no preview step --
    // launch_delegated_tool() either starts a fixed, already-trusted
    // executable or the action was already reported unavailable/unsupported
    // -- but they now get the same *visible confirmation* regional
    // mutations already have, rather than dispatching immediately on click.
    // Maps a delegated action to the one discovery model whose watch-*
    // stream keeps its provider/action offer fresh.
    function delegateDiscovery(actionId) {
        if (actionId === "accounts-open" || actionId === "password-open") return accountDiscoveryModel;
        if (actionId === "printers-open") return printerDiscoveryModel;
        if (actionId === "sources-open") return discoveryModel;
        return null;
    }

    // Every precondition confirmDelegate() must recheck at dispatch time,
    // not just at prepare time -- fresh discovery, no operation/recovery
    // owning the workflow, and the action still reported available.
    function delegateContextReason(actionId) {
        const monitor = root.delegateDiscovery(actionId);
        if (monitor === null) return "This delegated action is not supported.";
        if (!root.settingsVisible) return "Open System Settings to prepare this action.";
        if (root.snapshotOwned || root.snapshotPending || root.requiredPending || root.discoveryBatch
                || !monitor.visible || !monitor.ready || monitor.failed || !monitor.cycle.enabled
                || monitor.cycle.phase !== "idle" || monitor.cycle.unresolved)
            return "Wait for fresh provider status, or reload status to retry.";
        if (!root.validGeneration(root.generation) || !operationModel.canStart)
            return "An operation or its recovery still owns the system workflow.";
        const action = root.actions.find(item => item.id === actionId);
        if (!action || action.status !== "available")
            return action && action.detail.length > 0 ? action.detail : "The provider did not offer this action.";
        return "";
    }

    function delegateActionReason(actionId) {
        if (root.dispatchingUpdate || root.dispatchingNative || root.updateConfirmation !== null
                || regionalModel.ownsPreparation() || regionalModel.confirmation !== null)
            return "Finish or dismiss the current confirmation first.";
        return root.delegateContextReason(actionId);
    }

    function prepareDelegate(actionId) {
        if (root.nativeConfirmation !== null) return false;
        const reason = root.delegateActionReason(actionId);
        if (reason.length > 0) {
            root.nativeConfirmationMessage = reason;
            return false;
        }
        const pending = { "actionId": actionId, "generation": root.generation,
            "requestGeneration": root.requestGeneration, "epoch": root.delegateDiscovery(actionId).cycle.epoch };
        root.dispatchingNative = true;
        root.nativeConfirmationMessage = "";
        // Reentrant closure or discovery callbacks may retire this preparation.
        if (root.delegateContextReason(actionId) === "" && pending.generation === root.generation
                && pending.requestGeneration === root.requestGeneration
                && pending.epoch === root.delegateDiscovery(actionId).cycle.epoch)
            root.nativeConfirmation = pending;
        root.dispatchingNative = false;
        return root.nativeConfirmation === pending;
    }

    function discardDelegate() {
        root.nativeConfirmation = null;
        root.nativeConfirmationMessage = "";
    }

    // domain "" invalidates unconditionally (a mutual-exclusion/generation
    // change unrelated to any one discovery monitor); a nonempty domain
    // only retires a confirmation prepared against that exact monitor.
    function invalidateNativeConfirmation(domain) {
        const pending = root.nativeConfirmation;
        if (pending === null) return;
        const monitor = root.delegateDiscovery(pending.actionId);
        if (domain !== "" && (monitor === null || monitor.domain !== domain)) return;
        root.nativeConfirmationMessage = "Provider state changed. Reload status and confirm again.";
        root.nativeConfirmation = null;
    }

    function confirmDelegate() {
        const pending = root.nativeConfirmation;
        if (pending === null || root.dispatchingUpdate || root.dispatchingNative) return false;
        if (root.delegateActionReason(pending.actionId) !== "") {
            root.invalidateNativeConfirmation("");
            return false;
        }
        root.dispatchingNative = true;
        root.nativeConfirmation = null;
        // Recheck after prompt callbacks; the operation owner checks its own
        // source ownership again before constructing the fixed empty argv.
        const monitor = root.delegateDiscovery(pending.actionId);
        const current = root.delegateContextReason(pending.actionId) === ""
            && pending.generation === root.generation && pending.requestGeneration === root.requestGeneration
            && monitor !== null && pending.epoch === monitor.cycle.epoch;
        const started = current && operationModel.startNative(pending.actionId, "", "");
        root.nativeConfirmationMessage = started ? "" : "Provider state changed. Reload status and confirm again.";
        root.dispatchingNative = false;
        return started;
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
        // Sync Sprint 2 S2-05 (#286): a failed recovery-only (snapshotProcess.core)
        // read provides no new evidence about optional information -- retire
        // mutation offers without erasing that projection, matching the
        // treatment a successful minor-1-only core read already gets below
        // in parseSnapshot().
        const preserveInformation = root.snapshotOwned && snapshotProcess.core;
        const providers = {};
        const states = {};
        if (preserveInformation) {
            for (const owner of Information.owners()) {
                if (root.nativeProviders[owner]) providers[owner] = root.nativeProviders[owner];
            }
            for (const identifier of Information.stateIds()) {
                if (root.nativeStates[identifier]) states[identifier] = root.nativeStates[identifier];
            }
        }
        root.snapshotState = "unavailable";
        root.message = reason;
        root.generation = "";
        root.updateProvider = root.providerFallback(reason);
        root.recoveryProvider = root.recoveryFallback(reason);
        root.updateSummary = root.stateFallback(reason);
        root.updateLastRefresh = root.stateFallback(reason);
        root.updateRestart = root.stateFallback(reason);
        root.actions = preserveInformation ? root.actions.filter(item => item.id === "health-open") : [];
        root.updates = [];
        root.packageChanges = [];
        root.nativeProviders = providers;
        root.nativeStates = states;
        root.accounts = [];
        root.repositories = [];
        if (!preserveInformation) {
            root.filesystems = [];
            root.filesystemsRetained = false;
        }
        root.errors = preserveInformation
            ? root.errors.filter(item => Information.owners().indexOf(item.capability) >= 0) : [];
        root.activeOperation = null;
        root.terminalHandoff = null;
    }

    function openSettings() {
        root.settingsVisible = true;
        // #261: batch the five discovery models' open() calls so a signal
        // one of them fires mid-loop (refresh()'s requestPending() can fire
        // synchronously; open() itself cannot, but both funnel through this
        // same guard for one consistent rule) queues rather than starting
        // its own fetch before the rest have even opened.
        root.discoveryBatch = true;
        timeReconciliationModel.open();
        for (const model of root.discoveryModels()) model.open();
        root.refreshRecovery();
        root.discoveryBatch = false;
        root.requestSnapshot(root.requiredPending);
    }

    function closeSettings() {
        root.settingsVisible = false;
        timeReconciliationModel.close();
        root.confirmationInvalidated();
        for (const model of root.discoveryModels()) model.close();
        root.snapshotPending = false;
        // A required fetch (recovering operation evidence) is not this
        // pane's to kill: it keeps running so operationModel can still
        // reattach to an in-progress or unacknowledged operation offscreen.
        if (!root.snapshotRequired && snapshotProcess.running) snapshotProcess.running = false;
    }

    function refresh() {
        if (!root.settingsVisible) return;
        // Refresh retires the preview immediately, even while replacement
        // subscriptions are still waiting for their readiness handshake.
        root.confirmationInvalidated();
        root.discoveryBatch = true;
        timeReconciliationModel.open();
        for (const model of root.discoveryModels()) model.refresh();
        root.refreshRecovery();
        root.discoveryBatch = false;
        root.requestSnapshot(root.requiredPending);
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
    // each open discovery model's take()/beforePublish()/complete() (#261:
    // now up to five, one per domain, not just discoveryModel) so a signal
    // arriving mid-read schedules exactly one follow-up settling read
    // rather than a read per signal.
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
    // Also guarded on discoveryBatch (#261): openSettings()/refresh() loop
    // over all five models before calling this once themselves, so a signal
    // one of those models fires mid-loop must defer too, the same as an
    // already-owned fetch.
    // `required` (Sync Phase 7) is operationModel asking for recovery
    // evidence: it bypasses discoveryReady()'s settingsVisible tie, but
    // still only hands each model's take() the request when the batch is
    // actually ready -- an unready/invisible model's take() would return
    // null anyway (SystemDiscoveryCycle.js's owns() no-ops a null token
    // through beforePublish/complete), so the read still runs without
    // joining any visible cycle.
    function requestSnapshot(required) {
        // S1-08 (#275): a fresh snapshot also outdates any time-status/
        // ntp-sample read timeReconciliationModel still owns -- reserve
        // snapshot priority over it the same way as an in-flight regional
        // preparation below, before either can claim the shared owner.
        if (timeReconciliationModel.ownsRead()) {
            root.snapshotPending = root.snapshotPending || !required;
            root.requiredPending = root.requiredPending || !!required;
            timeReconciliationModel.beforeSnapshot();
            if (timeReconciliationModel.ownsRead()) return;
        }
        // S1-05 (#268): a fresh snapshot changes root.generation, which
        // would silently outdate any regional preview/confirmation ticket
        // still in flight (regionalModel's own matches() check would catch
        // this eventually, but only on the user's next interaction) --
        // cancel it first and defer the read exactly like an already-owned
        // fetch, rather than let a stale regional prompt survive a
        // generation it no longer matches.
        if (regionalModel.ownsPreparation()) {
            root.snapshotPending = root.snapshotPending || !required;
            root.requiredPending = root.requiredPending || !!required;
            regionalModel.invalidate("");
            // Optional preflight cancellation must be reaped before recovery
            // or discovery can claim the shared snapshot owner.
            if (regionalModel.ownsPreparation()) return;
        }
        if (root.snapshotOwned || snapshotProcess.running || root.discoveryBatch) {
            root.snapshotPending = root.snapshotPending || !required;
            root.requiredPending = root.requiredPending || !!required;
            return;
        }
        required = required || root.requiredPending;
        const ready = root.discoveryReady();
        if (!required && (!ready || !root.discoveryModels().some(model => model.canTake()))) return;
        root.snapshotPending = false;
        root.requiredPending = false;
        root.snapshotOwned = true;
        timeReconciliationModel.beforeSnapshot();
        root.snapshotAttempted = false;
        root.snapshotRequired = required;
        // Sync Sprint 2 S2-05 (#286): a required (recovery-only) read never
        // probes optional information -- it must not open the filesystem
        // inventory's unmonitored initialization gap, so it always asks for
        // snapshot-core. An optional read asks for the full snapshot once
        // the storage domain's own subscription is actually ready, and
        // snapshot-without-storage otherwise (a blocked cycle is treated the
        // same as not-yet-ready: its own retained projection is untrustworthy).
        snapshotProcess.core = required;
        snapshotProcess.storageOmitted = !required
            && (!storageDiscoveryModel.ready || storageDiscoveryModel.phase === "blocked");
        root.requestGeneration++;
        root.confirmationInvalidated();
        const tokens = [];
        // A required read bypasses subscription setup, but cannot certify
        // optional freshness until every domain has a handshake or fallback
        // -- it must not consume tokens an optional read still needs.
        if (ready && !required) {
            for (const model of root.discoveryModels()) {
                const token = model.take();
                if (token !== null) tokens.push({ "model": model, "token": token });
            }
        } else if (required && root.discoveryModels().some(model => model.canTake())) {
            // This required read is skipping every domain's token on purpose
            // (above), including one whose own requestSnapshot(false) call is
            // what brought execution here (an already-pending required need
            // upgrades the very call a settling domain's cycle triggered).
            // That domain will not signal again on its own -- queue the
            // follow-up optional drain onRunningChanged already retries.
            root.snapshotPending = true;
        }
        snapshotProcess.cycleTokens = tokens;
        root.snapshotState = "loading";
        root.message = "Loading system update status...";
        snapshotProcess.command = Commands.checkedCommand(Commands.systemManagementCommand(
            required ? "snapshot-core" : snapshotProcess.storageOmitted ? "snapshot-without-storage" : "snapshot", []));
        snapshotProcess.running = true;
    }

    // Cycle bookkeeping, plus handing the parsed operation state to
    // operationModel -- ownership and the next launch are handled
    // separately, gated on the process's real exit (see requestSnapshot).
    function finishSnapshot(successful) {
        const tokens = snapshotProcess.cycleTokens;
        for (const item of tokens) item.model.beforePublish(item.token);
        if (successful) operationModel.acceptSnapshot(root.activeOperation, root.terminalHandoff);
        else operationModel.snapshotFailed();
        for (const item of tokens) item.model.complete(item.token, successful);
        timeReconciliationModel.afterSnapshot();
        snapshotProcess.cycleTokens = [];
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
                || (header[2] !== "0" && header[2] !== "1" && header[2] !== "2")) {
            root.resetToFallback("System management provider returned an unsupported protocol");
            return false;
        }
        const minor = Number(header[2]);
        if (lines[lines.length - 1] !== "complete\tsnapshot") {
            root.resetToFallback("System management provider returned a truncated snapshot");
            return false;
        }
        // Sync Sprint 2 S2-05 (#286): minor 2's information/storage/security
        // owners, state identifiers, and the diagnostics health-open action
        // only join the active set a producer that actually declared minor 2
        // may use -- a minor-1-only producer naming one of these identifiers
        // must not have it silently accepted as native.
        const nativeOwners = root.validNativeOwners.slice();
        const nativeStateIds = root.validNativeStateIds.slice();
        const nativeActionIds = root.validNativeActionIds.slice();
        if (minor === 2) {
            nativeOwners.push(...Information.owners());
            nativeStateIds.push(...Information.stateIds());
            nativeActionIds.push("health-open");
        }
        const priorHealthAction = root.actions.find(item => item.id === "health-open");

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
        // its existing all-or-nothing strictness, untouched). Sync Sprint 2
        // S2-05 extends the same independence to minor 2's information,
        // storage, and security owners.
        const nativeProviders = {};
        const nativeStates = {};
        const nativeActions = {};
        const nativeInvalid = {};
        const accountsList = [];
        const repositoriesList = [];
        const filesystemsList = [];
        const seenAccountIds = {};
        const seenRepositoryIds = {};
        const seenFilesystemIds = {};

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
                if (minor >= 1 && fields.length >= 2 && nativeOwners.indexOf(fields[1]) >= 0) {
                    if (nativeProviders[fields[1]] !== undefined) {
                        root.resetToFallback("System management provider repeated a provider record");
                        return false;
                    }
                    if (fields.length !== 6 || root.validStatus.indexOf(fields[2]) < 0
                            || fields[3] !== Information.providerClass(fields[1])) {
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
                if (minor >= 1 && nativeOwner.length > 0 && nativeStateIds.indexOf(fields[1]) >= 0) {
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
                if (minor >= 1 && nativeOwner.length > 0 && nativeActionIds.indexOf(fields[1]) >= 0) {
                    if (nativeActions[fields[1]] !== undefined) {
                        root.resetToFallback("System management provider repeated an action record");
                        return false;
                    }
                    if (fields.length !== 7 || root.validActionStatus.indexOf(fields[2]) < 0
                            || fields[3] !== (nativeOwner === "diagnostics" ? "user-session" : "delegated")
                            || fields[4] !== nativeOwner) {
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
            } else if (kind === "account" || kind === "repository" || kind === "filesystem") {
                // Sync Sprint 2 S2-05 (#286): filesystem is cumulative with
                // account/repository, active only from minor 2 (they remain
                // active at minor 2 too -- build_native_snapshot() still runs).
                if (minor < 1 || (kind === "filesystem" && minor < 2)) {
                    root.resetToFallback("System management provider returned an inactive list owner");
                    return false;
                }
                const isAccount = kind === "account";
                const isFilesystem = kind === "filesystem";
                const owner = isAccount ? "accounts" : isFilesystem ? "storage" : "sources";
                const seen = isAccount ? seenAccountIds : isFilesystem ? seenFilesystemIds : seenRepositoryIds;
                if (fields.length < 2 || fields[1].length === 0) {
                    root.resetToFallback("System management provider returned a list without an identity");
                    return false;
                }
                if (seen[fields[1]] !== undefined) {
                    root.resetToFallback("System management provider repeated a list identity");
                    return false;
                }
                seen[fields[1]] = true;
                const list = isAccount ? accountsList : isFilesystem ? filesystemsList : repositoriesList;
                // #259: match the helper's own REPOSITORY_MAX_ROWS (512), not
                // the generic update/package-change list bound (4096) -- the
                // protocol contract is 512, and accepting more here would
                // just mean silently trusting a provider past its own cap.
                // Filesystem matches the helper's own FILESYSTEM_RECORDS (256).
                if (list.length >= (isAccount || isFilesystem ? 256 : 512)) {
                    nativeInvalid[owner] = true;
                    continue;
                }
                if (isAccount) {
                    if (fields.length !== 5 || (fields[2] !== "current" && fields[2] !== "other") || fields[4].length === 0) {
                        nativeInvalid[owner] = true;
                        continue;
                    }
                    accountsList.push({ "id": fields[1], "scope": fields[2], "displayName": fields[3], "loginName": fields[4] });
                } else if (isFilesystem) {
                    if (fields.length !== 10 || !Information.validFilesystem(fields)) {
                        nativeInvalid[owner] = true;
                        continue;
                    }
                    filesystemsList.push(Information.filesystem(fields));
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
                        || (fields[6] !== "yes" && fields[6] !== "no")
                        // #251/#262: only an update action may report itself
                        // cancelable or sit in cancel-requested -- that state
                        // is reachable exclusively through the same cancel
                        // path that requires cancelable in the first place.
                        || (root.updateActionKind(fields[2]).length === 0
                            && (fields[6] !== "no" || fields[4] === "cancel-requested"))) {
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
        // #262: whether the recovery journal itself was legitimately read,
        // independent of any one domain's own record shape -- an active or
        // terminal-handoff identity is direct evidence, as is a recovery
        // provider that read as "available". Upstream also OR-in valid
        // native action availability below (a working regional/delegated
        // domain is independent proof the same journal infrastructure is
        // readable); upstream's own `!recoveryInvalid` guard is dropped here
        // because Lyona's mandatory-record check above already returns false
        // outright when the recovery provider record itself is missing or
        // malformed, so that condition can never reach this point true.
        let journalAdmitted = activeOperation !== null || terminalHandoff !== null
            || recoveryProvider.status === "available";
        if (minor >= 1) {
            for (let i = 0; i < nativeOwners.length; i++) {
                if (nativeProviders[nativeOwners[i]] === undefined) nativeInvalid[nativeOwners[i]] = true;
            }
            for (let i = 0; i < nativeStateIds.length; i++) {
                const identifier = nativeStateIds[i];
                if (nativeStates[identifier] === undefined) nativeInvalid[root.nativeStateOwner(identifier)] = true;
            }
            for (let i = 0; i < nativeActionIds.length; i++) {
                if (nativeActions[nativeActionIds[i]] === undefined)
                    nativeInvalid[root.nativeActionOwner(nativeActionIds[i])] = true;
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
            // Sync Sprint 2 S2-05 (#286): the filesystem-summary counter must
            // agree with the actual filesystem list it summarizes, the same
            // consistency accounts-count already requires of the account list.
            if (minor === 2 && !nativeInvalid.storage) {
                const summary = nativeStates["filesystem-summary"];
                if ((summary.status === "available" && (Number(summary.value) !== filesystemsList.length
                            || filesystemsList.some(item => item.status !== "available")))
                        || (summary.status !== "available" && summary.status !== "partial" && filesystemsList.length > 0))
                    nativeInvalid.storage = true;
            }
            for (let i = 0; i < nativeOwners.length; i++) {
                const owner = nativeOwners[i];
                if (nativeInvalid[owner]) {
                    const detail = "System management provider returned malformed " + owner + " state";
                    publishedProviders[owner] = { "status": "partial", "class": Information.providerClass(owner), "owner": "", "detail": detail };
                    errors.push({ "capability": owner, "code": "malformed", "detail": detail });
                } else publishedProviders[owner] = nativeProviders[owner];
            }
            for (let i = 0; i < nativeStateIds.length; i++) {
                const identifier = nativeStateIds[i];
                const owner = root.nativeStateOwner(identifier);
                publishedStates[identifier] = nativeInvalid[owner]
                    ? { "status": "partial", "value": "unknown", "detail": publishedProviders[owner].detail }
                    : nativeStates[identifier];
            }
            // #262: a valid, available native action offer is itself proof
            // the journal is readable, even when update-domain recovery
            // (e.g. logind) reports unavailable and no active/handoff
            // identity exists. health-open is excluded -- its availability
            // never depends on the journal and so is not evidence of it.
            if (!journalAdmitted) {
                journalAdmitted = nativeActionIds.some(function(identifier) {
                    return identifier !== "health-open" && !nativeInvalid[root.nativeActionOwner(identifier)]
                        && nativeActions[identifier].status === "available";
                });
            }
            for (let i = 0; i < nativeActionIds.length; i++) {
                const actionId = nativeActionIds[i];
                if ((actionId === "health-open" || journalAdmitted) && !nativeInvalid[root.nativeActionOwner(actionId)])
                    actions.push(nativeActions[actionId]);
            }
        }
        // Recovery-only reads do not probe optional information. Keep a prior
        // readable projection until the pane's monitored information read lands.
        if (snapshotProcess.core && minor === 1) {
            for (const owner of Information.owners()) {
                if (root.nativeProviders[owner]) publishedProviders[owner] = root.nativeProviders[owner];
            }
            for (const identifier of Information.stateIds()) {
                if (root.nativeStates[identifier]) publishedStates[identifier] = root.nativeStates[identifier];
            }
            if (priorHealthAction) actions.push(priorHealthAction);
            errors.push(...root.errors.filter(item => Information.owners().indexOf(item.capability) >= 0));
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
        root.accounts = minor >= 1 && !nativeInvalid.accounts ? accountsList : [];
        root.repositories = minor >= 1 && !nativeInvalid.sources ? repositoriesList : [];
        if (!snapshotProcess.core || minor !== 1) {
            const omitted = snapshotProcess.storageOmitted && minor === 2 && !nativeInvalid.storage
                && nativeStates["filesystem-summary"].status === "partial" && filesystemsList.length === 0;
            root.filesystemsRetained = omitted && root.filesystems.length > 0;
            if (!root.filesystemsRetained)
                root.filesystems = minor === 2 && !nativeInvalid.storage ? filesystemsList : [];
        }
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
        // The function's own return value is a narrower question --
        // journalAdmitted (#262) -- consumed by finishSnapshot()'s
        // acceptSnapshot()/snapshotFailed() split, not by snapshotState.
        root.snapshotState = "loaded";
        root.message = updates.length + " update" + (updates.length === 1 ? "" : "s") + " found";
        return journalAdmitted;
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

    // #261: the generic SystemProviderDiscovery form (Sync Phase 4) already
    // supports these four domains via domainDefinition() -- only their
    // instantiation and coordination into the snapshot cycle was missing.
    SystemProviderDiscovery {
        id: timeDiscoveryModel
        domain: "time"
        externalUnresolved: timeReconciliationModel.blocked
        externalDetail: timeReconciliationModel.detail
        onSnapshotRequested: root.requestSnapshot(false)
        // S1-05: a live timezone/NTP change must retire any regional
        // preview/confirmation prepared against now-stale time state.
        onInvalidated: {
            timeReconciliationModel.beforeSnapshot();
            regionalModel.invalidate("time");
        }
        // S1-08 (#275): owner arrival is uncertainty, not proof of a changed
        // property -- timeReconciliationModel reconciles it with a bounded
        // time-status read instead of treating it as an ordinary invalidation.
        onOwnerArrived: timeReconciliationModel.arrived()
    }
    SystemProviderDiscovery {
        id: localeDiscoveryModel
        domain: "locale"
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: regionalModel.invalidate("locale")
    }
    SystemProviderDiscovery {
        id: accountDiscoveryModel
        domain: "accounts"
        onSnapshotRequested: root.requestSnapshot(false)
        // #266: a live account change must retire any confirmation prepared
        // against a now-stale account/password offer.
        onInvalidated: root.invalidateNativeConfirmation("accounts")
    }
    SystemProviderDiscovery {
        id: printerDiscoveryModel
        domain: "printers"
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: root.invalidateNativeConfirmation("printers")
    }
    SystemProviderDiscovery {
        id: storageDiscoveryModel
        domain: "storage"
        onSnapshotRequested: root.requestSnapshot(false)
    }
    SystemProviderDiscovery {
        id: securityDiscoveryModel
        domain: "security"
        onSnapshotRequested: root.requestSnapshot(false)
    }

    SystemOperationModel {
        id: operationModel
        // S1-08 (#276): a completed ntp-set result is a reason to sample
        // network time promptly, not just wait for the next periodic timer.
        onResultChanged: timeReconciliationModel.sampleAfterOperation(result)
        // #262: invalidate only the domain the dispatched/watched/acknowledged
        // action actually belongs to, not always the update discovery model.
        onDiscoveryInvalidated: actionId => root.invalidateActionDiscovery(actionId)
        onSnapshotRequested: root.requestSnapshot(true)
        onAcknowledged: operationId => {
            if (root.terminalHandoff !== null && root.terminalHandoff.id === operationId)
                root.terminalHandoff = null;
            if (root.activeOperation !== null && root.activeOperation.id === operationId)
                root.activeOperation = null;
        }
    }

    // Sync Sprint 1 S1-05 (#268): takes over regional preview/confirm state
    // that used to live directly on this model (Sync Phase 9's PR #33
    // regionalPreview/prepareRegional()/confirmRegional() family, removed
    // above) -- confirmed dispatch goes through model.operation.startNative()
    // internally, same split discoveryModel/operationModel already have
    // between read and mutate.
    SystemRegionalSettingsModel {
        id: regionalModel
        model: root
        onReleased: Qt.callLater(function() {
            if (root.requiredPending) root.requestSnapshot(true);
            else if (root.snapshotPending && root.settingsVisible) root.requestSnapshot(false);
            else timeReconciliationModel.requestPending();
        })
    }

    // Sync Sprint 1 S1-08 (#275, extended by #276): owner-arrival
    // reconciliation and periodic network-time sampling for the "time"
    // domain, ported nearly unchanged -- verified against this file's
    // actual settingsVisible/snapshotOwned/discoveryBatch/generation shape
    // rather than assumed from the plan doc.
    SystemTimeReconciliationModel {
        id: timeReconciliationModel
        model: root
        onReleased: Qt.callLater(function() {
            if (root.requiredPending) root.requestSnapshot(true);
            else if (root.snapshotPending && root.settingsVisible) root.requestSnapshot(false);
        })
    }

    Process {
        id: snapshotProcess
        property var cycleTokens: []
        property bool core: false
        property bool storageOmitted: false
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
