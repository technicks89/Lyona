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
// - Flatpak apps are counted too (S15-03), and Settings runs system and
//   Flatpak updates in a terminal through lyona-update-terminal (S15-04,
//   decision D-26); this model owns that one run at a time.
Scope {
    id: root

    required property var updateModel

    // System packages, from the last check.
    property string systemState: "unknown" // unknown | available | current | unavailable | error
    property int systemCount: 0
    property string systemDetail: ""
    property double lastSuccessMs: 0

    // Flatpak apps, from the same check (S15-03).
    property string flatpakState: "unknown" // unknown | available | current | unavailable | error
    property int flatpakCount: 0
    property string flatpakDetail: ""

    // The settings, as the helper reports them.
    property int intervalHours: 6
    property bool showWhenCurrent: false
    property bool floatTerminal: false
    // Whether window-rules.toml has the rule that floats the update terminal.
    property bool floatRulePresent: false
    property bool settingsBusy: false
    property string message: ""

    // Whether NetworkManager can be watched; false once the helper says it
    // cannot, so the watcher is not restarted for nothing.
    property bool networkWatched: true

    // The update in a terminal (S15-04): which provider, and its last result.
    property string terminalProvider: ""
    property string terminalResult: "" // succeeded | not-updated | interrupted | not-started
    property string terminalDetail: ""
    readonly property bool terminalBusy: terminalProcess.running

    readonly property int minimumGapMs: 10 * 60 * 1000
    readonly property bool checking: checkProcess.running
    readonly property bool releaseAvailable: root.updateModel !== null && root.updateModel.updateAvailable
    readonly property int count: root.systemCount + root.flatpakCount + (root.releaseAvailable ? 1 : 0)
    // Not while an update runs: its own progress pill shows then.
    readonly property bool shown: root.updateModel !== null && !root.updateModel.progressShown
        && (root.count > 0 || root.showWhenCurrent)
    readonly property string summary: {
        const parts = [];
        if (root.systemCount > 0)
            parts.push(root.systemCount === 1 ? "1 package update" : root.systemCount + " package updates");
        if (root.flatpakCount > 0)
            parts.push(root.flatpakCount === 1 ? "1 Flatpak update" : root.flatpakCount + " Flatpak updates");
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

    // All or nothing: a malformed reply never changes a count. The system line is
    // required; Flatpak's is read when present.
    function parseCheck(text) {
        const invalid = function() {
            root.systemState = "error";
            root.systemDetail = "The update check returned invalid data";
        };
        const lines = text.trim().split("\n");
        if (lines.length < 3 || lines[0] !== "update-indicator-protocol\t1\t0"
                || lines[lines.length - 1] !== "complete\tcheck") {
            invalid();
            return;
        }
        const parsed = {};
        for (let index = 1; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            if (fields.length !== 5 || fields[0] !== "provider") continue;
            if (fields[1] !== "system" && fields[1] !== "flatpak") continue;
            const count = Number(fields[3]);
            if (["available", "current", "unavailable", "error"].indexOf(fields[2]) < 0
                    || !/^[0-9]+$/.test(fields[3]) || (fields[2] === "available") !== (count > 0)
                    || parsed[fields[1]] !== undefined) {
                invalid();
                return;
            }
            parsed[fields[1]] = { state: fields[2], count: count, detail: fields[4] };
        }
        if (parsed.system === undefined) {
            invalid();
            return;
        }
        root.systemState = parsed.system.state;
        root.systemCount = parsed.system.count;
        root.systemDetail = parsed.system.detail;
        if (parsed.flatpak !== undefined) {
            root.flatpakState = parsed.flatpak.state;
            root.flatpakCount = parsed.flatpak.count;
            root.flatpakDetail = parsed.flatpak.detail;
        }
        if (parsed.system.state === "available" || parsed.system.state === "current") root.lastSuccessMs = Date.now();
    }

    function parseSettings(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 6 || lines[0] !== "update-indicator-protocol\t1\t0"
                || lines[5] !== "complete\tstatus") return false;
        let interval = -1, show = "", floating = "", rule = "";
        for (const line of lines.slice(1, 5)) {
            const fields = line.split("\t");
            if (fields.length !== 3 || fields[0] !== "setting") return false;
            if (fields[1] === "interval-hours") interval = Number(fields[2]);
            else if (fields[1] === "show-when-current") show = fields[2];
            else if (fields[1] === "float-terminal") floating = fields[2];
            else if (fields[1] === "float-rule") rule = fields[2];
        }
        if ([1, 3, 6, 12, 24].indexOf(interval) < 0 || (show !== "yes" && show !== "no")
                || (floating !== "yes" && floating !== "no") || (rule !== "present" && rule !== "missing"))
            return false;
        root.intervalHours = interval;
        root.showWhenCurrent = show === "yes";
        root.floatTerminal = floating === "yes";
        root.floatRulePresent = rule === "present";
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

    function setFloatTerminal(enabled) {
        root.runSetting("set-float-terminal", enabled ? "yes" : "no");
    }

    // One terminal update at a time; the counts are read again once it closes.
    function updateInTerminal(provider) {
        if (terminalProcess.running || (provider !== "system" && provider !== "flatpak")) return;
        root.terminalProvider = provider;
        root.terminalResult = "";
        root.terminalDetail = "";
        terminalProcess.command = Commands.updateTerminalCommand("launch", [provider]);
        terminalProcess.running = true;
    }

    function parseTerminal(text) {
        const lines = text.trim().split("\n");
        const fields = lines.length === 3 ? lines[1].split("\t") : [];
        if (lines[0] !== "update-terminal-protocol\t1\t0" || lines[2] !== "complete\tlaunch"
                || fields.length !== 5 || fields[0] !== "result" || fields[1] !== root.terminalProvider
                || ["succeeded", "not-updated", "interrupted", "not-started"].indexOf(fields[2]) < 0) {
            root.terminalResult = "not-started";
            root.terminalDetail = "The update terminal returned invalid data";
            return;
        }
        root.terminalResult = fields[2];
        root.terminalDetail = fields[4];
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

    Process {
        id: terminalProcess
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseTerminal(this.text) }
        stderr: StdioCollector {}
        onRunningChanged: if (!running) {
            if (root.terminalResult.length === 0) {
                root.terminalResult = "not-started";
                root.terminalDetail = "The update terminal did not report a result";
            }
            root.check(true);
        }
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
