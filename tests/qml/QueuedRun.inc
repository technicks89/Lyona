    // Runs inside an isolated copy of the production ShellRoot. Characterises the
    // "queue while a read runs, start it after, clear the flag once it has started"
    // rule on AutostartModel: refresh() while a read is running queues exactly one
    // more, the queued read runs after the first ends, its setup runs only when it
    // starts, and closing the pane while one is queued drops it.
    property int queueStage: 0
    property double queueStageStarted: Date.now()

    function queueCheck(ok, detail) {
        if (!ok) {
            console.error("Queued run FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function queueNext() {
        root.queueStage++;
        root.queueStageStarted = Date.now();
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            const model = autostartModel;
            const waited = Date.now() - root.queueStageStarted;
            switch (root.queueStage) {
            case 0:
                if (waited < 800) return;
                // A closed pane refreshes nothing.
                model.refresh();
                root.queueCheck(model.testStarts === 0, "a closed pane started a read");
                model.openSettings();
                root.queueNext();
                return;
            case 1:
                if (waited < 150) return;
                root.queueCheck(model.testStarts === 1, "opening did not start exactly one read: " + model.testStarts);
                root.queueCheck(!model.snapshotPending, "the flag is set with nothing queued");
                root.queueCheck(model.initialLoading, "the pane is not loading while its read runs");
                // Two refreshes while it runs: one queued read, and no setup yet.
                model.mutationGeneration = 5;
                model.refresh();
                model.refresh();
                root.queueCheck(model.testStarts === 1, "a refresh while running started another read");
                root.queueCheck(model.snapshotPending, "a refresh while running was not queued");
                root.queueCheck(model.snapshotGeneration !== 5, "the queued refresh ran its setup before it started");
                root.queueNext();
                return;
            case 2:
                // The first read ends after about half a second; the queued one follows.
                if (model.testStarts < 2) {
                    root.queueCheck(waited < 2500, "the queued read never started");
                    return;
                }
                root.queueCheck(model.testStarts === 2, "more than one read followed two queued refreshes");
                root.queueCheck(!model.snapshotPending, "the flag is still set after the queued read started");
                root.queueCheck(model.snapshotGeneration === 5, "the queued read did not run its setup when it started");
                root.queueNext();
                return;
            case 3:
                if (model.initialLoading) {
                    root.queueCheck(waited < 2500, "the queued read never finished");
                    return;
                }
                root.queueCheck(model.testStarts === 2, "a read started with nothing queued: " + model.testStarts);
                root.queueCheck(!model.initialLoading, "the pane is still loading with no read running or queued");
                model.refresh();
                root.queueNext();
                return;
            case 4:
                // Close while a refresh is queued: nothing runs afterwards.
                if (waited < 150) return;
                root.queueCheck(model.testStarts === 3, "an idle refresh did not start a read");
                model.refresh();
                root.queueCheck(model.snapshotPending, "a refresh while running was not queued (second round)");
                model.closeSettings();
                root.queueCheck(!model.snapshotPending, "closing left a queued refresh behind");
                root.queueNext();
                return;
            default:
                if (waited < 1500) return;
                root.queueCheck(model.testStarts === 3, "a read started after the pane was closed: " + model.testStarts);
                root.queueCheck(!model.initialLoading, "a closed pane is still loading");
                console.info("Queued run: PASS");
                Qt.quit();
                return;
            }
        }
    }
