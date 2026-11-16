import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// Clipboard history (#469, upstream dwm-titus #389): Super+V. Search, copy an
// entry back, delete one or all, and the two opt-ins: capture, then saving to
// disk. Entries are text from other programs, shown as plain text.
FloatingWindow {
    id: root

    required property var clipboardModel

    title: "dwm clipboard"
    visible: clipboardModel.visible
    property bool confirmClear: false
    screen: clipboardModel.targetScreen
    implicitWidth: 720
    implicitHeight: 600
    color: Theme.transparent

    function focusSearch() {
        clipboardSearch.forceActiveFocus();
        clipboardSearch.cursorPosition = clipboardSearch.text.length;
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(root.focusSearch);
        } else {
            root.confirmClear = false;
        }
    }

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.clipboardModel.timeTick++
    }

    ShellSurface {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.clipboardModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            LargeSurfaceHeader {
                Layout.fillWidth: true
                eyebrow: "Clipboard"
                title: "Clipboard History"
                subtitle: "Type to filter / Enter to copy / Esc to close"
                status: root.clipboardModel.status
                statusColor: Theme.accent
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.largeSurfaceSearchHeight
                color: clipboardSearch.activeFocus ? Theme.controlFocusFill : Theme.controlNormalFill
                border.color: clipboardSearch.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                border.width: clipboardSearch.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                radius: Theme.largeSurfaceCardRadius

                UiText {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "/"
                    color: clipboardSearch.activeFocus ? Theme.menuActionText : Theme.menuMutedText
                    font.bold: true
                }

                TextInput {
                    id: clipboardSearch

                    // The window's focus item from the start: dwm's hold_keys
                    // hands over keys typed after Super+V as soon as it
                    // focuses the window (#391).
                    focus: true
                    anchors.fill: parent
                    anchors.leftMargin: 38
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.controlFocusText
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    text: root.clipboardModel.query
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    clip: true

                    onTextChanged: root.clipboardModel.setQuery(text)

                    Keys.onPressed: function(event) {
                        const ctrl = event.modifiers & Qt.ControlModifier;

                        if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                            root.clipboardModel.selectRelative(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                            root.clipboardModel.selectRelative(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageDown) {
                            root.clipboardModel.selectRelative(8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            root.clipboardModel.selectRelative(-8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            root.clipboardModel.selectAbsolute(0);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            root.clipboardModel.selectAbsolute(root.clipboardModel.filteredEntries.length - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.clipboardModel.copySelected();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_D && ctrl) {
                            root.clipboardModel.deleteAt(root.clipboardModel.selectedIndex);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape || (event.key === Qt.Key_C && ctrl)) {
                            root.clipboardModel.close();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.verticalCenter: parent.verticalCenter
                    visible: clipboardSearch.text.length === 0
                    text: "Search clipboard entries"
                    color: Theme.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                }
            }

            RowLayout {
                Layout.fillWidth: true

                SectionLabel {
                    label: "Entries"
                }

                UiText {
                    text: root.clipboardModel.filteredEntries.length + " shown"
                    color: Theme.menuMutedText
                    font.pixelSize: Theme.fontCaptionSize
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                }

                UiText {
                    text: "Capture"
                    color: root.clipboardModel.captureEnabled ? Theme.menuText : Theme.menuMutedText
                    font.pixelSize: Theme.smallFontSize
                }

                PanelToggleSwitch {
                    objectName: "clipboardCaptureSwitch"
                    checked: root.clipboardModel.capturing
                    busy: root.clipboardModel.busy
                    enabled: root.clipboardModel.settingsKnown && root.clipboardModel.settingsAvailable
                    accessibleName: "Capture clipboard history"
                    accessibleDescription: "Keeps copied text in this list, except from identifiable password managers and marked copies"
                    onToggled: root.clipboardModel.toggleCapture()
                }

                UiText {
                    text: "Save"
                    color: root.clipboardModel.persistEnabled ? Theme.menuText : Theme.menuMutedText
                    font.pixelSize: Theme.smallFontSize
                }

                PanelToggleSwitch {
                    objectName: "clipboardPersistSwitch"
                    checked: root.clipboardModel.persistEnabled
                    busy: root.clipboardModel.busy
                    enabled: root.clipboardModel.captureEnabled
                    accessibleName: "Save clipboard history across restarts"
                    accessibleDescription: "Writes the list to a private file; off removes the file"
                    onToggled: root.clipboardModel.setPersist(!root.clipboardModel.persistEnabled)
                }

                ShellButton {
                    // Asked twice, like deleting a finger (#529).
                    label: root.confirmClear ? "Confirm Clear" : "Clear all"
                    danger: true
                    enabled: root.clipboardModel.entries.length > 0 || root.clipboardModel.persistEnabled
                    accessibleDescription: "Delete every entry, and the saved history"
                    onActivated: {
                        if (root.confirmClear) {
                            root.confirmClear = false;
                            root.clipboardModel.clearAll();
                        } else {
                            root.confirmClear = true;
                        }
                    }
                }
            }

            UiText {
                Layout.fillWidth: true
                text: "Capture is off until you turn it on. Copies from browsers and terminals are kept; copies from identifiable password managers, and copies an application marks as secret, are not. A password copied by a browser extension, or from a terminal, can still be kept. Saving to disk is a separate choice; turning it off deletes the file, and so does turning capture off."
                wrapMode: Text.WordWrap
                color: Theme.menuMutedText
                font.pixelSize: Theme.smallFontSize
            }

            UiText {
                Layout.fillWidth: true
                visible: root.clipboardModel.message.length > 0
                text: root.clipboardModel.message
                wrapMode: Text.WordWrap
                color: Theme.danger
                font.pixelSize: Theme.smallFontSize
            }

            UiText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: root.clipboardModel.filteredEntries.length === 0
                text: !root.clipboardModel.captureEnabled ? "Turn capture on to keep what you copy"
                    : root.clipboardModel.entries.length === 0
                    ? "Nothing copied yet: copy some text and it appears here"
                    : "No entries match your search"
                color: Theme.menuMutedText
            }

            ListView {
                id: clipboardResults

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                // Only while shown: a hidden list rebuilt its rows at every copy
                // (#529).
                model: root.visible ? root.clipboardModel.filteredEntries : []

                onModelChanged: {
                    if (root.clipboardModel.filteredEntries.length > 0) {
                        positionViewAtIndex(root.clipboardModel.selectedIndex, ListView.Contain);
                    }
                }

                Connections {
                    target: root.clipboardModel

                    function onSelectedIndexChanged() {
                        if (root.clipboardModel.filteredEntries.length > 0) {
                            clipboardResults.positionViewAtIndex(root.clipboardModel.selectedIndex, ListView.Contain);
                        }
                    }
                }

                delegate: ClipboardEntryRow {
                    width: clipboardResults.width
                    selected: index === root.clipboardModel.selectedIndex
                    clipboardModel: root.clipboardModel
                    timeTick: root.clipboardModel.timeTick
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "Enter copy  |  Ctrl+D delete  |  Esc close"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
