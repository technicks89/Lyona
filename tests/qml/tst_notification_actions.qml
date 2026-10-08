import QtQuick
import QtTest
import "../../config/quickshell/notifications/NotificationActions.js" as NotificationActions

/*
 * Notification buttons (#260): which of a notification's actions become
 * buttons, fed plain objects in place of Quickshell's NotificationAction.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "NotificationActions"

    function action(identifier, text) {
        return { "identifier": identifier, "text": text };
    }

    function test_no_actions_no_buttons() {
        compare(NotificationActions.buttons(undefined).length, 0);
        compare(NotificationActions.buttons([]).length, 0);
    }

    function test_buttons_keep_identifier_and_text() {
        const buttons = NotificationActions.buttons([action("run", "Add and run"), action("add", "Add only")]);
        compare(buttons.length, 2);
        compare(buttons[0].identifier, "run");
        compare(buttons[0].text, "Add and run");
        compare(buttons[1].identifier, "add");
    }

    function test_default_action_is_not_a_button() {
        const buttons = NotificationActions.buttons([action("default", "Open"), action("run", "Run")]);
        compare(buttons.length, 1);
        compare(buttons[0].identifier, "run");
    }

    function test_actions_without_text_are_skipped() {
        compare(NotificationActions.buttons([action("a", ""), action("b", "   "), null]).length, 0);
    }

    function test_at_most_three_buttons() {
        const buttons = NotificationActions.buttons([action("1", "One"), action("2", "Two"),
            action("3", "Three"), action("4", "Four")]);
        compare(buttons.length, NotificationActions.MAX_BUTTONS);
        compare(buttons[2].identifier, "3");
    }

    function popup(key, withButtons) {
        return { "key": key, "actions": withButtons ? [action("run", "Run")] : [] };
    }

    function keys(list) {
        return list.map(item => item.key).join(",");
    }

    function test_ordinary_popups_keep_the_limit() {
        const fitted = NotificationActions.fitPopups([popup("e"), popup("d"), popup("c"), popup("b"), popup("a")], 4);
        compare(keys(fitted.kept), "e,d,c,b");
        compare(keys(fitted.overflow), "a");
    }

    function test_questions_are_never_pushed_out() {
        // The oldest is a question; four newer ordinary ones arrive.
        const fitted = NotificationActions.fitPopups([popup("e"), popup("d"), popup("c"), popup("b"),
            popup("q", true)], 4);
        compare(keys(fitted.kept), "e,d,c,b,q");
        compare(fitted.overflow.length, 0);
    }

    function test_questions_do_not_count_toward_the_limit() {
        const fitted = NotificationActions.fitPopups([popup("q1", true), popup("e"), popup("q2", true),
            popup("d"), popup("c"), popup("b"), popup("a")], 4);
        compare(keys(fitted.kept), "q1,e,q2,d,c,b");
        compare(keys(fitted.overflow), "a");
    }

    function test_long_text_is_cut() {
        const buttons = NotificationActions.buttons([action("x", "y".repeat(100))]);
        compare(buttons[0].text.length, NotificationActions.MAX_TEXT);
    }
}
