import QtQuick
import Quickshell

// The clock's month calendar (Sync Sprint 12 S12-20). It has no timer of its
// own: today comes from the shared ClockModel, which already ticks each minute,
// and the month grid is computed only while the popup is open.
Scope {
    id: root

    required property var clock

    property bool visible: false
    // The pill's x on its panel, so the popup opens under the clock.
    property real anchorX: 0
    property int shownYear: 2000
    property int shownMonth: 0
    // The day the keyboard is on, in the shown month.
    property int selectedDay: 1

    // Locale.firstDayOfWeek and Date.getDay() both count Sunday as 0.
    readonly property int firstWeekday: Qt.locale().firstDayOfWeek
    readonly property var today: new Date(root.clock && root.clock.timestamp > 0
        ? root.clock.timestamp : Date.now())
    readonly property string title: Qt.formatDate(new Date(root.shownYear, root.shownMonth, 1), "MMMM yyyy")
    readonly property var weekdays: {
        const names = [];
        for (let index = 0; index < 7; index++)
            names.push(Qt.locale().dayName((root.firstWeekday + index) % 7, Locale.ShortFormat));
        return names;
    }
    // Six weeks, from the week that holds the 1st. Empty while closed.
    readonly property var cells: root.visible ? root.monthCells(root.shownYear, root.shownMonth) : []

    function daysIn(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function monthCells(year, month) {
        const first = new Date(year, month, 1);
        const offset = (first.getDay() - root.firstWeekday + 7) % 7;
        const result = [];
        for (let index = 0; index < 42; index++) {
            const date = new Date(year, month, 1 - offset + index);
            result.push({
                "day": date.getDate(),
                "inMonth": date.getMonth() === month,
                "today": date.getFullYear() === root.today.getFullYear()
                    && date.getMonth() === root.today.getMonth()
                    && date.getDate() === root.today.getDate(),
                "selected": date.getMonth() === month && date.getDate() === root.selectedDay,
                "label": Qt.formatDate(date, "dddd d MMMM yyyy")
            });
        }
        return result;
    }

    function showDate(date) {
        root.shownYear = date.getFullYear();
        root.shownMonth = date.getMonth();
        root.selectedDay = date.getDate();
    }

    function open(anchorX) {
        root.anchorX = anchorX || 0;
        root.showDate(root.today);
        root.visible = true;
    }

    function close() {
        root.visible = false;
    }

    function toggle(anchorX) {
        if (root.visible) root.close();
        else root.open(anchorX);
    }

    function goToday() {
        root.showDate(root.today);
    }

    // A month back or forward, keeping the day where the month has it.
    function moveMonth(delta) {
        const target = new Date(root.shownYear, root.shownMonth + delta, 1);
        const day = Math.min(root.selectedDay, root.daysIn(target.getFullYear(), target.getMonth()));
        root.showDate(new Date(target.getFullYear(), target.getMonth(), day));
    }

    // Days back or forward; crossing into another month shows that month.
    function moveDays(delta) {
        root.showDate(new Date(root.shownYear, root.shownMonth, root.selectedDay + delta));
    }

    function selectCell(index) {
        const cell = root.cells[index];
        if (!cell) return;
        const offset = (new Date(root.shownYear, root.shownMonth, 1).getDay() - root.firstWeekday + 7) % 7;
        root.showDate(new Date(root.shownYear, root.shownMonth, 1 - offset + index));
    }
}
