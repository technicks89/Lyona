import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// Join a hidden Wi-Fi network (#471, upstream dwm-titus #379): its name, its
// security and the password, sent to dwm-quickshell-network
// wifi-connect-hidden (the password on stdin). A window of its own, as the
// password prompt is, so the keyboard reaches it. A failure keeps it open,
// with the name kept and the reason shown.
FloatingWindow {
    id: root

    required property var networkModel
    property bool revealPassword: false

    readonly property var securityChoices: [
        { "id": "wpa-psk", "label": "WPA/WPA2" },
        { "id": "sae", "label": "WPA3" },
        { "id": "open", "label": "Open" }
    ]
    readonly property string problem: root.networkModel.hiddenJoinProblem()

    title: "dwm hidden network"
    visible: root.networkModel.hiddenPromptVisible
    implicitWidth: Math.min(Theme.dp(460), screen ? screen.width : Theme.dp(460))
    implicitHeight: Math.min(Math.max(Theme.dp(300), column.implicitHeight + Theme.sectionSpacing * 2),
        screen ? screen.height : Theme.dp(300))
    color: Theme.transparent

    onClosed: root.networkModel.cancelHiddenPrompt()
    onVisibleChanged: {
        if (!visible) return;
        root.revealPassword = false;
        Qt.callLater(function() { ssidField.input.forceActiveFocus(); });
    }

    Rectangle {
        anchors.fill: parent
        focus: true
        color: Theme.popupBackground
        border.color: Theme.popupBorder
        border.width: Theme.controlBorderWidth
        radius: Theme.radius

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape && !root.networkModel.busy) {
                root.networkModel.cancelHiddenPrompt();
                event.accepted = true;
            }
        }

        Flickable {
            id: viewport
            anchors.fill: parent
            anchors.margins: Theme.sectionSpacing
            contentWidth: Math.max(width, Theme.dp(460) - Theme.sectionSpacing * 2)
            contentHeight: Math.max(height, column.implicitHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.AutoFlickIfNeeded

            ColumnLayout {
                id: column

                width: viewport.contentWidth
                height: viewport.contentHeight
                spacing: Theme.popupSpacing

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "Join a hidden network"
                    color: Theme.textStrong
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                }

                component Field: Rectangle {
                    id: field

                    property alias input: fieldInput
                    property string placeholder: ""

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Theme.dp(44), Theme.inputFontSize + Theme.dp(20))
                    color: Theme.controlNormalFill
                    border.color: fieldInput.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                    border.width: fieldInput.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                    radius: Theme.radius

                    TextInput {
                        id: fieldInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.rowSpacing
                        anchors.rightMargin: Theme.rowSpacing
                        color: Theme.textStrong
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        enabled: !root.networkModel.busy
                        activeFocusOnTab: true
                        onAccepted: root.networkModel.joinHidden()
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.rowSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        visible: fieldInput.text.length === 0
                        text: field.placeholder
                        color: Theme.placeholder
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                    }
                }

                Field {
                    id: ssidField
                    objectName: "hiddenSsidField"
                    placeholder: "Network name"
                    input.text: root.networkModel.hiddenSsid
                    input.onTextChanged: root.networkModel.hiddenSsid = input.text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.rowSpacing

                    Repeater {
                        model: root.securityChoices

                        delegate: ShellButton {
                            id: choice

                            required property var modelData

                            Layout.fillWidth: true
                            label: choice.modelData.label
                            primary: root.networkModel.hiddenSecurity === choice.modelData.id
                            enabled: !root.networkModel.busy
                            onActivated: root.networkModel.hiddenSecurity = choice.modelData.id
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Theme.dp(44), Theme.inputFontSize + Theme.dp(20))
                    spacing: Theme.rowSpacing
                    visible: root.networkModel.hiddenSecurity !== "open"

                    Field {
                        id: passwordField
                        objectName: "hiddenPasswordField"
                        Layout.fillHeight: true
                        placeholder: "Password"
                        input.text: root.networkModel.hiddenPassword
                        input.echoMode: root.revealPassword ? TextInput.Normal : TextInput.Password
                        input.onTextChanged: root.networkModel.hiddenPassword = input.text
                    }

                    ShellButton {
                        Layout.preferredWidth: Math.max(Theme.dp(62), implicitWidth)
                        Layout.fillHeight: true
                        label: root.revealPassword ? "Hide" : "Show"
                        enabled: !root.networkModel.busy
                        onActivated: {
                            root.revealPassword = !root.revealPassword;
                            passwordField.input.forceActiveFocus();
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    objectName: "hiddenMessage"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.networkModel.hiddenMessage
                    color: root.networkModel.busy ? Theme.textMuted : Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.rowSpacing

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.networkModel.busy ? "" : root.problem
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                        elide: Text.ElideRight
                    }

                    ShellButton {
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: Theme.buttonHeight
                        label: "Cancel"
                        enabled: !root.networkModel.busy
                        onActivated: root.networkModel.cancelHiddenPrompt()
                    }

                    ShellButton {
                        objectName: "hiddenJoinButton"
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: Theme.buttonHeight
                        label: "Join"
                        enabled: !root.networkModel.busy && root.problem.length === 0
                        onActivated: root.networkModel.joinHidden()
                    }
                }
            }
        }
    }
}
