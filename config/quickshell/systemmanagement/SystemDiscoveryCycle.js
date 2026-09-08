// Serialized state only: no QML property signals inside the completion handoff.
/** Create a disabled discovery cycle in its initial idle state. */
function create() {
    return { epoch: 0, enabled: false, phase: "idle", dirty: false,
        unresolved: false, forceSettle: false, settlingDirty: false };
}

/** Begin a new initial-read cycle and invalidate tokens from older epochs. */
function begin(cycle) {
    cycle.epoch++;
    cycle.enabled = true;
    cycle.phase = "initial-pending";
    cycle.dirty = false;
    cycle.forceSettle = cycle.unresolved;
    cycle.settlingDirty = false;
}

/** Disable a cycle and invalidate any outstanding read token. */
function close(cycle) {
    cycle.epoch++;
    cycle.enabled = false;
    cycle.phase = "idle";
    cycle.dirty = false;
}

/** Record a provider change and schedule at most one bounded follow-up read. */
function invalidate(cycle) {
    if (!cycle.enabled) return;
    if (cycle.phase === "idle") begin(cycle);
    else if (cycle.phase === "initial-active" || cycle.phase === "initial-completing")
        cycle.dirty = true;
    else if (cycle.phase === "settling-active" || cycle.phase === "settling-completing") {
        cycle.settlingDirty = true;
        cycle.unresolved = true;
    }
    // Pending invalidations are covered by the reserved read. Blocked cycles
    // retain their unresolved bit without scheduling a third automatic read.
}

/** Return whether the cycle has a snapshot read ready to start. */
function pending(cycle) {
    return cycle.enabled && (cycle.phase === "initial-pending" || cycle.phase === "settling-pending");
}

/** Reserve the pending read and return the token that owns its completion. */
function take(cycle) {
    if (!pending(cycle)) return null;
    const settling = cycle.phase === "settling-pending";
    cycle.phase = settling ? "settling-active" : "initial-active";
    cycle.settlingDirty = false;
    return { epoch: cycle.epoch, settling: settling };
}

/** Return whether a token still owns the active or completing read. */
function owns(cycle, token) {
    if (token === null || !cycle.enabled || token.epoch !== cycle.epoch) return false;
    const prefix = token.settling ? "settling" : "initial";
    return cycle.phase === prefix + "-active" || cycle.phase === prefix + "-completing";
}

/** Mark an owned read as completing before its snapshot is published. */
function beforePublish(cycle, token) {
    if (owns(cycle, token))
        cycle.phase = token.settling ? "settling-completing" : "initial-completing";
}

/** Complete an owned read and select the next bounded cycle phase. */
function complete(cycle, token, successful) {
    if (!owns(cycle, token)) return;
    if (!successful) {
        cycle.unresolved = true;
        cycle.phase = "blocked";
    } else if (token.settling) {
        cycle.unresolved = cycle.settlingDirty;
        cycle.phase = cycle.unresolved ? "blocked" : "idle";
    } else if (cycle.dirty || cycle.forceSettle) {
        cycle.dirty = false;
        cycle.phase = "settling-pending";
    } else cycle.phase = "idle";
}
