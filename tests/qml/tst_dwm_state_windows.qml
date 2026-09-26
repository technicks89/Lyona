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

    // decodeClass()/parseWindows() -- a class is percent-encoded by
    // dwm-quickshell-state's own sanitize_class() before it reaches this
    // wire format (":" -> %3A, "|" -> %7C, "%" -> %25), never space-replaced
    // the way a title is, so it must decode back exactly here.
    function test_decodeClass_reverses_percent_encoding() {
        compare(WindowsLib.decodeClass("edge%3Acase%7Cwith%257c"), "edge:case|with%7c");
    }

    function test_decodeClass_plain_value_is_unchanged() {
        compare(WindowsLib.decodeClass("alacritty"), "alacritty", "No encoded sequences: a safe no-op");
    }

    function test_decodeClass_malformed_percent_sequence_does_not_throw() {
        // decodeURIComponent() throws URIError on "%" not followed by two hex
        // digits; a malformed value must fall back to itself, not crash the
        // whole apps=/windows= parse over one bad entry.
        compare(WindowsLib.decodeClass("bad%zzvalue"), "bad%zzvalue");
    }

    function test_parseWindows_decodes_a_percent_encoded_class() {
        const windows = WindowsLib.parseWindows("0xee:2:edge%3Acase%7Cwith%257c:Edge title");

        compare(windows[0].appClass, "edge:case|with%7c");
        compare(windows[0].title, "Edge title", "Only appClass is decoded; title is unaffected");
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
            "Without a fallback count, every workspace belongs to a single monitor 0");
    }

    function test_resolveWindowLocation_no_rows_uses_screen_count_fallback() {
        compare(WindowsLib.resolveWindowLocation(3, [], 9, 2),
            { "tagIndex": 3, "monitorIndex": 0 });
        compare(WindowsLib.resolveWindowLocation(4, [], 9, 2),
            { "tagIndex": 4, "monitorIndex": 1 });
        compare(WindowsLib.resolveWindowLocation(8, twoMonitorRows(), 9, 3),
            { "tagIndex": 8, "monitorIndex": 1 }, "Reported rows override the fallback screen count");
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

    function test_windowsByTag_uses_screen_count_when_rows_are_empty() {
        const windows = WindowsLib.parseWindows("0xaa:3:alacritty:Term|0xbb:7:firefox:Web");
        const resolved = WindowsLib.windowsByTag(windows, [], 9, 2);

        compare(resolved[0].monitorIndex, 0);
        compare(resolved[1].tagIndex, 7);
        compare(resolved[1].monitorIndex, 1);
    }

    readonly property var nineNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    // groupByTag() is what OverviewModel.qml's own `groups` property calls
    // (config/quickshell/overview/OverviewModel.qml) -- without it defined
    // here, OverviewModel.groups throws every time it evaluates, which is
    // constantly, since OverviewModel is instantiated unconditionally in
    // shell.qml. These tests exist specifically to keep that call site real.
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

    function test_groupByTag_honours_the_fallback_screen_count_like_windowsByTag_does() {
        const windows = WindowsLib.parseWindows("0xaa:4:alacritty:Term");
        const groups = WindowsLib.groupByTag(windows, [], nineNames, 2);

        compare(groups.length, 1);
        compare(groups[0].tagIndex, 4);
        compare(groups[0].windows[0].monitorIndex, 1);
    }

    function test_groupByTag_decodes_a_percent_encoded_class_via_parseWindows() {
        const windows = WindowsLib.parseWindows("0xee:2:edge%3Acase%7Cwith%257c:Edge title");
        const groups = WindowsLib.groupByTag(windows, twoMonitorRows(), nineNames);

        compare(groups[0].windows[0].appClass, "edge:case|with%7c");
    }

    // flatIndex (Sync Sprint 8 S8-01, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md):
    // a sequential index across the whole groups list, in the exact order
    // WindowOverview.qml's nested Repeaters render it, so keyboard navigation
    // can select "the next card" without re-deriving the traversal order.
    function test_groupByTag_assigns_flatIndex_sequentially_across_groups() {
        const windows = WindowsLib.parseWindows(
            "0xdd:7:firefox:Web|0xaa:3:alacritty:One|0xcc:3:alacritty:Two|0xbb:0:firefox:Three");
        const groups = WindowsLib.groupByTag(windows, twoMonitorRows(), nineNames);

        compare(groups.length, 3, "Three occupied tags: 0, 3, 7");
        compare(groups[0].tagIndex, 0);
        compare(groups[0].windows[0].flatIndex, 0);
        compare(groups[1].tagIndex, 3);
        compare(groups[1].windows[0].flatIndex, 1, "Continues from the previous group, not reset per tag");
        compare(groups[1].windows[1].flatIndex, 2);
        compare(groups[2].tagIndex, 7);
        compare(groups[2].windows[0].flatIndex, 3);
    }

    function test_groupByTag_flatIndex_does_not_disturb_other_fields() {
        const windows = WindowsLib.parseWindows("0xaa:3:alacritty:Term one");
        const groups = WindowsLib.groupByTag(windows, twoMonitorRows(), nineNames);
        const win = groups[0].windows[0];

        compare(win.windowId, "0xaa");
        compare(win.appClass, "alacritty");
        compare(win.title, "Term one");
        compare(win.tagIndex, 3);
        compare(win.monitorIndex, 0);
        compare(win.flatIndex, 0);
    }
}
