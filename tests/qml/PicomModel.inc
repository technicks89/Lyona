    // Runs inside an isolated copy of the production ShellRoot. Open the Picom
    // model the way the Appearance pane does, let the stubbed helper play its
    // scenario, then report what the model ended up showing; the test script
    // counts the status reads the stub logged.
    Timer {
        interval: 200
        running: true
        onTriggered: appearanceModel.testPicom.active = true
    }
    // Press the Appearance pane's Refresh, when the scenario asks for it.
    Timer {
        interval: Number(Quickshell.env("PICOM_REFRESH_MS") || 0)
        running: interval > 0
        onTriggered: {
            console.info("Picom before refresh: failure=" + appearanceModel.testPicom.failure);
            appearanceModel.refreshAll(true);
        }
    }
    Timer {
        interval: Number(Quickshell.env("PICOM_RUN_MS") || 3000)
        running: true
        onTriggered: {
            const picom = appearanceModel.testPicom;
            console.info("Picom result: revision=" + picom.snapshot.revision
                + " busy=" + picom.statusBusy + " failure=" + picom.failure);
            Qt.quit();
        }
    }
