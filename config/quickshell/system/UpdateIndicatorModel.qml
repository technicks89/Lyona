import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The panel's updates-available indicator (Sync Sprint 15 S15-02, decision
// D-25). It counts what can be updated and links to Settings > System, which
// stays the one place updates are run.
//
// - System packages come from lyona-update-indicator, which counts them with
//   checkupdates and changes nothing. The lyona release comes from the shell's
//   UpdateModel, whose own check already runs once after login.
// - When: a few minutes after login; at the interval the user sets (remote
//   repositories have no change signal, so this is the sampled fallback); when
//   NetworkManager reports a connection, through its D-Bus signal; and by hand,
//   from Settings only.
// - One check at a time: a check never starts while the last one runs. An
//   automatic check also waits out minimumGapMs after the last successful one,
//   so a flapping connection cannot repeat it.
// - The release is re-checked automatically only while update.conf's
//   check_on_login allows automatic checks.
Scope {
    id: root

    required property var updateModel

    // System packages, from the last check.
    property string systemState: "unknown" // unknown | available | current | unavailable | error
    property int systemCount: 0
    property string systemDetail: ""
    property double lastSuccessMs: 0

    // The settings, as the helper reports them.
    property int intervalHours: 6
    property bool showWhenCurrent: false
    property bool settingsBusy: false
    property string message: ""

    // Whether NetworkManager can be watched; false once the helper says it
    // cannot, so the watcher is not restarted for nothing.
    property bool networkWatched: true

    readonly property int minimumGapMs: 10 * 60 * 1000
    readonly property bool checking: checkProcess.running
    readonly property bool releaseAvailable: root.updateModel !== null && root.updateModel.updateAvailable
    readonly property int count: root.systemCount + (root.releaseAvailable ? 1 : 0)
    // Not while an update runs: its own progress pill shows then.
    readonly property bool shown: root.updateModel !== null && !root.updateModel.progressShown
        && (root.count > 0 || root.showWhenCurrent)
    readonly property string summary: {
        const parts = [];
        if (root.systemCount > 0)
            parts.push(root.systemCount === 1 ? "1 package update" : root.systemCount + " package updates");
        if (root.releaseAvailable)
            parts.push("lyona " + root.updateModel.availableVersion);
        if (parts.length > 0) return parts.join(", ") + " - open Settings to update";
        if (root.systemState === "error" || root.systemState === "unavailable") return root.systemDetail;
        return "Everything is up to date";
    }

    function check(manual) {
        if (checkProcess.running) return;
        if (!manual && root.lastSuccessMs > 0 && Date.now() - root.lastSuccessMs < root.minimumGapMs) return;
        checkProcess.running = true;
        if (root.updateModel !== null && !root.updateModel.busy && (manual || root.updateModel.checkOnLogin))
            root.updateModel.refreshCheck();
    }

    // All or nothing: a malformed reply never changes the count.
    function parseCheck(text) {
        const lines = text.trim().split("\n");
        if (lines.length < 3 || lines[0] !== "update-indicator-protocol\t1\t0"
                || lines[lines.length - 1] !== "complete\tcheck") {
            root.systemState = "error";
            root.systemDetail = "The update check returned invalid data";
            return;
        }
        let system = null;
        for (let index = 1; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            if (fields.length !== 5 || fields[0] !== "provider") continue;
            if (fields[1] !== "system") continue;
            const count = Number(fields[3]);
            if (["available", "current", "unavailable", "error"].indexOf(fields[2]) < 0
                    || !/^[0-9]+$/.test(fields[3]) || (fields[2] === "available") !== (count > 0)) {
                system = null;
                break;
            }
            system = { state: fields[2], count: count, detail: fields[4] };
        }
        if (system === null) {
            root.systemState = "error";
            root.systemDetail = "The update check returned invalid data";
            return;
        }
        root.systemState = system.state;
        root.systemCount = system.count;
        root.systemDetail = system.detail;
        if (system.state === "available" || system.state === "current") root.lastSuccessMs = Date.now();
    }

    function parseSettings(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 4 || lines[0] !== "update-indicator-protocol\t1\t0"
                || lines[3] !== "complete\tstatus") return false;
        let interval = -1, show = "";
        for (const line of lines.slice(1, 3)) {
            const fields = line.split("\t");
            if (fields.length !== 3 || fields[0] !== "setting") return false;
            if (fields[1] === "interval-hours") interval = Number(fields[2]);
            else if (fields[1] === "show-when-current") show = fields[2];
        }
        if ([1, 3, 6, 12, 24].indexOf(interval) < 0 || (show !== "yes" && show !== "no")) return false;
        root.intervalHours = interval;
        root.showWhenCurrent = show === "yes";
        return true;
    }

    function networkEvent(text) {
        if (text === "network-event\tconnected") root.check(false);
        else if (text === "network-event\tunavailable") root.networkWatched = false;
    }

    function runSetting(action, value) {
        if (root.settingsBusy) return;
        root.settingsBusy = true;
        root.message = "";
        settingProcess.command = Commands.checkedCommand(Commands.updateIndicatorCommand(action, [value]));
        settingProcess.running = true;
    }

    function setIntervalHours(hours) {
        root.runSetting("set-interval", String(hours));
    }

    function setShowWhenCurrent(enabled) {
        root.runSetting("set-show-when-current", enabled ? "yes" : "no");
    }

    Component.onCompleted: {
        statusProcess.running = true;
        networkWatch.start();
        startTimer.restart();
    }

    // After login, once the session has settled; jittered so the sessions on a
    // machine do not all sync the package databases at once.
    Timer {
        id: startTimer
        interval: 2 * 60 * 1000 + Math.floor(Math.random() * 3 * 60 * 1000)
        repeat: false
        onTriggered: root.check(false)
    }

    Timer {
        interval: root.intervalHours * 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.check(false)
    }

    WatchedProcess {
        id: networkWatch
        active: root.networkWatched
        command: Commands.watchCommand(Commands.updateIndicatorCommand("watch-network", []))
        onLine: text => root.networkEvent(text)
    }

    // The settings file can change outside the shell; follow it.
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || "").startsWith("/")
            ? Quickshell.env("XDG_CONFIG_HOME") + "/lyona/update-indicator.conf"
            : (Quickshell.env("HOME") || "") + "/.config/lyona/update-indicator.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: if (!statusProcess.running) statusProcess.running = true
    }

    Process {
        id: checkProcess
        command: Commands.updateIndicatorCommand("check", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseCheck(this.text) }
        stderr: StdioCollector {}
    }

    Process {
        id: statusProcess
        command: Commands.updateIndicatorCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseSettings(this.text) }
        stderr: StdioCollector {}
    }

    Process {
        id: settingProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.message = root.parseSettings(this.text) ? "Saved" : ""
        }
        stderr: StdioCollector { id: settingError }
        onRunningChanged: if (!running) {
            if (root.message.length === 0)
                root.message = settingError.text.trim().length > 0
                    ? settingError.text.trim() : "The setting was not saved";
            root.settingsBusy = false;
        }
    }
}
