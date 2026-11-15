    // Runs inside an isolated copy of the production ShellRoot (#444): a
    // wallpaper status read queued behind an inventory read must run once that
    // read ends, even when the inventory read's own retry has to wait for a
    // watch that is restarting. The watch here never becomes ready, as one
    // still restarting after a change; the inventory read is slowed so the
    // status read is asked for while it runs.
    property int queueStage: 0
    property double queueStageStarted: Date.now()
    readonly property string queueDir: Quickshell.env("APPEARANCE_DIR")
    readonly property string queueNewPath: queueDir + "/home/Pictures/backgrounds/b.png"

    function queueCheck(ok, detail) {
        if (!ok) {
            console.error("Appearance status queue FAILED at stage " + root.queueStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function queueNext() {
        root.queueStage++;
        root.queueStageStarted = Date.now();
    }
    Process { id: queueShell; running: false }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const model = appearanceModel;
            const wallpaper = model.wallpaper;
            const waited = Date.now() - root.queueStageStarted;
            const state = "path '" + wallpaper.path + "', fit " + wallpaper.fit
                + ", statusPending " + wallpaper.statusPending + ", status running " + wallpaper.reading
                + ", inventoryRunning " + model.inventoryRunning + ", inventoryPending " + model.inventoryPending
                + ", watch ready " + model.inventoryWatchReady + ", watch failed " + model.inventoryWatchFailed
                + ", watch state " + model.inventoryWatchState;
            root.queueCheck(waited < 8000, "timed out: " + state);
            switch (root.queueStage) {
            case 0:
                model.openSettings();
                root.queueNext();
                return;
            case 1:
                // Settled: the first status read is done; the watch is not ready.
                if (wallpaper.statusPending || wallpaper.reading || model.inventoryRunning
                        || wallpaper.providerState !== "available" || waited < 500) return;
                root.queueCheck(!model.inventoryWatchReady && !model.inventoryWatchFailed, "the watch: " + state);
                root.queueCheck(wallpaper.path === "", "a wallpaper before the apply: " + state);
                // An inventory read that the watch's last ready allowed, slowed.
                queueShell.command = ["sh", "-c", 'echo 1.5 >"$1/inventory-delay"', "sh", root.queueDir];
                queueShell.running = true;
                root.queueNext();
                return;
            case 2:
                if (queueShell.running) return;
                model.refreshInventory(true);
                root.queueNext();
                return;
            case 3:
                if (!model.inventoryRunning) return;
                // While it runs, a wallpaper is applied outside Settings: its
                // config is published, the watch reports a change (and goes
                // down to restart), and Settings asks for the status, which
                // waits behind the inventory read.
                queueShell.command = ["sh", "-c",
                    'printf "version=1\\nmode=selection\\npath=%s\\nfit=max\\n" "$2" >"$1/home/.config/lyona/wallpaper.conf.new" '
                    + '&& chmod 600 "$1/home/.config/lyona/wallpaper.conf.new" '
                    + '&& mv "$1/home/.config/lyona/wallpaper.conf.new" "$1/home/.config/lyona/wallpaper.conf"',
                    "sh", root.queueDir, root.queueNewPath];
                queueShell.running = true;
                root.queueNext();
                return;
            case 4:
                if (queueShell.running) return;
                // What the watch's "changed" line does.
                model.inventoryWatchReady = false;
                model.inventoryWatchSawEvent = true;
                model.inventoryPending = true;
                wallpaper.refreshStatus();
                root.queueCheck(wallpaper.statusPending && model.inventoryRunning, "the status read was not queued: " + state);
                root.queueNext();
                return;
            case 5:
                // The status read runs once the inventory read ends, though the
                // inventory retry waits for the watch.
                if (wallpaper.path !== root.queueNewPath) return;
                root.queueCheck(wallpaper.fit === "max", "fit: " + state);
                console.log("Appearance status queue: PASS");
                Qt.quit();
                return;
            }
        }
    }
