import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    required property var model
    property real activeOpacity: 100
    property real inactiveOpacity: 100
    property real cornerRadius: 0
    property bool changed: false
    property bool radiusChanged: false
    property string editRevision: ""
    property string radiusRevision: ""
    property string submittedEdit: ""
    property string submittedRevision: ""
    Layout.fillWidth: true
    spacing: Theme.spacingXl

    function synchronize() {
        if (!root.model.snapshot.radius_editable) {
            radiusDelay.stop();
            root.radiusChanged = false;
        }
        if (!root.model.snapshot.editable) {
            keyboardDelay.stop();
            radiusDelay.stop();
            root.changed = false;
            root.radiusChanged = false;
        } else if (foreground.pressed || background.pressed || corners.pressed
                || root.changed || root.radiusChanged) return;
        root.activeOpacity = root.model.snapshot.active;
        root.inactiveOpacity = root.model.snapshot.inactive;
        root.cornerRadius = root.model.snapshot.corner_radius || 0;
    }

    function applyOpacity() {
        keyboardDelay.stop();
        if (!root.changed) return;
        if (!root.model.snapshot.editable) {
            root.synchronize();
            return;
        }
        if (root.model.busy) return;
        root.changed = false;
        root.submittedEdit = "opacity";
        root.submittedRevision = root.editRevision;
        root.model.setOpacity(root.activeOpacity, root.inactiveOpacity, root.editRevision);
    }

    function applyCornerRadius() {
        radiusDelay.stop();
        if (!root.radiusChanged) return;
        if (!root.model.snapshot.radius_editable) {
            root.synchronize();
            return;
        }
        if (root.model.busy) return;
        root.radiusChanged = false;
        root.submittedEdit = "radius";
        root.submittedRevision = root.radiusRevision;
        root.model.setCornerRadius(root.cornerRadius, root.radiusRevision);
    }

    Component.onCompleted: root.synchronize()
    Connections {
        target: root.model
        function onSnapshotChanged() { root.synchronize(); }
        function onBusyChanged() {
            if (!root.model.busy) {
                // Only our successful save advances the other edit's base.
                // An edit already based on an older snapshot must stay stale.
                if (!root.model.actionFailure) {
                    if (root.submittedEdit === "opacity" && root.radiusChanged
                            && root.radiusRevision === root.submittedRevision)
                        root.radiusRevision = root.model.snapshot.revision;
                    else if (root.submittedEdit === "radius" && root.changed
                            && root.editRevision === root.submittedRevision)
                        root.editRevision = root.model.snapshot.revision;
                }
                root.submittedEdit = "";
                if (root.changed) keyboardDelay.restart();
                else if (root.radiusChanged) radiusDelay.restart();
                else root.synchronize();
            }
        }
    }

    SectionLabel { label: "Compositor" }
    UiText {
        Layout.fillWidth: true
        text: root.model.snapshot.detail
        color: Theme.menuMutedText
        wrapMode: Text.WordWrap
    }
    UiText {
        Layout.fillWidth: true
        text: root.model.snapshot.path
        color: Theme.menuMutedText
        wrapMode: Text.WrapAnywhere
    }
    UiText {
        text: "Foreground (active): " + Math.round(root.activeOpacity) + "%"
        color: Theme.menuText
    }
    Controls.Slider {
        id: foreground
        objectName: "picomActiveOpacity"
        Accessible.name: "Foreground window opacity"
        palette.highlight: Theme.accent
        palette.button: Theme.controlNormalFill
        Layout.fillWidth: true
        from: 0; to: 100; stepSize: 1
        value: root.activeOpacity
        enabled: root.model.editable
        onMoved: {
            if (!root.changed) root.editRevision = root.model.snapshot.revision;
            root.activeOpacity = value;
            root.changed = true;
            if (!pressed) keyboardDelay.restart();
        }
        onPressedChanged: { if (!pressed) root.applyOpacity(); }
    }
    UiText {
        text: "Background (inactive): " + Math.round(root.inactiveOpacity) + "%"
        color: Theme.menuText
    }
    Controls.Slider {
        id: background
        objectName: "picomInactiveOpacity"
        Accessible.name: "Background window opacity"
        palette.highlight: Theme.accent
        palette.button: Theme.controlNormalFill
        Layout.fillWidth: true
        from: 0; to: 100; stepSize: 1
        value: root.inactiveOpacity
        enabled: root.model.editable
        onMoved: {
            if (!root.changed) root.editRevision = root.model.snapshot.revision;
            root.inactiveOpacity = value;
            root.changed = true;
            if (!pressed) keyboardDelay.restart();
        }
        onPressedChanged: { if (!pressed) root.applyOpacity(); }
    }
    UiText {
        text: "Window corner radius: " + Math.round(root.cornerRadius) + " px"
        color: Theme.menuText
    }
    Controls.Slider {
        id: corners
        objectName: "picomCornerRadius"
        Accessible.name: "Window corner radius"
        palette.highlight: Theme.accent
        palette.button: Theme.controlNormalFill
        Layout.fillWidth: true
        from: 0; to: 32; stepSize: 1
        value: root.cornerRadius
        enabled: root.model.snapshot.radius_editable && !root.model.busy
        onMoved: {
            if (!root.radiusChanged) root.radiusRevision = root.model.snapshot.revision;
            root.cornerRadius = value;
            root.radiusChanged = true;
            if (!pressed) radiusDelay.restart();
        }
        onPressedChanged: { if (!pressed) root.applyCornerRadius(); }
    }
    UiText {
        text: "Backend" + (root.model.snapshot.effective ? " (current: " + root.model.snapshot.effective + ")" : "")
        color: Theme.menuText
    }
    Controls.ComboBox {
        objectName: "picomBackend"
        Accessible.name: "Picom backend"
        implicitHeight: Theme.controlHeight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.inputFontSize
        palette.button: Theme.controlNormalFill
        palette.buttonText: Theme.controlNormalText
        palette.base: Theme.popupBackground
        palette.window: Theme.popupBackground
        palette.text: Theme.popupText
        palette.highlight: Theme.controlSelectedFill
        palette.highlightedText: Theme.controlSelectedText
        Layout.fillWidth: true
        model: ["Automatic", "XRender", "GLX", "EGL (experimental)"]
        currentIndex: ["auto", "xrender", "glx", "egl"].indexOf(root.model.snapshot.policy)
        enabled: root.model.editable && !root.model.snapshot.override
        onActivated: index => root.model.mutate("set-backend", [["auto", "xrender", "glx", "egl"][index]])
    }
    // #288: off by default. On, a full-screen game skips the compositor,
    // which is faster, but the overview cannot preview it and some GPUs
    // flicker when switching.
    RowLayout {
        Layout.fillWidth: true
        visible: root.model.snapshot.unredirect !== undefined

        UiText {
            Layout.fillWidth: true
            text: "Let full-screen windows bypass the compositor (faster games; no overview preview while full screen)"
            color: Theme.menuText
            wrapMode: Text.WordWrap
        }

        PanelToggleSwitch {
            objectName: "picomUnredirect"
            checked: root.model.snapshot.unredirect === true
            busy: root.model.busy
            enabled: root.model.editable
            accessibleName: "Full-screen windows bypass the compositor"
            accessibleDescription: "Faster full-screen games; the overview cannot preview a full-screen window while this is on"
            onToggled: root.model.setUnredirect(!checked)
        }
    }
    ShellButton {
        visible: root.model.snapshot.copyable
        enabled: !root.model.busy
        label: "Create user configuration"
        onActivated: root.model.mutate("copy-config", [])
    }
    UiText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.model.failure || root.model.message
        color: root.model.failure ? Theme.danger : Theme.menuMutedText
        wrapMode: Text.WordWrap
    }
    Timer {
        id: keyboardDelay
        interval: 250
        onTriggered: root.applyOpacity()
    }
    Timer {
        id: radiusDelay
        interval: 250
        onTriggered: root.applyCornerRadius()
    }
}
