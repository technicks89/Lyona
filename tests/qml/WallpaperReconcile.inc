    // Runs inside an isolated copy of the production ShellRoot. A failed wallpaper
    // preview is reconciled by a queued retry; the retry must run once whatever
    // was blocking it (a busy model, a font change, another wallpaper action) is
    // over, not only when a later status poll happens to come along.
    property int reconcileStage: 0
    property double reconcileStageStarted: Date.now()
    property int reconcileBefore: 0
    readonly property var reconcileBlockers: ["busy", "fontBusy", "wallpaperBusy", "wallpaperStatusPending"]

    function reconcileCheck(ok, detail) {
        if (!ok) {
            console.error("Wallpaper reconcile FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function reconcileNext() {
        root.reconcileStage++;
        root.reconcileStageStarted = Date.now();
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            const waited = Date.now() - root.reconcileStageStarted;
            const model = appearanceModel;
            if (root.reconcileStage === 0) {
                if (waited < 800) return;
                const idle = !model.busy && !model.fontBusy && !model.wallpaperBusy
                    && !model.wallpaperStatusBusy;
                root.reconcileCheck(idle || waited < 8000,
                    "the appearance model did not become idle before wallpaper reconciliation");
                if (!idle) return;
                root.reconcileNext();
                return;
            }
            const index = Math.floor((root.reconcileStage - 1) / 3);
            if (index >= root.reconcileBlockers.length) {
                console.info("Wallpaper reconcile: PASS");
                Qt.quit();
                return;
            }
            const blocker = root.reconcileBlockers[index];
            switch ((root.reconcileStage - 1) % 3) {
            case 0: {
                // A failed preview, and something blocking the reconcile.
                model.wallpaperPreviewState = "failed";
                model.wallpaperPreviewToken = "test-token";
                model.wallpaperPreviewPath = "/tmp/test-wallpaper.png";
                model.wallpaperPreviewFit = "fill";
                model[blocker] = true;
                root.reconcileBefore = model.testReconcileRuns;
                model.reconcileWallpaperPreview();
                root.reconcileCheck(model.wallpaperReconcilePending,
                    "a reconcile blocked by " + blocker + " is not queued");
                root.reconcileCheck(model.testReconcileRuns === root.reconcileBefore,
                    "a reconcile ran while " + blocker + " was set");
                root.reconcileNext();
                return;
            }
            case 1: {
                // Still blocked: it must wait, not run early or be dropped.
                if (waited < 300) return;
                root.reconcileCheck(model.testReconcileRuns === root.reconcileBefore,
                    "a reconcile ran while " + blocker + " was still set");
                root.reconcileCheck(model.wallpaperReconcilePending,
                    "the queued reconcile was dropped while " + blocker + " was set");
                model[blocker] = false;
                root.reconcileNext();
                return;
            }
            default: {
                // Unblocked: the queued reconcile must now run, exactly once.
                if (model.testReconcileRuns === root.reconcileBefore) {
                    root.reconcileCheck(waited < 3000,
                        "the queued reconcile never ran after " + blocker + " was cleared");
                    return;
                }
                root.reconcileCheck(model.testReconcileRuns === root.reconcileBefore + 1,
                    "the reconcile ran more than once after " + blocker + " was cleared");
                root.reconcileCheck(!model.wallpaperReconcilePending,
                    "the reconcile ran but is still queued (" + blocker + ")");
                // Let the action finish before the next case.
                if (model.wallpaperBusy) return;
                root.reconcileNext();
                return;
            }
            }
        }
    }
