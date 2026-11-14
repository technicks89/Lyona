import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "../core/Protocol.js" as Protocol

// The panel's weather (Sync Sprint 12 S12-20, decision D-19). The lyona-weather
// helper fetches and caches; this asks it only while the Bar Widgets switch is
// on: once when it turns on, then every 30 minutes. Weather is an inherently
// sampled value, so a timer is the right source; while the switch is off there
// is no timer and no request, and the switch starts off.
//
// A failed refresh keeps the last good report, marked stale, instead of
// blanking the widget until the next refresh 30 minutes later (#480, upstream
// dwm-titus #422). "Unavailable" is shown only when there is no report. The
// report is dropped when the widget is turned off or the settings change, so
// one place's weather is never shown for another. No extra request is made.
Scope {
    id: root

    required property var panelSettingsModel

    readonly property bool enabled: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("weather") : false
    property bool visible: false
    property real anchorX: 0

    // The last result: available, unconfigured, unavailable, or loading.
    property string weatherState: "loading"
    property string detail: ""
    property string temperature: ""
    property string unit: ""
    property int code: -1
    property string description: ""
    property string place: ""
    property string observed: ""
    // The report above is the last good one, and the latest refresh failed;
    // detail says why.
    property bool stale: false
    // The location setting the report was fetched for.
    property string reportLocation: ""
    // Weather is read once the settings are: at start and after a change.
    property bool refreshAfterSettings: false
    property bool settingsLoaded: false

    // The settings, as the helper reports them.
    property string location: ""
    property string units: "auto"
    property string resolvedUnits: "celsius"
    property bool busy: false
    property string message: ""

    readonly property string panelText: root.weatherState === "available"
        ? Math.round(Number(root.temperature)) + "°" + root.unit
        : root.weatherState === "unconfigured" ? "Weather" : root.weatherState === "loading" ? "..." : "Unavailable"

    function clearReport() {
        root.temperature = "";
        root.unit = "";
        root.code = -1;
        root.description = "";
        root.place = "";
        root.observed = "";
        root.stale = false;
        root.reportLocation = "";
    }

    // A refresh that did not bring a report: keep the last good one, marked
    // stale, or show the failure when there is none.
    function failRefresh(detail) {
        root.detail = detail;
        if (root.temperature.length > 0) {
            root.weatherState = "available";
            root.stale = true;
        } else {
            root.weatherState = "unavailable";
        }
    }

    function refresh() {
        if (!root.enabled || currentProcess.running) return;
        if (!root.settingsLoaded) {
            root.refreshAfterSettings = true;
            root.refreshSettings();
            return;
        }
        currentProcess.running = true;
    }

    function refreshSettings() {
        if (!statusProcess.running) statusProcess.running = true;
    }

    function parseCurrent(text) {
        const lines = text.trim().split("\n");
        if (lines.length < 3 || !Protocol.isHeader(lines[0].split("\t"), "weather-protocol", 1)
                || lines[lines.length - 1] !== "complete\tcurrent") {
            root.failRefresh("The weather helper returned invalid data");
            return;
        }
        const state = lines[1].split("\t");
        if (state.length !== 3 || state[0] !== "state"
                || ["available", "unconfigured", "unavailable"].indexOf(state[1]) < 0) {
            root.failRefresh("The weather helper returned invalid data");
            return;
        }
        if (state[1] === "unavailable") {
            root.failRefresh(state[2]);
            return;
        }
        if (state[1] === "unconfigured") {
            root.clearReport();
        } else {
            const fields = lines.length === 4 ? lines[2].split("\t") : [];
            if (fields.length !== 7 || fields[0] !== "weather" || isNaN(Number(fields[1]))) {
                root.failRefresh("The weather helper returned invalid data");
                return;
            }
            root.temperature = fields[1];
            root.unit = fields[2];
            root.code = Number(fields[3]);
            root.description = fields[4];
            root.place = fields[5];
            root.observed = fields[6];
            root.stale = false;
            root.reportLocation = root.location;
        }
        root.weatherState = state[1];
        root.detail = state[2];
    }

    function parseSettings(text) {
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields.length !== 3 || fields[0] !== "setting") continue;
            if (fields[1] === "location") root.location = fields[2];
            else if (fields[1] === "units") root.units = fields[2];
            else if (fields[1] === "resolved-units") root.resolvedUnits = fields[2];
        }
        root.settingsLoaded = true;
        // A report fetched for another location is not kept for this one.
        if (root.temperature.length > 0 && root.reportLocation !== root.location) {
            root.clearReport();
            if (root.weatherState === "available") root.weatherState = "loading";
        }
        if (root.refreshAfterSettings) {
            root.refreshAfterSettings = false;
            root.refresh();
        }
    }

    function runAction(action, value) {
        if (root.busy) return;
        root.busy = true;
        root.message = "";
        // The helper drops its cache on any settings change; so does this.
        root.clearReport();
        root.weatherState = "loading";
        actionProcess.command = Commands.checkedCommand(Commands.weatherCommand(action, [value]));
        actionProcess.running = true;
    }

    function setLocation(text) {
        root.runAction("set-location", String(text).trim());
    }

    function setUnits(value) {
        root.runAction("set-units", value);
    }

    function open(anchorX) {
        root.anchorX = anchorX || 0;
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
    }

    function toggle(anchorX) {
        if (root.visible) root.close();
        else root.open(anchorX);
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            root.close();
            root.clearReport();
            root.weatherState = "loading";
        }
    }
    Component.onCompleted: root.refreshSettings()

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: root.enabled
        onTriggered: root.refresh()
    }

    Process {
        id: currentProcess
        command: Commands.weatherCommand("current", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseCurrent(this.text) }
    }

    Process {
        id: statusProcess
        command: Commands.weatherCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseSettings(this.text) }
    }

    Process {
        id: actionProcess
        running: false
        stderr: StdioCollector { id: actionError }
        onExited: exitCode => {
            root.busy = false;
            root.message = exitCode === 0 ? "Weather settings saved"
                : actionError.text.trim().length > 0 ? actionError.text.trim()
                : "The weather helper did not confirm the change";
            // The settings first, so the report that follows is checked
            // against the location it was fetched for.
            root.refreshAfterSettings = true;
            root.refreshSettings();
        }
    }
}
