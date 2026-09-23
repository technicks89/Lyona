import QtQuick
import QtTest
import "../../config/quickshell/overview/OverviewFilter.js" as Filter

/*
 * Direct, non-UI tests for the pure type-to-filter matching (Sync Sprint 8
 * S8-03, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md), split out of
 * OverviewModel.qml the same way tst_overview_selection.qml tests
 * OverviewSelection.js directly rather than through a live QML component --
 * here because OverviewModel.qml imports Quickshell and cannot be
 * instantiated in plain qmltestrunner (the real Quickshell plugin is
 * unavailable there). Converted into Lyona's own tst_*.qml/TestCase
 * convention (matching tst_display_layout.qml's precedent for a pure-logic
 * library), so it's automatically picked up by `qmltestrunner -input
 * tests/qml` with no new Makefile target needed.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "OverviewFilter"

    function windows() {
        return [
            { "windowId": "0xaa", "desktop": 3, "appClass": "alacritty", "title": "Term one" },
            { "windowId": "0xbb", "desktop": 1, "appClass": "firefox", "title": "GitHub - Lyona" },
            { "windowId": "0xcc", "desktop": 0, "appClass": "code", "title": "main.c - VS Code" }
        ];
    }

    function test_empty_query_returns_every_window_unfiltered() {
        compare(Filter.filterWindows(windows(), "").length, 3);
        compare(Filter.filterWindows(windows(), "   ").length, 3, "Whitespace-only trims to empty: no filtering");
    }

    function test_matches_title_case_insensitively() {
        const matched = Filter.filterWindows(windows(), "GITHUB");
        compare(matched.length, 1);
        compare(matched[0].windowId, "0xbb");
    }

    function test_matches_appClass_case_insensitively() {
        const matched = Filter.filterWindows(windows(), "Alacritty");
        compare(matched.length, 1);
        compare(matched[0].windowId, "0xaa");
    }

    function test_matches_a_substring_not_just_a_whole_word() {
        const matched = Filter.filterWindows(windows(), "term");
        compare(matched.length, 1);
        compare(matched[0].windowId, "0xaa");
    }

    function test_no_match_returns_an_empty_list_not_an_error() {
        compare(Filter.filterWindows(windows(), "nonexistent-app").length, 0);
    }

    function test_matching_query_preserves_relative_order() {
        // "e" appears in all three windows (title or class) -- order must
        // stay first-seen, the same guarantee windowsByTag()/groupByTag()
        // already give, since keyboard navigation depends on a stable order.
        const matched = Filter.filterWindows(windows(), "e");
        compare(matched.length, 3);
        compare(matched[0].windowId, "0xaa");
        compare(matched[1].windowId, "0xbb");
        compare(matched[2].windowId, "0xcc");
    }

    // excludeIds() (Sync Sprint 8 S8-04): a card closed from the overview is
    // hidden immediately, before DwmState.windowStates itself catches up
    // with the next watch update.
    function test_excludeIds_empty_list_returns_every_window_unchanged() {
        compare(Filter.excludeIds(windows(), []).length, 3);
    }

    function test_excludeIds_removes_only_the_named_ids() {
        const remaining = Filter.excludeIds(windows(), ["0xbb"]);
        compare(remaining.length, 2);
        compare(remaining[0].windowId, "0xaa");
        compare(remaining[1].windowId, "0xcc");
    }

    function test_excludeIds_removes_multiple_ids() {
        const remaining = Filter.excludeIds(windows(), ["0xaa", "0xcc"]);
        compare(remaining.length, 1);
        compare(remaining[0].windowId, "0xbb");
    }

    function test_excludeIds_an_id_not_present_is_a_no_op() {
        compare(Filter.excludeIds(windows(), ["0xdeadbeef"]).length, 3);
    }
}
