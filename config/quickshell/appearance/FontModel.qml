import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

pragma ComponentBehavior: Bound

/*
 * The managed shell font of Settings > Appearance, through dwm-settings-font (#282):
 * split from AppearanceModel.qml, as PicomModel.qml was. The message line,
 * Settings' visibility, the asset inventory and the other appearance changes
 * it waits for are the Appearance model's, given as `appearance`.
 */
Scope {
    id: root

    required property var appearance

    property string selectionState: "idle"

    property string family: "MesloLGS Nerd Font Mono"

    property real scale: 1.0

    property string detail: "Managed shell font state has not been loaded"

    property string providerState: "idle"

    property string providerDetail: "Font provider has not been checked"

    property bool mutationReady: false

    property bool busy: false

    readonly property bool statusBusy: statusProcess.running || readinessProcess.running

    property bool statusParsed: false

    property bool statusPending: false

    property int statusRetryAttempts: 0

    property string previewState: "none"

    property string previewToken: ""

    property string previewFamily: ""

    property real previewScale: 1.0

    property alias previewRemaining: countdown.remaining

    property string previewDetail: ""

    property string actionKind: ""

    property string actionToken: ""

    property string actionFamily: ""

    property real actionScale: 1.0

    property string actionError: ""

    property bool actionSucceeded: false

    readonly property string configPath: root.appearance.configHome + "/lyona/font.conf"

    readonly property string previewPath: root.appearance.stateHome
        + "/lyona/appearance/font/preview.current"

    readonly property var candidates: root.appearance.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "font";
    })

    function validScale(value) {
        return value === "0.80" || value === "0.90" || value === "1.00"
            || value === "1.10" || value === "1.25" || value === "1.50";
    }

    function refreshStatus() {
        if (!readinessProcess.running && !actionProcess.running) {
            root.mutationReady = false;
            readinessProcess.running = true;
        }
        QueuedRun.startOrQueue(statusProcess, root, "statusPending", actionProcess.running,
            function() { root.statusParsed = false; });
    }

    function nextPreviewToken() {
        return "font-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function clearStatus(detail) {
        root.statusParsed = false;
        root.providerState = "unavailable";
        root.providerDetail = detail;
        root.selectionState = "unavailable";
        root.detail = detail;
        root.mutationReady = false;
        if (!statusRetryTimer.running && root.statusRetryAttempts < 3) {
            root.statusRetryAttempts++;
            statusRetryTimer.restart();
        }
    }

    function parseStatus(text) {
        let protocolValid = false;
        let provider = null;
        let selection = null;
        let preview = null;
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "appearance-font-action-protocol") {
                protocolValid = Protocol.validHeader(fields, 1);
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "font" && root.appearance.validState(fields[2])
                    && fields[3] === "user-session"
                    && root.appearance.validInventoryField(fields[4], false)) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "selection" && fields.length === 5
                    && root.appearance.validState(fields[1]) && root.appearance.validInventoryField(fields[2], false)
                    && root.validScale(fields[3])
                    && root.appearance.validInventoryField(fields[4], false)) {
                selection = { "state": fields[1], "family": fields[2],
                    "scale": Number(fields[3]), "detail": fields[4] };
            } else if (fields[0] === "preview" && fields.length === 7
                    && (fields[1] === "none" || fields[1] === "active" || fields[1] === "failed")
                    && root.appearance.validInventoryField(fields[2], true)
                    && root.appearance.validInventoryField(fields[3], true)
                    && (fields[4].length === 0 || root.validScale(fields[4]))
                    && /^[0-9]+$/.test(fields[5])
                    && root.appearance.validInventoryField(fields[6], false)) {
                preview = { "state": fields[1], "token": fields[2], "family": fields[3],
                    "scale": fields[4].length > 0 ? Number(fields[4]) : 1.0,
                    "remaining": Number(fields[5]), "detail": fields[6] };
            }
        }
        if (!protocolValid || provider === null || selection === null || preview === null) {
            root.clearStatus("Font helper returned an unsupported response");
            return;
        }
        const previewWasActive = root.previewState === "active";
        const previousRemaining = root.previewRemaining;
        root.statusParsed = true;
        root.statusRetryAttempts = 0;
        statusRetryTimer.stop();
        root.providerState = provider.state;
        root.providerDetail = provider.detail;
        root.selectionState = selection.state;
        root.family = selection.family;
        root.scale = selection.scale;
        root.detail = selection.detail;
        root.previewState = preview.state;
        root.previewToken = preview.token;
        root.previewFamily = preview.family;
        root.previewScale = preview.scale;
        root.previewRemaining = preview.remaining;
        root.previewDetail = preview.detail;
        Theme.applyFontPreferences(root.family, root.scale);
        if (!previewWasActive && preview.state === "active") {
            root.appearance.message = "Font preview active; keep it within " + preview.remaining
                + (preview.remaining === 1 ? " second" : " seconds") + " or it will revert";
            root.appearance.messageSeverity = "warning";
        } else if (previewWasActive && preview.state === "none"
                && previousRemaining <= 1) {
            root.appearance.message = "Font preview expired and reverted automatically";
            root.appearance.messageSeverity = "warning";
        }
    }

    function runAction(action, args, family, scale, token) {
        if (root.busy || actionProcess.running || statusProcess.running
                || root.appearance.busy || root.appearance.wallpaper.busy) {
            root.appearance.message = "Another appearance change is already in progress";
            root.appearance.messageSeverity = "warning";
            return;
        }
        root.busy = true;
        root.actionKind = action;
        root.actionFamily = family || "";
        root.actionScale = scale || 1.0;
        root.actionToken = token || "";
        root.actionError = "";
        root.actionSucceeded = false;
        root.appearance.message = "Applying font change...";
        root.appearance.messageSeverity = "idle";
        actionProcess.command = Commands.checkedCommand(Commands.settingsFontCommand(action, args));
        actionProcess.running = true;
    }

    function preview(family, scale) {
        const scaleArgument = Number(scale).toFixed(2);
        if (!root.mutationReady || readinessProcess.running
                || !root.appearance.validInventoryField(family, false)
                || !root.validScale(scaleArgument) || root.previewState !== "none") return;
        const token = root.nextPreviewToken();
        root.runAction("preview", [token, "30", family, scaleArgument], family, scale, token);
    }

    function apply(family, scale) {
        const scaleArgument = Number(scale).toFixed(2);
        if (!root.mutationReady || readinessProcess.running
                || !root.appearance.validInventoryField(family, false)
                || !root.validScale(scaleArgument) || root.previewState !== "none") return;
        root.runAction("apply", [family, scaleArgument], family, scale, "");
    }

    function reset() {
        if (!root.mutationReady || readinessProcess.running
                || root.previewState !== "none") return;
        root.runAction("reset", [], "", 1.0, "");
    }

    function keepPreview() {
        if (root.previewState !== "active" || root.previewToken.length === 0) return;
        root.runAction("keep", [root.previewToken], root.previewFamily,
            root.previewScale, root.previewToken);
    }

    function revertPreview() {
        if ((root.previewState !== "active" && root.previewState !== "failed")
                || root.previewToken.length === 0) return;
        root.runAction("revert", [root.previewToken], root.previewFamily,
            root.previewScale, root.previewToken);
    }

    function abandonPreview() {
        if (root.previewState !== "failed" || root.previewToken.length === 0) return;
        root.runAction("abandon", [root.previewToken], root.previewFamily,
            root.previewScale, root.previewToken);
    }

    function parseAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || !Protocol.isHeader(lines[0].split("\t"), "appearance-font-action-protocol", 1)) return;
        const fields = lines[1].split("\t");
        if (fields.length !== 2 || fields[0] !== "result") return;
        const expected = root.actionKind === "preview" ? "preview-started"
            : root.actionKind === "apply" ? "applied" : root.actionKind;
        root.actionSucceeded = fields[1] === expected;
    }

    function finishAction() {
        root.busy = false;
        if (root.actionSucceeded) {
            if (root.actionKind === "preview") {
                root.previewState = "active";
                root.previewToken = root.actionToken;
                root.previewFamily = root.actionFamily;
                root.previewScale = root.actionScale;
                root.previewRemaining = 30;
                root.previewDetail = "Automatic rollback is armed";
            } else if (root.actionKind === "keep" || root.actionKind === "revert"
                    || root.actionKind === "abandon") {
                root.previewState = "none";
                root.previewToken = "";
                root.previewFamily = "";
                root.previewScale = 1.0;
                root.previewRemaining = 0;
                root.previewDetail = "";
            }
            root.appearance.message = root.actionKind === "preview"
                ? "Font preview active; keep it within 30 seconds or it will revert"
                : root.actionKind === "keep" ? "Font preview kept"
                    : root.actionKind === "revert" ? "Font preview reverted"
                        : root.actionKind === "abandon" ? "External font state accepted"
                            : root.actionKind === "reset"
                                ? "Font reset to the managed shell default" : "Font applied";
            root.appearance.messageSeverity = root.actionKind === "preview" ? "warning" : "success";
        } else {
            root.appearance.message = root.actionError.length > 0 ? root.actionError
                : "Font helper did not confirm the requested change";
            root.appearance.messageSeverity = "danger";
        }
        Qt.callLater(root.refreshStatus);
        if (root.appearance.settingsVisible) root.appearance.refreshInventory(true);
    }

    onBusyChanged: if (!root.busy) root.appearance.wallpaper.retryQueuedReconcile()

    FileView {
        id: configWatch
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: changeSettleTimer.restart()
        onLoadFailed: changeSettleTimer.restart()
        onFileChanged: reload()
    }

    FileView {
        id: previewWatch
        path: root.previewPath
        watchChanges: true
        printErrors: false
        onLoaded: changeSettleTimer.restart()
        onLoadFailed: changeSettleTimer.restart()
        onFileChanged: reload()
    }

    Process {
        id: readinessProcess
        command: Commands.booleanStatusCommand(Commands.settingsFontCommand("mutation-ready", []))
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.mutationReady = this.text.trim() === "available"
        }
    }

    Process {
        id: statusProcess
        command: Commands.checkedCommand(Commands.settingsFontCommand("status", []))
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: fontStatusError }
        onRunningChanged: {
            if (running) return;
            if (!root.statusParsed) {
                const error = fontStatusError.text.trim();
                root.clearStatus(error.length > 0 ? error
                    : "Font helper failed before returning a valid status");
            }
            if (root.statusPending) Qt.callLater(root.refreshStatus);
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

    Timer {
        id: changeSettleTimer
        interval: 100
        repeat: false
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: statusRetryTimer
        interval: 250
        repeat: false
        onTriggered: root.refreshStatus()
    }

    PreviewCountdown {
        id: countdown
        active: root.appearance.settingsVisible && root.previewState === "active"
        onExpired: Qt.callLater(root.refreshStatus)
    }
}
