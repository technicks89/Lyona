import QtQuick
import Quickshell
import qs.core

PopupWindow {
    id: root

    default property alias popupContent: popupHost.data
    required property var targetWindow
    property int popupX: 0
    property int popupY: Theme.panelHeight
    property int popupWidth: 320
    property int popupHeight: 320
    // Whether the owner wants the popup shown. Owners set this, not visible:
    // the popup can also close on its own (below), and only this tells the two
    // apart.
    property bool open: false

    signal dismissed

    // With a compositor, the popup is a transparent surface over the whole
    // screen below the panel, and a click anywhere outside the menu lands on
    // it and closes the menu. Without one, X draws that surface black (#384),
    // so the window is the menu alone. A click outside it then reaches another
    // window or the desktop, which takes the keyboard from the popup (dwm sees
    // to that for the desktop and the selected window too), and a popup that
    // loses the keyboard closes (below). Compositor.running follows Picom
    // starting and stopping, also while a menu is open.
    readonly property bool clickAwaySurface: Compositor.running

    // Keep the transparent click-away surface below the panel so compositors
    // cannot blur the bar through this popup. Content coordinates stay panel-relative.
    readonly property int panelOffset: targetWindow ? targetWindow.height : 0
    readonly property int areaWidth: targetWindow ? targetWindow.width : 0
    readonly property int areaHeight: targetWindow && targetWindow.screen
        ? Math.max(0, targetWindow.screen.height - panelOffset) : 0
    // The menu's place in the area below the panel.
    readonly property int menuWidth: Math.min(root.popupWidth, root.areaWidth)
    readonly property int menuHeight: Math.min(root.popupHeight, root.areaHeight)
    readonly property int menuX: Math.max(0, Math.min(root.popupX, root.areaWidth - root.menuWidth))
    readonly property int menuY: Math.max(0, Math.min(root.popupY - root.panelOffset, root.areaHeight - root.menuHeight))

    // Whether the popup takes the keyboard while shown: owners turn it off to
    // let the keyboard go (the overview's closing fade, the network popup's
    // password prompt). The popup asks for the keyboard itself (below), not
    // through Quickshell's grabFocus: that makes it a Qt::Popup, and Qt 6
    // closes every popup at once when its own activation of one and the X
    // FocusIn for it arrive in the other order, which a busy machine made
    // happen: a menu vanished as it opened (#397).
    property bool wantsKeyboard: true

    visible: open
    color: Theme.transparent
    grabFocus: false
    implicitWidth: clickAwaySurface ? areaWidth : menuWidth
    implicitHeight: clickAwaySurface ? areaHeight : menuHeight

    anchor {
        window: targetWindow
        rect.x: root.clickAwaySurface ? 0 : root.menuX
        rect.y: root.panelOffset + (root.clickAwaySurface ? 0 : root.menuY)
    }

    // On X11 a popup is override-redirect, so the window manager never focuses
    // it by itself: with any window open, Escape and
    // the arrow keys went to that window (#280 VM). Activating asks dwm for the
    // focus (_NET_ACTIVE_WINDOW), which it gives an override-redirect window
    // and hands back to the selected client when the popup closes.
    function requestKeyboard() {
        const popupWindow = popupHost.Window.window;
        if (root.visible && root.wantsKeyboard && popupWindow)
            popupWindow.requestActivate();
    }

    // Losing the keyboard while shown is a click away (#384): on another
    // window or the desktop, which dwm then focuses. Not while the popup has
    // let the keyboard go itself (wantsKeyboard false). Checked once the focus
    // change has settled, not inside it: closing changes what it depends on.
    readonly property bool hasKeyboard: popupHost.Window.active
    function dismissWithoutKeyboard() {
        if (!root.hasKeyboard && root.open && root.visible && root.wantsKeyboard)
            root.dismissed();
    }
    onHasKeyboardChanged: if (!hasKeyboard) Qt.callLater(root.dismissWithoutKeyboard)

    // Hidden while the owner still wants it shown (the window went away): the
    // owner is told, so its state closes too and the next open is one click.
    onVisibleChanged: {
        if (visible)
            Qt.callLater(root.requestKeyboard);
        else if (root.open)
            root.dismissed();
    }
    onWantsKeyboardChanged: if (wantsKeyboard && visible) Qt.callLater(root.requestKeyboard)

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Flickable {
        id: viewport
        objectName: "popupViewport"

        x: root.clickAwaySurface ? root.menuX : 0
        y: root.clickAwaySurface ? root.menuY : 0
        width: root.menuWidth
        height: root.menuHeight
        contentWidth: root.popupWidth
        contentHeight: root.popupHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        z: 1
        onVisibleChanged: if (visible) { contentX = 0; contentY = 0; }

        Item {
            id: popupHost

            width: root.popupWidth
            height: root.popupHeight
            opacity: 1.0

            MouseArea {
                anchors.fill: parent
            }
        }
    }
}
