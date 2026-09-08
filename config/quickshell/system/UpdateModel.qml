import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    // Provider: can lyona-update/lyona-version be reached and trusted at all.
    property string providerState: "idle" // idle | available | offline | unknown | unavailable
    property string providerDetail: "Loading update status"

    // Installed, from lyona-version (a separate helper from lyona-update,
    // per docs/P6-UPDATE-SURFACE.md -- consistent especially must come from
    // there, since it is the one signal that an install is damaged).
    property string installedVersion: ""
    property string installedCommit: ""
    property string installedSource: ""
    property bool consistent: true
    property string installedMismatchDetail: ""

    // Available, from the configured channel.
    property string availableVersion: ""
    property string availableCommit: ""
    property string availableDate: ""
    property string availableChecksum: ""
    property string availableSize: ""

    property string updateState: "unknown" // current | behind | ahead | downgrade-offered | unknown | offline | unavailable
    property string channel: "stable"
    property bool checkOnLogin: true

    // Action / long-running progress.
    property bool busy: false
    property string phase: "idle" // idle|checking|downloading|verifying|building|installing|verifying-install|restarting
    property string progressDetail: ""
    property string message: ""
    property bool actionSucceeded: false

    property var backups: []
    property bool backupsLoaded: false

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string configuredStateHome: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string stateHome: root.configuredStateHome.startsWith("/")
        ? root.configuredStateHome : root.homeDir + "/.local/state"
    readonly property string updateConfPath: root.configHome + "/lyona/update.conf"
    readonly property string statusPath: root.stateHome + "/lyona/update.status"

    readonly property var validUpdateStates: ["current", "behind", "ahead",
        "downgrade-offered", "unknown", "offline", "unavailable"]
    readonly property bool updateAvailable: root.updateState === "behind"
        || root.updateState === "downgrade-offered"

    function refresh() {
        root.refreshCheck();
        root.refreshInstalled();
    }

    function refreshCheck() {
        if (checkProcess.running) return;
        checkProcess.command = Commands.updateCommand("check", []);
        checkProcess.running = true;
    }

    function refreshInstalled() {
        if (versionProcess.running) return;
        versionProcess.running = true;
    }

    function refreshBackups() {
        if (backupsProcess.running) return;
        backupsProcess.running = true;
    }

    function parseCheck(text) {
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        let validProtocol = false;
        let validComplete = false;
        let state = "", stateMessage = "";
        let iVersion = "", iCommit = "";
        let aVersion = "", aCommit = "", aDate = "";
        let assetChecksum = "", assetSize = "";
        let reportedChannel = root.channel;

        for (const line of lines) {
            const fields = line.split("\t");
            if (fields[0] === "lyona-update-protocol" && fields[1] === "1") {
                validProtocol = true;
            } else if (fields[0] === "state" && fields.length >= 3) {
                state = fields[1];
                stateMessage = fields[2];
            } else if (fields[0] === "installed" && fields.length >= 3) {
                iVersion = fields[1];
                iCommit = fields[2];
            } else if (fields[0] === "available" && fields.length >= 4) {
                aVersion = fields[1];
                aCommit = fields[2];
                aDate = fields[3];
            } else if (fields[0] === "channel" && fields.length >= 2) {
                reportedChannel = fields[1];
            } else if (fields[0] === "asset" && fields.length >= 4) {
                assetChecksum = fields[2];
                assetSize = fields[3];
            } else if (fields[0] === "complete" && fields[1] === "check") {
                validComplete = true;
            }
        }

        if (!validProtocol || !validComplete || root.validUpdateStates.indexOf(state) < 0) {
            root.providerState = "unavailable";
            root.providerDetail = "Update provider returned an unsupported response";
            return;
        }

        root.updateState = state;
        root.message = stateMessage;
        root.channel = reportedChannel;
        if (iVersion.length > 0) root.installedVersion = iVersion;
        if (iCommit.length > 0) root.installedCommit = iCommit;
        root.availableVersion = aVersion;
        root.availableCommit = aCommit;
        root.availableDate = aDate;
        root.availableChecksum = assetChecksum;
        root.availableSize = assetSize;

        if (state === "unavailable") {
            root.providerState = "unavailable";
            root.providerDetail = stateMessage;
        } else if (state === "unknown") {
            root.providerState = "unknown";
            root.providerDetail = stateMessage;
        } else if (state === "offline") {
            root.providerState = "offline";
            root.providerDetail = stateMessage;
        } else {
            root.providerState = "available";
            root.providerDetail = stateMessage;
        }
    }

    function parseInstalled(text) {
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        let validProtocol = false;
        let systemVersion = "none", userVersion = "none", binaryVersion = "";
        let userCommit = "", userSource = "", systemCommit = "", systemSource = "";
        let consistentValue = true;
        for (const line of lines) {
            const fields = line.split("\t");
            if (fields[0] === "lyona-version-protocol" && fields[1] === "1") {
                validProtocol = true;
            } else if (fields[0] === "system" && fields.length >= 4) {
                systemVersion = fields[1];
                systemCommit = fields[2];
                systemSource = fields[3];
            } else if (fields[0] === "user" && fields.length >= 4) {
                userVersion = fields[1];
                userCommit = fields[2];
                userSource = fields[3];
            } else if (fields[0] === "binary" && fields.length >= 2) {
                binaryVersion = fields[1];
            } else if (fields[0] === "consistent" && fields.length >= 2) {
                consistentValue = fields[1] === "yes";
            }
        }
        if (!validProtocol) {
            root.consistent = true;
            return;
        }
        if (userVersion !== "none") {
            root.installedVersion = userVersion;
            root.installedCommit = userCommit;
            root.installedSource = userSource;
        } else if (systemVersion !== "none") {
            root.installedVersion = systemVersion;
            root.installedCommit = systemCommit;
            root.installedSource = systemSource;
        }
        root.consistent = consistentValue;
        root.installedMismatchDetail = consistentValue ? "" :
            "system " + systemVersion + ", user " + userVersion + ", binary " + binaryVersion;
    }

    function parseBackups(text) {
        const list = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        let validProtocol = false;
        for (const line of lines) {
            const fields = line.split("\t");
            if (fields[0] === "lyona-update-protocol" && fields[1] === "1") {
                validProtocol = true;
            } else if (fields[0] === "backup" && fields.length >= 3) {
                list.push({ "id": fields[1], "version": fields[2], "date": fields[1].split("-")[0] });
            }
        }
        if (!validProtocol) return;
        root.backups = list;
        root.backupsLoaded = true;
    }

    // update.conf is read directly (not through lyona-update) because the
    // login-time check needs check_on_login before it can decide whether to
    // call the helper at all, and lyona-update's own "check" protocol never
    // echoes that field back.
    function parseConf(text) {
        for (const line of text.split("\n")) {
            const pair = line.split("=");
            if (pair.length !== 2) continue;
            if (pair[0] === "channel" && (pair[1] === "stable" || pair[1] === "preview")) {
                root.channel = pair[1];
            } else if (pair[0] === "check_on_login") {
                root.checkOnLogin = pair[1] === "true";
            }
        }
    }

    function setChannel(value) {
        if (root.busy || (value !== "stable" && value !== "preview")) return;
        root.busy = true;
        channelProcess.command = Commands.updateCommand("set-channel", [value]);
        channelProcess.running = true;
    }

    function apply(version) {
        if (root.busy || !version || version.length === 0) return;
        root.busy = true;
        root.actionSucceeded = false;
        root.phase = "downloading";
        root.progressDetail = "Starting update to " + version;
        root.message = "";
        applyProcess.command = Commands.updateCommand("apply", ["--version", version, "--allow-downgrade", "--yes"]);
        applyProcess.running = true;
    }

    function rollback(backupId) {
        if (root.busy || !backupId || backupId.length === 0) return;
        root.busy = true;
        root.actionSucceeded = false;
        root.phase = "restarting";
        root.progressDetail = "Starting rollback";
        root.message = "";
        rollbackProcess.command = Commands.updateCommand("rollback", ["--backup", backupId, "--yes"]);
        rollbackProcess.running = true;
    }

    // Written by lyona-update at every phase transition of apply/rollback,
    // both of which can restart Quickshell (destroying this model instance
    // mid-action by design -- see docs/P6-UPDATE-SURFACE.md). Watching this
    // file, rather than only the launching Process, is what lets a fresh
    // model instance report the outcome of an update that completed across
    // its own restart instead of that success looking like a crash.
    function parseStatusFile(text) {
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        let validProtocol = false;
        let phaseValue = "", phaseDetail = "", outcome = "", outcomeMessage = "";
        for (const line of lines) {
            const fields = line.split("\t");
            if (fields[0] === "lyona-update-status-protocol" && fields[1] === "1") {
                validProtocol = true;
            } else if (fields[0] === "phase" && fields.length >= 3) {
                phaseValue = fields[1];
                phaseDetail = fields[2];
            } else if (fields[0] === "outcome" && fields.length >= 2) {
                outcome = fields[1];
                outcomeMessage = fields.length >= 3 ? fields[2] : "";
            }
        }
        if (!validProtocol) return;

        if (outcome === "pending") {
            root.busy = true;
            root.phase = phaseValue.length > 0 ? phaseValue : "idle";
            root.progressDetail = phaseDetail;
            return;
        }

        // Terminal: the operation this file describes has already finished,
        // whether that was moments ago in this same session or across a
        // restart this model instance never saw happen.
        root.busy = false;
        root.actionSucceeded = outcome === "succeeded";
        root.phase = "idle";
        root.progressDetail = "";
        root.message = outcome === "succeeded"
            ? "Update complete"
            : (outcomeMessage.length > 0 ? outcomeMessage : "The last update attempt failed");
        if (outcome === "succeeded") Qt.callLater(root.refresh);
    }

    Component.onCompleted: {
        confFile.reload();
        statusFile.reload();
        root.refresh();
        loginCheckJitter.restart();
    }

    FileView {
        id: confFile
        path: root.updateConfPath
        watchChanges: true
        printErrors: false
        onLoaded: root.parseConf(this.text())
        onFileChanged: reload()
    }

    FileView {
        id: statusFile
        path: root.statusPath
        watchChanges: true
        printErrors: false
        onLoaded: root.parseStatusFile(this.text())
        onFileChanged: reload()
    }

    // check_on_login=true (the update.conf default) runs one check shortly
    // after session start, jittered so every session on a machine does not
    // hit the update server at the same instant, and never more than once.
    property bool loginCheckDone: false
    Timer {
        id: loginCheckJitter
        interval: 15000 + Math.floor(Math.random() * 45000)
        repeat: false
        onTriggered: {
            if (root.loginCheckDone || !root.checkOnLogin) return;
            root.loginCheckDone = true;
            root.refreshCheck();
        }
    }

    Process {
        id: checkProcess
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseCheck(this.text) }
        stderr: StdioCollector { id: checkError }
        onRunningChanged: if (!running) {
            if (checkError.text.trim().length > 0 && root.providerState !== "unavailable")
                root.providerDetail = checkError.text.trim();
        }
    }

    Process {
        id: versionProcess
        command: Commands.versionCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseInstalled(this.text) }
        stderr: StdioCollector {}
    }

    Process {
        id: backupsProcess
        command: Commands.updateCommand("backups", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseBackups(this.text) }
        stderr: StdioCollector {}
    }

    Process {
        id: channelProcess
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector { id: channelError }
        onRunningChanged: if (!running) {
            root.busy = false;
            if (channelError.text.trim().length > 0) root.message = channelError.text.trim();
            Qt.callLater(root.refresh);
        }
    }

    // apply/rollback: the Process only reliably reports a failure that
    // happens before the privileged step (before any restart can occur);
    // a successful run's completion is observed through statusFile instead,
    // since a successful apply destroys this Process along with the rest of
    // this model instance when Quickshell restarts.
    Process {
        id: applyProcess
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector { id: applyError }
        onRunningChanged: if (!running && root.busy) {
            if (applyError.text.trim().length > 0) {
                root.busy = false;
                root.actionSucceeded = false;
                root.message = applyError.text.trim();
            }
        }
    }

    Process {
        id: rollbackProcess
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector { id: rollbackError }
        onRunningChanged: if (!running && root.busy) {
            if (rollbackError.text.trim().length > 0) {
                root.busy = false;
                root.actionSucceeded = false;
                root.message = rollbackError.text.trim();
            }
        }
    }
}
