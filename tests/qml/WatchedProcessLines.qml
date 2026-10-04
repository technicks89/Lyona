import QtQuick
import Quickshell
import qs.core

// Sync Sprint 12 S12-14: WatchedProcess reports each line (the new `line`
// signal), still coalesces a burst into one `settled`, restarts a helper that
// exits while active, and does not restart one that exits while inactive.
// Sync Sprint 16 R16-36: a helper that keeps exiting at once is restarted less
// and less often, not at a fixed rate.
ShellRoot {
    id: root
    property int assertions: 0
    property var burstLines: []
    property int burstSettles: 0
    property int restartedLines: 0
    property int inactiveLines: 0
    property int backoffLines: 0

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

    // Prints one line and exits: restarted while active (at a fixed 200 ms
    // here, the backoff capped).
    WatchedProcess {
        id: restarting
        command: ["sh", "-c", "printf 'x\\n'"]
        active: true
        restartInterval: 200
        maxRestartInterval: 200
        onLine: root.restartedLines++
    }

    // The same from a 100 ms base, backing off: 100, 200, 400, 800 ms, so
    // about 5 runs in 1.5 s, where a fixed 100 ms would make about 15.
    WatchedProcess {
        id: backingOff
        command: ["sh", "-c", "printf 'x\\n'"]
        active: true
        restartInterval: 100
        onLine: root.backoffLines++
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
        backingOff.start();
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
            root.check(root.backoffLines >= 3 && root.backoffLines <= 7,
                "a helper that keeps exiting backs off (" + root.backoffLines + " runs)");
            root.check(root.inactiveLines === 1,
                "an inactive helper is not restarted (" + root.inactiveLines + " runs)");
            burst.stop();
            console.info("WatchedProcess tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }
}
