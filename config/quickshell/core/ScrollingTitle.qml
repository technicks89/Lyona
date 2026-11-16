import QtQuick
import qs.core

// A one-line title that, when it does not fit, scrolls across once after each
// change and then rests at its start, elided (#499, upstream dwm-titus #393):
// the end of a long window title is often the part that tells windows apart.
// One bounded animation per change, and nothing runs while it rests. With
// reduced motion it never moves.
//
// Given the window it names (`key`), a new window always scrolls, but a title
// that changes in the same window scrolls at most once per sameKeyInterval
// (#532): a terminal or chat window whose long title keeps changing kept the
// panel animating. Without a key every change scrolls, as before.
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
    // The window the title is of ("" when not known), and how long a title
    // change in that window waits for its next scroll.
    property string key: ""
    property int sameKeyInterval: 30000
    // The window last seen, whether its title scrolled or not, and when a
    // title last scrolled: a switch to a window whose title fits and back
    // is still a new window.
    property string observedKey: ""
    property real lastScrollAt: 0

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    clip: true

    function rest() {
        scroll.stop();
        label.x = 0;
    }

    function scrollOnce() {
        root.rest();
        const sameWindow = root.key.length > 0 && root.key === root.observedKey;
        // Another window is not held to the last one's interval: one switched
        // to with a title that fits still scrolls its first that does not.
        if (!sameWindow) root.lastScrollAt = 0;
        root.observedKey = root.key;
        if (Theme.reducedMotion || root.overflow <= 0 || !root.visible) {
            return;
        }
        if (root.key.length > 0) {
            const now = Date.now();
            if (sameWindow && now - root.lastScrollAt < root.sameKeyInterval) return;
            root.lastScrollAt = now;
        }
        scroll.start();
    }

    // Another window with the same title scrolls too.
    onKeyChanged: Qt.callLater(root.scrollOnce)

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
