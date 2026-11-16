    // Runs inside an isolated copy of the production ShellRoot (#469): the
    // clipboard history model and window, against a stub dwm-clipboard-history
    // whose observer follows a feed file this test writes.
    property int clipStage: 0
    property double clipStageStarted: Date.now()
    property string clipLog: ""
    property string clipSaved: ""
    property int clipObserves: 0
    readonly property string clipDir: Quickshell.env("CLIPBOARD_DIR")

    function clipCheck(ok, detail) {
        if (!ok) {
            console.error("Clipboard history FAILED at stage " + root.clipStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function clipNext() {
        root.clipStage++;
        root.clipStageStarted = Date.now();
    }
    function feed(line) {
        clipFeed.command = ["sh", "-c", 'printf "%s\\n" "$1" >>"$2"', "sh", line, root.clipDir + "/feed"];
        clipFeed.running = true;
    }

    FileView {
        id: clipLogFile
        path: root.clipDir + "/log"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.clipLog = clipLogFile.text()
    }
    FileView {
        id: clipSavedFile
        path: root.clipDir + "/saved"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.clipSaved = clipSavedFile.text()
    }
    Process { id: clipFeed; running: false }
    Process {
        id: clipReset
        command: ["sh", "-c", 'printf "%s\\n" "{\\"event\\":\\"ready\\",\\"protocol\\":1}" >"$1/feed"', "sh", root.clipDir]
        running: false
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const model = clipboardModel;
            const waited = Date.now() - root.clipStageStarted;
            root.clipCheck(waited < 10000, "timed out: capture " + model.captureEnabled + ", saving " + model.persistEnabled
                + ", ready " + model.backendReady + ", failed " + model.backendFailed + ", entries " + model.entries.length
                + ", message '" + model.message + "', log " + JSON.stringify(root.clipLog) + ", saved " + JSON.stringify(root.clipSaved));
            switch (root.clipStage) {
            case 0:
                // Off by default: no source started.
                if (!model.settingsKnown || waited < 500) return;
                root.clipCheck(!model.captureEnabled && !model.persistEnabled, "capture or saving on by default");
                root.clipCheck(root.clipLog.indexOf("observe") < 0, "the source ran with capture off");
                model.setCapture(true);
                root.clipNext();
                return;
            case 1:
                // On: the source starts and says it is ready.
                if (!model.captureEnabled || !model.backendReady) return;
                root.clipCheck(root.clipLog.indexOf("set capture on") >= 0, "log: " + root.clipLog);
                root.feed('{"event":"text","text":"first copy"}');
                root.clipNext();
                return;
            case 2:
                if (model.entries.length < 1 || clipFeed.running) return;
                root.feed('{"event":"text","text":"second\\nline"}');
                root.clipNext();
                return;
            case 3:
                // Newest first; a repeated copy moves up rather than doubling.
                if (model.entries.length < 2 || clipFeed.running) return;
                root.clipCheck(model.entries[0].text === "second\nline", "newest: " + model.entries[0].text);
                root.feed('{"event":"text","text":"first copy"}');
                root.clipNext();
                return;
            case 4:
                if (model.entries[0].text !== "first copy") return;
                root.clipCheck(model.entries.length === 2, "a repeated copy doubled: " + model.entries.length);
                model.setQuery("SECOND");
                root.clipCheck(model.filteredEntries.length === 1 && model.filteredEntries[0].text === "second\nline",
                    "search: " + JSON.stringify(model.filteredEntries));
                model.setQuery("");
                root.clipCheck(root.clipSaved === "", "saved with saving off: " + root.clipSaved);
                model.setPersist(true);
                root.clipNext();
                return;
            case 5:
                // Saving on: the history is written, as JSON, through the helper.
                if (!model.persistEnabled || root.clipSaved.indexOf("second") < 0) return;
                const saved = JSON.parse(root.clipSaved);
                root.clipCheck(saved.version === 1 && saved.entries.length === 2 && saved.entries[0].text === "first copy",
                    "saved: " + root.clipSaved);
                // Copy back: to the clipboard, at the top, and the window closes.
                model.open();
                root.clipCheck(model.visible, "the window did not open");
                model.select(1);
                root.clipCheck(Quickshell.clipboardText === "second\nline", "clipboard: " + Quickshell.clipboardText);
                root.clipCheck(model.entries[0].text === "second\nline" && !model.visible, "copy back");
                // The observer then reports the same text: already first, so it is
                // not a change to save again (#529).
                root.clipCheck(!model.recordEntry("second\nline") && model.entries.length === 2,
                    "a copy already first counted as new: " + model.entries.length);
                // What is saved (#532): the newest entries that fit, measured
                // once each; non-ASCII text counts in UTF-8 bytes.
                const big = [];
                for (let i = 0; i < 50; i++)
                    big.push({ "text": String(i) + "é".repeat(60000), "timestamp": 1000 + i });
                const savedText = model.serialize(big);
                const savedEntries = JSON.parse(savedText).entries;
                const withOneMore = JSON.stringify({ "version": 1, "entries": big.slice(0, savedEntries.length + 1) });
                root.clipCheck(model.utf8Bytes(savedText) <= model.maxSavedBytes
                    && model.utf8Bytes(withOneMore) > model.maxSavedBytes
                    && savedEntries.length > 0 && savedEntries.length < 50 && savedEntries[0].text === big[0].text,
                    "serialize kept " + savedEntries.length + " entries, " + model.utf8Bytes(savedText) + " bytes");
                model.deleteAt(1);
                root.clipCheck(model.entries.length === 1, "delete");
                root.clipNext();
                return;
            case 6:
                if (root.clipSaved.indexOf("first copy") >= 0) return;
                // A malformed record stops the source; capture says so.
                root.feed("not json");
                root.clipNext();
                return;
            case 7:
                if (!model.backendFailed) return;
                root.clipCheck(model.status.indexOf("Capture stopped") === 0, "status: " + model.status);
                // The switch shows off, so the click the status asks for retries.
                root.clipCheck(!model.capturing && model.captureEnabled, "switch while failed");
                clipReset.running = true;
                root.clipNext();
                return;
            case 8:
                // Turning capture on again, as the switch does, retries (#516).
                if (clipReset.running) return;
                model.toggleCapture();
                root.clipNext();
                return;
            case 9:
                if (model.backendFailed || !model.backendReady) return;
                // The retry kept saving on and the list (#516).
                root.clipCheck(model.capturing && model.persistEnabled && model.entries.length > 0,
                    "after retry: persist " + model.persistEnabled + ", entries " + model.entries.length);
                // Skip xclip (#535): off by default; turned on, the source starts
                // again to take it.
                root.clipCheck(!model.skipXclip, "skip xclip on by default");
                root.clipObserves = root.clipLog.split("\n").filter(line => line === "observe").length;
                model.setSkipXclip(true);
                root.clipNext();
                return;
            case 10:
                if (!model.skipXclip || model.busy || !model.backendReady
                        || root.clipLog.split("\n").filter(line => line === "observe").length <= root.clipObserves) return;
                root.clipCheck(root.clipLog.indexOf("set skip-xclip on") >= 0 && model.capturing, "log: " + root.clipLog);
                // Off: the list empties and saving goes with it.
                model.setCapture(false);
                root.clipNext();
                return;
            case 11:
                if (model.captureEnabled || model.busy) return;
                root.clipCheck(model.entries.length === 0 && !model.persistEnabled, "after capture off");
                root.clipCheck(root.clipLog.indexOf("set capture off") >= 0, "log: " + root.clipLog);
                model.clearAll();
                root.clipNext();
                return;
            case 12: {
                if (root.clipLog.indexOf("clear") < 0) return;
                // Loading saved history: what is in the list now wins over a
                // saved entry with the same text; a load from before a clear,
                // delete or capture off changes nothing.
                const saved = JSON.stringify({ "version": 1, "entries": [
                    { "text": "fresh", "timestamp": 1 }, { "text": "older", "timestamp": 1 } ] });
                model.entries = [{ "text": "fresh", "timestamp": Date.now() }];
                model.parseHistory(saved, model.historyGeneration - 1);
                root.clipCheck(model.entries.length === 1, "a stale load changed the list");
                model.parseHistory(saved, model.historyGeneration);
                root.clipCheck(model.entries.length === 2 && model.entries[0].text === "fresh"
                    && model.entries[0].timestamp !== 1 && model.entries[1].text === "older",
                    "merge: " + JSON.stringify(model.entries));
                // Saving: a list too large for the helper loses its oldest
                // entries until it fits; a small one is saved whole.
                root.clipCheck(JSON.parse(model.serialize(model.entries)).entries.length === 2, "a small list was trimmed");
                const big = [];
                for (let i = 0; i < 50; i++)
                    big.push({ "text": String(i) + "\u0001".repeat(60000), "timestamp": i + 1 });
                const text = model.serialize(big);
                const kept = JSON.parse(text).entries;
                root.clipCheck(model.utf8Bytes(text) <= model.maxSavedBytes && kept.length > 0 && kept.length < 50
                    && kept[0].timestamp === 1, "trimmed to " + kept.length + " entries, " + model.utf8Bytes(text) + " bytes");
                model.entries = [];
                console.log("Clipboard history: PASS");
                Qt.quit();
                return;
            }
            }
        }
    }
