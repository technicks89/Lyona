import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string page: "overview"
    property bool utilityVisible: false
    property string utilityPage: ""
    property var utilityScreen: null
    property var panelSettingsModel: null
    readonly property var widgetIds: ({
        "Workspaces": "workspaces",
        "Volume": "volume",
        "Bluetooth": "bluetooth",
        "Network": "network",
        "Power": "power",
        "Calendar": "calendar",
        "Weather": "weather"
    })
    readonly property bool showVolumeWidget: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("volume") : true
    readonly property bool showBluetoothWidget: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("bluetooth") : true
    readonly property bool showNetworkWidget: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("network") : true
    readonly property bool showPowerWidget: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("power") : true
    readonly property bool showWorkspaceWidget: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("workspaces") : true
    property string message: ""
    property string pendingAction: ""
    property bool actionSucceeded: false
    property string actionError: ""
    property var powerModel: null
    property var infoRows: []
    property var themeRows: []
    property var keybindRows: []
    // Quick Actions that need something optional, from the helper's
    // optional-actions: Self-Heal once configured, GTK Settings with nwg-look.
    property var optionalActions: []
    property bool actionInTerminal: false
    readonly property var actions: {
        const availableActions = [
            { "id": "restart-picom", "label": "Restart Picom" },
            { "id": "restart-quickshell", "label": "Restart Quickshell" },
            { "id": "reload-wallpaper", "label": "Reload Wallpaper" },
            { "id": "restart-networkmanager", "label": "Restart NetworkManager" },
            { "id": "dependency-check", "label": "Dependency Check" },
            { "id": "install-missing-deps", "label": "Install Missing Deps" },
            { "id": "open-wallpapers", "label": "Wallpaper Folder" }
        ];
        if (root.optionalActions.indexOf("self-heal") >= 0) {
            availableActions.push({ "id": "self-heal", "label": "Self-Heal" });
        }
        if (root.optionalActions.indexOf("gtk-settings") >= 0) {
            availableActions.push({ "id": "gtk-settings", "label": "GTK Settings" });
        }
        return availableActions;
    }

    function actionLabel(action) {
        for (const entry of root.actions) {
            if (entry.id === action) {
                return entry.label;
            }
        }
        return action;
    }
    function openPage(name, message, process) {
        if (root.powerModel) {
            if (name === "power" && !root.powerModel.controlCenterVisible)
                root.powerModel.openControlCenter();
            else if (name !== "power" && root.powerModel.controlCenterVisible)
                root.powerModel.closeControlCenter();
        }
        root.page = name;
        root.message = message;
        if (process && !process.running) {
            process.running = true;
        }
    }

    function open() {
        root.visible = true;
        root.openOverview();
    }

    function close() {
        if (root.powerModel) root.powerModel.closeControlCenter();
        root.visible = false;
        root.page = "overview";
        root.message = "";
    }

    function closeUtility() {
        root.utilityVisible = false;
        root.utilityPage = "";
        root.utilityScreen = null;
        root.message = "";
    }

    function widgetEnabled(name) {
        const id = root.widgetIds[name];
        if (id === undefined) return true;
        // The weather is off until it is turned on (D-19, Sync Sprint 12 S12-20).
        if (!root.panelSettingsModel) return id !== "weather";
        return root.panelSettingsModel.widgetEnabled(id);
    }

    function toggleWidget(name) {
        const id = root.widgetIds[name];
        if (!root.panelSettingsModel || id === undefined) return;
        root.panelSettingsModel.toggleWidget(id);
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh() {
        root.refreshCurrentPage();
    }

    function openOverview() {
        root.openPage("overview", "", null);
    }

    function openWidgets() {
        root.openPage("widgets", "", null);
    }

    function openActions() {
        root.openPage("actions", "", null);
        if (!optionalActionsProcess.running) {
            optionalActionsProcess.running = true;
        }
    }

    function openAppearance() {
        root.openPage("appearance", "Loading themes...", themesProcess);
    }

    function openKeybinds() {
        root.openKeybindsOnScreen(root.utilityScreen);
    }

    function openKeybindsOnScreen(screen) {
        root.utilityScreen = screen;
        root.utilityPage = "keybinds";
        root.utilityVisible = true;
        root.openPage("keybinds", "Loading keybinds...", keybindsProcess);
    }

    function openPower() {
        root.openPage("power", "", null);
    }

    function openInfo() {
        root.openInfoOnScreen(root.utilityScreen);
    }

    function openInfoOnScreen(screen) {
        root.utilityScreen = screen;
        root.utilityPage = "info";
        root.utilityVisible = true;
        root.openPage("info", "Loading system info...", infoProcess);
    }

    function refreshCurrentPage() {
        if (root.page === "appearance") {
            root.openAppearance();
        } else if (root.page === "keybinds") {
            root.openKeybinds();
        } else if (root.page === "power") {
            if (root.powerModel) root.powerModel.refresh();
        } else if (root.page === "info") {
            root.openInfo();
        }
    }

    function parseRows(text, names) {
        const rows = [];
        const lines = text.trim().split("\n");

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim().length === 0) {
                continue;
            }

            const fields = lines[i].split("\t");
            const row = {};
            for (let f = 0; f < names.length; f++) {
                row[names[f]] = fields.length > f ? fields[f] : "";
            }
            rows.push(row);
        }

        return rows;
    }

    function runAction(action) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.pendingAction = action;
        root.actionSucceeded = false;
        root.actionError = "";
        root.actionInTerminal = false;
        root.message = "Running " + root.actionLabel(action) + "...";
        actionProcess.command = Commands.controlCenterHelperCommand("action", [action]);
        actionProcess.running = true;
    }

    function setTheme(name) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.message = "Applying " + name + "...";
        themeSetProcess.command = Commands.controlCenterHelperCommand("theme-set", [name]);
        themeSetProcess.running = true;
    }

    Process {
        id: infoProcess

        command: Commands.controlCenterHelperCommand("info")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.infoRows = root.parseRows(this.text, ["label", "value"]);
                root.message = "";
            }
        }
    }

    Process {
        id: themesProcess

        command: Commands.controlCenterHelperCommand("themes")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.themeRows = root.parseRows(this.text, ["status", "name"]);
                root.message = root.themeRows.length + " themes";
            }
        }
    }

    Process {
        id: keybindsProcess

        command: Commands.controlCenterHelperCommand("keybinds")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.keybindRows = root.parseRows(this.text, ["keys", "description"]);
                root.message = root.keybindRows.length + " keybinds";
            }
        }
    }

    Process {
        id: optionalActionsProcess

        command: Commands.controlCenterHelperCommand("optional-actions")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.optionalActions = root.parseRows(this.text, ["kind", "id"])
                .filter(row => row.kind === "optional-action").map(row => row.id)
        }
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.actionSucceeded = this.text.indexOf("action\t") === 0;
                const line = this.text.split("\n").find(row => row.indexOf("action\t") === 0) || "";
                root.actionInTerminal = line.split("\t")[2] === "terminal";
            }
        }

        stderr: StdioCollector {
            onStreamFinished: root.actionError = this.text.trim().slice(0, 1024)
        }

        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                const label = root.actionLabel(root.pendingAction);
                root.message = root.actionSucceeded
                    ? label + (root.actionInTerminal ? ": opened in a terminal" : ": done")
                    : (root.actionError.length > 0 ? root.actionError : label + " failed");
                root.pendingAction = "";
                root.refreshCurrentPage();
            }
        }
    }

    Process {
        id: themeSetProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                root.message = "Theme applied";
                root.openAppearance();
            }
        }
    }

}
