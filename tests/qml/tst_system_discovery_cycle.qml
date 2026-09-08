import QtQuick
import QtTest
import "../../config/quickshell/systemmanagement/SystemDiscoveryCycle.js" as Cycle

/*
 * Direct, non-UI tests for the pure discovery-cycle state machine
 * (Sync Phase 4, docs/SYNC-P4-DISCOVERY-EVENTS.md). Cycle.js is plain
 * functions over a plain object with no QML property signals inside the
 * completion handoff -- exactly what makes it safe to test as pure logic,
 * without a Process, a helper, or a display, per the phase document's own
 * "test it directly rather than only through the UI" instruction.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "SystemDiscoveryCycle"

    function test_fresh_cycle_is_idle_and_disabled() {
        const c = Cycle.create();
        compare(c.phase, "idle");
        compare(c.enabled, false);
        compare(c.unresolved, false);
    }

    function test_begin_enters_initial_pending() {
        const c = Cycle.create();
        Cycle.begin(c);
        compare(c.enabled, true);
        compare(c.phase, "initial-pending");
        compare(Cycle.pending(c), true);
    }

    function test_take_moves_pending_to_active_and_returns_a_token() {
        const c = Cycle.create();
        Cycle.begin(c);
        const token = Cycle.take(c);
        verify(token !== null);
        compare(token.epoch, c.epoch);
        compare(token.settling, false);
        compare(c.phase, "initial-active");
        compare(Cycle.pending(c), false);
    }

    function test_take_returns_null_when_nothing_is_pending() {
        const c = Cycle.create();
        compare(Cycle.take(c), null);
        Cycle.begin(c);
        Cycle.take(c);
        // Already active, not pending again.
        compare(Cycle.take(c), null);
    }

    function test_a_clean_read_returns_to_idle() {
        const c = Cycle.create();
        Cycle.begin(c);
        const token = Cycle.take(c);
        Cycle.beforePublish(c, token);
        compare(c.phase, "initial-completing");
        Cycle.complete(c, token, true);
        compare(c.phase, "idle");
        compare(c.unresolved, false);
    }

    function test_changed_during_initial_read_schedules_exactly_one_settling_read() {
        const c = Cycle.create();
        Cycle.begin(c);
        const token = Cycle.take(c);
        Cycle.invalidate(c);
        compare(c.dirty, true);
        // A second invalidation while still active must not schedule twice.
        Cycle.invalidate(c);
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, true);
        compare(c.phase, "settling-pending");
        const settlingToken = Cycle.take(c);
        compare(settlingToken.settling, true);
        Cycle.beforePublish(c, settlingToken);
        Cycle.complete(c, settlingToken, true);
        // No further invalidation arrived during the settling read: done.
        compare(c.phase, "idle");
        compare(c.unresolved, false);
    }

    function test_changed_during_settling_read_blocks_without_a_third_automatic_read() {
        const c = Cycle.create();
        Cycle.begin(c);
        const initial = Cycle.take(c);
        Cycle.invalidate(c);
        Cycle.beforePublish(c, initial);
        Cycle.complete(c, initial, true);
        compare(c.phase, "settling-pending");
        const settling = Cycle.take(c);
        Cycle.invalidate(c);
        compare(c.unresolved, true);
        Cycle.beforePublish(c, settling);
        Cycle.complete(c, settling, true);
        compare(c.phase, "blocked");
        compare(c.unresolved, true);
        // Blocked is terminal until an explicit begin(); nothing is pending.
        compare(Cycle.pending(c), false);
    }

    function test_a_failed_read_blocks_regardless_of_phase() {
        // Failing the initial read.
        let c = Cycle.create();
        Cycle.begin(c);
        let token = Cycle.take(c);
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, false);
        compare(c.phase, "blocked");
        compare(c.unresolved, true);

        // Failing the settling read (reached via a change during the
        // initial read, so a settling read is actually pending to fail).
        c = Cycle.create();
        Cycle.begin(c);
        token = Cycle.take(c);
        Cycle.invalidate(c);
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, true);
        compare(c.phase, "settling-pending");
        token = Cycle.take(c);
        compare(token.settling, true);
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, false);
        compare(c.phase, "blocked");
        compare(c.unresolved, true);
    }

    function test_recovering_from_blocked_forces_a_settling_read_even_without_a_new_change() {
        const c = Cycle.create();
        Cycle.begin(c);
        const token = Cycle.take(c);
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, false);
        compare(c.phase, "blocked");

        // An explicit reload (begin()) after blocked must reconcile via a
        // settling read even if nothing changes during the initial read,
        // because the reload itself does not know what was missed.
        Cycle.begin(c);
        compare(c.forceSettle, true);
        const initial = Cycle.take(c);
        Cycle.beforePublish(c, initial);
        Cycle.complete(c, initial, true);
        compare(c.phase, "settling-pending");
    }

    function test_close_discards_any_late_completion_via_the_epoch() {
        const c = Cycle.create();
        Cycle.begin(c);
        const token = Cycle.take(c);
        Cycle.close(c);
        compare(c.enabled, false);
        compare(Cycle.owns(c, token), false);
        // beforePublish/complete on a token from a closed cycle are no-ops.
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, true);
        compare(c.phase, "idle");
        compare(c.enabled, false);
    }

    function test_a_new_cycle_after_close_uses_a_fresh_epoch_the_old_token_cannot_own() {
        const c = Cycle.create();
        Cycle.begin(c);
        const staleToken = Cycle.take(c);
        Cycle.close(c);
        Cycle.begin(c);
        compare(Cycle.owns(c, staleToken), false);
        const freshToken = Cycle.take(c);
        compare(Cycle.owns(c, freshToken), true);
        verify(freshToken.epoch !== staleToken.epoch);
    }

    function test_owns_and_publish_helpers_reject_a_null_token() {
        const c = Cycle.create();
        Cycle.begin(c);
        compare(Cycle.owns(c, null), false);
        // Must not throw.
        Cycle.beforePublish(c, null);
        Cycle.complete(c, null, true);
        compare(c.phase, "initial-pending");
    }

    function test_invalidate_on_a_disabled_cycle_is_a_no_op() {
        const c = Cycle.create();
        Cycle.invalidate(c);
        compare(c.phase, "idle");
        compare(c.dirty, false);
    }

    function test_invalidate_while_idle_and_enabled_starts_a_cycle() {
        const c = Cycle.create();
        Cycle.begin(c);
        const token = Cycle.take(c);
        Cycle.beforePublish(c, token);
        Cycle.complete(c, token, true);
        compare(c.phase, "idle");
        Cycle.invalidate(c);
        compare(c.phase, "initial-pending");
    }
}
