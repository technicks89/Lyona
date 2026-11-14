import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

Scope {
    id: root

    readonly property bool initialLoading: statusProcess.running || root.refreshPending

    property string providerState: "idle"
    property string providerDetail: "Loading panel settings"
    property bool busy: false
    property string message: ""
    property string pendingWidget: ""
    property string pendingValue: ""
    property bool statusParsed: false
    property bool refreshPending: false
    property bool mutationRefreshPending: false
    property bool actionSucceeded: false
    property var values: ({
        "workspaces": true,
        "volume": true,
        "bluetooth": true,
        "network": true,
        "power": true,
        "calendar": true,
        "weather": false,
        "keyboard": true
    })
    // Options, which are not widgets (#472): the clock shows seconds.
    property bool clockSeconds: false
    readonly property string configHome: Xdg.configHome
    readonly property string configPath: root.configHome + "/lyona/panel-widgets.conf"
    readonly property bool mutationReady: root.providerState !== "unavailable"
    readonly property var widgets: [
        { "id": "workspaces", "label": "Workspaces" },
        { "id": "volume", "label": "Volume" },
        { "id": "bluetooth", "label": "Bluetooth" },
        { "id": "network", "label": "Network" },
        { "id": "power", "label": "Power" },
        // Sync Sprint 12 S12-20: the clock's month calendar, and the weather,
        // which is off until turned on (decision D-19).
        { "id": "calendar", "label": "Calendar" },
        { "id": "weather", "label": "Weather" },
        // #470: shown only with two or more keyboard layouts.
        { "id": "keyboard", "label": "Keyboard layout" }
    ]

    function validWidget(id) {
        return id === "workspaces" || id === "volume" || id === "bluetooth"
            || id === "network" || id === "power" || id === "calendar" || id === "weather"
            || id === "keyboard";
    }

    function validOption(id) {
        return id === "clock-seconds";
    }

    function widgetEnabled(id) {
        if (!root.validWidget(id)) return true;
        return id === "weather" ? root.values[id] === true : root.values[id] !== false;
    }

    function useDefaults() {
        root.values = ({
            "workspaces": true,
            "volume": true,
            "bluetooth": true,
            "network": true,
            "power": true,
            "calendar": true,
            "weather": false,
            "keyboard": true
        });
        root.clockSeconds = false;
    }

    function refresh() {
        QueuedRun.startOrQueue(statusProcess, root, "refreshPending", false, function() {
            root.statusParsed = false;
        });
    }

    // The header, the state, a widget line for each widget, option lines (1.1,
    // #472) and the end; a record of a kind or name this does not know is
    // skipped, as Protocol.js says, so a later minor version still reads.
    function parseStatus(text) {
        const lines = text.trim().split("\n");
        if (lines.length < 3 || !Protocol.isHeader(lines[0].split("\t"), "panel-settings-protocol", 1)
                || lines[lines.length - 1] !== "complete\tstatus") return;
        const state = lines[1].split("\t");
        if (state.length !== 3 || state[0] !== "state"
                || ["available", "defaults", "partial", "unavailable"].indexOf(state[1]) < 0)
            return;
        const parsed = {};
        const options = {};
        for (let index = 2; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            if (fields.length !== 3 || (fields[0] !== "widget" && fields[0] !== "option")) continue;
            const known = fields[0] === "widget" ? root.validWidget(fields[1]) : root.validOption(fields[1]);
            const seen = fields[0] === "widget" ? parsed : options;
            if (!known) continue;
            if ((fields[2] !== "enabled" && fields[2] !== "disabled") || seen[fields[1]] !== undefined) return;
            seen[fields[1]] = fields[2] === "enabled";
        }
        for (const widget of root.widgets) {
            if (parsed[widget.id] === undefined) return;
        }
        root.values = parsed;
        root.clockSeconds = options["clock-seconds"] === true;
        root.providerState = state[1];
        root.providerDetail = state[2];
        root.statusParsed = true;
    }

    function setWidget(id, enabled) {
        if ((!root.validWidget(id) && !root.validOption(id)) || root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingWidget = id;
        root.pendingValue = enabled ? "enabled" : "disabled";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(
            Commands.panelSettingsCommand("set", [id, root.pendingValue]));
        actionProcess.running = true;
    }

    function toggleWidget(id) {
        root.setWidget(id, !root.widgetEnabled(id));
    }

    function reset() {
        if (root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingWidget = "all";
        root.pendingValue = "defaults";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(Commands.panelSettingsCommand("reset", []));
        actionProcess.running = true;
    }

    function parseAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || !Protocol.isHeader(lines[0].split("\t"), "panel-settings-action-protocol", 1)) return;
        const fields = lines[1].split("\t");
        if (fields.length !== 4 || fields[0] !== "result") return;
        if (fields[1] === "set")
            root.actionSucceeded = fields[2] === root.pendingWidget
                && fields[3] === root.pendingValue;
        else if (fields[1] === "reset")
            root.actionSucceeded = root.pendingWidget === "all"
                && fields[2] === "all" && fields[3] === "defaults";
    }

    Component.onCompleted: root.refresh()

    FileView {
        id: configWatch
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: settleTimer.restart()
        onLoadFailed: settleTimer.restart()
        onFileChanged: reload()
    }

    Timer {
        id: settleTimer
        interval: 75
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess
        command: Commands.panelSettingsCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: statusError }
        onRunningChanged: if (!running) {
            if (!root.statusParsed) {
                root.useDefaults();
                root.providerState = "unavailable";
                root.providerDetail = statusError.text.trim().length > 0
                    ? statusError.text.trim() : "Panel settings provider returned invalid data";
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
            root.message = root.actionSucceeded ? "Panel visibility updated"
                : actionError.text.trim().length > 0 ? actionError.text.trim()
                : "Panel settings helper did not confirm the change";
            root.mutationRefreshPending = true;
            Qt.callLater(root.refresh);
        }
    }
}
