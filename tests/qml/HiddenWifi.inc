    // Runs inside an isolated copy of the production ShellRoot (#471): the
    // hidden network prompt, against the real NetworkModel and prompt window.
    // Snapshots are given to the model directly; the join goes to a stub.
    property int hiddenStage: 0
    property double hiddenStageStarted: Date.now()
    readonly property string hiddenHeader: "connectivity-protocol\t1\nprovider\tnetwork\tavailable\tdelegated\tNetworkManager\nnetwork-state\tdisconnected\n"
    readonly property string withAdapter: root.hiddenHeader + "network-device\twlan0\twifi\tdisconnected\t-\n"
    readonly property string withTwoAdapters: root.hiddenHeader + "network-device\twlan0\twifi\tdisconnected\t-\nnetwork-device\twlan1\twifi\tconnected\tHome\n"
    readonly property string withoutAdapter: root.hiddenHeader + "network-device\teth0\tethernet\tunavailable\t-\n"
    property string hiddenLog: ""
    // The success message was shown (a refresh after it may replace it).
    property bool sawJoined: false
    property bool sawCancelled: false

    Connections {
        target: networkModel
        function onMessageChanged() {
            if (networkModel.message === "Joined Back Office") root.sawJoined = true;
            if (networkModel.message === "Did not join Slow Net") root.sawCancelled = true;
        }
    }

    function hiddenCheck(ok, detail) {
        if (!ok) {
            console.error("Hidden Wi-Fi FAILED at stage " + root.hiddenStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function hiddenNext() {
        root.hiddenStage++;
        root.hiddenStageStarted = Date.now();
    }

    FileView {
        id: hiddenLogFile
        path: Quickshell.env("HIDDEN_WIFI_LOG")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.hiddenLog = hiddenLogFile.text()
    }

    Process {
        id: hiddenFail
        command: ["touch", Quickshell.env("HIDDEN_WIFI_LOG") + ".fail"]
        running: false
    }
    Process {
        id: hiddenSlow
        command: ["touch", Quickshell.env("HIDDEN_WIFI_LOG") + ".slow"]
        running: false
    }
    Process {
        id: hiddenSucceed
        command: ["rm", "-f", Quickshell.env("HIDDEN_WIFI_LOG") + ".fail"]
        running: false
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const model = networkModel;
            const waited = Date.now() - root.hiddenStageStarted;
            root.hiddenCheck(waited < 10000, "timed out");
            switch (root.hiddenStage) {
            case 0:
                if (waited < 500) return;
                // Before any snapshot has named the adapters, the prompt waits;
                // a snapshot that fails keeps it waiting.
                model.stateKnown = false;
                model.openHiddenPrompt();
                root.hiddenCheck(model.hiddenPromptPending && !model.hiddenPromptVisible, "opened before a snapshot");
                model.parseSnapshot("not a snapshot");
                root.hiddenCheck(model.hiddenPromptPending && !model.hiddenPromptVisible, "a failed snapshot opened or dropped it");
                model.parseSnapshot(root.withAdapter);
                root.hiddenCheck(model.hiddenPromptVisible && !model.hiddenPromptPending, "a snapshot did not open it");
                root.hiddenCheck(model.hiddenMessage === "", "message: " + model.hiddenMessage);
                root.hiddenNext();
                return;
            case 1:
                // An adapter that goes and comes back: said, then cleared, and
                // the prompt stays open.
                model.parseSnapshot(root.withoutAdapter);
                root.hiddenCheck(model.hiddenPromptVisible, "a snapshot closed the prompt");
                root.hiddenCheck(model.hiddenMessage.indexOf("No Wi-Fi adapter") === 0, "no adapter message: " + model.hiddenMessage);
                root.hiddenCheck(model.hiddenJoinProblem() === "No Wi-Fi adapter", "joinable without an adapter");
                model.parseSnapshot(root.withAdapter);
                root.hiddenCheck(model.hiddenMessage === "", "the adapter message stayed");
                // What it asks for before Join is enabled.
                root.hiddenCheck(model.hiddenJoinProblem() === "Enter the network name", model.hiddenJoinProblem());
                model.hiddenSsid = "n".repeat(33);
                root.hiddenCheck(model.hiddenJoinProblem() === "A network name is at most 32 bytes", model.hiddenJoinProblem());
                model.hiddenSsid = "é".repeat(16);
                root.hiddenCheck(model.hiddenJoinProblem() === "A WPA password is 8 to 63 characters", model.hiddenJoinProblem());
                model.hiddenSsid = "Back Office";
                model.hiddenPassword = "short";
                root.hiddenCheck(model.hiddenJoinProblem().length > 0, "a short WPA password");
                model.hiddenSecurity = "open";
                root.hiddenCheck(model.hiddenJoinProblem() === "", "open: " + model.hiddenJoinProblem());
                model.hiddenSecurity = "wpa-psk";
                model.hiddenPassword = "wrong password";
                root.hiddenCheck(model.hiddenJoinProblem() === "", model.hiddenJoinProblem());
                hiddenFail.running = true;
                root.hiddenNext();
                return;
            case 2:
                if (hiddenFail.running || waited < 200) return;
                model.joinHidden();
                root.hiddenCheck(model.busy, "the join did not start");
                root.hiddenNext();
                return;
            case 3:
                // Failed: the prompt stays, the name kept, the password gone,
                // the helper's reason shown.
                if (model.busy) return;
                root.hiddenCheck(model.hiddenPromptVisible, "a failed join closed the prompt");
                root.hiddenCheck(model.hiddenSsid === "Back Office" && model.hiddenPassword === "",
                    "after a failure: name " + model.hiddenSsid + ", password kept " + (model.hiddenPassword !== ""));
                root.hiddenCheck(model.hiddenMessage === "wrong password, or the network asked for one it did not get",
                    "reason: " + model.hiddenMessage);
                root.hiddenCheck(root.hiddenLog.indexOf("args wlan0 Back Office wpa-psk --password-stdin\n") >= 0
                    && root.hiddenLog.indexOf("stdin wrong password\n") >= 0, "the stub saw: " + root.hiddenLog);
                root.hiddenCheck(root.hiddenLog.indexOf("args") === root.hiddenLog.lastIndexOf("args")
                    || root.hiddenLog.split("args")[1].indexOf("wrong password") < 0, "the password was in argv");
                hiddenSucceed.running = true;
                root.hiddenNext();
                return;
            case 4:
                if (hiddenSucceed.running || waited < 200) return;
                model.parseSnapshot(root.withAdapter);
                model.hiddenPassword = "correct horse battery";
                model.joinHidden();
                root.hiddenNext();
                return;
            case 5:
                // Joined: the prompt closes and says so.
                if (model.busy) return;
                root.hiddenCheck(!model.hiddenPromptVisible && model.hiddenSsid === "", "a join left the prompt open");
                root.hiddenCheck(root.sawJoined, "no success message");
                hiddenSlow.running = true;
                root.hiddenNext();
                return;
            case 6:
                // A join that hangs can be cancelled: the prompt closes at once,
                // and the popover says when the helper has stopped (#529).
                if (hiddenSlow.running || waited < 200) return;
                model.openHiddenPrompt();
                model.parseSnapshot(root.withAdapter);
                model.hiddenSsid = "Slow Net";
                model.hiddenPassword = "correct horse battery";
                model.joinHidden();
                root.hiddenCheck(model.busy, "the slow join did not start");
                root.hiddenNext();
                return;
            case 7:
                if (waited < 300) return;
                model.cancelHiddenJoin();
                root.hiddenCheck(!model.hiddenPromptVisible && model.hiddenSsid === "", "Cancel left the prompt open");
                root.hiddenCheck(model.message.indexOf("Cancelling the join of Slow Net") === 0, "message: " + model.message);
                root.hiddenNext();
                return;
            case 8:
                if (model.busy) return;
                root.hiddenCheck(root.sawCancelled, "after cancel: " + model.message);
                // Two adapters (#534): the connected one by default, the one
                // chosen otherwise.
                model.parseSnapshot(root.withTwoAdapters);
                root.hiddenCheck(model.hiddenJoinDevice === "wlan1", "default adapter: " + model.hiddenJoinDevice);
                model.hiddenDevice = "wlan0";
                root.hiddenCheck(model.hiddenJoinDevice === "wlan0", "chosen adapter: " + model.hiddenJoinDevice);
                model.hiddenDevice = "wlan9";
                root.hiddenCheck(model.hiddenJoinDevice === "wlan1", "a missing adapter was used: " + model.hiddenJoinDevice);
                console.log("Hidden Wi-Fi: PASS");
                Qt.quit();
                return;
            }
        }
    }
