    // Runs inside an isolated copy of the production ShellRoot. The status and
    // log files live in a private XDG_STATE_HOME; the model watches them exactly
    // as it does for a real lyona-update run.
    property int updateStage: 0
    property double updateStageStarted: Date.now()
    property var updatePillItem: null

    function updateCheck(ok, detail) {
        if (!ok) {
            console.error("Update progress FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function updateItems(item, predicate) {
        let result = predicate(item) ? [item] : [];
        for (const child of item.children || [])
            result = result.concat(updateItems(child, predicate));
        return result;
    }
    function updateFind(container, objectName) {
        return updateItems(container, item => item.objectName === objectName)[0];
    }
    function updateStatusText(phase, detail, outcome, message, ageMs) {
        const stamp = new Date(Date.now() - ageMs).toISOString().replace(/\.\d+Z$/, "Z");
        return "lyona-update-status-protocol\t1\t0\nphase\t" + phase + "\t" + detail
            + "\ntarget\t2026.10.0\noutcome\t" + outcome + "\t" + message
            + "\ntimestamp\t" + stamp + "\ncomplete\tstatus\n";
    }
    // Same atomic replace lyona-update itself uses, so the model's file watch
    // sees what it sees in production.
    function updateWriteFile(path, text) {
        updateFileWriter.command = ["sh", "-c", 'printf "%s" "$1" > "$2.tmp" && mv "$2.tmp" "$2"', "sh", text, path];
        updateFileWriter.running = true;
    }
    function updateNext() {
        root.updateStage++;
        root.updateStageStarted = Date.now();
    }
    function updatePanelItem(objectName) {
        return root.updateFind(root.defaultPanelWindow.contentItem, objectName);
    }
    Process { id: updateFileWriter; running: false }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            const waited = Date.now() - root.updateStageStarted;
            if (waited > 8000)
                root.updateCheck(false, "stage " + root.updateStage + " timed out");
            const model = updateModel;
            const popup = updateProgressWindow;
            switch (root.updateStage) {
            case 0: {
                // The shell starts while an update is in flight (as after the
                // restart an apply causes): the progress surfaces are already up.
                if (!(model.busy && model.phase === "installing")) return;
                root.updateCheck(model.progressShown && !model.popupClosed,
                    "an update in flight is not shown at shell start");
                root.updateCheck(popup.visible, "the progress popup is not visible at shell start");
                root.updatePillItem = root.updatePanelItem("updatePill");
                root.updateCheck(root.updatePillItem !== undefined && root.updatePillItem.visible,
                    "the panel indicator is not visible while an update runs");
                model.refreshLog();
                root.updateNext();
                return;
            }
            case 1: {
                if (model.logState === "loading" || model.logState === "idle") return;
                root.updateCheck(model.logState === "ready" && model.logText.indexOf("fixture log line two") >= 0
                    && !model.logTruncated, "the update log was not read: " + model.logState);
                popup.showLog = true;
                root.updateNext();
                return;
            }
            case 2: {
                const body = root.updateFind(popup.contentItem, "updateLogBody");
                if (body === undefined || body.text.indexOf("fixture log line two") < 0) return;
                root.updateCheck(true, "");
                root.updateNext();
                return;
            }
            case 3: {
                // Hide it while the update keeps running: the indicator stays,
                // and clicking it brings the popup back.
                model.closePopup();
                root.updateCheck(!popup.visible, "closing the popup did not hide it");
                root.updateCheck(model.busy && model.progressShown && root.updatePillItem.visible,
                    "hiding the popup removed the indicator or ended the update");
                const area = root.updatePanelItem("updatePillArea");
                root.updateCheck(area !== undefined, "the indicator has no click area");
                area.clicked(null);
                root.updateCheck(popup.visible && !model.popupClosed, "clicking the indicator did not reopen the popup");
                popup.showLog = false;
                root.updateWriteFile(model.statusPath, root.updateStatusText("restarting", "Update complete",
                    "succeeded", "", 0));
                root.updateNext();
                return;
            }
            case 4: {
                // The update finished: the outcome is shown, even if the popup had been hidden.
                if (model.busy) return;
                root.updateCheck(model.actionSucceeded && model.message === "Update complete",
                    "a finished update is not reported as complete");
                root.updateCheck(model.progressShown && popup.visible && root.updatePillItem.visible,
                    "a finished update is not shown");
                model.dismissProgress();
                root.updateCheck(!model.progressShown && !popup.visible && !root.updatePillItem.visible,
                    "dismissing did not remove the popup and the indicator");
                // An old failure (30 minutes) is news to nobody.
                root.updateWriteFile(model.statusPath, root.updateStatusText("installing", "Installing",
                    "failed", "old failure A", 30 * 60 * 1000));
                root.updateNext();
                return;
            }
            case 5: {
                if (model.message !== "old failure A") return;
                root.updateCheck(!model.progressShown && !popup.visible && !root.updatePillItem.visible,
                    "an outcome from 30 minutes ago was shown again");
                // A pending status left by a crash two hours ago must not spin forever.
                root.updateWriteFile(model.statusPath, root.updateStatusText("building", "Building",
                    "pending", "", 2 * 60 * 60 * 1000));
                root.updateNext();
                return;
            }
            case 6: {
                if (model.phase !== "building") return;
                root.updateCheck(!model.progressShown && !popup.visible && !root.updatePillItem.visible,
                    "a stale pending status from a crashed update was shown");
                root.updateWriteFile(model.statusPath, root.updateStatusText("installing", "Installing",
                    "failed", "fresh failure B (exit 3)", 0));
                root.updateNext();
                return;
            }
            case 7: {
                if (model.message !== "fresh failure B (exit 3)") return;
                root.updateCheck(!model.busy && !model.actionSucceeded && model.progressShown && popup.visible
                    && root.updatePillItem.visible && popup.failed, "a fresh failure is not shown");
                // The log is bounded: 200 KB written, at most 64 KiB read, cut at a line.
                updateFileWriter.command = ["sh", "-c",
                    'yes "line of update log output" | head -c 200000 > "$1" && printf "\\nEND-OF-LOG\\n" >> "$1"',
                    "sh", model.logPath];
                updateFileWriter.running = true;
                root.updateNext();
                return;
            }
            case 8: {
                if (updateFileWriter.running) return;
                model.refreshLog();
                root.updateNext();
                return;
            }
            case 9: {
                if (model.logState === "loading") return;
                root.updateCheck(model.logState === "ready", "the large log was not read: " + model.logState);
                root.updateCheck(model.logTruncated, "a 200 KB log was not reported as truncated");
                root.updateCheck(model.logText.length <= 65536, "more than 64 KiB of log was loaded: " + model.logText.length);
                root.updateCheck(model.logText.indexOf("line of update log output\n") === 0,
                    "the log tail does not start at a line boundary");
                root.updateCheck(model.logText.indexOf("END-OF-LOG") > 0, "the newest output is missing from the tail");
                updateFileWriter.command = ["sh", "-c", 'rm -f "$1"', "sh", model.logPath];
                updateFileWriter.running = true;
                root.updateNext();
                return;
            }
            case 10: {
                if (updateFileWriter.running) return;
                model.refreshLog();
                root.updateNext();
                return;
            }
            case 11: {
                if (model.logState === "loading") return;
                root.updateCheck(model.logState === "unavailable" && model.logText === "",
                    "a missing log was not reported as unavailable: " + model.logState);
                console.info("Update progress: PASS");
                Qt.quit();
                return;
            }
            }
        }
    }
