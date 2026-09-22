import QtQuick
import QtTest
import "../../config/quickshell/state/DwmStateWindows.js" as WindowsLib

/*
 * Direct, non-UI tests for the pure windows=-parsing and tag/monitor
 * resolution library (Sync Sprint 7 S7-02,
 * docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md), split out of DwmState.qml the
 * same way tst_panel_tooltip_position.qml tests PanelTooltipPosition.js
 * directly rather than through the live PanelTooltip.qml component -- here
 * because DwmState.qml's own Process { running: true } would otherwise spawn
 * a real "dwm-quickshell-state watch" the moment it was instantiated.
 * Converted into Lyona's own tst_*.qml/TestCase convention (matching
 * tst_display_layout.qml's precedent for a pure-logic library), so it's
 * automatically picked up by `qmltestrunner -input tests/qml` with no new
 * Makefile target needed.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "DwmStateWindows"

    function test_parseWindows_empty_value_is_empty_list() {
        compare(WindowsLib.parseWindows("").length, 0, "Empty value parses to no windows");
    }

    function test_parseWindows_splits_fields_and_rejoins_title_around_embedded_colons() {
        const windows = WindowsLib.parseWindows(
            "0xaa:3:alacritty:Term one|0xbb:1:firefox:Firefox page|0xcc:0:alacritty:");

        compare(windows.length, 3, "One entry per window, no dedup by class");

        compare(windows[0].windowId, "0xaa");
        compare(windows[0].desktop, 3, "desktop is parsed as a number");
        compare(windows[0].appClass, "alacritty");
        compare(windows[0].title, "Term one");

        compare(windows[1].windowId, "0xbb");
        compare(windows[1].desktop, 1);
        compare(windows[1].appClass, "firefox");
        compare(windows[1].title, "Firefox page");

        // No title at all: empty string, not undefined and not a crash.
        compare(windows[2].windowId, "0xcc");
        compare(windows[2].desktop, 0);
        compare(windows[2].appClass, "alacritty");
        compare(windows[2].title, "");
    }

    function test_parseWindows_title_with_embedded_colon_survives_intact() {
        const windows = WindowsLib.parseWindows("0xee:2:xclock:12:34 PM");

        compare(windows.length, 1);
        compare(windows[0].title, "12:34 PM", "Only the first three colons are field separators");
    }

    function test_parseWindows_decodes_only_class_delimiters() {
        const windows = WindowsLib.parseWindows(
            "0xaa:3:edge%3Acase%7Cwith%257c:12:34 PM|0xbb:1:firefox:Unchanged");

        compare(windows.length, 2);
        compare(windows[0].windowId, "0xaa");
        compare(windows[0].desktop, 3);
        compare(windows[0].appClass, "edge:case|with%7c");
        compare(windows[0].title, "12:34 PM");
        compare(windows[1].appClass, "firefox");
        compare(windows[1].title, "Unchanged");
    }

    function twoMonitorRows() {
        // Only .length matters to the resolution math (it derives monitor
        // count from the row count, mirroring DwmState.qml's own
        // workspaceIndexes()); the x/y/width/height values themselves are
        // irrelevant here since resolution works from the raw desktop
        // number, not screen geometry.
        return [
            { "x": 0, "y": 0, "width": 1920, "height": 1080, "desktop": 0 },
            { "x": 1920, "y": 0, "width": 1920, "height": 1080, "desktop": 4 }
        ];
    }

    function test_resolveWindowLocation_splits_workspaces_across_monitors_with_last_taking_remainder() {
        // 9 workspaces / 2 monitors = 4 per monitor, remainder on the last:
        // monitor 0 owns tags 0-3, monitor 1 owns tags 4-8.
        compare(WindowsLib.resolveWindowLocation(0, twoMonitorRows(), 9),
            { "tagIndex": 0, "monitorIndex": 0 });
        compare(WindowsLib.resolveWindowLocation(3, twoMonitorRows(), 9),
            { "tagIndex": 3, "monitorIndex": 0 });
        compare(WindowsLib.resolveWindowLocation(4, twoMonitorRows(), 9),
            { "tagIndex": 4, "monitorIndex": 1 });
        compare(WindowsLib.resolveWindowLocation(8, twoMonitorRows(), 9),
            { "tagIndex": 8, "monitorIndex": 1 });
    }

    function test_resolveWindowLocation_out_of_range_desktop_falls_back_to_tag_zero_monitor_zero() {
        compare(WindowsLib.resolveWindowLocation(99, twoMonitorRows(), 9),
            { "tagIndex": 0, "monitorIndex": 0 }, "No matching row must not crash, and picks a sane default");
    }

    function test_resolveWindowLocation_no_rows_at_all_treats_everything_as_one_monitor() {
        compare(WindowsLib.resolveWindowLocation(5, [], 9), { "tagIndex": 5, "monitorIndex": 0 },
            "With no monitorWorkspaceRows fixture, every workspace belongs to a single monitor 0");
    }

    function test_windowsByTag_decorates_each_window_without_losing_its_fields() {
        const windows = WindowsLib.parseWindows("0xaa:3:alacritty:Term one|0xbb:7:firefox:Web");
        const resolved = WindowsLib.windowsByTag(windows, twoMonitorRows(), 9);

        compare(resolved.length, 2);

        compare(resolved[0].windowId, "0xaa");
        compare(resolved[0].appClass, "alacritty");
        compare(resolved[0].title, "Term one");
        compare(resolved[0].tagIndex, 3);
        compare(resolved[0].monitorIndex, 0);

        compare(resolved[1].windowId, "0xbb");
        compare(resolved[1].tagIndex, 7);
        compare(resolved[1].monitorIndex, 1);
    }

    readonly property var nineNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    function test_groupByTag_orders_groups_ascending_and_omits_empty_tags() {
        // Deliberately out of tag order and with a class repeated across two
        // different tags, to pin that grouping is by tag, not by class.
        const windows = WindowsLib.parseWindows(
            "0xdd:7:firefox:Web|0xaa:3:alacritty:Term one|0xcc:3:alacritty:Term two");
        const groups = WindowsLib.groupByTag(windows, twoMonitorRows(), nineNames);

        compare(groups.length, 2, "Only the two occupied tags produce a group, ascending");
        compare(groups[0].tagIndex, 3);
        compare(groups[0].tagLabel, "4", "tagLabel comes from workspaceNames[tagIndex]");
        compare(groups[0].windows.length, 2, "Both windows on tag 3 land in the same group");
        compare(groups[1].tagIndex, 7);
        compare(groups[1].windows.length, 1);
        compare(groups[1].windows[0].windowId, "0xdd");
    }

    function test_groupByTag_tag_label_falls_back_when_workspaceNames_is_empty() {
        // No rows and no names at all (a plausible transient state before
        // the first watch update parses either): resolution's own defensive
        // fallback lands on tag 0, and with workspaceNames empty even that
        // has no label to look up -- must fall back to a 1-based number, not
        // an undefined/crashing array access.
        const windows = WindowsLib.parseWindows("0xaa:5:alacritty:Term");
        const groups = WindowsLib.groupByTag(windows, [], []);

        compare(groups.length, 1);
        compare(groups[0].tagIndex, 0);
        compare(groups[0].tagLabel, "1", "No workspaceNames[0]: falls back to a 1-based number, not undefined");
    }

    function test_groupByTag_empty_windows_list_is_no_groups() {
        compare(WindowsLib.groupByTag([], twoMonitorRows(), nineNames).length, 0);
    }
}
