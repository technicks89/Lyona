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
 *                is still open, without spinning when it dies immediately:
 *                each exit soon after starting doubles the wait, up to
 *                maxRestartInterval, and a run of healthyRunInterval resets
 *                it (Sync Sprint 16 R16-36). A helper that cannot run at all,
 *                as without NetworkManager, is retried every few minutes
 *                rather than every 3 s.
 *
 * Both are gated on `active`, so closing the surface stops the supervision
 * rather than leaving a timer to restart a process nobody is watching.
 *
 * #279: the watchers that used to keep a Process of their own use this too.
 *
 *   restartPolicy  "backoff" (the default) restarts as above. "never" reports
 *                  the end and leaves the next start to the caller: a failed
 *                  watch that the user's Refresh retries, or a helper that
 *                  ends after each change by design.
 *   generation     Counts starts and stops. A restart is armed for one
 *                  generation and dropped once stop() or start() moves on, so
 *                  a timer from a run that was replaced never starts another.
 *   failureText    What the last run wrote to stderr, trimmed, set when it
 *                  ends; empty while one runs.
 *   ended          Emitted when a run ends while active (not after stop()),
 *                  with its exit code (-1 when it never started), after
 *                  failureText is set.
 */
Scope {
    id: root

    /* The helper to run. Changing it while active restarts the watch. */
    property var command: []

    /* Whether the watch should be running -- normally the surface's
     * visibility. Restarts only happen while this is true. */
    property bool active: false

    property string restartPolicy: "backoff"
    /* How the output is split into lines: a blank line for a helper that
     * writes records of several lines. */
    property string splitMarker: "\n"

    property int settleInterval: 250
    property int restartInterval: 3000
    property int maxRestartInterval: 5 * 60 * 1000
    property int healthyRunInterval: 60 * 1000

    // The wait before the next restart, and when the current run started.
    property int restartDelay: root.restartInterval
    property real startedAt: 0

    property int generation: 0
    property string failureText: ""
    property int lastExitCode: -1
    // The generation the armed restart belongs to, and the one the process
    // launched last belongs to: a stopped run may take a moment to exit, and
    // until it has, it is not the current one.
    property int restartGeneration: -1
    property int runGeneration: -1
    // start() came while a stopped run was still exiting: launch once it has.
    property bool startPending: false

    // The current run is live (not one stop() ended that is still exiting).
    readonly property bool running: watchProcess.running && root.runGeneration === root.generation

    /* Emitted once the helper's output has been quiet for settleInterval. */
    signal settled

    /* Emitted for each line the helper writes, before the settle timer
     * restarts. A watcher that reads its lines connects here instead of
     * owning its own Process (Sync Sprint 12 S12-14). */
    signal line(string text)

    signal ended(int exitCode)

    function launch() {
        root.runGeneration = root.generation;
        root.failureText = "";
        root.lastExitCode = -1;
        watchProcess.running = true;
    }

    function start() {
        root.restartDelay = root.restartInterval;
        // Already running: the run in progress stays the current one.
        if (root.running) return;
        root.generation++;
        restartTimer.stop();
        if (watchProcess.running) {
            root.startPending = true;
            return;
        }
        root.launch();
    }

    function stop() {
        root.generation++;
        root.startPending = false;
        settleTimer.stop();
        restartTimer.stop();
        watchProcess.running = false;
    }

    Process {
        id: watchProcess

        command: root.command
        running: false
        stdout: SplitParser {
            splitMarker: root.splitMarker
            onRead: data => {
                // Late output of a run that was stopped is not this one's.
                if (root.runGeneration !== root.generation) return;
                root.line(data);
                settleTimer.restart();
            }
        }
        stderr: StdioCollector { id: watchError }
        onExited: (exitCode, exitStatus) => {
            root.lastExitCode = exitStatus === 0 ? exitCode : -1;
        }
        onRunningChanged: {
            if (running) {
                root.startedAt = Date.now();
                return;
            }
            if (root.startPending) {
                root.startPending = false;
                root.launch();
                return;
            }
            // A run stop() ended is not reported, and never restarted. A
            // program that never started (missing) ends here too.
            if (!root.active || root.runGeneration !== root.generation)
                return;
            root.failureText = watchError.text.trim();
            const generation = root.generation;
            root.ended(root.lastExitCode);
            // A handler that stopped or started it again has decided.
            if (root.restartPolicy === "never" || !root.active || root.generation !== generation)
                return;
            if (Date.now() - root.startedAt >= root.healthyRunInterval)
                root.restartDelay = root.restartInterval;
            root.restartGeneration = root.generation;
            restartTimer.interval = root.restartDelay;
            restartTimer.restart();
            root.restartDelay = Math.min(root.restartDelay * 2, root.maxRestartInterval);
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

        interval: root.restartInterval  // set to restartDelay before each start
        repeat: false
        onTriggered: {
            if (root.active && !watchProcess.running && root.restartGeneration === root.generation)
                root.launch();
        }
    }
}
