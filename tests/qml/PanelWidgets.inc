    // Runs inside an isolated copy of the production ShellRoot (#474, #472,
    // #470), against the real panel, clock and DwmState, with every helper
    // replaced by `true`.
    property int widgetStage: 0
    property double widgetStageStarted: Date.now()
    readonly property var widgetPanel: panelVariants.instances.length > 0 ? panelVariants.instances[0] : null

    function widgetCheck(ok, detail) {
        if (!ok) {
            console.error("Panel widgets FAILED at stage " + root.widgetStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function widgetNext() {
        root.widgetStage++;
        root.widgetStageStarted = Date.now();
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const waited = Date.now() - root.widgetStageStarted;
            root.widgetCheck(waited < 10000, "timed out");
            const panel = root.widgetPanel;
            switch (root.widgetStage) {
            case 0:
                // The panel is up, and the helpers' status (from `true`)
                // has come and gone: the safe defaults hold.
                if (!panel || !panel.findItem("occupiedMarker") || waited < 500) return;
                dwmState.parseState("names=1|2|3|4|5|6|7|8|9\noccupied=");
                root.widgetNext();
                return;
            case 1: {
                // #474: no windows, no marker; a window on tag 1 shows it, in
                // the label's colour, and it goes when the tag empties.
                const marker = panel.findItem("occupiedMarker");
                root.widgetCheck(!marker.visible, "an empty tag shows the marker");
                dwmState.parseState("occupied=0|3");
                root.widgetCheck(marker.visible, "an occupied tag shows no marker");
                root.widgetCheck(marker.width > 0 && marker.height > 0, "the marker has no size");
                root.widgetCheck(Qt.colorEqual(marker.color, marker.parent.foreground),
                    "the marker is not in the label's colour");
                dwmState.parseState("occupied=3");
                root.widgetCheck(!marker.visible, "the marker stayed after the tag emptied");
                root.widgetNext();
                return;
            }
            case 2:
                // #472: off by default, the clock ticks once a minute and shows
                // no seconds; on, every second with seconds; off again, as before.
                root.widgetCheck(!panelSettingsModel.clockSeconds && !clock.showSeconds,
                    "seconds are on by default");
                root.widgetCheck(!clock.ticksEverySecond, "the clock ticks every second with seconds off");
                root.widgetCheck(/ - \d\d:\d\d$/.test(clock.panelText), "clock text: " + clock.panelText);
                clock.showSeconds = true;
                root.widgetCheck(clock.ticksEverySecond, "the clock does not tick every second with seconds on");
                root.widgetCheck(/ - \d\d:\d\d:\d\d$/.test(clock.panelText), "clock text with seconds: " + clock.panelText);
                clock.showSeconds = false;
                root.widgetCheck(!clock.ticksEverySecond && / - \d\d:\d\d$/.test(clock.panelText),
                    "seconds off again: " + clock.panelText);
                // The binding to the panel setting, restored.
                clock.showSeconds = Qt.binding(function() { return panelSettingsModel.clockSeconds; });
                root.widgetNext();
                return;
            case 3: {
                // #472, the model: a 1.1 status with the option on, a widget and
                // a record it does not know (skipped), then a status without
                // the option (off).
                panelSettingsModel.parseStatus("panel-settings-protocol\t1\t1\nstate\tavailable\tok\n"
                    + "widget\tworkspaces\tenabled\nwidget\tvolume\tenabled\nwidget\tbluetooth\tenabled\n"
                    + "widget\tnetwork\tenabled\nwidget\tpower\tenabled\nwidget\tcalendar\tenabled\n"
                    + "widget\tweather\tdisabled\nwidget\tkeyboard\tenabled\nwidget\tlater\tenabled\n"
                    + "option\tclock-seconds\tenabled\nfuture\trecord\there\ncomplete\tstatus\n");
                root.widgetCheck(panelSettingsModel.clockSeconds && clock.showSeconds && clock.ticksEverySecond,
                    "the clock-seconds option did not reach the clock");
                panelSettingsModel.parseStatus("panel-settings-protocol\t1\t0\nstate\tavailable\tok\n"
                    + "widget\tworkspaces\tenabled\nwidget\tvolume\tenabled\nwidget\tbluetooth\tenabled\n"
                    + "widget\tnetwork\tenabled\nwidget\tpower\tenabled\nwidget\tcalendar\tenabled\n"
                    + "widget\tweather\tdisabled\nwidget\tkeyboard\tenabled\ncomplete\tstatus\n");
                root.widgetCheck(!panelSettingsModel.clockSeconds && !clock.ticksEverySecond,
                    "a status without the option left seconds on");
                root.widgetNext();
                return;
            }
            case 4: {
                // #470: one layout, no pill; two, the active one's label.
                const pill = panel.findItem("keyboardLayoutPill");
                root.widgetCheck(pill !== undefined, "no keyboard layout pill");
                dwmState.parseState("keyboard_group=0|1\nkeyboard_layouts=US");
                root.widgetCheck(!pill.visible, "the pill shows with one layout");
                dwmState.parseState("keyboard_group=1|2\nkeyboard_layouts=US|DE");
                root.widgetCheck(pill.visible && dwmState.keyboardLabel === "DE",
                    "two layouts: visible " + pill.visible + ", label " + dwmState.keyboardLabel);
                // A malformed group hides it rather than showing a wrong label.
                dwmState.parseState("keyboard_group=2|2");
                root.widgetCheck(!pill.visible && dwmState.keyboardGroup === -1, "a group past the count");
                dwmState.parseState("keyboard_group=0|2");
                root.widgetCheck(pill.visible && dwmState.keyboardLabel === "US", "back to group 0");
                // Turned off in Settings, it hides.
                panelSettingsModel.parseStatus("panel-settings-protocol\t1\t1\nstate\tavailable\tok\n"
                    + "widget\tworkspaces\tenabled\nwidget\tvolume\tenabled\nwidget\tbluetooth\tenabled\n"
                    + "widget\tnetwork\tenabled\nwidget\tpower\tenabled\nwidget\tcalendar\tenabled\n"
                    + "widget\tweather\tdisabled\nwidget\tkeyboard\tdisabled\n"
                    + "option\tclock-seconds\tdisabled\ncomplete\tstatus\n");
                root.widgetCheck(!pill.visible, "the pill shows with its widget off");
                // Clicks queue, one request at a time, and all are sent.
                dwmState.nextKeyboardLayout();
                dwmState.nextKeyboardLayout();
                dwmState.nextKeyboardLayout();
                root.widgetCheck(dwmState.pendingKeyboardSteps === 2, "queued steps: " + dwmState.pendingKeyboardSteps);
                root.widgetNext();
                return;
            }
            case 5:
                if (dwmState.pendingKeyboardSteps > 0) return;
                console.log("Panel widgets: PASS");
                Qt.quit();
                return;
            }
        }
    }
