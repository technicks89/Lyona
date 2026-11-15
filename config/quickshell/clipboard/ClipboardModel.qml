import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

// Clipboard history (#469, upstream dwm-titus #389 and #411). Capture and
// saving to disk are separate opt-ins, both off until the user turns them on.
// The source is dwm-clipboard-observer (through dwm-clipboard-history
// observe), which admits only copies its policy allows
// (docs/CLIPBOARD-PRIVACY.md); this model never falls back to Quickshell's own
// clipboard, which would see everything. It runs only while capture is on. The
// settings and the saved history are dwm-clipboard-history's: the history
// file is written whole, mode 0600, only while saving is on, and removed when
// saving or capture is turned off. Nothing polls.
Scope {
    id: root

    readonly property int maxEntries: 50
    readonly property int maxEntryLength: 65536
    // A record is at most 64 KiB of text, escaped as \uXXXX at worst.
    readonly property int maxFrameLength: 393300

    property bool visible: false
    property string query: ""
    property int selectedIndex: 0
    property var targetScreen: null
    property var entries: []
    readonly property var filteredEntries: root.filterEntries(root.entries, root.query)
    property int timeTick: 0

    // From dwm-clipboard-history status.
    property bool settingsKnown: false
    property bool settingsAvailable: true
    property bool captureEnabled: false
    property bool persistEnabled: false
    // The observer said it is ready; a malformed record, an exit or no ready
    // in time stops capture until the user turns it on again.
    property bool backendReady: false
    property bool backendFailed: false
    property string observerBuffer: ""
    property bool busy: false
    property string message: ""
    // A save asked for while one runs, done once it ends.
    property bool savePending: false

    readonly property string status: {
        if (!root.settingsKnown) return "Reading the clipboard history settings...";
        if (!root.settingsAvailable) return "The clipboard history settings are not a plain file of yours";
        if (root.backendFailed) return "Capture stopped: the clipboard source is unavailable. Turn capture on to retry.";
        if (!root.captureEnabled) return "Capture is off";
        const count = root.entries.length === 0 ? "No entries yet"
            : root.entries.length === 1 ? "1 entry" : root.entries.length + " entries";
        return root.persistEnabled ? count + ", saved" : count + ", not saved";
    }

    function filterEntries(entries, query) {
        const needle = query.trim().toLowerCase();
        if (needle.length === 0) return entries;
        return entries.filter(entry => entry.text.toLowerCase().indexOf(needle) >= 0);
    }

    onFilteredEntriesChanged: {
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = Math.max(0, root.filteredEntries.length - 1);
    }

    // ── settings ────────────────────────────────────────────────────────
    // A read asked for while one runs runs again after it, so a change made
    // meanwhile is never missed.
    property bool refreshPending: false

    function refresh() {
        if (statusProcess.running) root.refreshPending = true;
        else statusProcess.running = true;
    }

    function parseStatus(text) {
        const lines = text.trim().split("\n");
        if (lines.length < 3 || !Protocol.isHeader(lines[0].split("\t"), "clipboard-history-protocol", 1)
                || lines[lines.length - 1] !== "complete\tstatus") return false;
        let capture = false, persist = false, available = true;
        for (const line of lines.slice(1, -1)) {
            const fields = line.split("\t");
            if (fields[0] === "state") available = fields[1] === "available";
            else if (fields[0] === "capture") capture = fields[1] === "on";
            else if (fields[0] === "persist") persist = fields[1] === "on";
        }
        const wasCapturing = root.captureEnabled;
        const wasSaving = root.persistEnabled;
        root.settingsAvailable = available;
        root.captureEnabled = capture;
        root.persistEnabled = capture && persist;
        root.settingsKnown = true;
        if (!capture) root.entries = [];
        // Saved history, once, when capture comes on with saving; and what is
        // in the list now, saved as soon as saving comes on.
        if (root.persistEnabled && !wasCapturing && root.entries.length === 0) loadProcess.running = true;
        else if (root.persistEnabled && !wasSaving && root.entries.length > 0) root.save();
        return true;
    }

    function setCapture(enabled) {
        if (root.busy) return;
        if (enabled) root.backendFailed = false;
        else root.entries = [];
        root.run(["set", "capture", enabled ? "on" : "off"]);
    }

    function setPersist(enabled) {
        if (root.busy || !root.captureEnabled) return;
        root.run(["set", "persist", enabled ? "on" : "off"]);
    }

    function run(args) {
        root.busy = true;
        root.message = "";
        actionProcess.command = Commands.clipboardHistoryCommand(args[0], args.slice(1));
        actionProcess.running = true;
    }

    // ── the source ──────────────────────────────────────────────────────
    function failBackend() {
        root.backendFailed = true;
        root.backendReady = false;
        root.observerBuffer = "";
    }

    // Raw chunks, so a line can never grow past maxFrameLength; the records
    // are ASCII JSON, so a chunk boundary never splits a character.
    function observerChunk(chunk) {
        if (!root.captureEnabled || root.backendFailed) return;
        for (let offset = 0; offset < chunk.length;) {
            const newline = chunk.indexOf("\n", offset);
            const end = newline < 0 ? chunk.length : newline;
            if (root.observerBuffer.length + end - offset > root.maxFrameLength) {
                root.failBackend();
                return;
            }
            root.observerBuffer += chunk.slice(offset, end);
            if (newline < 0) return;
            const frame = root.observerBuffer;
            root.observerBuffer = "";
            let value;
            try {
                value = JSON.parse(frame);
            } catch (error) {
                root.failBackend();
                return;
            }
            if (!value || typeof value !== "object" || Array.isArray(value)) {
                root.failBackend();
                return;
            }
            const keys = Object.keys(value).sort().join(",");
            if (!root.backendReady && keys === "event,protocol" && value.event === "ready" && value.protocol === 1) {
                root.backendReady = true;
            } else if (root.backendReady && keys === "event,text" && value.event === "text"
                    && typeof value.text === "string" && value.text.length <= root.maxEntryLength) {
                root.capture(value.text);
            } else {
                root.failBackend();
                return;
            }
            offset = newline + 1;
        }
    }

    function capture(text) {
        if (root.recordEntry(text) && root.persistEnabled) root.save();
    }

    // The newest copy first; a copy of an entry already there moves it up.
    function recordEntry(text) {
        if (typeof text !== "string" || text.trim().length === 0) return false;
        const value = text.length > root.maxEntryLength ? text.slice(0, root.maxEntryLength) : text;
        root.entries = [{ "text": value, "timestamp": Date.now() }]
            .concat(root.entries.filter(entry => entry.text !== value)).slice(0, root.maxEntries);
        return true;
    }

    // ── storage ─────────────────────────────────────────────────────────
    function save() {
        if (!root.persistEnabled) return;
        if (saveProcess.running) {
            root.savePending = true;
            return;
        }
        saveProcess.payload = JSON.stringify({ "version": 1, "entries": root.entries });
        saveProcess.running = true;
    }

    function parseHistory(text) {
        if (text.trim().length === 0) return;
        let value;
        try {
            value = JSON.parse(text);
        } catch (error) {
            root.message = "The saved clipboard history could not be read; it is replaced at the next copy.";
            return;
        }
        if (!value || value.version !== 1 || !Array.isArray(value.entries)) return;
        const loaded = [];
        for (const item of value.entries) {
            if (!item || typeof item.text !== "string" || item.text.trim().length === 0
                    || item.text.length > root.maxEntryLength) continue;
            if (loaded.some(entry => entry.text === item.text)) continue;
            loaded.push({ "text": item.text,
                "timestamp": typeof item.timestamp === "number" && item.timestamp > 0 ? item.timestamp : Date.now() });
        }
        // Copies made while it loaded stay in front.
        const kept = root.entries.filter(entry => !loaded.some(item => item.text === entry.text));
        root.entries = kept.concat(loaded).slice(0, root.maxEntries);
    }

    // ── the window ──────────────────────────────────────────────────────
    function open() {
        root.targetScreen = null;
        root.openWindow();
    }

    function openOnScreen(screen) {
        root.targetScreen = screen;
        root.openWindow();
    }

    function openWindow() {
        root.query = "";
        root.selectedIndex = 0;
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
        root.query = "";
        root.selectedIndex = 0;
    }

    function toggle() {
        if (root.visible) root.close();
        else root.open();
    }

    function setQuery(value) {
        root.query = value;
        root.selectedIndex = 0;
    }

    function selectRelative(delta) {
        const count = root.filteredEntries.length;
        root.selectedIndex = count === 0 ? 0 : ((root.selectedIndex + delta) % count + count) % count;
    }

    function selectAbsolute(index) {
        const count = root.filteredEntries.length;
        root.selectedIndex = count === 0 ? 0 : Math.max(0, Math.min(index, count - 1));
    }

    // Copies an entry back to the clipboard. The observer then sees the shell
    // as the owner and reports the same text, which only moves it to the top.
    function select(index) {
        const rows = root.filteredEntries;
        if (index < 0 || index >= rows.length) return;
        const text = rows[index].text;
        root.recordEntry(text);
        if (root.persistEnabled) root.save();
        Quickshell.clipboardText = text;
        root.close();
    }

    function copySelected() {
        root.select(root.selectedIndex);
    }

    function deleteAt(index) {
        const rows = root.filteredEntries;
        if (index < 0 || index >= rows.length) return;
        const text = rows[index].text;
        root.entries = root.entries.filter(entry => entry.text !== text);
        if (root.persistEnabled) root.save();
    }

    function clearAll() {
        root.entries = [];
        if (!clearProcess.running) clearProcess.running = true;
    }

    function relativeTime(timestamp) {
        const age = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));
        if (age < 60) return "now";
        if (age < 3600) return Math.floor(age / 60) + "m";
        if (age < 86400) return Math.floor(age / 3600) + "h";
        return Math.floor(age / 86400) + "d";
    }

    Component.onCompleted: root.refresh()

    Process {
        id: statusProcess
        command: Commands.clipboardHistoryCommand("status", [])
        running: false
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                Qt.callLater(root.refresh);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.parseStatus(this.text)) {
                    root.settingsKnown = true;
                    root.settingsAvailable = false;
                    root.captureEnabled = false;
                    root.persistEnabled = false;
                }
            }
        }
    }

    Process {
        id: actionProcess
        running: false
        stderr: StdioCollector { id: actionError }
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0) {
                const error = actionError.text.trim();
                root.message = error.length > 0 ? error : "The clipboard history settings could not be changed";
            }
            root.refresh();
        }
    }

    Process {
        id: loadProcess
        command: Commands.clipboardHistoryCommand("load", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseHistory(this.text) }
    }

    Process {
        id: saveProcess
        property string payload: ""
        command: Commands.clipboardHistoryCommand("save", [])
        running: false
        stdinEnabled: true
        stderr: StdioCollector { id: saveError }
        onStarted: {
            saveProcess.write(saveProcess.payload);
            saveProcess.payload = "";
            saveProcess.stdinEnabled = false;
        }
        onExited: exitCode => {
            saveProcess.stdinEnabled = true;
            if (exitCode !== 0) {
                const error = saveError.text.trim();
                root.message = error.length > 0 ? error : "The clipboard history could not be saved";
            }
            if (root.savePending) {
                root.savePending = false;
                Qt.callLater(root.save);
            }
        }
    }

    Process {
        id: clearProcess
        command: Commands.clipboardHistoryCommand("clear", [])
        running: false
    }

    // The source, only while capture is on and has not failed.
    Process {
        id: observer
        command: Commands.watchCommand(Commands.clipboardHistoryCommand("observe", []))
        running: root.settingsKnown && root.captureEnabled && !root.backendFailed
        onRunningChanged: {
            root.backendReady = false;
            root.observerBuffer = "";
        }
        onExited: {
            if (root.captureEnabled && !root.backendFailed) root.failBackend();
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.observerChunk(data)
        }
    }

    Timer {
        interval: 3000
        running: observer.running && !root.backendReady
        onTriggered: root.failBackend()
    }
}
