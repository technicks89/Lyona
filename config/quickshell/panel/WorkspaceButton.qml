import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property string label
    required property bool selected
    required property bool occupied
    signal clicked()

    Layout.preferredWidth: Theme.workspaceButtonSize
    Layout.preferredHeight: Theme.workspaceButtonSize
    radius: Theme.smallRadius
    // On the panel's keyboard path (#534): Enter or Space shows the tag.
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: "Tag " + root.label + (root.selected ? ", shown" : "")
        + (root.occupied ? ", has windows" : "")
    Accessible.onPressAction: root.clicked()
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        }
    }
    color: selected ? Theme.controlSelectedFill
        : activeFocus ? Theme.controlFocusFill
        : workspaceMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
    border.color: activeFocus ? Theme.controlFocusBorder
        : selected ? Theme.controlSelectedBorder
        : workspaceMouse.containsMouse ? Theme.controlHoverBorder : Theme.transparent
    border.width: activeFocus ? Math.max(Theme.pillBorderWidth, Theme.controlFocusBorderWidth)
        : selected || workspaceMouse.containsMouse ? Theme.pillBorderWidth : 0

    // The label's colour in each state, which the theme contrast check holds
    // to 4.5:1 on that state's surface; the occupied marker shares it.
    readonly property color foreground: root.selected ? Theme.controlSelectedText
        : root.activeFocus ? Theme.controlFocusText
        : workspaceMouse.containsMouse ? Theme.controlHoverText : Theme.textMuted

    // A tag with windows (#474, upstream dwm-titus #395): a small square in
    // the top-left corner, as stock dwm's bar draws it.
    Rectangle {
        objectName: "occupiedMarker"
        visible: root.occupied
        x: Theme.dp(3)
        y: Theme.dp(3)
        width: Theme.dp(4)
        height: width
        radius: Math.max(1, Theme.dp(1))
        color: root.foreground
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.label
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.panelFontSize
        font.bold: root.selected
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: workspaceMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
