import QtQuick
import Quickshell
import qs.core

// Sync Sprint 12 S12-14: WatchedProcess reports each line (the new `line`
// signal), still coalesces a burst into one `settled`, restarts a helper that
// exits while active, and does not restart one that exits while inactive.
ShellRoot {
    id: root
    property int assertions: 0
    property var burstLines: []
    property int burstSettles: 0
    property int restartedLines: 0
    property int inactiveLines: 0

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("WatchedProcess FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }

    // One burst of three lines, then the helper stays up.
    WatchedProcess {
        id: burst
        command: ["sh", "-c", "printf 'a\\nb\\nc\\n'; exec sleep 5"]
        active: true
        settleInterval: 200
        onLine: text => root.burstLines = root.burstLines.concat([text])
        onSettled: root.burstSettles++
    }

    // Prints one line and exits: restarted while active.
    WatchedProcess {
        id: restarting
        command: ["sh", "-c", "printf 'x\\n'"]
        active: true
        restartInterval: 200
        onLine: root.restartedLines++
    }

    // The same, but inactive: it runs once and is not restarted.
    WatchedProcess {
        id: inactive
        command: ["sh", "-c", "printf 'x\\n'"]
        active: false
        restartInterval: 200
        onLine: root.inactiveLines++
    }

    Component.onCompleted: {
        burst.start();
        restarting.start();
        inactive.start();
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: {
            root.check(root.burstLines.join(",") === "a,b,c",
                "each line arrives, in order: " + root.burstLines.join(","));
            root.check(root.burstSettles === 1, "a burst settles once, not " + root.burstSettles);
            root.check(root.restartedLines >= 3,
                "an active helper that exits is restarted (" + root.restartedLines + " runs)");
            root.check(root.inactiveLines === 1,
                "an inactive helper is not restarted (" + root.inactiveLines + " runs)");
            burst.stop();
            console.info("WatchedProcess tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }
}
