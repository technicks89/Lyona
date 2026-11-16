import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

// Settings > Appearance > Layout (#479): the layout, master area size, master
// window count and tile gap of the tag the selected monitor shows, and title
// bars on floating windows (#534). It only binds: LayoutSettingsModel, owned
// by SettingsModel, reads and writes (#530).
ColumnLayout {
    id: root

    required property var layoutModel
    readonly property var model: layoutModel

    // The monitor and tag shown when a slider drag began, "" with no drag.
    property string dragTarget: ""

    spacing: Theme.spacingMd

    // A slider's commit. A drag saves only when the view it began on is still
    // shown; the model queues it behind a write that is running.
    function commit(field, value) {
        const began = root.dragTarget;
        root.dragTarget = "";
        if (began.length > 0 && began !== root.model.target()) {
            root.model.message = "The shown tag changed during the drag; nothing was saved.";
            masterSlider.liveValue = root.model.shown("mfact");
            countSlider.liveValue = root.model.shown("nmaster");
            gapSlider.liveValue = root.model.shown("gap");
            return;
        }
        root.model.save(field, value);
    }

    UiText {
        Layout.fillWidth: true
        visible: !root.model.available
        text: root.model.reported
            ? "dwm has not published its layout settings yet. Log out and back in once after updating."
            : "Reading the layout settings..."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    UiText {
        Layout.fillWidth: true
        visible: root.model.available
        text: root.model.editable
            ? root.model.viewLabel + ". The layout applies now and is not saved; the master area and gap are saved for this tag only."
            : "Showing several tags: choose one tag to change its layout settings."
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Repeater {
            model: root.model.layoutChoices

            delegate: ShellButton {
                id: choice

                required property var modelData

                Layout.fillWidth: true
                label: choice.modelData.label
                primary: root.model.layoutIndex === choice.modelData.index
                enabled: root.model.available
                onActivated: root.model.setLayout(choice.modelData.index)
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
        minimum: root.model.limits.mfact.minimum
        maximum: root.model.limits.mfact.maximum
        step: 1
        value: root.model.shown("mfact")
        enabled: root.model.editable && root.model.layoutIndex !== 1
        onDraggingChanged: if (dragging) root.dragTarget = root.model.target()
        onValueCommitted: value => root.commit("mfact", value)
    }

    UiText {
        Layout.fillWidth: true
        text: "Windows in the master area: " + Math.round(countSlider.liveValue)
        color: Theme.text
    }

    PanelSlider {
        id: countSlider

        Layout.fillWidth: true
        minimum: root.model.limits.nmaster.minimum
        maximum: root.model.limits.nmaster.maximum
        step: 1
        value: root.model.shown("nmaster")
        enabled: root.model.editable
        onDraggingChanged: if (dragging) root.dragTarget = root.model.target()
        onValueCommitted: value => root.commit("nmaster", value)
    }

    UiText {
        Layout.fillWidth: true
        text: "Gap between windows: " + Math.round(gapSlider.liveValue) + " px"
        color: Theme.text
    }

    PanelSlider {
        id: gapSlider

        Layout.fillWidth: true
        minimum: root.model.limits.gap.minimum
        maximum: root.model.limits.gap.maximum
        step: 1
        value: root.model.shown("gap")
        enabled: root.model.editable
        onDraggingChanged: if (dragging) root.dragTarget = root.model.target()
        onValueCommitted: value => root.commit("gap", value)
    }

    ShellButton {
        label: "Reset to Default"
        accessibleDescription: "Sets this tag's master area size, window count and gap back to the defaults"
        enabled: root.model.editable
        onActivated: root.model.resetTag()
    }

    UiText {
        Layout.fillWidth: true
        visible: root.model.message.length > 0
        text: root.model.message
        color: Theme.danger
        wrapMode: Text.WordWrap
    }

    // Title bars on floating windows (#534): a strip to drag a floating window
    // by, with an x to close it, on the tags chosen.
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        UiText {
            Layout.fillWidth: true
            text: "Title bars on floating windows"
            color: Theme.text
        }

        PanelToggleSwitch {
            objectName: "titlebarsSwitch"
            checked: root.model.titlebarsEnabled
            busy: root.model.titlebarsBusy
            enabled: root.model.titlebarsKnown
            accessibleName: "Title bars on floating windows"
            accessibleDescription: "A strip above each floating window to move it, with a close button"
            onToggled: root.model.setTitlebars(!root.model.titlebarsEnabled, root.model.titlebarTags)
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: root.model.titlebarsEnabled
        text: "On tags:"
        color: Theme.textMuted
    }

    Flow {
        Layout.fillWidth: true
        visible: root.model.titlebarsEnabled
        spacing: Theme.spacingSm

        Repeater {
            model: 9

            delegate: ShellButton {
                id: tagChoice

                required property int index
                readonly property int tag: tagChoice.index + 1

                label: String(tagChoice.tag)
                primary: root.model.tagHasTitlebars(tagChoice.tag)
                accessibleDescription: "Title bars on tag " + tagChoice.tag
                    + (root.model.tagHasTitlebars(tagChoice.tag) ? ": on" : ": off")
                enabled: !root.model.titlebarsBusy
                onActivated: root.model.toggleTitlebarTag(tagChoice.tag)
            }
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: root.model.titlebarsMessage.length > 0
        text: root.model.titlebarsMessage
        color: Theme.danger
        wrapMode: Text.WordWrap
    }
}
