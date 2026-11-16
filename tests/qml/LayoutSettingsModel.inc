    // Runs inside an isolated copy of the production ShellRoot (#530, #534):
    // Settings > Appearance > Layout's model against a stub helper.
    property int lmStage: 0
    property double lmStageStarted: Date.now()
    property string lmLog: ""
    property int lmReads: 0
    readonly property string lmDir: Quickshell.env("LAYOUT_DIR")

    function lmCheck(ok, detail) {
        if (!ok) {
            console.error("Layout settings model FAILED at stage " + root.lmStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function lmNext() {
        root.lmStage++;
        root.lmStageStarted = Date.now();
    }
    function lmFeed(line) {
        lmShell.command = ["sh", "-c", 'printf "%s\\n" "$1" >>"$2"', "sh", line, root.lmDir + "/feed"];
        lmShell.running = true;
    }
    function lmShellRun(script) {
        lmShell.command = ["sh", "-c", script, "sh", root.lmDir];
        lmShell.running = true;
    }
    function lmSets(field) {
        return root.lmLog.split("\n").filter(line => line.indexOf("set 0 1 " + field + " ") === 0);
    }

    FileView {
        id: lmLogFile
        path: root.lmDir + "/log"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.lmLog = lmLogFile.text()
    }
    Process { id: lmShell; running: false }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const model = settingsModel.layoutSettingsModel;
            const waited = Date.now() - root.lmStageStarted;
            root.lmCheck(waited < 10000, "timed out: available " + model.available + ", reported " + model.reported
                + ", requested " + JSON.stringify(model.requested) + ", log " + JSON.stringify(root.lmLog));
            switch (root.lmStage) {
            case 0:
                // Not reading while Appearance is not shown.
                if (waited < 300) return;
                root.lmCheck(!model.active, "active with Settings closed");
                settingsModel.open("appearance");
                root.lmCheck(model.active && !model.reported, "open: active " + model.active + ", reported " + model.reported);
                root.lmFeed("layout-settings\t0\t1\t55\t1\t0\t0");
                root.lmNext();
                return;
            case 1:
                if (!model.available || lmShell.running) return;
                root.lmCheck(model.reported && model.editable && model.viewLabel.indexOf("tag 1") > 0, "label: " + model.viewLabel);
                // Three quick steps: the first is written, the third waits behind
                // it, and the second never goes (the latest per field).
                model.save("gap", 4);
                model.save("gap", 5);
                model.save("gap", 6);
                root.lmCheck(model.shown("gap") === 6, "shown while queued: " + model.shown("gap"));
                root.lmNext();
                return;
            case 2:
                if (root.lmSets("gap").length < 1) return;
                // dwm reports the first write while the next waits: the slider
                // stays on what was asked for.
                root.lmFeed("layout-settings\t0\t1\t55\t1\t4\t0");
                root.lmNext();
                return;
            case 3:
                if (lmShell.running || model.gap !== 4) return;
                root.lmCheck(model.shown("gap") === 6, "a stale watch line moved the slider: " + model.shown("gap"));
                root.lmNext();
                return;
            case 4:
                if (root.lmSets("gap").length < 2 || model.savingField !== "") return;
                root.lmCheck(JSON.stringify(root.lmSets("gap")) === '["set 0 1 gap 4","set 0 1 gap 6"]',
                    "writes: " + JSON.stringify(root.lmSets("gap")));
                // Both writes done, and a line from before the last arrives
                // late, as on a slow machine: the settle keeps the slider.
                root.lmFeed("layout-settings\t0\t1\t55\t1\t5\t0");
                root.lmNext();
                return;
            case 5:
                if (lmShell.running || model.gap !== 5) return;
                root.lmCheck(model.shown("gap") === 6, "a late stale line moved the slider: " + model.shown("gap"));
                root.lmFeed("layout-settings\t0\t1\t55\t1\t6\t0");
                root.lmNext();
                return;
            case 6:
                if (lmShell.running || model.gap !== 6) return;
                root.lmCheck(model.requested.gap === undefined && model.shown("gap") === 6, "after dwm caught up: " + JSON.stringify(model.requested));
                // Reset: the tag's three values back to the defaults.
                model.resetTag();
                root.lmNext();
                return;
            case 7:
                if (root.lmLog.indexOf("set 0 1 gap default") < 0) return;
                root.lmCheck(root.lmLog.indexOf("set 0 1 mfact default") >= 0 && root.lmLog.indexOf("set 0 1 nmaster default") >= 0,
                    "reset: " + root.lmLog);
                root.lmNext();
                return;
            case 8:
                // Title bars: read, turned on, a tag turned off.
                if (!model.titlebarsKnown) return;
                root.lmCheck(!model.titlebarsEnabled && model.titlebarTags === 511, "titlebars read");
                model.setTitlebars(true, 511);
                root.lmNext();
                return;
            case 9:
                if (!model.titlebarsEnabled || model.titlebarsBusy) return;
                root.lmCheck(root.lmLog.indexOf("titlebars 1 511") >= 0, "titlebars on: " + root.lmLog);
                model.toggleTitlebarTag(1);
                root.lmNext();
                return;
            case 10:
                if (model.titlebarTags !== 510 || model.titlebarsBusy) return;
                root.lmCheck(!model.tagHasTitlebars(1) && model.tagHasTitlebars(2), "tag 1 off");
                // The last tag stays: dwm needs at least one.
                root.lmShellRun('printf "1 1\\n" >"$1/titlebars"');
                root.lmNext();
                return;
            case 11:
                if (lmShell.running) return;
                model.refreshTitlebars();
                root.lmNext();
                return;
            case 12:
                if (model.titlebarTags !== 1 || model.titlebarsBusy) return;
                model.toggleTitlebarTag(1);
                root.lmCheck(!model.titlebarsBusy && model.titlebarTags === 1, "the last tag was turned off");
                // A failed write: a message, and the sliders back on dwm's values.
                root.lmShellRun(': >"$1/fail"');
                root.lmNext();
                return;
            case 13:
                if (lmShell.running) return;
                model.save("mfact", 70);
                root.lmCheck(model.shown("mfact") === 70, "asked for 70");
                root.lmNext();
                return;
            case 14:
                if (model.message.length === 0) return;
                root.lmCheck(model.message.indexOf("cannot write") >= 0 && model.shown("mfact") === 55,
                    "after a failure: " + model.message + ", shown " + model.shown("mfact"));
                // A value dwm never reports back: once the last write is done,
                // the slider goes back to dwm's value after the settle.
                root.lmShellRun('rm -f "$1/fail"');
                root.lmNext();
                return;
            case 15:
                if (lmShell.running) return;
                model.save("gap", 9);
                root.lmNext();
                return;
            case 16:
                if (root.lmLog.indexOf("set 0 1 gap 9") < 0) return;
                root.lmCheck(model.shown("gap") === 9, "right after the write: " + model.shown("gap"));
                root.lmNext();
                return;
            case 17:
                if (model.requested.gap !== undefined) return;
                root.lmCheck(waited > 800 && model.shown("gap") === model.gap,
                    "settled after " + waited + " ms: shown " + model.shown("gap") + ", dwm " + model.gap);
                // Reopened, the last session's values are shown but nothing can
                // be saved until dwm reports again.
                settingsModel.close();
                root.lmCheck(!model.active, "still active after Settings closed");
                settingsModel.open("appearance");
                root.lmCheck(model.available && !model.editable, "editable on stale state");
                root.lmNext();
                return;
            case 18:
                if (!model.editable || model.titlebarsBusy) return;
                root.lmCheck(model.reported, "editable before a report");
                // A read asked for while one runs is not dropped: it runs after.
                root.lmReads = root.lmLog.split("\n").filter(line => line === "status").length;
                model.refreshTitlebars();
                model.refreshTitlebars();
                root.lmCheck(model.titlebarsBusy, "a read did not start");
                root.lmNext();
                return;
            case 19:
                if (model.titlebarsBusy || root.lmLog.split("\n").filter(line => line === "status").length < root.lmReads + 2) return;
                settingsModel.close();
                console.log("Layout settings model: PASS");
                Qt.quit();
                return;
            }
        }
    }
