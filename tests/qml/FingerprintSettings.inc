    // Runs inside an isolated copy of the production ShellRoot (#483): Settings
    // lists Fingerprint only with a reader, reads the fingers and uses, loads
    // the pane, enrolls with progress, and asks for a use to be turned on.
    property int fpStage: 0
    property double fpStageStarted: Date.now()
    property string fpLog: ""
    readonly property string fpDir: Quickshell.env("FINGERPRINT_DIR")

    function fpCheck(ok, detail) {
        if (!ok) {
            console.error("Fingerprint settings FAILED at stage " + root.fpStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function fpNext() {
        root.fpStage++;
        root.fpStageStarted = Date.now();
    }
    function fpListed() {
        return settingsModel.sections.some(function(section) { return section.id === "fingerprint"; });
    }

    FileView {
        id: fpLogFile
        path: root.fpDir + "/log"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.fpLog = fpLogFile.text()
    }
    Process { id: fpShell; running: false }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const model = settingsModel.fingerprintModel;
            const waited = Date.now() - root.fpStageStarted;
            root.fpCheck(waited < 10000, "timed out: reader " + model.readerState + ", fingers "
                + JSON.stringify(model.fingers) + ", uses " + JSON.stringify(model.uses) + ", message '"
                + model.message + "', log " + JSON.stringify(root.fpLog));
            switch (root.fpStage) {
            case 0:
                // No reader: Settings opens without the section.
                settingsModel.open("displays");
                root.fpNext();
                return;
            case 1:
                if (model.readerState !== "none") return;
                root.fpCheck(!root.fpListed(), "listed without a reader");
                settingsModel.close();
                fpShell.command = ["sh", "-c", 'cp "$1/status-noreader-on" "$1/status"', "sh", root.fpDir];
                fpShell.running = true;
                root.fpNext();
                return;
            case 2:
                // No reader, but sudo still on: listed, so it can be turned off (#522).
                if (fpShell.running) return;
                settingsModel.open("displays");
                root.fpNext();
                return;
            case 3:
                if (model.useState("sudo") !== "on") return;
                root.fpCheck(model.readerState === "none" && model.anyUseActive && root.fpListed(),
                    "not listed with sudo on and no reader: " + JSON.stringify(model.uses));
                settingsModel.close();
                fpShell.command = ["sh", "-c", 'cp "$1/status-reader" "$1/status"', "sh", root.fpDir];
                fpShell.running = true;
                root.fpNext();
                return;
            case 4:
                if (fpShell.running) return;
                // Opened on a section after Fingerprint's place, so its keyboard
                // place has to follow when Fingerprint is listed.
                settingsModel.open("system");
                root.fpNext();
                return;
            case 5:
                // A reader: listed, fingers and uses read, the pane selected.
                if (model.readerState !== "available" || !root.fpListed()) return;
                root.fpCheck(settingsModel.selectedSectionId === "system"
                    && settingsModel.filteredSections[settingsModel.selectedIndex].id === "system",
                    "the keyboard's place did not follow System: index " + settingsModel.selectedIndex);
                root.fpCheck(model.readerDetail === "Test Reader", "reader: " + model.readerDetail);
                root.fpCheck(JSON.stringify(model.fingers) === '["right-index-finger"]', "fingers");
                // Enrolled outside Settings (#535): said until acknowledged.
                root.fpCheck(JSON.stringify(model.addedFingers) === '["right-index-finger"]', "added: " + JSON.stringify(model.addedFingers));
                root.fpCheck(model.useState("lightdm") === "external" && model.useState("sudo") === "off"
                    && model.useState("polkit") === "on" && model.moduleAvailable, "uses: " + JSON.stringify(model.uses));
                settingsModel.selectSection("fingerprint");
                root.fpCheck(settingsModel.selectedSectionId === "fingerprint", "not selected");
                model.enroll("left-thumb");
                root.fpNext();
                return;
            case 6:
                // Enrolling: progress, then the result, then a fresh status.
                if (model.busy || root.fpLog.indexOf("enroll left-thumb") < 0) return;
                root.fpCheck(model.enrollPassed === 2, "scans counted: " + model.enrollPassed);
                root.fpCheck(model.message === "Left thumb enrolled" && model.messageSeverity === "success",
                    "enroll message: " + model.message);
                model.setUse("sudo", "on");
                root.fpNext();
                return;
            case 7:
                if (model.busy || root.fpLog.indexOf("set sudo on") < 0) return;
                root.fpCheck(model.messageSeverity === "success" && model.message === "sudo now accepts a finger",
                    "set message: " + model.message);
                // A dismissed password dialog is said as cancelled, not failed (#529).
                model.setUse("lightdm", "off");
                root.fpNext();
                return;
            case 8:
                if (model.busy || root.fpLog.indexOf("set lightdm off") < 0) return;
                root.fpCheck(model.message === "Not changed: the password prompt was cancelled"
                    && model.messageSeverity === "idle", "cancelled message: " + model.message + " / " + model.messageSeverity);
                // Bad requests never reach the helper.
                model.setUse("login", "on");
                model.setUse("sudo", "maybe");
                model.enroll("nose");
                model.enroll("right-index-finger");
                root.fpCheck(!model.busy, "a bad request started something");
                root.fpNext();
                return;
            case 9:
                if (waited < 300) return;
                root.fpCheck(root.fpLog.indexOf("login") < 0 && root.fpLog.indexOf("maybe") < 0
                    && root.fpLog.indexOf("nose") < 0 && root.fpLog.indexOf("enroll right-index-finger") < 0,
                    "a bad request reached the helper: " + JSON.stringify(root.fpLog));
                // The reader goes away while Fingerprint is shown, with every use
                // off: the section leaves the list, and the selection moves to one
                // that is listed.
                root.fpCheck(settingsModel.selectedSectionId === "fingerprint", "not on Fingerprint any more");
                fpShell.command = ["sh", "-c", 'sed -E -e "s/^reader\tavailable\t.*/reader\tnone\tNo fingerprint reader was found/" -e "s/^use\t([a-z]+)\t(on|external)\t.*/use\t\\1\toff\tThe password only/" "$1/status-reader" >"$1/status"',
                    "sh", root.fpDir];
                fpShell.running = true;
                root.fpNext();
                return;
            case 10:
                if (fpShell.running) return;
                model.refresh();
                root.fpNext();
                return;
            case 11:
                if (model.readerState !== "none") return;
                root.fpCheck(!root.fpListed(), "still listed without a reader");
                root.fpCheck(settingsModel.selectedSectionId === settingsModel.sections[0].id
                    && settingsModel.selectedSection().id === settingsModel.selectedSectionId,
                    "the selection stayed on " + settingsModel.selectedSectionId);
                settingsModel.close();
                // With a reader found, opening Settings again reads only the PAM
                // files (#532); with none, it still looks (stage 2 relies on it).
                root.fpCheck(!model.readerChecked, "no reader, yet the answer was kept");
                fpShell.command = ["sh", "-c", 'cp "$1/status-reader" "$1/status"', "sh", root.fpDir];
                fpShell.running = true;
                root.fpNext();
                return;
            case 12:
                if (fpShell.running) return;
                settingsModel.open("displays");
                root.fpNext();
                return;
            case 13:
                if (!model.readerChecked) return;
                settingsModel.close();
                settingsModel.open("displays");
                root.fpNext();
                return;
            case 14:
                if (root.fpLog.indexOf("status --uses") < 0 || model.busy) return;
                model.acknowledgeAdded();
                root.fpNext();
                return;
            case 15:
                if (root.fpLog.indexOf("acknowledge right-index-finger") < 0 || model.busy) return;
                root.fpCheck(model.message === "Noted as yours", "acknowledge message: " + model.message);
                settingsModel.close();
                console.log("Fingerprint settings: PASS");
                Qt.quit();
                return;
            }
        }
    }
