import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

pragma ComponentBehavior: Bound

/*
 * The wallpaper of Settings > Appearance, through dwm-settings-wallpaper (#282):
 * split from AppearanceModel.qml, as PicomModel.qml was. The message line,
 * Settings' visibility, the asset inventory and the other appearance changes
 * it waits for are the Appearance model's, given as `appearance`.
 */
Scope {
    id: root

    required property var appearance

    property string selectionState: "idle"

    property string path: ""

    property string fit: "fill"

    property string detail: "Wallpaper state has not been loaded"

    property string providerState: "idle"

    property string providerDetail: "Wallpaper provider has not been checked"

    property string mutationState: "idle"

    property bool mutationReady: false

    property string mutationDetail: "Wallpaper changes have not been checked"

    property string resetState: "idle"

    property bool resetReady: false

    property string resetDetail: "Wallpaper reset readiness has not been checked"

    property bool busy: false

    property bool reconcilePending: false

    readonly property bool statusBusy: readinessProcess.running
        || statusProcess.running || root.appearance.inventoryRunning
        || root.statusPending || root.appearance.inventoryPending
        || root.appearance.inventoryWatchStarting

    // What the Appearance model asks of the wallpaper's processes (#282).
    readonly property bool reading: statusProcess.running || actionProcess.running

    function startReadiness() {
        if (!readinessProcess.running)
            readinessProcess.running = true;
    }

    function stopStatusRead() {
        statusProcess.running = false;
    }

    readonly property bool previewActionBusy: readinessProcess.running
        || statusProcess.running || actionProcess.running || root.appearance.busy

    property string previewState: "none"

    property string previewToken: ""

    property string previewPath: ""

    property string previewFit: "fill"

    property alias previewRemaining: countdown.remaining

    property string previewDetail: ""

    property string actionKind: ""

    property string actionToken: ""

    property string actionPath: ""

    property string actionFit: "fill"

    property string actionResultState: ""

    property string actionError: ""

    property bool actionSucceeded: false

    property bool statusParsed: false

    property bool statusPending: false

    readonly property string configPath: root.appearance.configHome + "/lyona/wallpaper.conf"

    readonly property var candidates: root.appearance.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "wallpaper";
    })

    function validWallpaperFit(value) {
        return value === "center" || value === "fill" || value === "max"
            || value === "scale" || value === "tile";
    }

    function refreshStatus() {
        if (!root.appearance.settingsVisible) return;
        if (root.reconcilePending) root.tryReconcilePreview();
        QueuedRun.startOrQueue(statusProcess, root, "statusPending",
            readinessProcess.running || actionProcess.running || root.appearance.inventoryRunning,
            function() { root.statusParsed = false; });
    }

    function nextPreviewToken() {
        return "wallpaper-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function clearStatus(detail) {
        const preservePreview = (root.previewState === "active"
                || root.previewState === "failed")
            && root.previewToken.length > 0;
        root.statusParsed = false;
        root.providerState = "unavailable";
        root.providerDetail = detail;
        root.selectionState = "unavailable";
        root.path = "";
        root.fit = "fill";
        root.detail = detail;
        root.mutationState = "unavailable";
        root.mutationReady = false;
        root.mutationDetail = detail;
        root.resetState = "unavailable";
        root.resetReady = false;
        root.resetDetail = detail;
        if (!preservePreview) {
            root.previewState = "none";
            root.previewToken = "";
            root.previewRemaining = 0;
            root.previewPath = "";
            root.previewFit = "fill";
            root.previewDetail = "";
        }
    }

    function parseStatus(text) {
        let protocolValid = false;
        let provider = null;
        let selection = null;
        let mutation = null;
        let reset = { "state": "restricted",
            "detail": "Installed wallpaper helper does not report reset readiness" };
        let preview = null;
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "wallpaper-protocol") {
                protocolValid = Protocol.validHeader(fields, 1);
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "wallpaper" && root.appearance.validState(fields[2])
                    && fields[3] === "user-session" && root.appearance.validInventoryField(fields[4], false)) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "selection" && fields.length === 5
                    && root.appearance.validState(fields[1]) && root.appearance.validInventoryField(fields[2], true)
                    && root.validWallpaperFit(fields[3]) && root.appearance.validInventoryField(fields[4], false)) {
                selection = { "state": fields[1], "path": fields[2], "fit": fields[3],
                    "detail": fields[4] };
            } else if (fields[0] === "mutation" && fields.length === 3
                    && (fields[1] === "available" || fields[1] === "restricted")
                    && root.appearance.validInventoryField(fields[2], false)) {
                mutation = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "reset" && fields.length === 3
                    && (fields[1] === "available" || fields[1] === "restricted")
                    && root.appearance.validInventoryField(fields[2], false)) {
                reset = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "preview" && fields.length === 7
                    && (fields[1] === "none" || fields[1] === "active" || fields[1] === "failed")
                    && root.appearance.validInventoryField(fields[2], true) && /^[0-9]+$/.test(fields[3])
                    && root.appearance.validInventoryField(fields[4], true) && root.validWallpaperFit(fields[5])
                    && root.appearance.validInventoryField(fields[6], false)) {
                preview = { "state": fields[1], "token": fields[2], "remaining": Number(fields[3]),
                    "path": fields[4], "fit": fields[5], "detail": fields[6] };
            }
        }
        if (!protocolValid || provider === null || selection === null || mutation === null
                || preview === null) {
            root.clearStatus("Wallpaper helper returned an unsupported response");
            return;
        }
        const previewWasActive = root.previewState === "active";
        const previewRemainingBefore = root.previewRemaining;
        root.statusParsed = true;
        root.providerState = provider.state;
        root.providerDetail = provider.detail;
        root.selectionState = selection.state;
        root.path = selection.path;
        root.fit = selection.fit;
        root.detail = selection.detail;
        root.mutationState = mutation.state;
        root.mutationReady = mutation.state === "available";
        root.mutationDetail = mutation.detail;
        root.resetState = reset.state;
        root.resetReady = reset.state === "available";
        root.resetDetail = reset.detail;
        root.previewState = preview.state;
        root.previewToken = preview.token;
        root.previewRemaining = preview.remaining;
        root.previewPath = preview.path;
        root.previewFit = preview.fit;
        root.previewDetail = preview.detail;
        if (!previewWasActive && preview.state === "active") {
            root.appearance.message = "Wallpaper preview active; keep it within " + preview.remaining
                + (preview.remaining === 1 ? " second" : " seconds") + " or it will revert";
            root.appearance.messageSeverity = "warning";
        } else if (previewWasActive && preview.state === "none"
                && root.appearance.message.startsWith("Wallpaper preview active; keep it within ")
                && root.appearance.message.endsWith(" or it will revert")) {
            root.appearance.message = previewRemainingBefore <= 1
                ? "Wallpaper preview expired and reverted automatically"
                : "Wallpaper preview completed outside Settings";
            root.appearance.messageSeverity = previewRemainingBefore <= 1 ? "warning" : "idle";
        }
    }

    function runAction(action, args, path, fit, token) {
        const previewDecision = root.previewState === "active"
            && (action === "keep" || action === "revert");
        if (previewDecision && (root.appearance.inventoryRunning || root.appearance.inventoryPending
                || root.statusPending)
                && !root.busy && !actionProcess.running
                && !readinessProcess.running && !statusProcess.running
                && !root.appearance.busy && !root.appearance.font.busy) {
            root.appearance.inventoryGeneration++;
            root.statusPending = false;
            root.appearance.inventoryPending = false;
            root.appearance.inventoryPendingAllowUnwatched = false;
            root.appearance.stopInventoryRead();
        }
        if (root.busy || actionProcess.running
                || readinessProcess.running || statusProcess.running
                || (!previewDecision && (root.appearance.inventoryRunning
                    || root.statusPending || root.appearance.inventoryPending))
                || (!previewDecision && root.appearance.inventoryWatchStarting)
                || root.appearance.busy || root.appearance.font.busy) {
            root.appearance.message = "Another appearance change is already in progress";
            root.appearance.messageSeverity = "warning";
            return;
        }
        root.busy = true;
        root.actionKind = action;
        root.actionPath = path || "";
        root.actionFit = fit || "fill";
        root.actionResultState = "";
        root.actionToken = token || "";
        root.actionError = "";
        root.actionSucceeded = false;
        root.appearance.message = "Applying wallpaper change...";
        root.appearance.messageSeverity = "idle";
        actionProcess.command = Commands.checkedCommand(
            Commands.settingsWallpaperCommand(action === "reconcile" ? "status" : action, args));
        actionProcess.running = true;
    }

    function preview(path, fit) {
        if (!root.mutationReady || !root.appearance.validInventoryField(path, false)
                || !root.validWallpaperFit(fit) || root.previewState !== "none") return;
        const token = root.nextPreviewToken();
        root.runAction("preview", [token, "30", path, fit], path, fit, token);
    }

    function apply(path, fit) {
        if (!root.mutationReady || !root.appearance.validInventoryField(path, false)
                || !root.validWallpaperFit(fit) || root.previewState !== "none") return;
        root.runAction("apply", [path, fit], path, fit, "");
    }

    function reset() {
        if (!root.resetReady || root.previewState !== "none") return;
        root.runAction("reset", [], "", "fill", "");
    }

    function keepPreview() {
        if (root.previewState !== "active" || root.previewToken.length === 0) return;
        root.runAction("keep", [root.previewToken], root.previewPath,
            root.previewFit, root.previewToken);
    }

    function revertPreview() {
        if ((root.previewState !== "active" && root.previewState !== "failed")
                || root.previewToken.length === 0) return;
        root.runAction("revert", [root.previewToken], root.previewPath,
            root.previewFit, root.previewToken);
    }

    function abandonPreview() {
        if (root.previewState !== "failed" || root.previewToken.length === 0) return;
        root.runAction("abandon", [root.previewToken], root.previewPath,
            root.previewFit, root.previewToken);
    }

    function reconcilePreview() {
        if (root.previewState !== "failed") return;
        root.reconcilePending = true;
        root.tryReconcilePreview();
    }

    // runAction() silently drops the reconcile request whenever the
    // continuous background status poller (or another action) is mid-flight,
    // which happens often enough while the wallpaper pane is open that a
    // single fire-and-forget attempt can be lost with no user-visible retry.
    // refreshStatus() re-attempts this on every poll cycle instead.
    function tryReconcilePreview() {
        if (!root.reconcilePending) return;
        if (root.previewState !== "failed") {
            root.reconcilePending = false;
            return;
        }
        if (root.busy || actionProcess.running || readinessProcess.running
                || statusProcess.running || root.appearance.inventoryRunning
                || root.statusPending || root.appearance.inventoryPending
                || root.appearance.inventoryWatchStarting
                || root.appearance.busy || root.appearance.font.busy) {
            return;
        }
        root.reconcilePending = false;
        root.runAction("reconcile", [], root.previewPath,
            root.previewFit, root.previewToken);
    }

    // A reconcile that found something blocking it stays queued. Retry it as soon
    // as anything that can have been blocking it clears, so it does not depend on
    // a later status poll (or a watcher event) happening to come along.
    function retryQueuedReconcile() {
        if (root.reconcilePending) Qt.callLater(root.tryReconcilePreview);
    }

    onBusyChanged: if (!root.busy) root.retryQueuedReconcile()

    onStatusBusyChanged: if (!root.statusBusy) root.retryQueuedReconcile()

    function parseAction(text) {
        if (root.actionKind === "reconcile") {
            root.statusParsed = false;
            root.parseStatus(text);
            root.actionSucceeded = root.statusParsed;
            return;
        }
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || !Protocol.isHeader(lines[0].split("\t"), "wallpaper-action-protocol", 1)) return;
        const fields = lines[1].split("\t");
        if (root.actionKind === "preview") {
            root.actionSucceeded = fields.length === 5 && fields[0] === "preview"
                && fields[1] === root.actionToken && fields[2] === "30"
                && fields[3] === root.actionPath && fields[4] === root.actionFit;
        } else if (root.actionKind === "apply") {
            root.actionSucceeded = fields.length === 4 && fields[0] === "result"
                && fields[1] === "apply" && fields[2] === root.actionPath
                && fields[3] === root.actionFit;
        } else if (root.actionKind === "reset") {
            root.actionSucceeded = fields.length === 3 && fields[0] === "result"
                && fields[1] === "reset" && (fields[2] === "applied" || fields[2] === "unavailable");
            if (root.actionSucceeded) root.actionResultState = fields[2];
        } else {
            root.actionSucceeded = fields.length === 3 && fields[0] === "result"
                && fields[1] === root.actionKind && fields[2] === root.actionToken;
        }
    }

    function finishAction() {
        if (root.actionSucceeded) {
            if (root.actionKind === "preview") {
                root.previewState = "active";
                root.previewToken = root.actionToken;
                root.previewRemaining = 30;
                root.previewPath = root.actionPath;
                root.previewFit = root.actionFit;
                root.previewDetail = "Automatic rollback is armed";
            } else if (root.actionKind === "keep"
                    || root.actionKind === "revert"
                    || root.actionKind === "abandon") {
                root.previewState = "none";
                root.previewToken = "";
                root.previewRemaining = 0;
                root.previewPath = "";
                root.previewFit = "fill";
                root.previewDetail = "";
            }
            root.appearance.message = root.actionKind === "reconcile"
                ? root.previewState === "failed"
                    ? "Wallpaper preview recovery still needs attention"
                    : "Wallpaper preview recovery reconciled"
                : root.actionKind === "preview"
                ? "Wallpaper preview active; keep it within 30 seconds or it will revert"
                : root.actionKind === "keep" ? "Wallpaper preview kept"
                    : root.actionKind === "revert" ? "Wallpaper preview reverted"
                        : root.actionKind === "abandon" ? "External wallpaper state restored"
                            : root.actionKind === "reset"
                                ? root.actionResultState === "applied"
                                    ? "Wallpaper reset to the session default"
                                    : "Wallpaper selection reset; no session default was available"
                                : "Wallpaper applied";
            root.appearance.messageSeverity = root.actionKind === "reconcile"
                ? root.previewState === "failed" ? "warning" : "success"
                : root.actionKind === "preview"
                    || (root.actionKind === "reset"
                        && root.actionResultState === "unavailable")
                ? "warning" : "success";
        } else {
            root.appearance.message = root.actionError.length > 0 ? root.actionError
                : "Wallpaper helper did not confirm the requested change";
            root.appearance.messageSeverity = "danger";
        }
        root.busy = false;
        Qt.callLater(root.refreshStatus);
        root.appearance.refreshInventory(true);
    }

    Process {
        id: readinessProcess
        command: Commands.booleanStatusCommand(Commands.settingsWallpaperCommand("reset-ready", []))
        running: false
        onRunningChanged: {
            if (!running && root.appearance.settingsVisible)
                Qt.callLater(root.refreshStatus);
        }
    }

    Process {
        id: statusProcess
        command: Commands.settingsWallpaperCommand("status", ["--read-only"])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: wallpaperStatusError }
        onRunningChanged: {
            if (!running && root.appearance.settingsVisible && !root.statusParsed) {
                const error = wallpaperStatusError.text.trim();
                root.clearStatus(error.length > 0 ? error
                    : "Wallpaper helper failed before returning a valid status");
            }
            if (!running && root.appearance.settingsVisible && root.appearance.inventoryPending) {
                Qt.callLater(root.appearance.retryInventoryRefresh);
            } else if (!running && root.appearance.settingsVisible && root.statusPending) {
                Qt.callLater(root.refreshStatus);
            }
        }
    }

    Process {
        id: actionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseAction(this.text) }
        stderr: StdioCollector { onStreamFinished: root.actionError = this.text.trim() }
        onRunningChanged: if (!running && root.busy) root.finishAction()
    }

    PreviewCountdown {
        id: countdown
        active: root.appearance.settingsVisible && root.previewState === "active"
        onExpired: Qt.callLater(root.refreshStatus)
    }
}
