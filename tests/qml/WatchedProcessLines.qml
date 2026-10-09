import QtQuick
import Quickshell
import qs.core

// Sync Sprint 12 S12-14: WatchedProcess reports each line (the new `line`
// signal), still coalesces a burst into one `settled`, restarts a helper that
// exits while active, and does not restart one that exits while inactive.
// Sync Sprint 16 R16-36: a helper that keeps exiting at once is restarted less
// and less often, not at a fixed rate.
// #279: restartPolicy "never" reports the end, with stderr, and does not
// restart; a missing program ends too; records split on a blank line; stop()
// from an end leaves nothing armed.
ShellRoot {
    id: root
    property int assertions: 0
    property var burstLines: []
    property int burstSettles: 0
    property int restartedLines: 0
    property int inactiveLines: 0
    property int backoffLines: 0
    property int neverLines: 0
    property var neverEnds: []
    property string neverFailure: ""
    property var missingEnds: []
    property var records: []
    property int stoppedLines: 0
    property var restartedEnds: []
    property var reopenedLines: []

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

    // Fails with a message on stderr: reported once, never restarted.
    WatchedProcess {
        id: never
        command: ["sh", "-c", "printf 'x\\n'; printf 'watch broke\\n' >&2; exit 4"]
        active: true
        restartPolicy: "never"
        restartInterval: 100
        onLine: root.neverLines++
        onEnded: code => {
            root.neverEnds = root.neverEnds.concat([code]);
            root.neverFailure = never.failureText;
        }
    }

    // A program that does not exist: an end with no exit code, then backoff.
    WatchedProcess {
        id: missing
        command: ["/nonexistent/lyona-watch"]
        active: true
        restartInterval: 5000
        onEnded: code => root.missingEnds = root.missingEnds.concat([code])
    }

    // Records of several lines, split on the blank line between them.
    WatchedProcess {
        id: recordSplit
        command: ["sh", "-c", "printf 'a 1\\nb 2\\n\\nc 3\\n\\n'; exec sleep 5"]
        active: true
        splitMarker: "\n\n"
        onLine: text => root.records = root.records.concat([text])
    }

    // Stopped from its own end: the restart it would arm never runs.
    WatchedProcess {
        id: stopped
        command: ["sh", "-c", "printf 'x\\n'"]
        active: true
        restartInterval: 100
        onLine: root.stoppedLines++
        onEnded: stopped.stop()
    }

    // start() again while it runs: the run in progress is still reported.
    WatchedProcess {
        id: startedTwice
        command: ["sh", "-c", "sleep 0.3; exit 5"]
        active: true
        restartPolicy: "never"
        onEnded: code => root.restartedEnds = root.restartedEnds.concat([code])
    }

    // Stopped, then started again before the stopped run has exited (it takes
    // 0.3 s on TERM): a new run follows once it has, and the old run's late
    // output is not reported as the new one's.
    WatchedProcess {
        id: reopened
        command: ["sh", "-c", "trap 'sleep 0.3; echo late; exit 0' TERM; echo run; while :; do sleep 0.05; done"]
        active: true
        onLine: text => root.reopenedLines = root.reopenedLines.concat([text])
    }

    Timer {
        interval: 300
        running: true
        onTriggered: {
            reopened.stop();
            root.check(!reopened.running, "a stopped watcher is not running while its run exits");
            reopened.start();
        }
    }

    Component.onCompleted: {
        burst.start();
        restarting.start();
        backingOff.start();
        inactive.start();
        never.start();
        missing.start();
        recordSplit.start();
        stopped.start();
        startedTwice.start();
        startedTwice.start();
        reopened.start();
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
            root.check(root.neverLines === 1 && root.neverEnds.join(",") === "4",
                "a never-restart helper runs once and reports its exit (" + root.neverLines
                + " runs, ends " + root.neverEnds.join(",") + ")");
            root.check(root.neverFailure === "watch broke",
                "the end carries what the helper wrote to stderr: '" + root.neverFailure + "'");
            root.check(root.missingEnds.join(",") === "-1",
                "a missing program ends once, with no exit code: " + root.missingEnds.join(","));
            root.check(JSON.stringify(root.records) === JSON.stringify(["a 1\nb 2", "c 3"]),
                "records split on a blank line: " + JSON.stringify(root.records));
            root.check(root.restartedEnds.join(",") === "5",
                "a second start() keeps the running one reported: " + root.restartedEnds.join(","));
            root.check(root.reopenedLines.join(",") === "run,run" && reopened.running,
                "a start() during a stopped run's exit runs it again: " + root.reopenedLines.join(","));
            reopened.stop();
            root.check(root.stoppedLines === 1, "stop() leaves no restart armed (" + root.stoppedLines + " runs)");
            burst.stop();
            recordSplit.stop();
            console.info("WatchedProcess tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }
}
