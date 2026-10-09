import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

Scope {
    id: root

    readonly property bool initialLoading: statusProcess.running || root.refreshPending

    property string providerState: "idle"
    property string providerDetail: "Loading accessibility policy"
    property bool highContrast: false
    property bool reducedMotion: false
    property bool busy: false
    property string message: ""
    property string mutationState: "unavailable"
    property string mutationDetail: "Loading accessibility policy"
    property bool statusParsed: false
    property bool refreshPending: false
    property bool mutationRefreshPending: false
    property bool actionSucceeded: false
    property string pendingSetting: ""
    property string pendingValue: ""
    readonly property bool mutationReady: root.mutationState === "available"
    readonly property string configHome: Xdg.configHome

    function useDefaults() {
        root.highContrast = false;
        root.reducedMotion = false;
        Theme.applyAccessibility(false, false);
    }

    function refresh() {
        QueuedRun.startOrQueue(statusProcess, root, "refreshPending", false, function() {
            root.statusParsed = false;
        });
    }

    function parseStatus(text) {
        const lines = text.trim().split("\n");
        if (lines.length < 6 || !Protocol.isHeader(lines[0].split("\t"), "accessibility-settings-protocol", 1)
                || lines[lines.length - 1] !== "complete\tstatus") return;
        let state = null;
        let mutation = null;
        const parsed = {};
        for (let index = 1; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            if (fields[0] === "state") {
                if (state !== null || fields.length !== 3 || fields[2].length === 0
                        || ["available", "defaults", "partial", "unavailable"]
                            .indexOf(fields[1]) < 0) return;
                state = fields;
            } else if (fields[0] === "setting") {
                if (fields.length !== 3 || parsed[fields[1]] !== undefined) return;
                if (fields[1] === "contrast"
                        && (fields[2] === "standard" || fields[2] === "high"))
                    parsed.contrast = fields[2];
                else if (fields[1] === "motion"
                        && (fields[2] === "full" || fields[2] === "reduced"))
                    parsed.motion = fields[2];
                else return;
            } else if (fields[0] === "mutation") {
                if (mutation !== null || fields.length !== 3 || fields[2].length === 0
                        || ["available", "unavailable"].indexOf(fields[1]) < 0) return;
                mutation = fields;
            } else if (fields[0] === "accessibility-settings-protocol"
                    || fields[0] === "complete") return;
        }
        if (state === null || mutation === null || parsed.contrast === undefined
                || parsed.motion === undefined) return;
        root.highContrast = parsed.contrast === "high";
        root.reducedMotion = parsed.motion === "reduced";
        Theme.applyAccessibility(root.highContrast, root.reducedMotion);
        root.providerState = state[1];
        root.providerDetail = state[2];
        root.mutationState = mutation[1];
        root.mutationDetail = mutation[2];
        root.statusParsed = true;
    }

    function setSetting(setting, value) {
        if (root.busy || !root.mutationReady) return;
        if (!((setting === "contrast" && (value === "standard" || value === "high"))
                || (setting === "motion" && (value === "full" || value === "reduced")))) return;
        root.busy = true;
        root.pendingSetting = setting;
        root.pendingValue = value;
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(
            Commands.accessibilitySettingsCommand("set", [setting, value]));
        actionProcess.running = true;
    }

    function reset() {
        if (root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingSetting = "all";
        root.pendingValue = "defaults";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(
            Commands.accessibilitySettingsCommand("reset", []));
        actionProcess.running = true;
    }

    function parseAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2
                || !Protocol.isHeader(lines[0].split("\t"), "accessibility-settings-action-protocol", 1)) return;
        const fields = lines[1].split("\t");
        if (fields.length !== 4 || fields[0] !== "result") return;
        if (fields[1] === "set")
            root.actionSucceeded = fields[2] === root.pendingSetting
                && fields[3] === root.pendingValue;
        else if (fields[1] === "reset")
            root.actionSucceeded = root.pendingSetting === "all"
                && fields[2] === "all" && fields[3] === "defaults";
    }

    Component.onCompleted: root.refresh()

    // The one file, watched in the shell (#285): no inotifywait on the whole
    // folder. It sees the file created, replaced and removed; the helper still
    // checks it on every read. A missing folder is never watched, so it is
    // created first, private, as the old watcher did.
    property bool configDirReady: false

    Process {
        id: configDirProcess
        command: ["mkdir", "-p", "-m", "700", "--", root.configHome + "/lyona"]
        running: true
        onRunningChanged: if (!running) root.configDirReady = true
    }

    FileView {
        id: accessibilityWatch
        path: root.configDirReady ? root.configHome + "/lyona/accessibility.conf" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            accessibilitySettle.restart();
        }
    }

    Timer {
        id: accessibilitySettle
        interval: 100
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess
        command: Commands.accessibilitySettingsCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: statusError }
        onRunningChanged: if (!running) {
            if (!root.statusParsed) {
                root.useDefaults();
                root.providerState = "unavailable";
                root.providerDetail = statusError.text.trim().length > 0
                    ? statusError.text.trim()
                    : "Accessibility settings provider returned invalid data";
                root.mutationState = "unavailable";
                root.mutationDetail = root.providerDetail;
            }
            if (root.refreshPending) {
                Qt.callLater(root.refresh);
            } else if (root.mutationRefreshPending) {
                root.mutationRefreshPending = false;
                root.busy = false;
            }
        }
    }

    Process {
        id: actionProcess
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseAction(this.text) }
        stderr: StdioCollector { id: actionError }
        onRunningChanged: if (!running && root.busy) {
            root.message = root.actionSucceeded ? "Accessibility policy updated"
                : actionError.text.trim().length > 0 ? actionError.text.trim()
                : "Accessibility settings helper did not confirm the change";
            root.mutationRefreshPending = true;
            Qt.callLater(root.refresh);
        }
    }
}
