import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

pragma ComponentBehavior: Bound

/*
 * The cursor, icon, GTK and Qt overrides of Settings > Appearance, through
 * dwm-settings-toolkit (#282): split from AppearanceModel.qml, as
 * PicomModel.qml was. The message line, Settings' visibility and the other
 * appearance changes it waits for are the Appearance model's, given as
 * `appearance`.
 */
Scope {
    id: root

    required property var appearance

    // Cursor, icon, GTK and Qt overrides. Each capability is independent: a
    // sentinel hands one back to the active theme without disturbing the rest.
    property string providerState: "idle"
    property string providerDetail: "Toolkit provider has not been checked"
    property bool mutationReady: false
    property string mutationDetail: "Toolkit changes have not been checked"
    property var selections: ({})
    property var candidates: ({})
    property bool busy: false
    readonly property bool statusBusy: statusProcess.running
    property bool statusParsed: false
    property bool statusPending: false
    property string previewState: "none"
    property string previewToken: ""
    property string previewCapability: ""
    property string previewValue: ""
    property alias previewRemaining: countdown.remaining
    property string previewDetail: ""
    property string actionKind: ""
    property string actionCapability: ""
    property string actionValue: ""
    property string actionToken: ""
    property string actionError: ""
    property bool actionSucceeded: false
    readonly property var capabilities: ["cursor", "icon", "gtk", "qt"]
    readonly property var sentinels: ({
        "cursor": "follow-theme",
        "icon": "follow-system",
        "gtk": "follow-theme",
        "qt": "follow-theme"
    })
    readonly property var titles: ({
        "cursor": "Cursor theme",
        "icon": "Icon theme",
        "gtk": "GTK theme",
        "qt": "Qt platform theme"
    })

    function sentinelFor(capability) {
        return root.sentinels[capability] || "follow-theme";
    }

    function selectionFor(capability) {
        const entry = root.selections[capability];
        if (entry === undefined) {
            return { "state": "idle", "option": root.sentinelFor(capability),
                "live": "", "detail": "Toolkit state has not been loaded" };
        }
        return entry;
    }

    function candidatesFor(capability) {
        const entry = root.candidates[capability];
        return entry === undefined ? [] : entry;
    }

    function clearStatus(detail) {
        root.providerState = "unavailable";
        root.providerDetail = detail;
        root.mutationReady = false;
        root.mutationDetail = detail;
        root.selections = ({});
        root.candidates = ({});
        root.previewState = "none";
        root.previewToken = "";
        root.previewCapability = "";
        root.previewValue = "";
        root.previewRemaining = 0;
        root.previewDetail = "";
    }

    function refreshStatus() {
        QueuedRun.startOrQueue(statusProcess, root, "statusPending", actionProcess.running,
            function() { root.statusParsed = false; });
    }

    function parseStatus(text) {
        let protocolValid = false;
        let complete = false;
        let provider = null;
        let preview = null;
        let mutation = null;
        const selections = ({});
        const candidates = ({});
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "toolkit-action-protocol") {
                protocolValid = Protocol.validHeader(fields, 1);
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "toolkit" && root.appearance.validInventoryField(fields[4], false)) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "selection" && fields.length === 6
                    && root.capabilities.indexOf(fields[1]) !== -1
                    && root.appearance.validInventoryField(fields[3], false)
                    && root.appearance.validInventoryField(fields[4], true)
                    && root.appearance.validInventoryField(fields[5], false)) {
                selections[fields[1]] = { "state": fields[2], "option": fields[3],
                    "live": fields[4], "detail": fields[5] };
            } else if (fields[0] === "candidate" && fields.length === 3
                    && root.capabilities.indexOf(fields[1]) !== -1
                    && root.appearance.validInventoryField(fields[2], false)) {
                if (candidates[fields[1]] === undefined) candidates[fields[1]] = [];
                candidates[fields[1]].push(fields[2]);
            } else if (fields[0] === "preview" && fields.length === 7
                    && (fields[1] === "none" || fields[1] === "active" || fields[1] === "failed")
                    && root.appearance.validInventoryField(fields[2], true)
                    && root.appearance.validInventoryField(fields[3], true)
                    && root.appearance.validInventoryField(fields[4], true)
                    && /^[0-9]+$/.test(fields[5])
                    && root.appearance.validInventoryField(fields[6], false)) {
                preview = { "state": fields[1], "token": fields[2], "capability": fields[3],
                    "value": fields[4], "remaining": Number(fields[5]), "detail": fields[6] };
            } else if (fields[0] === "mutation" && fields.length === 3
                    && (fields[1] === "ready" || fields[1] === "blocked")
                    && root.appearance.validInventoryField(fields[2], true)) {
                mutation = { "ready": fields[1] === "ready", "detail": fields[2] };
            } else if (fields[0] === "complete") {
                complete = true;
            }
        }
        // A status that stopped early would otherwise render as a pane with
        // some capabilities missing, which looks like they are unsupported.
        if (!protocolValid || !complete || provider === null || preview === null
                || mutation === null) {
            root.clearStatus("Toolkit helper returned an unsupported response");
            return;
        }
        for (const capability of root.capabilities) {
            if (selections[capability] === undefined) {
                root.clearStatus("Toolkit helper returned an incomplete response");
                return;
            }
        }
        const previewWasActive = root.previewState === "active";
        const previousRemaining = root.previewRemaining;
        root.statusParsed = true;
        root.providerState = provider.state;
        root.providerDetail = provider.detail;
        root.selections = selections;
        root.candidates = candidates;
        root.mutationReady = mutation.ready;
        root.mutationDetail = mutation.detail;
        root.previewState = preview.state;
        root.previewToken = preview.token;
        root.previewCapability = preview.capability;
        root.previewValue = preview.value;
        root.previewRemaining = preview.remaining;
        root.previewDetail = preview.detail;
        if (!previewWasActive && preview.state === "active") {
            root.appearance.message = "Toolkit preview active; keep it within " + preview.remaining
                + (preview.remaining === 1 ? " second" : " seconds") + " or it will revert";
            root.appearance.messageSeverity = "warning";
        } else if (previewWasActive && preview.state === "none" && previousRemaining <= 1) {
            root.appearance.message = "Toolkit preview expired and reverted automatically";
            root.appearance.messageSeverity = "warning";
        }
    }

    function runAction(action, args, capability, value, token) {
        if (root.busy || actionProcess.running || statusProcess.running
                || root.appearance.busy || root.appearance.wallpaper.busy || root.appearance.font.busy) {
            root.appearance.message = "Another appearance change is already in progress";
            root.appearance.messageSeverity = "warning";
            return;
        }
        root.busy = true;
        root.actionKind = action;
        root.actionCapability = capability || "";
        root.actionValue = value || "";
        root.actionToken = token || "";
        root.actionError = "";
        root.actionSucceeded = false;
        root.appearance.message = "Applying toolkit change...";
        root.appearance.messageSeverity = "idle";
        actionProcess.command = Commands.checkedCommand(
            Commands.settingsToolkitCommand(action, args));
        actionProcess.running = true;
    }

    function validChoice(capability, value) {
        if (root.capabilities.indexOf(capability) === -1) return false;
        if (!root.appearance.validInventoryField(value, false)) return false;
        return root.candidatesFor(capability).indexOf(value) !== -1;
    }

    function nextPreviewToken() {
        return "toolkit-" + Date.now().toString(36);
    }

    function preview(capability, value) {
        if (!root.mutationReady || !root.validChoice(capability, value)
                || root.previewState !== "none") return;
        const token = root.nextPreviewToken();
        root.runAction("preview", [token, "30", capability, value],
            capability, value, token);
    }

    function apply(capability, value) {
        if (!root.mutationReady || !root.validChoice(capability, value)
                || root.previewState !== "none") return;
        root.runAction("apply", [capability, value], capability, value, "");
    }

    function reset(capability) {
        if (!root.mutationReady
                || root.capabilities.indexOf(capability) === -1
                || root.previewState !== "none") return;
        root.runAction("reset", [capability], capability,
            root.sentinelFor(capability), "");
    }

    function keepPreview() {
        if (root.previewState !== "active" || root.previewToken.length === 0) return;
        root.runAction("keep", [root.previewToken],
            root.previewCapability, root.previewValue, root.previewToken);
    }

    function revertPreview() {
        if (root.previewState !== "active" || root.previewToken.length === 0) return;
        root.runAction("revert", [root.previewToken],
            root.previewCapability, root.previewValue, root.previewToken);
    }

    function abandonPreview() {
        if (root.previewState !== "failed" || root.previewToken.length === 0) return;
        root.runAction("abandon", [root.previewToken],
            root.previewCapability, root.previewValue, root.previewToken);
    }

    function parseAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || !Protocol.isHeader(lines[0].split("\t"), "toolkit-action-protocol", 1)) return;
        const fields = lines[1].split("\t");
        if (fields.length < 2 || fields[0] !== "result") return;
        const expected = root.actionKind === "preview" ? "preview-started"
            : root.actionKind;
        root.actionSucceeded = fields[1] === expected;
    }

    function finishAction() {
        root.busy = false;
        if (root.actionSucceeded) {
            if (root.actionKind === "preview") {
                root.previewState = "active";
                root.previewToken = root.actionToken;
                root.previewCapability = root.actionCapability;
                root.previewValue = root.actionValue;
                root.previewRemaining = 30;
                root.previewDetail = "Automatic rollback is armed";
            } else if (root.actionKind === "keep" || root.actionKind === "revert"
                    || root.actionKind === "abandon") {
                root.previewState = "none";
                root.previewToken = "";
                root.previewCapability = "";
                root.previewValue = "";
                root.previewRemaining = 0;
                root.previewDetail = "";
            }
            const title = root.titles[root.actionCapability] || "Toolkit";
            root.appearance.message = root.actionKind === "preview"
                ? "Toolkit preview active; keep it within 30 seconds or it will revert"
                : root.actionKind === "keep" ? "Toolkit preview kept"
                    : root.actionKind === "revert" ? "Toolkit preview reverted"
                        : root.actionKind === "abandon" ? "External toolkit state accepted"
                            : root.actionKind === "reset"
                                ? title + " follows the active theme again"
                                : title + " updated";
            root.appearance.messageSeverity = root.actionKind === "preview" ? "warning" : "success";
        } else {
            root.appearance.message = root.actionError.length > 0 ? root.actionError
                : "Toolkit helper did not confirm the requested change";
            root.appearance.messageSeverity = "danger";
        }
        Qt.callLater(root.refreshStatus);
    }

    Process {
        id: statusProcess
        command: Commands.checkedCommand(Commands.settingsToolkitCommand("status", []))
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: statusError }
        onRunningChanged: {
            if (running) return;
            if (!root.statusParsed) {
                const error = statusError.text.trim();
                root.clearStatus(error.length > 0 ? error
                    : "Toolkit helper failed before returning a valid status");
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

    PreviewCountdown {
        id: countdown
        active: root.appearance.settingsVisible && root.previewState === "active"
        onExpired: Qt.callLater(root.refreshStatus)
    }
}
