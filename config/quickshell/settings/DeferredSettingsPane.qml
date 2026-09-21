import QtQuick
import qs.core

Loader {
    id: root

    required property bool selected
    required property bool windowVisible
    property bool dataLoading: false
    // A read that never finishes must not hide a pane for good: after this long
    // the pane is presented with whatever it has. Long enough not to cut short
    // a normal first read, short enough that a hung helper is not a dead end.
    property int loadingTimeoutMs: 5000
    property bool visited: false
    property bool presented: false

    // Keep visited items alive to preserve drafts and scroll positions. Reserve
    // the whole pane while its initial asynchronous snapshot and layout settle.
    active: visited
    asynchronous: true
    visible: selected
    focus: true

    function updatePresentation() {
        if (!windowVisible || !selected) return;
        visited = true;
        if (!presented && status === Loader.Ready) {
            if (!dataLoading) presentationTimer.restart();
            else if (!loadingCap.running) loadingCap.start();
        }
    }
    onPresentedChanged: if (presented) loadingCap.stop()
    onSelectedChanged: updatePresentation()
    onWindowVisibleChanged: updatePresentation()
    onDataLoadingChanged: updatePresentation()
    onStatusChanged: updatePresentation()
    Component.onCompleted: updatePresentation()

    // Opacity keeps the loaded layout participating in polish while hiding
    // intermediate geometry. Later refreshes never hide usable controls.
    Binding {
        target: root.item
        property: "opacity"
        value: root.presented ? 1 : 0
        when: root.item !== null
    }
    Binding {
        target: root.item
        property: "enabled"
        value: root.presented
        when: root.item !== null
    }
    Timer {
        id: loadingCap
        interval: root.loadingTimeoutMs
        onTriggered: {
            if (root.windowVisible && root.selected && root.status === Loader.Ready)
                root.presented = true;
        }
    }
    Timer {
        id: presentationTimer
        interval: 0
        onTriggered: {
            if (root.windowVisible && root.selected && root.status === Loader.Ready
                    && !root.dataLoading)
                root.presented = true;
        }
    }
    UiText {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - Theme.spacingXl * 2)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: !root.presented
        text: root.status === Loader.Error ? "This settings panel could not be loaded."
            : "Loading settings..."
        color: Theme.menuMutedText
    }
}
