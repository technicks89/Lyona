import QtQuick
import Quickshell
import Quickshell.Io

/*
 * A long-lived helper process that emits a line whenever something it watches
 * changes, supervised so that it survives the helper exiting.
 *
 * Three models carried this as a Process plus two Timers, identical but for
 * the command, the visibility flag guarding the restart, and what the settle
 * timer called. The two timers matter and are easy to get subtly wrong:
 *
 *   settleTimer  coalesces a burst of change lines into one refresh, so a
 *                helper reporting ten events in a row costs one reload.
 *   restartTimer brings the watcher back if the helper dies while the surface
 *                is still open, without spinning when it dies immediately.
 *
 * Both are gated on `active`, so closing the surface stops the supervision
 * rather than leaving a timer to restart a process nobody is watching.
 */
Scope {
    id: root

    /* The helper to run. Changing it while active restarts the watch. */
    property var command: []

    /* Whether the watch should be running -- normally the surface's
     * visibility. Restarts only happen while this is true. */
    property bool active: false

    property int settleInterval: 250
    property int restartInterval: 3000

    readonly property bool running: watchProcess.running

    /* Emitted once the helper's output has been quiet for settleInterval. */
    signal settled

    function start() {
        if (!watchProcess.running)
            watchProcess.running = true;
    }

    function stop() {
        settleTimer.stop();
        restartTimer.stop();
        watchProcess.running = false;
    }

    Process {
        id: watchProcess

        command: root.command
        running: false
        stdout: SplitParser {
            onRead: settleTimer.restart()
        }
        onRunningChanged: {
            if (!running && root.active)
                restartTimer.restart();
        }
    }

    Timer {
        id: settleTimer

        interval: root.settleInterval
        repeat: false
        onTriggered: root.settled()
    }

    Timer {
        id: restartTimer

        interval: root.restartInterval
        repeat: false
        onTriggered: {
            if (root.active && !watchProcess.running)
                watchProcess.running = true;
        }
    }
}
