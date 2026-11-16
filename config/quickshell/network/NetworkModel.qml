import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

Scope {
    id: root

    readonly property bool initialLoading: snapshotProcess.running || editorCheckProcess.running

    property bool visible: false
    property bool settingsVisible: false
    property bool busy: false
    // A refresh asked for while a snapshot is running, kept so it runs once the
    // snapshot ends instead of being dropped (Sync Sprint 12 S12-07).
    property bool refreshPending: false
    property bool refreshPendingRescan: false
    property bool editorAvailable: false
    property bool actionUsesPasswordStdin: false
    property bool wifiPasswordPromptVisible: false
    property string wifiPasswordPromptOrigin: ""
    property int selectedIndex: 0
    property int selectedWifiIndex: -1
    property string statusText: "NET offline"
    // NetworkManager reports full connectivity ("connected", not site or
    // local only). Followed by the update indicator (Sync Sprint 16 R16-34).
    property bool online: false
    // Set once the first snapshot has been read, so that "online" changing
    // from its default at login is not taken for a connection coming up.
    property bool stateKnown: false
    property string message: ""
    property string providerState: "idle"
    property string providerDetail: ""
    property string operationState: "read-only"
    property string actionOrigin: ""
    property string actionLabel: ""
    property string snapshotOrigin: ""
    property bool actionFailed: false
    property string wifiPassword: ""
    property var devices: []
    property var connections: []
    property var wifiNetworks: []
    property bool editorChecked: false
    // Joining a hidden network (#471, upstream dwm-titus #379). The prompt
    // opens once a snapshot has named the adapters, and a snapshot never closes
    // it: one that fails keeps a pending prompt waiting, and one that changes
    // the adapters only updates what it says.
    property bool hiddenPromptVisible: false
    property bool hiddenPromptPending: false
    property string hiddenSsid: ""
    property string hiddenSecurity: "wpa-psk"
    property string hiddenPassword: ""
    property string hiddenMessage: ""
    readonly property var wifiDeviceNames: root.devices.filter(function(device) {
        return device.type === "wifi";
    }).map(function(device) {
        return device.device;
    })
    readonly property bool promptVisible: root.wifiPasswordPromptVisible || root.hiddenPromptVisible

    readonly property var activeConnections: root.connections.filter(function(profile) {
        return profile.active;
    })
    readonly property var savedProfiles: root.connections.filter(function(profile) {
        return !profile.active && root.isSupportedProfile(profile.type);
    })
    readonly property bool active: true
    readonly property bool actionsAvailable: (providerState === "available" || providerState === "restricted")
        && operationState === "delegated"

    function isSupportedProfile(type) {
        return type === "802-3-ethernet" || type === "ethernet" || type === "802-11-wireless" || type === "wifi" || type === "vpn";
    }

    function supportsFixedWifiSecurity(security) {
        const value = (security || "").toUpperCase();
        return value.indexOf("802.1X") < 0 && value.indexOf("EAP") < 0
            && value.indexOf("ENTERPRISE") < 0;
    }

    function open() {
        root.visible = true;
        root.refresh(true);
    }

    function close() {
        root.visible = false;
        if (!hiddenJoinProcess.running) root.cancelHiddenPrompt();
        root.selectedIndex = 0;
        root.selectedWifiIndex = -1;
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.message = "";
        root.wifiPassword = "";
        root.stopUnownedWork("panel");
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refresh(false, "settings");
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.selectedWifiIndex = -1;
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.wifiPassword = "";
        root.stopUnownedWork("settings");
    }

    function stopUnownedWork(origin) {
        if (root.actionOrigin === origin && actionProcess.running) actionProcess.running = false;
        if (root.snapshotOrigin === origin && snapshotProcess.running) snapshotProcess.running = false;
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh(rescanWifi, origin) {
        if (!root.active) return;
        if (snapshotProcess.running) {
            root.refreshPending = true;
            root.refreshPendingRescan = root.refreshPendingRescan || rescanWifi === true;
            return;
        }
        root.providerState = "loading";
        root.snapshotOrigin = origin || (root.visible ? "panel" : "shared");
        // The Wi-Fi list only while a network window shows it (#285): a
        // change while both are closed reads the rest of the state alone.
        const wantWifi = root.visible || root.settingsVisible;
        snapshotProcess.command = Commands.networkHelperCommand("snapshot",
            ["--wifi", wantWifi ? "yes" : "no", "--rescan", rescanWifi && wantWifi ? "yes" : "no"]);
        snapshotProcess.running = true;
        // nm-connection-editor is looked up once, not on every refresh.
        if (!root.editorChecked && !editorCheckProcess.running) {
            editorCheckProcess.running = true;
        }
    }

    function refreshWifi(rescan, origin) {
        root.refresh(rescan === true, origin);
    }

    function parseSnapshot(text) {
        const devices = [];
        const connections = [];
        const wifiNetworks = [];
        let protocolValid = false;
        let providerSeen = false;
        let malformed = false;
        let connectedDevice = "";
        let generalState = "";
        root.operationState = "read-only";

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "connectivity-protocol") {
                protocolValid = Protocol.validHeader(fields, 1);
            } else if (fields[0] === "provider") {
                if (fields.length < 5 || fields[1] !== "network") { malformed = true; continue; }
                providerSeen = true;
                root.providerState = fields[2];
                root.operationState = fields[3];
                root.providerDetail = fields[4];
            } else if (fields[0] === "network-state") {
                if (fields.length >= 2) generalState = fields[1];
            } else if (fields[0] === "network-device") {
                if (fields.length < 5) { malformed = true; continue; }
                devices.push({ "device": fields[1], "type": fields[2], "state": fields[3], "connection": fields[4] === "-" ? "" : fields[4] });
                if (connectedDevice.length === 0 && fields[3] === "connected") connectedDevice = fields[1];
            } else if (fields[0] === "network-profile") {
                if (fields.length < 6) { malformed = true; continue; }
                connections.push({ "name": fields[1], "uuid": fields[2], "type": fields[3], "active": fields[4] === "yes", "device": fields[5] === "-" ? "" : fields[5] });
            } else if (fields[0] === "wifi-network") {
                if (fields.length < 8) { malformed = true; continue; }
                const security = fields[5] === "--" ? "" : fields[5];
                wifiNetworks.push({ "active": fields[1] === "*", "bssid": fields[2], "ssid": fields[3],
                    "signal": fields[4], "security": security, "channel": fields[6], "device": fields[7], "secured": security.length > 0 });
            }
        }

        if (!protocolValid || !providerSeen || malformed) {
            root.providerState = "failure";
            root.providerDetail = !protocolValid ? "Unsupported connectivity protocol" : "Malformed network provider record";
            root.statusText = "NET unavailable";
            root.online = false;
            root.stateKnown = true;
            root.devices = [];
            root.connections = [];
            root.wifiNetworks = [];
            root.message = root.providerDetail;
            return;
        }

        root.devices = devices;
        root.connections = connections;
        root.wifiNetworks = wifiNetworks;
        root.online = generalState === "connected";
        root.stateKnown = true;
        const stateReadable = root.providerState === "available" || root.providerState === "restricted";
        // Unavailable names the missing service, such as "NetworkManager not
        // installed", rather than a bare "NET unavailable" (#292).
        root.statusText = stateReadable ? (connectedDevice.length > 0 ? "NET " + connectedDevice : "NET offline")
            : root.providerState === "unavailable" && root.providerDetail.length > 0 ? root.providerDetail
            : "NET unavailable";
        if (root.providerState !== "available") root.message = root.providerDetail;
        else if (!root.actionFailed && !root.busy) root.message = "";
        if (root.selectedIndex >= connections.length) root.selectedIndex = Math.max(0, connections.length - 1);
        if (root.selectedWifiIndex >= wifiNetworks.length) root.selectedWifiIndex = -1;
        root.hiddenSnapshotRead();
    }

    // A snapshot was read: a pending prompt opens, and an open one says
    // whether there is an adapter to join with.
    function hiddenSnapshotRead() {
        if (root.hiddenPromptPending) {
            root.hiddenPromptPending = false;
            root.hiddenPromptVisible = true;
        }
        if (!root.hiddenPromptVisible || hiddenJoinProcess.running) return;
        const noAdapter = "No Wi-Fi adapter: connect one to join a network.";
        if (root.wifiDeviceNames.length === 0) root.hiddenMessage = noAdapter;
        else if (root.hiddenMessage === noAdapter) root.hiddenMessage = "";
    }

    function openHiddenPrompt() {
        if (root.busy || root.hiddenPromptVisible) return;
        root.hiddenPassword = "";
        root.hiddenMessage = "";
        root.cancelWifiPasswordPrompt();
        // Until a snapshot has been read the adapters are unknown.
        if (!root.stateKnown || snapshotProcess.running) {
            root.hiddenPromptPending = true;
            if (!snapshotProcess.running) root.refresh(false);
            return;
        }
        root.hiddenPromptVisible = true;
        root.hiddenSnapshotRead();
    }

    property string hiddenCancelledName: ""

    // Cancel in the prompt (#529): closes it at once, also while joining. The
    // helper is stopped and removes the profile it was adding; it can only do
    // that once its nmcli call returns, so the popover says so until it has.
    function cancelHiddenJoin() {
        if (!hiddenJoinProcess.running) {
            root.cancelHiddenPrompt();
            return;
        }
        root.hiddenCancelledName = root.hiddenSsid;
        root.cancelHiddenPrompt();
        root.message = "Cancelling the join of " + root.hiddenCancelledName + "...";
        hiddenJoinProcess.running = false;
    }

    function cancelHiddenPrompt() {
        root.hiddenPromptVisible = false;
        root.hiddenPromptPending = false;
        root.hiddenSsid = "";
        root.hiddenPassword = "";
        root.hiddenMessage = "";
        root.hiddenSecurity = "wpa-psk";
    }

    // The name in UTF-8 bytes, which 802.11 limits to 32.
    function utf8Length(text) {
        return encodeURIComponent(text).replace(/%[0-9A-F]{2}/g, "x").length;
    }

    // Why the hidden join cannot start yet, or "" when it can; the helper
    // checks the same again.
    function hiddenJoinProblem() {
        if (!root.actionsAvailable) return "NetworkManager is not available";
        if (root.wifiDeviceNames.length === 0) return "No Wi-Fi adapter";
        const length = root.utf8Length(root.hiddenSsid);
        if (length < 1) return "Enter the network name";
        if (length > 32) return "A network name is at most 32 bytes";
        if (/[\u0000-\u001f\u007f]/.test(root.hiddenSsid)) return "The network name has a control character";
        if (root.hiddenSecurity === "wpa-psk") {
            const password = root.hiddenPassword;
            if (password.length === 64 ? !/^[0-9A-Fa-f]{64}$/.test(password)
                    : password.length < 8 || password.length > 63)
                return "A WPA password is 8 to 63 characters";
        } else if (root.hiddenSecurity === "sae" && root.hiddenPassword.length === 0) {
            return "Enter the password";
        }
        return "";
    }

    function joinHidden() {
        if (root.busy || hiddenJoinProcess.running || root.hiddenJoinProblem().length > 0) return;
        const args = [root.wifiDeviceNames[0], root.hiddenSsid, root.hiddenSecurity];
        if (root.hiddenSecurity !== "open") args.push("--password-stdin");
        root.busy = true;
        root.hiddenMessage = "Joining " + root.hiddenSsid + "...";
        hiddenJoinProcess.command = Commands.networkHelperCommand("wifi-connect-hidden", args);
        hiddenJoinProcess.running = true;
    }

    function parseDevices(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 4) {
                continue;
            }

            rows.push({
                "device": fields[0],
                "type": fields[1],
                "state": fields[2],
                "connection": fields[3]
            });
        }

        root.devices = rows;
    }

    function parseConnections(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 5) {
                continue;
            }

            rows.push({
                "name": fields[0],
                "uuid": fields[1],
                "type": fields[2],
                "active": fields[3] === "yes",
                "device": fields[4]
            });
        }

        root.connections = rows;
        if (root.selectedIndex >= rows.length) {
            root.selectedIndex = Math.max(0, rows.length - 1);
        }
    }

    function parseWifiNetworks(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        const selectedBssid = root.selectedWifiNetwork() ? root.selectedWifiNetwork().bssid : "";

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 7 || fields[2].length === 0) {
                continue;
            }

            const security = fields[4] === "--" ? "" : fields[4];

            rows.push({
                "active": fields[0] === "*",
                "bssid": fields[1],
                "ssid": fields[2],
                "signal": fields[3],
                "security": security,
                "channel": fields[5],
                "device": fields[6],
                "secured": security.length > 0
            });
        }

        root.wifiNetworks = rows;
        root.selectedWifiIndex = -1;

        for (let i = 0; i < rows.length; i++) {
            if (rows[i].bssid === selectedBssid) {
                root.selectedWifiIndex = i;
                break;
            }
        }

        if (root.wifiPasswordPromptVisible && root.selectedWifiIndex < 0) {
            root.cancelWifiPasswordPrompt();
        }
    }

    function selectedWifiNetwork() {
        if (root.selectedWifiIndex < 0 || root.selectedWifiIndex >= root.wifiNetworks.length) {
            return null;
        }

        return root.wifiNetworks[root.selectedWifiIndex];
    }

    function selectWifi(index) {
        if (index < 0 || index >= root.wifiNetworks.length) {
            return;
        }

        if (root.selectedWifiIndex === index) {
            return;
        }

        root.selectedWifiIndex = index;
        root.wifiPasswordPromptVisible = false;
        root.wifiPassword = "";
        root.message = "";
    }

    function cancelWifiPasswordPrompt() {
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.selectedWifiIndex = -1;
        root.wifiPassword = "";
        root.message = "";
    }

    function connectWifi(network, origin) {
        if (!network || network.device.length === 0 || network.bssid.length === 0 || network.ssid.length === 0) {
            return;
        }
        if (!root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        if (!root.supportsFixedWifiSecurity(network.security)) {
            root.message = "Enterprise Wi-Fi opens in Advanced NetworkManager settings";
            root.openEditor();
            return;
        }

        if (network.secured && root.wifiPassword.length === 0) {
            for (let i = 0; i < root.wifiNetworks.length; i++) {
                if (root.wifiNetworks[i].bssid === network.bssid && root.wifiNetworks[i].device === network.device) {
                    root.selectedWifiIndex = i;
                    break;
                }
            }
            root.wifiPasswordPromptVisible = true;
            root.wifiPasswordPromptOrigin = origin || "panel";
            root.message = "";
            return;
        }

        const args = [network.device, network.bssid, network.ssid];
        if (network.secured) {
            args.push("--password-stdin");
            args.push(network.security);
        }

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "connect Wi-Fi";
        root.actionUsesPasswordStdin = network.secured;
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.message = "Connecting " + network.ssid;
        actionProcess.command = Commands.networkHelperCommand("wifi-connect", args);
        actionProcess.running = true;
    }

    function connectSelectedWifi(origin) {
        root.connectWifi(root.selectedWifiNetwork(), origin);
    }

    function connectProfile(profile, origin) {
        if (!profile || profile.uuid.length === 0) {
            return;
        }
        if (!root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "activate profile";
        root.actionUsesPasswordStdin = false;
        root.message = "Connecting " + profile.name;
        actionProcess.command = Commands.networkHelperCommand("connect", [profile.uuid]);
        actionProcess.running = true;
    }

    function disconnectDevice(device, origin) {
        if (!device || device.length === 0) {
            return;
        }
        if (!root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "disconnect device";
        root.actionUsesPasswordStdin = false;
        root.message = "Disconnecting " + device;
        actionProcess.command = Commands.networkHelperCommand("disconnect", [device]);
        actionProcess.running = true;
    }

    function forgetProfile(profile, origin) {
        if (!root.actionsAvailable || !profile || profile.uuid.length === 0 || root.busy || actionProcess.running) return;
        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "forget profile";
        root.actionUsesPasswordStdin = false;
        root.message = "Forgetting " + profile.name;
        actionProcess.command = Commands.networkHelperCommand("forget", [profile.uuid]);
        actionProcess.running = true;
    }

    function openEditor() {
        if (!root.editorAvailable) {
            return;
        }

        editorProcess.running = true;
    }

    Process {
        id: snapshotProcess

        command: Commands.networkHelperCommand("snapshot", ["--rescan", "no"])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseSnapshot(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) {
                    root.providerState = "failure";
                    root.providerDetail = error;
                    root.message = error;
                }
            }
        }
        onRunningChanged: {
            if (running) return;
            root.snapshotOrigin = "";
            if (root.refreshPending) {
                const rescan = root.refreshPendingRescan;
                root.refreshPending = false;
                root.refreshPendingRescan = false;
                Qt.callLater(root.refresh, rescan, "shared");
            }
        }
    }

    Process {
        id: statusProcess

        command: Commands.networkHelperCommand("status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();

                root.statusText = text.length > 0 ? text : "NET offline";
            }
        }
    }

    Process {
        id: devicesProcess

        command: Commands.networkHelperCommand("devices")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(this.text)
        }
    }

    Process {
        id: connectionsProcess

        command: Commands.networkHelperCommand("connections")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseConnections(this.text)
        }
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false
        stdinEnabled: true

        onStarted: {
            if (root.actionUsesPasswordStdin) {
                write(root.wifiPassword + "\n");
                root.actionUsesPasswordStdin = false;
                root.wifiPassword = "";
            }
        }

        onRunningChanged: {
            if (!running) {
                root.busy = false;
                root.actionUsesPasswordStdin = false;
                root.wifiPassword = "";
                if (!root.actionFailed) root.message = "";
                root.refresh(false);
                root.actionOrigin = "";
                root.actionLabel = "";
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) {
                    root.actionFailed = true;
                    root.message = root.actionLabel + " failed: " + error;
                }
            }
        }
    }

    // The hidden join: the password on stdin, then forgotten; on failure the
    // prompt stays, with the name kept and the reason shown.
    Process {
        id: hiddenJoinProcess

        running: false
        stdinEnabled: true
        stderr: StdioCollector { id: hiddenJoinError }

        onStarted: {
            if (root.hiddenSecurity !== "open") write(root.hiddenPassword + "\n");
            root.hiddenPassword = "";
        }
        onExited: exitCode => {
            root.busy = false;
            if (root.hiddenCancelledName.length > 0) {
                // A join that finished before the stop took effect is kept by
                // the helper (it exits 0): say so, not that it was cancelled.
                root.message = (exitCode === 0 ? "Joined " : "Did not join ") + root.hiddenCancelledName;
                root.hiddenCancelledName = "";
                root.refresh(false);
                return;
            }
            if (exitCode === 0) {
                const name = root.hiddenSsid;
                root.cancelHiddenPrompt();
                root.message = "Joined " + name;
            } else {
                const error = hiddenJoinError.text.trim();
                root.hiddenMessage = error.length > 0 ? error.split("\n")[0] : "Could not join the network";
            }
            root.refresh(false);
        }
    }

    Process {
        id: wifiScanProcess

        command: Commands.networkHelperCommand("wifi-scan", ["--rescan", "no"])
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseWifiNetworks(this.text)
        }
    }

    // Always on, and restarted 3 s after it exits. A burst of monitor lines (one
    // change prints several) is one refresh, after the lines settle for 300 ms
    // (Sync Sprint 12 S12-14: on WatchedProcess, not its own Process and timers).
    WatchedProcess {
        id: networkMonitor
        command: Commands.watchCommand(Commands.networkHelperCommand("monitor"))
        active: true
        settleInterval: 300
        onSettled: root.refresh(false, "shared")
        Component.onCompleted: networkMonitor.start()
    }

    Process {
        id: editorProcess

        command: Commands.networkHelperCommand("editor")
        running: false
    }

    Process {
        id: editorCheckProcess

        command: ["sh", "-c", "command -v nm-connection-editor >/dev/null 2>&1 && printf yes || printf no"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.editorAvailable = this.text.trim() === "yes";
                root.editorChecked = true;
            }
        }
    }
}
