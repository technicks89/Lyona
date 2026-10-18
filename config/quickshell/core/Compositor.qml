pragma Singleton

import QtQuick
import Quickshell
import qs.core

/*
 * Whether a compositor runs on this display (#384). Only a compositor shows a
 * transparent window as see-through: without one, X draws it black. So
 * ClickAwayPopup covers the screen with its transparent click-away surface
 * only while `running` is true, and otherwise sizes each popup to its menu.
 *
 * dwm-window-thumb watch-compositor reports the _NET_WM_CM_S<screen> owner now
 * and on every change (XFixes selection events, no polling), so Picom starting
 * or stopping while a menu is open moves it to the other way at once. One
 * resident helper, blocked on the X connection, for the whole shell.
 *
 * Unknown counts as no compositor: before the first report, with the helper
 * missing, or after it ended. A popup sized to its menu looks right with or
 * without one; it only lets the click that closes it reach the window under it.
 */
Singleton {
    id: root

    property bool running: false

    WatchedProcess {
        id: compositorWatch

        command: Commands.watchCommand(["dwm-window-thumb", "watch-compositor"])
        active: true
        onLine: data => {
            if (data === "compositor 1")
                root.running = true;
            else if (data === "compositor 0")
                root.running = false;
        }
        onEnded: root.running = false
    }

    Component.onCompleted: compositorWatch.start()
}
