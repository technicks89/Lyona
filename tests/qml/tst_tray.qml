import QtQuick
import QtTest
import "../../config/quickshell/panel/Tray.js" as Tray

/*
 * The tray's pure logic (config/quickshell/panel/Tray.js): which items the
 * panel draws, and how a DBusMenu entry is labelled. TrayArea.qml and
 * TrayMenu.qml import Quickshell, which plain qmltestrunner cannot load.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "Tray"

    function ids(items) {
        return items.map(function(item) { return item.id; });
    }

    function test_blueman_is_hidden() {
        const items = [{ "id": "blueman" }, { "id": "blueman-applet" }, { "id": "steam" }];
        compare(ids(Tray.visibleTrayItems(items, [])), ["steam"]);
    }

    function test_app_with_a_running_window_is_hidden() {
        const items = [{ "id": "steam" }, { "id": "discord" }];
        const running = [{ "windowId": "0x1", "appClass": "steam" }, { "windowId": "0x2", "appClass": "firefox" }];
        compare(ids(Tray.visibleTrayItems(items, running)), ["discord"]);
    }

    function test_item_id_matches_case_insensitively() {
        const items = [{ "id": "TelegramDesktop" }];
        const running = [{ "windowId": "0x1", "appClass": "telegramdesktop" }];
        compare(Tray.visibleTrayItems(items, running).length, 0);
    }

    function test_item_returns_when_window_closes_to_tray() {
        compare(ids(Tray.visibleTrayItems([{ "id": "steam" }], [])), ["steam"]);
    }

    function test_item_without_an_id_is_kept() {
        compare(Tray.visibleTrayItems([{ "title": "Thing" }], [{ "appClass": "" }]).length, 1,
            "An empty id must not match a window with an empty class");
        compare(Tray.visibleTrayItems([{ "title": "Thing" }], [{ "appClass": "steam" }]).length, 1);
    }

    function test_menu_label_drops_access_key_marks() {
        compare(Tray.menuLabel("_Library"), "Library");
        compare(Tray.menuLabel("Big _Picture"), "Big Picture");
        compare(Tray.menuLabel("snake__case"), "snake_case");
        compare(Tray.menuLabel(""), "");
        compare(Tray.menuLabel(undefined), "");
    }

    function test_check_detail() {
        compare(Tray.checkDetail(0, 0), "");
        compare(Tray.checkDetail(1, 2), "[x]");
        compare(Tray.checkDetail(1, 0), "[ ]");
        compare(Tray.checkDetail(2, 2), "(*)");
        compare(Tray.checkDetail(2, 0), "( )");
    }

    function test_redundant_separators() {
        const s = { "isSeparator": true };
        const e = { "isSeparator": false };
        const entries = [s, e, s, s, e, s];
        compare([0, 1, 2, 3, 4, 5].map(function(i) { return Tray.redundantSeparator(entries, i); }),
            [true, false, false, true, false, true]);
    }
}
