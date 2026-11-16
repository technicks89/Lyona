import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Settings > Appearance > Layout (#479, #530): the layout, master area size,
// master window count and tile gap of the tag the selected monitor shows, and
// title bars on floating windows (#534). SettingsModel owns it, so the pane
// only binds; the processes start here, as the models-only rule asks.
//
// The values come from dwm's _DWM_LAYOUT_SETTINGS, watched by
// dwm-layout-settings only while `active` (the Appearance section shown in an
// open Settings window); a change is saved to layout.toml, which dwm reloads.
// Title bars are two keys of themes.toml's [appearance], read and written by
// dwm-settings-theme. Unprivileged throughout.
Scope {
    id: root

    // Set by SettingsModel.
    property bool active: false
    property var dwmState: null

    // The limits dwm (config.c load_layout_toml) and dwm-layout-settings
    // apply; tests/test-layout-settings.sh checks the three agree (#530).
    readonly property var limits: ({
        "mfact": { "minimum": 5, "maximum": 95 },
        "nmaster": { "minimum": 0, "maximum": 20 },
        "gap": { "minimum": 0, "maximum": 64 }
    })

    // From the helper; -1 until it reports.
    property int monitorIndex: -1
    property int tagNumber: -1
    property int masterSize: 55
    property int masterCount: 1
    property int gap: 0
    property int layoutIndex: -1
    property bool available: false
    // A first line has come since the watch started: until then the pane
    // says it is reading, not that dwm has published nothing (#530).
    property bool reported: false
    property string message: ""
    readonly property bool editable: root.available && root.tagNumber >= 1

    // The monitor's output name (DP-1), from the panel's own mapping of dwm's
    // monitor order to screens; "" when it is not known.
    readonly property string outputName: {
        if (!root.dwmState || root.monitorIndex < 0) return "";
        const screen = root.dwmState.screenForMonitorIndex(root.monitorIndex);
        return screen && screen.name ? screen.name : "";
    }
    readonly property string viewLabel: (root.outputName.length > 0 ? root.outputName
        : "Monitor " + (root.monitorIndex + 1)) + ", tag " + root.tagNumber

    // Index into dwm's default layouts[], as the Control Center's switcher.
    readonly property var layoutChoices: [
        { "label": "Tile", "index": 0 },
        { "label": "Floating", "index": 1 },
        { "label": "Monocle", "index": 2 }
    ]

    // Writes waiting to start, the latest per field: { field: { target, value } }.
    property var pendingSaves: ({})
    // The field being written now, "" when none.
    property string savingField: ""
    // Values asked for that dwm has not reported yet, by field. The sliders
    // show these (#529): a watch line arriving between quick steps moved a
    // slider back, and the next step started from the old value.
    property var requested: ({})
    readonly property var watched: ({ "mfact": root.masterSize, "nmaster": root.masterCount, "gap": root.gap })

    // Title bars (#534): on or off, and which tags, as dwm reads them.
    property bool titlebarsKnown: false
    property bool titlebarsEnabled: false
    property int titlebarTags: 511
    property bool titlebarsBusy: titlebarSetProcess.running
    property string titlebarsMessage: ""

    onActiveChanged: {
        if (root.active) {
            layoutWatch.start();
            root.refreshTitlebars();
        } else {
            layoutWatch.stop();
            root.reported = false;
        }
    }
    Component.onCompleted: if (root.active) layoutWatch.start()
    Component.onDestruction: layoutWatch.stop()

    function target() {
        return root.monitorIndex + " " + root.tagNumber;
    }

    function shown(field) {
        return root.requested[field] !== undefined ? root.requested[field] : root.watched[field];
    }

    function parseState(text) {
        const fields = text.trim().split("\t");
        if (fields[0] !== "layout-settings") return;
        root.reported = true;
        if (fields.length === 2 && fields[1] === "unavailable") {
            root.available = false;
            return;
        }
        if (fields.length !== 7) return;
        const values = fields.slice(1).map(function(value) { return parseInt(value, 10); });
        if (values.some(isNaN)) return;
        const sameView = values[0] === root.monitorIndex && values[1] === root.tagNumber;
        root.monitorIndex = values[0];
        root.tagNumber = values[1];
        root.masterSize = values[2];
        root.masterCount = values[3];
        root.gap = values[4];
        root.layoutIndex = values[5];
        root.available = true;
        root.reconcileRequested(sameView);
    }

    // dwm's value wins once it matches, once no write for the field is left,
    // or when another monitor or tag is shown.
    function reconcileRequested(sameView) {
        const kept = {};
        for (const field of Object.keys(root.requested)) {
            const writing = root.savingField === field || root.pendingSaves[field] !== undefined;
            if (sameView && writing && root.requested[field] !== root.watched[field]) kept[field] = root.requested[field];
        }
        root.requested = kept;
    }

    // Queues one value (or "default") for the tag shown now. The pane checks a
    // drag's tag before it calls this.
    function save(field, value) {
        if (!root.editable || root.limits[field] === undefined) return;
        const saved = value === "default" ? "default" : Math.round(value);
        root.message = "";
        const asked = Object.assign({}, root.requested);
        if (saved === "default") delete asked[field];
        else asked[field] = saved;
        root.requested = asked;
        const pending = Object.assign({}, root.pendingSaves);
        pending[field] = { "target": root.target(), "value": saved };
        root.pendingSaves = pending;
        root.sendPendingSave();
    }

    // Reset (#530): the tag's three values back to the defaults, as removing
    // its entries from layout.toml would.
    function resetTag() {
        if (!root.editable) return;
        root.save("mfact", "default");
        root.save("nmaster", "default");
        root.save("gap", "default");
    }

    // Starts the next waiting write; while one runs, its exit starts the next,
    // so writes go one at a time and in order. A write whose tag is no longer
    // shown is dropped.
    function sendPendingSave() {
        if (saveProcess.running) return;
        const fields = Object.keys(root.pendingSaves);
        if (fields.length === 0) return;
        const pending = Object.assign({}, root.pendingSaves);
        const field = fields[0];
        const next = pending[field];
        delete pending[field];
        root.pendingSaves = pending;
        if (next.target !== root.target()) {
            root.sendPendingSave();
            return;
        }
        root.savingField = field;
        saveProcess.command = Commands.layoutSettingsCommand("set", [
            String(root.monitorIndex), String(root.tagNumber), field, String(next.value)
        ]);
        saveProcess.running = true;
    }

    function setLayout(index) {
        Quickshell.execDetached(Commands.stateHelperCommand("layout", [String(index)]));
    }

    function refreshTitlebars() {
        if (!titlebarStatusProcess.running) titlebarStatusProcess.running = true;
    }

    function parseTitlebars(text) {
        let headerOk = false;
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "appearance-titlebars-protocol") headerOk = fields[1] === "1";
            else if (headerOk && fields[0] === "titlebars" && fields.length === 3
                    && (fields[1] === "0" || fields[1] === "1")) {
                const mask = parseInt(fields[2], 10);
                if (isNaN(mask) || mask < 1 || mask > 511) continue;
                root.titlebarsEnabled = fields[1] === "1";
                root.titlebarTags = mask;
                root.titlebarsKnown = true;
            }
        }
    }

    function tagHasTitlebars(tag) {
        return (root.titlebarTags & (1 << (tag - 1))) !== 0;
    }

    // Writes both keys; the last tag cannot be turned off (dwm needs 1-511).
    function setTitlebars(enabled, mask) {
        if (!root.titlebarsKnown || titlebarSetProcess.running || mask < 1 || mask > 511) return;
        root.titlebarsMessage = "";
        titlebarSetProcess.command = Commands.settingsThemeCommand("titlebars", [enabled ? "1" : "0", String(mask)]);
        titlebarSetProcess.running = true;
    }

    function toggleTitlebarTag(tag) {
        const mask = root.titlebarTags ^ (1 << (tag - 1));
        if (mask === 0) return;
        root.setTitlebars(root.titlebarsEnabled, mask);
    }

    WatchedProcess {
        id: layoutWatch
        command: Commands.watchCommand(Commands.layoutSettingsCommand("watch"))
        active: root.active
        onLine: text => root.parseState(text)
    }

    Process {
        id: saveProcess
        running: false
        stderr: StdioCollector { id: saveError }
        onExited: exitCode => {
            root.savingField = "";
            root.message = exitCode === 0 ? ""
                : saveError.text.trim().length > 0 ? saveError.text.trim()
                : "The layout settings could not be saved";
            if (exitCode === 0) {
                root.sendPendingSave();
            } else {
                // Nothing more is sent, and the sliders go back to dwm's values.
                root.pendingSaves = ({});
                root.requested = ({});
            }
        }
    }

    Process {
        id: titlebarStatusProcess
        command: Commands.settingsThemeCommand("titlebars-status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseTitlebars(this.text) }
    }

    Process {
        id: titlebarSetProcess
        running: false
        stderr: StdioCollector { id: titlebarError }
        onExited: exitCode => {
            root.titlebarsMessage = exitCode === 0 ? ""
                : titlebarError.text.trim().replace(/^dwm-settings-theme: /, "") || "Title bars could not be saved";
            root.refreshTitlebars();
        }
    }
}
