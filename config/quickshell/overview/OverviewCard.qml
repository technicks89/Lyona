import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

// One window's card in the overview popup (Sync Sprint 7 S7-03): icon,
// title, and a monitor label. Mirrors RunningAppItem.qml's own icon/click shape,
// just laid out as a row instead of a panel pill. When the model can capture
// previews (Sprint 9 S9-01: only with a compositor running, see
// docs/evidence/s9-01-thumbnail-spike.md) the card is taller and starts with a
// preview of the window, showing its icon until the capture arrives. `selected` (Sync Sprint 8 S8-01) is the
// keyboard-navigated card, styled the same way LauncherResultDelegate.qml's own
// `selected` state already is -- a distinct fill/border from mouse hover, since
// the two can disagree (arrow keys move `selected` without the mouse moving).
//
// Sprint 9: every colour is a Theme token (text roles included, so light
// palettes stay readable), state changes ease with Theme.animationFast (0 under
// reduced motion, an instant change rather than a skipped one), and the card is
// an accessible list item that a screen reader can tell apart from another
// window of the same app.
Rectangle {
    id: root

    required property var window
    required property bool selected
    // How many monitors there are (the label only matters above one), and the tag
    // this card is grouped under, for the accessible description.
    property int monitorCount: 1
    property string tagLabel: ""
    // Preview of the window (Sprint 9 S9-01). `thumbnailsEnabled` is whether previews
    // can be captured at all; `thumbnailSource` is the captured image, or "" until it
    // arrives (or when this window could not be captured).
    property bool thumbnailsEnabled: false
    property string thumbnailSource: ""
    readonly property string windowLabel: root.window.title.length > 0 ? root.window.title : root.window.appClass
    readonly property bool hovered: cardMouse.containsMouse || closeMouse.containsMouse
    signal focusRequested(string windowId)
    signal closeRequested(string windowId)

    objectName: "overviewCard"
    Layout.fillWidth: true
    Layout.preferredHeight: root.thumbnailsEnabled ? Theme.dp(64) : Theme.dp(48)
    radius: Theme.controlRadius
    color: root.selected ? Theme.menuSelectedBackground
        : root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.selected ? Theme.controlSelectedBorder
        : root.hovered ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth

    Behavior on color { ColorAnimation { duration: Theme.animationFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animationFast } }

    Accessible.role: Accessible.ListItem
    Accessible.name: root.windowLabel
    Accessible.description: "Tag " + root.tagLabel + ", " + root.window.appClass
        + (root.monitorCount > 1 ? ", monitor " + (root.window.monitorIndex + 1) : "")
    Accessible.selectable: true
    Accessible.selected: root.selected
    Accessible.onPressAction: root.focusRequested(root.window.windowId)

    MouseArea {
        id: cardMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusRequested(root.window.windowId)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.rowSpacing
        anchors.rightMargin: Theme.rowSpacing
        spacing: Theme.rowSpacing

        // The window's icon, or with previews on a frame holding its preview. The
        // preview is decoration: the card already carries the name and description.
        Item {
            Layout.preferredWidth: root.thumbnailsEnabled ? Theme.dp(88) : Theme.trayIconSize
            Layout.preferredHeight: root.thumbnailsEnabled ? Theme.dp(52) : Theme.trayIconSize

            Rectangle {
                objectName: "overviewPreviewFrame"
                anchors.fill: parent
                visible: root.thumbnailsEnabled
                radius: Theme.controlRadius
                color: Theme.surface
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
            }

            Image {
                id: preview

                objectName: "overviewPreview"
                anchors.fill: parent
                anchors.margins: Theme.controlBorderWidth
                visible: root.thumbnailsEnabled && status === Image.Ready
                source: root.thumbnailsEnabled ? root.thumbnailSource : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // The file is replaced by the next capture and deleted when the overview
                // closes, so the image must not outlive it in Qt's cache.
                cache: false
                Accessible.ignored: true
            }

            IconImage {
                anchors.centerIn: parent
                width: Theme.trayIconSize
                height: Theme.trayIconSize
                visible: !preview.visible
                source: Icons.launcherIcon(root.window.appClass)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.windowLabel
                color: root.selected ? Theme.menuSelectedText
                    : root.hovered ? Theme.controlHoverText : Theme.controlNormalText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                elide: Text.ElideRight
            }

            // With previews the icon is no longer beside the title, so name the app.
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.thumbnailsEnabled
                text: root.window.appClass
                color: Theme.menuMutedText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontCaptionSize
                elide: Text.ElideRight
            }
        }

        Text {
            textFormat: Text.PlainText
            objectName: "overviewMonitorLabel"
            visible: root.monitorCount > 1
            text: "Mon " + (root.window.monitorIndex + 1)
            color: Theme.menuMutedText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
        }

        // Shown on hover and on the keyboard-selected card, so the selected card's
        // Ctrl+W (WindowOverview.qml) has a visible counterpart. Ignored by
        // keyboard focus on purpose: the shortcut is the keyboard path.
        Rectangle {
            id: closeButton

            objectName: "overviewCloseButton"
            visible: root.hovered || root.selected
            Layout.preferredWidth: Theme.dp(24)
            Layout.preferredHeight: Theme.dp(24)
            radius: Theme.controlRadius
            color: closeMouse.containsMouse ? Theme.danger : Theme.transparent
            Behavior on color { ColorAnimation { duration: Theme.animationFast } }
            Accessible.role: Accessible.Button
            Accessible.name: "Close " + root.windowLabel
            Accessible.onPressAction: root.closeRequested(root.window.windowId)

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "×"
                color: closeMouse.containsMouse ? Theme.readableText(Theme.textStrong, Theme.danger) : Theme.menuMutedText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySize
                font.bold: true
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested(root.window.windowId)
            }
        }
    }
}
