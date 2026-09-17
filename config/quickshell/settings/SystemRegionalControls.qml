import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.core
import qs.systemmanagement

pragma ComponentBehavior: Bound

/*
 * Sync Phase 9 follow-up (docs/SYNC-P9-REGIONAL-MUTATION.md §5.3): the
 * visible timezone/locale/NTP surface for SystemManagementModel's regional
 * actions. Mirrors SystemUpdateControls.qml's shape exactly -- confirmation
 * itself is owned by the model (prepareRegional()/confirmRegional()/
 * discardRegional()), this component only renders `regionalPreview` and
 * forwards user intent, so a captured plan is never re-derived or
 * re-validated in two places.
 *
 * Two private SystemRegionalPreflightModel instances read the timezone/
 * locale choice catalogs (one per picker); SystemManagementModel owns a
 * third, separate instance for the preview read itself. The preflight
 * model's own doc comment is explicit that it serves "one request at a
 * time; a new request cancels whatever is in flight" -- three independent
 * concerns (two pickers plus one preview) need three independent instances,
 * not one juggling all of them.
 *
 * Sync Sprint 1 S1-04 (#267): the delegated-administration section
 * (accounts/password/printers/software-sources launch buttons) that used to
 * live here moved to its own SystemDelegateControls.qml, now that delegated
 * launches get a visible confirmation step instead of dispatching
 * immediately -- the same split SystemUpdateControls.qml/SystemRegionalControls.qml
 * already have between the update and regional confirmation surfaces.
 */
