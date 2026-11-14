import QtQuick
import qs.core

// A one-line title that, when it does not fit, scrolls across once after each
// change and then rests at its start, elided (#499, upstream dwm-titus #393):
// the end of a long window title is often the part that tells windows apart.
// One bounded animation per change, and nothing runs while it rests. With
// reduced motion it never moves.
Item {
    id: root

    property alias text: label.text
    property alias color: label.color
    // How far the text is wider than the space it has.
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    readonly property bool scrolling: scroll.running
    readonly property real textX: label.x

    // Pixels per second, and the pauses before and after the scroll.
    property real speed: 40
    property int startPause: 1000
    property int endPause: 1500
    // A very long title still scrolls in bounded time.
    property int maxScrollDuration: 8000

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    clip: true

    function rest() {
        scroll.stop();
        label.x = 0;
    }

    function scrollOnce() {
        root.rest();
        if (Theme.reducedMotion || root.overflow <= 0 || !root.visible) {
            return;
        }
        scroll.start();
    }

    UiText {
        id: label

        height: root.height
        // Full length while it scrolls; elided to the space it has at rest.
        width: scroll.running ? implicitWidth : root.width
        elide: scroll.running ? Text.ElideNone : Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        // After the layout has given the new title its width.
        onTextChanged: Qt.callLater(root.scrollOnce)
    }

    SequentialAnimation {
        id: scroll

        PauseAnimation {
            duration: root.startPause
        }
        NumberAnimation {
            target: label
            property: "x"
            to: -root.overflow
            duration: Math.min(root.maxScrollDuration, Math.max(500, root.overflow / root.speed * 1000))
            easing.type: Easing.Linear
        }
        PauseAnimation {
            duration: root.endPause
        }
        ScriptAction {
            script: label.x = 0
        }
    }

    // Reduced motion turned on mid-scroll stops it at once.
    Connections {
        target: Theme

        function onReducedMotionChanged() {
            if (Theme.reducedMotion) {
                root.rest();
            }
        }
    }
}
