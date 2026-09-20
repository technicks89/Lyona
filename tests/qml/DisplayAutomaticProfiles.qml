import QtQuick
import Quickshell
import "settings" as Settings

/*
 * Bespoke Quickshell harness (Sync Sprint 3 S3-02,
 * docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md, ported from upstream's
 * 6b7548b (#290) tests/quickshell-display-profiles.qml) exercising
 * SettingsModel.qml's automatic-profile draft/model logic directly.
 *
 * SettingsModel is a Scope that imports qs.core and instantiates
 * Quickshell-provided types (Process, FileView, Timer), so -- per S1-08's
 * established finding (docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md) -- it cannot
 * be instantiated under bare qmltestrunner. This stays a bespoke harness,
 * spawned via `quickshell --no-duplicate --path .../shell.qml` from
 * tests/test-settings.sh, the same mechanism upstream's own script uses for
 * this exact file, and the same pattern SystemRegionalPreflightOwner.qml
 * already established in tests/qml.
 *
 * Run (from a copy of config/quickshell with this file as its shell.qml):
 * QT_QPA_PLATFORM=offscreen quickshell --no-duplicate --path shell.qml
 */
Scope {
    id: root
    Settings.SettingsModel { id: model }
    function require(condition, message) {
        if (!condition) throw new Error(message);
    }
    Timer { interval: 1; running: true; onTriggered: root.runTests() }
    function runTests() {
        try {
            model.parseDisplays("display-protocol\t1\n"
                + "output\teDP-1\t0\t0\t\t0\t0\tnormal\tunsupported\n"
                + "mode\teDP-1\t2560x1600\t90.00\t0\t1\n"
                + "output\tDVI-I-2-2\t1\t1\t2560x1440\t2560\t0\tnormal\tunsupported\n"
                + "mode\tDVI-I-2-2\t2560x1440\t60.00\t1\t1\n"
                + "output\tDVI-I-1-1\t1\t0\t2560x1440\t0\t0\tnormal\tunsupported\n"
                + "mode\tDVI-I-1-1\t2560x1440\t60.00\t1\t1\n");
            const docked = JSON.parse(JSON.stringify(model.displayOutputs));
            const mobile = [{ name: "eDP-1", enabled: true, primary: true, mode: "2560x1600",
                rate: "90.00", x: 0, y: 0, rotation: "normal" }];
            model.automaticDisplayState = { available: true, profiles: [
                { role: "undocked", name: "mobile", saved: true, outputs: mobile, error: "" },
                { role: "docked", name: "docked", saved: true, outputs: docked, error: "" }
            ], detected: ["docked"], current: [], default: "mobile", error: "" };
            const baseline = model.displayBaseline;
            model.editAutomaticDisplay("undocked");
            require(model.displayEditingRole === "undocked", "Selected editor role");
            require(model.displayOutputs.filter(item => item.enabled).length === 1, "Only builtin enabled in undocked draft");
            require(model.displayOutputs[0].primary && model.displayOutputs[0].mode === "2560x1600", "Restored builtin mode and primary");
            require(model.displayBaseline === baseline && model.displayHasPendingChanges, "Editing does not alter live baseline");
            require(model.previewToken === "" && !model.previewOperationLocked, "Editing cannot start a live preview");
            require(model.automaticDisplayArrangement("docked").tiles.length === 2, "Saved preview independent of draft");
            require(model.automaticDisplaySummary("undocked").indexOf("90.00 Hz") >= 0, "Saved rates visible");
            model.editAutomaticDisplay("docked");
            require(model.displayOutputs.filter(item => item.enabled).length === 2, "Restored dock draft");
            require(!model.displayHasPendingChanges, "Restored dock equals baseline");
            const modes = model.displayModes;
            model.displayModes = [];
            model.displayOutputs = model.displayOutputs.map(item => Object.assign({}, item, { pixelWidth: 800, pixelHeight: 600 }));
            model.editAutomaticDisplay("undocked");
            require(model.displayArrangement.width === 2560, "Saved geometry cannot reuse stale live dimensions");
            model.displayModes = modes;
            model.editAutomaticDisplay("docked");
            model.previewOperationLocked = true;
            model.editAutomaticDisplay("undocked");
            require(model.displayEditingRole === "docked", "Preview locks editing");
            model.previewOperationLocked = false;
            model.displayOutputs = model.displayOutputs.slice(0, 1);
            model.editAutomaticDisplay("docked");
            require(model.automaticDisplayMessage.indexOf("Connect") === 0, "Missing saved monitors block editing");
            console.log("Automatic display draft/model assertions: PASS");
            Qt.quit();
        } catch (error) {
            console.error(error);
            Qt.exit(1);
        }
    }
}
