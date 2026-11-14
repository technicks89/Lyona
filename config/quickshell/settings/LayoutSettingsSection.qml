import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core

pragma ComponentBehavior: Bound

// Settings > Appearance > Layout (#479, upstream dwm-titus #424): the layout,
// master area size, master window count and tile gap of the tag the selected
// monitor shows. The values come from dwm's _DWM_LAYOUT_SETTINGS, watched by
// dwm-layout-settings only while this section is visible; a change is saved
// to layout.toml, which dwm reloads and applies. Unprivileged throughout.
ColumnLayout {
    id: root

    spacing: Theme.spacingMd

    // From the helper; -1 until it reports.
    property int monitorIndex: -1
    property int tagNumber: -1
    property int masterSize: 55
    property int masterCount: 1
    property int gap: 0
    property int layoutIndex: -1
    property bool available: false
    property string message: ""
    readonly property bool editable: root.available && root.tagNumber >= 1
    // Shown: this section's tab selected and the Settings window open. The
    // pane stays loaded when the window hides, so its own visibility is not
    // enough to stop the watch.
    readonly property bool showing: root.visible && root.Window.window !== null
        && root.Window.window.visible

    // Index into dwm's default layouts[], as the Control Center's switcher.
    readonly property var layoutChoices: [
        { "label": "Tile", "index": 0 },
        { "label": "Floating", "index": 1 },
        { "label": "Monocle", "index": 2 }
    ]

    function parseState(text) {
        const fields = text.trim().split("\t");
        if (fields[0] !== "layout-settings") return;
        if (fields.length === 2 && fields[1] === "unavailable") {
            root.available = false;
            return;
        }
        if (fields.length !== 7) return;
        const values = fields.slice(1).map(function(value) { return parseInt(value, 10); });
        if (values.some(isNaN)) return;
        root.monitorIndex = values[0];
        root.tagNumber = values[1];
        root.masterSize = values[2];
        root.masterCount = values[3];
        root.gap = values[4];
        root.layoutIndex = values[5];
        root.available = true;
    }

    // Saves one value for the tag shown now, named exactly, so a view that
    // changes meanwhile is never written instead.
    function save(field, value) {
        if (!root.editable || saveProcess.running) return;
        root.message = "";
        saveProcess.command = Commands.layoutSettingsCommand("set", [
            String(root.monitorIndex), String(root.tagNumber), field, String(Math.round(value))
        ]);
        saveProcess.running = true;
    }

    function setLayout(index) {
        Quickshell.execDetached(Commands.stateHelperCommand("layout", [String(index)]));
    }

    onShowingChanged: root.showing ? layoutWatch.start() : layoutWatch.stop()
    Component.onCompleted: if (root.showing) layoutWatch.start()
    Component.onDestruction: layoutWatch.stop()

    WatchedProcess {
        id: layoutWatch
        command: Commands.watchCommand(Commands.layoutSettingsCommand("watch"))
        active: root.showing
        onLine: text => root.parseState(text)
    }

    Process {
        id: saveProcess
        running: false
        stderr: StdioCollector { id: saveError }
        onExited: exitCode => {
            root.message = exitCode === 0 ? ""
                : saveError.text.trim().length > 0 ? saveError.text.trim()
                : "The layout settings could not be saved";
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: !root.available
        text: "dwm has not published its layout settings yet. Log out and back in once after updating."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    UiText {
        Layout.fillWidth: true
        visible: root.available
        text: root.editable
            ? "Monitor " + root.monitorIndex + ", tag " + root.tagNumber + ". Saved for this tag only."
            : "Showing several tags: choose one tag to change its layout settings."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Repeater {
            model: root.layoutChoices

            delegate: ShellButton {
                id: choice

                required property var modelData

                Layout.fillWidth: true
                label: choice.modelData.label
                primary: root.layoutIndex === choice.modelData.index
                enabled: root.available
                onActivated: root.setLayout(choice.modelData.index)
            }
        }
    }

    UiText {
        Layout.fillWidth: true
        text: "Master area size: " + Math.round(masterSlider.liveValue) + "%"
        color: Theme.text
    }

    PanelSlider {
        id: masterSlider

        Layout.fillWidth: true
        minimum: 5
        maximum: 95
        step: 1
        value: root.masterSize
        enabled: root.editable && root.layoutIndex !== 1
        onValueCommitted: value => root.save("mfact", value)
    }

    UiText {
        Layout.fillWidth: true
        text: "Windows in the master area: " + Math.round(countSlider.liveValue)
        color: Theme.text
    }

    PanelSlider {
        id: countSlider

        Layout.fillWidth: true
        minimum: 0
        maximum: 20
        step: 1
        value: root.masterCount
        enabled: root.editable
        onValueCommitted: value => root.save("nmaster", value)
    }

    UiText {
        Layout.fillWidth: true
        text: "Gap between windows: " + Math.round(gapSlider.liveValue) + " px"
        color: Theme.text
    }

    PanelSlider {
        id: gapSlider

        Layout.fillWidth: true
        minimum: 0
        maximum: 64
        step: 1
        value: root.gap
        enabled: root.editable
        onValueCommitted: value => root.save("gap", value)
    }

    UiText {
        Layout.fillWidth: true
        visible: root.message.length > 0
        text: root.message
        color: Theme.danger
        wrapMode: Text.WordWrap
    }
}
