import QtQuick
import QtTest
import "../../config/quickshell/overview/OverviewSelection.js" as Selection

/*
 * Direct, non-UI tests for the pure keyboard-navigation math
 * (Sync Sprint 8 S8-01, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md),
 * split out of OverviewModel.qml the same way tst_dwm_state_windows.qml
 * tests DwmStateWindows.js directly rather than through a live QML
 * component -- here because OverviewModel.qml imports Quickshell and cannot
 * be instantiated in plain qmltestrunner (the real Quickshell plugin is
 * unavailable there), the same constraint that shaped DwmStateWindows.js's
 * own split. Converted into Lyona's own tst_*.qml/TestCase convention
 * (matching tst_display_layout.qml's precedent for a pure-logic library),
 * so it's automatically picked up by `qmltestrunner -input tests/qml` with
 * no new Makefile target needed.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "OverviewSelection"

    function test_selectRelative_wraps_forward_past_the_end() {
        compare(Selection.selectRelative(4, 1, 5), 0, "Past the last card wraps to the first");
    }

    function test_selectRelative_wraps_backward_past_the_start() {
        compare(Selection.selectRelative(0, -1, 5), 4, "Before the first card wraps to the last");
    }

    function test_selectRelative_moves_by_one_within_bounds() {
        compare(Selection.selectRelative(2, 1, 5), 3);
        compare(Selection.selectRelative(2, -1, 5), 1);
    }

    function test_selectRelative_empty_list_resets_to_zero() {
        compare(Selection.selectRelative(3, 1, 0), 0, "Nothing to select: reset, do not carry a stale index");
    }

    function test_selectRelative_large_delta_still_wraps_correctly() {
        // A PageDown-style multi-step delta (LauncherWindow.qml's own
        // Keys.onPressed uses 8) must still land inside bounds, not just a
        // single +-1 step.
        compare(Selection.selectRelative(0, 8, 5), 3);
        compare(Selection.selectRelative(4, -8, 5), 1);
    }

    function test_selectAbsolute_clamps_to_the_last_index_not_the_count() {
        compare(Selection.selectAbsolute(99, 5), 4, "Clamped to length - 1, never an out-of-range index");
    }

    function test_selectAbsolute_clamps_negative_to_zero() {
        compare(Selection.selectAbsolute(-1, 5), 0);
    }

    function test_selectAbsolute_within_bounds_is_unchanged() {
        compare(Selection.selectAbsolute(2, 5), 2);
    }

    function test_selectAbsolute_empty_list_resets_to_zero() {
        compare(Selection.selectAbsolute(2, 0), 0);
    }

    // isValidIndex() (Sync Sprint 8 S8-02): OverviewModel.activateSelected()'s
    // own guard against a selectedIndex left stale by a window closing while
    // the popup is open -- must refuse to act rather than focus whatever
    // windowId now happens to sit at a reused array index.
    function test_isValidIndex_true_within_bounds() {
        compare(Selection.isValidIndex(2, 5), true);
        compare(Selection.isValidIndex(0, 5), true, "The first index is valid");
        compare(Selection.isValidIndex(4, 5), true, "The last index is valid");
    }

    function test_isValidIndex_false_at_or_past_cardCount() {
        compare(Selection.isValidIndex(5, 5), false, "cardCount itself is one past the last valid index");
        compare(Selection.isValidIndex(99, 5), false);
    }

    function test_isValidIndex_false_negative() {
        compare(Selection.isValidIndex(-1, 5), false);
    }

    function test_isValidIndex_false_when_cardCount_is_zero() {
        compare(Selection.isValidIndex(0, 0), false, "Index 0 is not valid when there is nothing to select");
    }
}
