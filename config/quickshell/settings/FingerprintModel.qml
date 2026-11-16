import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

// Settings > Fingerprint (#483): the reader, the enrolled fingers and where a
// finger is accepted, from dwm-settings-fingerprint. The section is listed only
// while a reader is available (SettingsModel.sections).
Scope {
    id: root

    // unknown until the first read; then available, none or unavailable.
    property string readerState: "unknown"
    property string readerDetail: ""
    property var fingers: []
    // Fingers enrolled outside Settings (#535), until acknowledged: someone
    // else's finger would work wherever fingerprint is on.
    property var addedFingers: []
    property bool moduleAvailable: false
    // { lightdm: { state, detail }, polkit: ..., sudo: ... }
    property var uses: ({})
    readonly property bool readerAvailable: root.readerState === "available"
    // A use whose PAM line is in place, Lyona's or one added by hand: Settings
    // stays listed while one is, so it can be turned off without a reader (#522).
    readonly property bool anyUseActive: ["lightdm", "polkit", "sudo"].some(function(use) {
        const state = root.uses[use] ? root.uses[use].state : "";
        return state === "on" || state === "external";
    })
    property bool statusPending: false
    property bool loaded: false
    readonly property bool initialLoading: !root.loaded && (statusProcess.running || root.statusPending)
    readonly property bool busy: enrollProcess.running || actionProcess.running
    property string enrollingFinger: ""
    property int enrollPassed: 0
    property string enrollStatus: ""
    property string message: ""
    property string messageSeverity: "idle"
    property string pendingAction: ""

    readonly property var fingerNames: [
        "right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
        "right-middle-finger", "left-middle-finger", "right-ring-finger", "left-ring-finger",
        "right-little-finger", "left-little-finger"
    ]

    function fingerLabel(name) {
        const words = String(name).replace(/-finger$/, "").split("-");
        const label = words.join(" ");
        return label.charAt(0).toUpperCase() + label.slice(1);
    }

    // fprintd's enroll statuses, as people would say them.
    function statusText(status) {
        switch (status) {
        case "enroll-stage-passed": return "Got it. Lift your finger, then touch the reader again";
        case "enroll-retry-scan": return "That scan did not take. Touch the reader again";
        case "enroll-swipe-too-short": return "Too short. Try again";
        case "enroll-finger-not-centered": return "Centre your finger on the reader";
        case "enroll-remove-and-retry": return "Lift your finger and try again";
        case "enroll-completed": return "Finger enrolled";
        case "enroll-data-full": return "The reader has no room for another finger";
        case "enroll-duplicate": return "That finger is already enrolled";
        case "enroll-disconnected": return "The reader was disconnected";
        default: return "Enrolling failed";
        }
    }

    function useState(use) {
        return root.uses[use] ? root.uses[use].state : "unavailable";
    }

    function useDetail(use) {
        return root.uses[use] ? root.uses[use].detail : "";
    }

    function refresh() {
        QueuedRun.startOrQueue(statusProcess, root, "statusPending", root.busy);
    }

    // Once a reader has been found, opening Settings reads only the PAM files
    // (#532): enough to list the section, without starting fprintd and probing
    // the reader every time. The Fingerprint section itself reads it all, and
    // with no reader found every open still looks, so one plugged in later is
    // seen; without fprintd that look fails at once.
    property bool readerChecked: false

    function refreshForSettings() {
        if (!root.readerChecked) {
            root.refresh();
            return;
        }
        if (!usesProcess.running && !statusProcess.running) usesProcess.running = true;
    }

    // status --uses: the module and use lines only; the reader and fingers
    // stay as last read.
    function parseUses(text) {
        const lines = String(text).trim().split("\n");
        const header = lines.length > 0 ? lines[0].split("\t") : [];
        if (!Protocol.isHeader(header, "fingerprint-protocol", 1)
                || lines[lines.length - 1] !== "complete\tstatus") return;
        const uses = {};
        let moduleAvailable = false;
        for (let i = 1; i < lines.length - 1; i++) {
            const fields = lines[i].split("\t");
            if (fields[0] === "module" && fields.length === 3) {
                moduleAvailable = fields[1] === "available";
            } else if (fields[0] === "use" && fields.length === 4
                    && (fields[1] === "lightdm" || fields[1] === "polkit" || fields[1] === "sudo")
                    && ["on", "off", "external", "unavailable"].indexOf(fields[2]) >= 0) {
                uses[fields[1]] = { "state": fields[2], "detail": fields[3] };
            }
        }
        root.moduleAvailable = moduleAvailable;
        root.uses = uses;
    }

    function parseStatus(text) {
        const lines = String(text).trim().split("\n");
        const header = lines.length > 0 ? lines[0].split("\t") : [];
        if (!Protocol.isHeader(header, "fingerprint-protocol", 1)
                || lines[lines.length - 1] !== "complete\tstatus") {
            root.readerState = "unavailable";
            root.readerDetail = "The fingerprint helper did not answer";
            return;
        }
        const fingers = [];
        const added = [];
        const uses = {};
        let readerState = "unavailable";
        let readerDetail = "";
        let moduleAvailable = false;
        for (let i = 1; i < lines.length - 1; i++) {
            const fields = lines[i].split("\t");
            if (fields[0] === "reader" && fields.length === 3
                    && (fields[1] === "available" || fields[1] === "none" || fields[1] === "unavailable")) {
                readerState = fields[1];
                readerDetail = fields[2];
            } else if (fields[0] === "finger" && fields.length === 2
                    && root.fingerNames.indexOf(fields[1]) >= 0) {
                fingers.push(fields[1]);
            } else if (fields[0] === "finger-added" && fields.length === 2
                    && root.fingerNames.indexOf(fields[1]) >= 0) {
                added.push(fields[1]);
            } else if (fields[0] === "module" && fields.length === 3) {
                moduleAvailable = fields[1] === "available";
            } else if (fields[0] === "use" && fields.length === 4
                    && (fields[1] === "lightdm" || fields[1] === "polkit" || fields[1] === "sudo")
                    && ["on", "off", "external", "unavailable"].indexOf(fields[2]) >= 0) {
                uses[fields[1]] = { "state": fields[2], "detail": fields[3] };
            }
        }
        root.readerState = readerState;
        root.readerDetail = readerDetail;
        root.fingers = fingers;
        root.addedFingers = added.filter(name => fingers.indexOf(name) >= 0);
        root.moduleAvailable = moduleAvailable;
        root.uses = uses;
        root.loaded = true;
        root.readerChecked = readerState === "available";
    }

    function enroll(finger) {
        if (root.busy || root.fingerNames.indexOf(finger) < 0 || root.fingers.indexOf(finger) >= 0) return;
        root.enrollingFinger = finger;
        root.enrollPassed = 0;
        root.enrollStatus = "";
        root.message = "Touch the reader with your " + root.fingerLabel(finger).toLowerCase()
            + ". fprintd may ask for your password first";
        root.messageSeverity = "idle";
        enrollProcess.command = Commands.settingsFingerprintCommand("enroll", [finger]);
        enrollProcess.running = true;
    }

    function cancelEnroll() {
        if (!enrollProcess.running) return;
        enrollProcess.running = false;
        root.message = "Enrolling cancelled";
        root.messageSeverity = "warning";
    }

    function enrollLine(line) {
        const fields = String(line).split("\t");
        if (fields[0] === "enroll-status" && fields.length === 2) {
            root.enrollStatus = fields[1];
            if (fields[1] === "enroll-stage-passed") root.enrollPassed++;
            root.message = root.statusText(fields[1]);
            root.messageSeverity = fields[1] === "enroll-stage-passed" || fields[1] === "enroll-completed"
                ? "idle" : "warning";
        } else if (fields[0] === "enroll-result" && fields.length === 3) {
            root.message = fields[1] === "completed"
                ? root.fingerLabel(root.enrollingFinger) + " enrolled"
                : root.statusText(fields[2]);
            root.messageSeverity = fields[1] === "completed" ? "success" : "danger";
        }
    }

    function runAction(kind, args, working) {
        if (root.busy) return;
        root.pendingAction = kind;
        root.message = working;
        root.messageSeverity = "idle";
        actionProcess.command = Commands.settingsFingerprintCommand(kind, args);
        actionProcess.running = true;
    }

    function deleteFinger(finger) {
        if (root.fingers.indexOf(finger) < 0) return;
        root.runAction("delete", [finger], "Deleting " + root.fingerLabel(finger).toLowerCase() + "...");
    }

    property string pendingUse: ""
    property string pendingValue: ""
    readonly property var useNames: ({ "lightdm": "The login and lock screen", "polkit": "Administrator prompts", "sudo": "sudo" })

    // The fingers added outside Settings were the user's own.
    function acknowledgeAdded() {
        if (root.addedFingers.length === 0) return;
        root.runAction("acknowledge", root.addedFingers.slice(), "Saving...");
    }

    function setUse(use, value) {
        if (["lightdm", "polkit", "sudo"].indexOf(use) < 0
                || ["on", "off", "remove-external"].indexOf(value) < 0) return;
        root.pendingUse = use;
        root.pendingValue = value;
        root.runAction("set", [use, value], "Waiting for the administrator password...");
    }

    // What a successful action did, in words (#529).
    function actionResult() {
        if (root.pendingAction === "delete") return "Finger deleted";
        if (root.pendingAction === "acknowledge") return "Noted as yours";
        if (root.pendingAction !== "set") return "Changed";
        const name = root.useNames[root.pendingUse] || root.pendingUse;
        if (root.pendingValue === "on") return name + " now accepts a finger";
        if (root.pendingValue === "off") return name + " now asks for the password only";
        return "The line added outside Lyona was removed";
    }

    function closeSettings() {
        root.cancelEnroll();
    }

    Process {
        id: usesProcess
        command: Commands.settingsFingerprintCommand("status", ["--uses"])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseUses(this.text) }
    }

    Process {
        id: statusProcess
        command: Commands.settingsFingerprintCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        onRunningChanged: if (!running && root.statusPending && !root.busy) Qt.callLater(root.refresh)
    }

    Process {
        id: enrollProcess
        running: false
        stdout: SplitParser { onRead: line => root.enrollLine(line) }
        onRunningChanged: {
            if (running) return;
            root.enrollingFinger = "";
            Qt.callLater(root.refresh);
        }
    }

    Process {
        id: actionProcess
        running: false
        stdout: StdioCollector { id: actionOutput }
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.message = root.actionResult();
                root.messageSeverity = "success";
            } else if (exitCode === 3 && root.pendingAction === "set") {
                // The password dialog was dismissed: not a failure (#529).
                root.message = "Not changed: the password prompt was cancelled";
                root.messageSeverity = "idle";
            } else {
                const error = actionError.text.trim().replace(/^dwm-settings-fingerprint: /, "");
                root.message = error.length > 0 ? error : "The change was not made";
                root.messageSeverity = "danger";
            }
            root.pendingAction = "";
            Qt.callLater(root.refresh);
        }
    }
}
