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
    // Copies owned by xclip or xsel refused too (#535), off until turned on:
    // pass -c and gopass copy through them.
    property bool skipXclip: false
    // What the Capture switch shows: off while the source has failed, so the
    // click the status asks for retries instead of turning capture off and
    // deleting the saved history (#516).
    readonly property bool capturing: root.captureEnabled && !root.backendFailed
    property string observerBuffer: ""
    property bool busy: false
    property string message: ""
    // A save asked for while one runs, done once it ends.
    property bool savePending: false
    // A clear asked for while a save runs, done once it ends, so that save
    // cannot put back what the clear removes.
    property bool clearPending: false
    // Raised by every change that takes entries away; a load that began
    // before it does not bring them back.
    property int historyGeneration: 0
    // dwm-clipboard-history keeps at most 4 MiB.
    readonly property int maxSavedBytes: 4 * 1024 * 1024

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
        let capture = false, persist = false, available = true, skip = false;
        for (const line of lines.slice(1, -1)) {
            const fields = line.split("\t");
            if (fields[0] === "state") available = fields[1] === "available";
            else if (fields[0] === "capture") capture = fields[1] === "on";
            else if (fields[0] === "persist") persist = fields[1] === "on";
            else if (fields[0] === "skip-xclip") skip = fields[1] === "on";
        }
        // A running source restarts to take the new choice.
        if (skip !== root.skipXclip) {
            root.skipXclip = skip;
            if (root.observing) {
                observer.stop();
                root.backendReady = false;
                root.observerBuffer = "";
                observer.start();
            }
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
        if (root.persistEnabled && !wasCapturing && root.entries.length === 0) root.load();
        else if (root.persistEnabled && !wasSaving && root.entries.length > 0) root.save();
        return true;
    }

    function setCapture(enabled) {
        if (root.busy) return;
        if (enabled) root.backendFailed = false;
        else {
            root.entries = [];
            root.historyGeneration++;
        }
        root.run(["set", "capture", enabled ? "on" : "off"]);
    }

    // The Capture switch: on (or a retry, after the source failed) or off.
    function toggleCapture() {
        root.setCapture(!root.capturing);
    }

    function setSkipXclip(enabled) {
        if (root.busy) return;
        root.run(["set", "skip-xclip", enabled ? "on" : "off"]);
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
        // Already first, as after a copy back from the list: nothing to save
        // again (#529); only its time moves.
        if (root.entries.length > 0 && root.entries[0].text === value) {
            root.entries = [{ "text": value, "timestamp": Date.now() }].concat(root.entries.slice(1));
            return false;
        }
        root.entries = [{ "text": value, "timestamp": Date.now() }]
            .concat(root.entries.filter(entry => entry.text !== value)).slice(0, root.maxEntries);
        return true;
    }

    // ── storage ─────────────────────────────────────────────────────────
    // A change to save: written a second after the last one (#532), so a
    // burst of copies is one write. A crash in that second loses those copies
    // from the file, never the file.
    function save() {
        if (!root.persistEnabled || root.clearPending) return;
        saveDebounce.restart();
    }

    function writeNow() {
        if (!root.persistEnabled || root.clearPending) return;
        if (saveProcess.running) {
            root.savePending = true;
            return;
        }
        saveProcess.payload = root.serialize(root.entries);
        saveProcess.running = true;
    }

    // UTF-8 bytes of a string.
    function utf8Bytes(text) {
        let bytes = 0;
        for (let i = 0; i < text.length; i++) {
            const unit = text.charCodeAt(i);
            if (unit < 0x80) bytes += 1;
            else if (unit < 0x800) bytes += 2;
            else if (unit >= 0xd800 && unit <= 0xdbff) {
                bytes += 4;
                i++;
            } else bytes += 3;
        }
        return bytes;
    }

    // Each entry's saved size in UTF-8 bytes, by its text, worked out once
    // (#532): the history was stringified and measured again for every entry
    // dropped, up to seconds on the GUI thread for a large one.
    property var entryBytesCache: ({})

    function entryBytes(entry) {
        const cached = root.entryBytesCache[entry.text];
        if (cached !== undefined && cached.timestamp === entry.timestamp) return cached.bytes;
        const bytes = root.utf8Bytes(JSON.stringify(entry));
        root.entryBytesCache[entry.text] = { "timestamp": entry.timestamp, "bytes": bytes };
        return bytes;
    }

    // The history as saved: the oldest entries left out until it fits what
    // dwm-clipboard-history keeps, so a full list is saved rather than refused.
    // Sizes are added and subtracted; the text is built once.
    function serialize(entries) {
        const overhead = JSON.stringify({ "version": 1, "entries": [] }).length;
        const sizes = entries.map(entry => root.entryBytes(entry));
        let count = entries.length;
        let total = overhead + sizes.reduce((sum, size) => sum + size, 0) + Math.max(0, count - 1);
        while (count > 0 && total > root.maxSavedBytes) {
            count--;
            total -= sizes[count] + (count > 0 ? 1 : 0);
        }
        // Only the entries kept stay in the cache.
        const cache = {};
        for (let i = 0; i < entries.length; i++) {
            const cached = root.entryBytesCache[entries[i].text];
            if (cached !== undefined) cache[entries[i].text] = cached;
        }
        root.entryBytesCache = cache;
        return JSON.stringify({ "version": 1, "entries": entries.slice(0, count) });
    }

    function load() {
        loadProcess.generation = root.historyGeneration;
        loadProcess.running = true;
    }

    function parseHistory(text, generation) {
        // Cleared, deleted from or turned off while it loaded: not brought back.
        if (generation !== root.historyGeneration) return;
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
            // Never more than the list keeps: a large or damaged file is not
            // scanned to the end (#529).
            if (loaded.length >= root.maxEntries) break;
            if (!item || typeof item.text !== "string" || item.text.trim().length === 0
                    || item.text.length > root.maxEntryLength) continue;
            if (loaded.some(entry => entry.text === item.text)) continue;
            loaded.push({ "text": item.text,
                "timestamp": typeof item.timestamp === "number" && item.timestamp > 0 ? item.timestamp : Date.now() });
        }
        // Copies made while it loaded stay in front, and win over a saved
        // entry with the same text.
        root.entries = root.entries.concat(loaded.filter(item => !root.entries.some(entry => entry.text === item.text)))
            .slice(0, root.maxEntries);
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
        if (root.recordEntry(text) && root.persistEnabled) root.save();
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
        root.historyGeneration++;
        if (root.persistEnabled) root.save();
    }

    function clearAll() {
        root.entries = [];
        root.historyGeneration++;
        root.savePending = false;
        saveDebounce.stop();
        // After a save that is running, which would otherwise put it back.
        if (saveProcess.running) root.clearPending = true;
        else if (!clearProcess.running) clearProcess.running = true;
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
        property int generation: 0
        command: Commands.clipboardHistoryCommand("load", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseHistory(this.text, loadProcess.generation) }
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
            if (root.clearPending) {
                root.clearPending = false;
                if (!clearProcess.running) clearProcess.running = true;
            } else if (root.savePending) {
                root.savePending = false;
                Qt.callLater(root.writeNow);
            }
        }
    }

    Timer {
        id: saveDebounce
        interval: 1000
        repeat: false
        onTriggered: root.writeNow()
    }

    Process {
        id: clearProcess
        command: Commands.clipboardHistoryCommand("clear", [])
        running: false
    }

    // The source, only while capture is on and has not failed, through the
    // shared WatchedProcess (#531): raw chunks (an empty split marker), and
    // never restarted, since a source that ended fails closed and the user's
    // click retries it.
    readonly property bool observing: root.settingsKnown && root.captureEnabled && !root.backendFailed
    onObservingChanged: {
        root.backendReady = false;
        root.observerBuffer = "";
        if (root.observing) observer.start();
        else observer.stop();
    }

    WatchedProcess {
        id: observer
        command: Commands.watchCommand(Commands.clipboardHistoryCommand("observe", []))
        active: root.observing
        restartPolicy: "never"
        splitMarker: ""
        onLine: text => root.observerChunk(text)
        onEnded: {
            if (root.captureEnabled && !root.backendFailed) root.failBackend();
        }
    }

    Timer {
        interval: 3000
        running: observer.running && !root.backendReady
        onTriggered: root.failBackend()
    }
}
