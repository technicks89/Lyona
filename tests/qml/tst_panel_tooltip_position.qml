import QtQuick
import QtTest
import "../../config/quickshell/core/PanelTooltipPosition.js" as TooltipPosition

/*
 * Direct, non-UI tests for the pure tooltip-position math behind
 * PanelTooltip.qml's anchor.rect.x (Sync Sprint 6 S6-01,
 * docs/SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md, small portable
 * fix from upstream's 2461027 (#343): the position now recomputes whenever
 * the anchor window's width, the tooltip's own width, or the anchor point
 * changes, as a live property binding, instead of only when Quickshell's
 * onAnchoring happens to fire. Split into its own tst_*.qml/TestCase
 * (matching tst_display_layout.qml's precedent), so it's automatically
 * picked up by `qmltestrunner -input tests/qml` with no new Makefile target.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "PanelTooltipPosition"

    function test_left_aligned_starts_at_the_anchor_point() {
        compare(TooltipPosition.clampedX(1024, 80, 200, false), 200,
            "A left-aligned tooltip should start exactly at the anchor point");
    }

    function test_right_aligned_ends_at_the_anchor_point() {
        compare(TooltipPosition.clampedX(1024, 80, 200, true), 120,
            "A right-aligned tooltip should end (not start) at the anchor point");
    }

    function test_clamped_to_the_left_edge() {
        compare(TooltipPosition.clampedX(1024, 80, 10, true), 0,
            "A right-aligned tooltip near x=0 must not go negative");
    }

    function test_clamped_to_the_right_edge() {
        compare(TooltipPosition.clampedX(1024, 80, 1020, false), 944,
            "A left-aligned tooltip near the far edge must not run past the window");
    }

    function test_a_narrower_window_reflows_the_same_anchor_point() {
        // The same anchor point, after the window narrows (a DPI change, a
        // monitor hot-plug): the tooltip must reflow to the new width, not
        // keep clipping off the edge the way a stale, one-shot position would.
        const wide = TooltipPosition.clampedX(1024, 80, 1020, false);
        const narrow = TooltipPosition.clampedX(700, 80, 1020, false);
        verify(narrow < wide, "A narrower window must pull the tooltip back in");
        compare(narrow, 620, "Clamped to the narrower window's own right edge");
    }

    function test_zero_or_negative_available_width_never_throws() {
        // A tooltip wider than its anchor window (a very long label): still a
        // finite number, not NaN or an exception, even though there is no
        // position that avoids clipping.
        const x = TooltipPosition.clampedX(50, 80, 10, false);
        verify(Number.isFinite(x), "clampedX must return a finite number even when the tooltip cannot fit");
    }
}
