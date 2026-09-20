import QtQuick
import qs.core

Loader {
    id: root

    required property bool selected
    required property bool windowVisible
    property bool visited: false

    // Keep visited items alive: switching sections must preserve local drafts,
    // scroll positions and bindings to the independently owned operation models.
    active: visited
    asynchronous: true
    visible: selected
    focus: true

    // #315: reserve the pane's space while it loads, so the first visit
    // fades in instead of popping in and reflowing the window.
    Rectangle {
        anchors.fill: parent
        visible: root.selected && root.status !== Loader.Ready
        color: "transparent"
        Text {
            anchors.centerIn: parent
            text: "Loading…"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
        }
    }
    onLoaded: if (item) { item.opacity = 0; fadeIn.target = item; fadeIn.start(); }
    NumberAnimation { id: fadeIn; property: "opacity"; to: 1; duration: Theme.reducedMotion ? 0 : 120 }

    function loadIfSelected() {
        if (windowVisible && selected) visited = true;
    }
    onSelectedChanged: loadIfSelected()
    onWindowVisibleChanged: loadIfSelected()
    Component.onCompleted: loadIfSelected()
}