ColumnLayout {
    id: root

    required property var model
    signal revealRequested(var target)

    readonly property var preview: root.model.regionalPreview
    readonly property var ntpState: root.model.nativeStates["ntp-enabled"]
    readonly property var timezoneState: root.model.nativeStates["timezone"]
    readonly property var localeState: root.model.nativeStates["locale"]

    Layout.fillWidth: true
    spacing: Theme.spacingMd

    component PlainText: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    component ActionButton: ShellButton {
        id: actionButton
        onActiveFocusChanged: if (actionButton.activeFocus) root.revealRequested(actionButton);
    }

    // Copied from DisplaySettingsPane.qml's DisplayComboBox (:15-45)
    // verbatim -- a local inline component there too, not a shared one, so
    // this follows the existing precedent rather than promoting one file's
    // private component into qs.core unasked.
    component RegionalComboBox: Controls.ComboBox {
        id: comboBox

        required property string accessibleLabel

        implicitHeight: Theme.controlHeight
        activeFocusOnTab: enabled
        displayText: currentIndex >= 0 ? currentText : ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.inputFontSize
        palette.button: Theme.controlNormalFill
        palette.buttonText: Theme.controlNormalText
        palette.base: Theme.popupBackground
        palette.window: Theme.popupBackground
        palette.text: Theme.popupText
        palette.highlight: Theme.controlSelectedFill
        palette.highlightedText: Theme.controlSelectedText
        Accessible.name: accessibleLabel

        delegate: Controls.ItemDelegate {
            required property var modelData
            required property int index

            width: comboBox.width
            text: modelData
            font: comboBox.font
            highlighted: comboBox.highlightedIndex === index
            hoverEnabled: comboBox.hoverEnabled
        }
    }

    // result stays null only until the first request completes (success or
    // failure both set a non-null outcome) or after cancel() clears it on
    // deactivation -- "request once per active session, on becoming active"
    // is enough to refresh after Settings is closed and reopened without
    // retry-hammering a genuine failure. Match "Reload status" elsewhere in
    // this pane for trying again after one.
    SystemRegionalPreflightModel {
        id: timezoneChoicesModel
        active: root.model.settingsVisible
        function ensureRequested() {
            if (timezoneChoicesModel.active && timezoneChoicesModel.result === null)
                timezoneChoicesModel.requestChoices("timezone");
        }
        Component.onCompleted: Qt.callLater(timezoneChoicesModel.ensureRequested)
        onActiveChanged: Qt.callLater(timezoneChoicesModel.ensureRequested)
    }

    SystemRegionalPreflightModel {
        id: localeChoicesModel
        active: root.model.settingsVisible
        function ensureRequested() {
            if (localeChoicesModel.active && localeChoicesModel.result === null)
                localeChoicesModel.requestChoices("locale");
        }
        Component.onCompleted: Qt.callLater(localeChoicesModel.ensureRequested)
        onActiveChanged: Qt.callLater(localeChoicesModel.ensureRequested)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        UiText {
            text: "Timezone"
            color: Theme.menuMutedText
        }

        RegionalComboBox {
            id: timezoneSelector
            readonly property var choices: timezoneChoicesModel.result === null
                || timezoneChoicesModel.result.status !== "available"
                ? [] : timezoneChoicesModel.result.choices
            Layout.preferredWidth: 260
            accessibleLabel: "System timezone"
            enabled: root.timezoneState !== undefined && root.timezoneState.status === "available"
                && timezoneSelector.choices.length > 0
            model: timezoneSelector.choices
            currentIndex: root.timezoneState === undefined ? -1
                : timezoneSelector.choices.indexOf(root.timezoneState.value)
            onActivated: index => root.model.prepareRegional("timezone-set", timezoneSelector.choices[index])
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        UiText {
            text: "Locale"
            color: Theme.menuMutedText
        }

        RegionalComboBox {
            id: localeSelector
            readonly property var choices: localeChoicesModel.result === null
                || localeChoicesModel.result.status !== "available"
                ? [] : localeChoicesModel.result.choices
            Layout.preferredWidth: 260
            accessibleLabel: "System locale"
            enabled: root.localeState !== undefined && root.localeState.status === "available"
                && localeSelector.choices.length > 0
            model: localeSelector.choices
            currentIndex: root.localeState === undefined ? -1
                : localeSelector.choices.indexOf(root.localeState.value)
            onActivated: index => root.model.prepareRegional("locale-set", "LANG=" + localeSelector.choices[index])
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        UiText {
            text: "Network time synchronization"
            color: Theme.menuMutedText
        }

        PanelToggleSwitch {
            id: ntpToggle
            checked: root.ntpState !== undefined && root.ntpState.value === "yes"
            enabled: root.ntpState !== undefined && root.ntpState.status === "available"
            accessibleName: "Network time synchronization"
            onToggled: root.model.prepareRegional("ntp-set", ntpToggle.checked ? "disabled" : "enabled")
        }
    }

    PlainText {
        visible: text.length > 0
        text: root.model.regionalConfirmMessage
        color: Theme.warning
    }

    PlainText {
        visible: root.model.regionalPreviewPending
        text: "Reading current state..."
        color: Theme.menuMutedText
    }

    PlainText {
        visible: root.model.regionalPreviewError.length > 0
        text: root.model.regionalPreviewError
        color: Theme.danger
    }

    Rectangle {
        id: confirmationCard
        Layout.fillWidth: true
        implicitHeight: confirmationContent.implicitHeight + Theme.spacingLg * 2
        visible: root.preview !== null
        // Mirrors SystemUpdateControls.qml's own confirmationCard: the card
        // becoming visible is what must reveal it for a button that already
        // held focus (e.g. activated by keyboard without a focus change),
        // alongside (not instead of) the focus-based path above.
        onVisibleChanged: if (confirmationCard.visible) root.revealRequested(confirmationCard);
        color: Theme.controlNormalFill
        border.color: Theme.warning
        border.width: Theme.controlBorderWidth
        radius: Theme.controlRadius

        ColumnLayout {
            id: confirmationContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            PlainText {
                text: root.preview === null ? "" : "Confirm " + root.preview.detail
                font.bold: true
                color: Theme.controlNormalText
            }

            PlainText {
                text: root.preview === null ? "" : root.preview.current + " -> " + root.preview.target
                color: Theme.controlNormalText
            }

            PlainText {
                text: "This change is dispatched immediately once confirmed and cannot be cancelled mid-flight. "
                    + "If interrupted, reload status to recover the recorded operation."
                color: Theme.warning
            }

            RowLayout {
                ActionButton {
                    objectName: "declineRegional"
                    label: "Not now"
                    onActivated: root.model.discardRegional()
                }

                ActionButton {
                    objectName: "confirmRegional"
                    label: "Confirm"
                    danger: true
                    onActivated: root.model.confirmRegional()
                }
            }
        }
    }

}
