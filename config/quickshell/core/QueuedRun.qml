pragma Singleton

import Quickshell

// One rule for every "read again once this read is over" flag: start the
// process, or remember that another run is wanted while it (or something it must
// wait for) is in the way, and clear that memory only after the process has
// really been started. The start and the clear live together here so a caller
// cannot clear the flag early, leave it set by returning between the two, or
// clear it from a running-changed handler while the retry is still only scheduled.
Singleton {
    // Starts `process` unless it is running or `blocked` is true. In that case
    // `owner[flag]` is set (the caller's own "queued" property, which its
    // owner retries from when the blocker ends) and false is returned.
    // `prepare`, if given, runs only when the process is about to start.
    function startOrQueue(process, owner, flag, blocked, prepare) {
        if (blocked || process.running) {
            owner[flag] = true;
            return false;
        }
        if (prepare) prepare();
        process.running = true;
        owner[flag] = false;
        return true;
    }
}
