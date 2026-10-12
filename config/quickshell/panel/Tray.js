.pragma library

// Pure tray logic, kept out of TrayArea.qml/TrayMenu.qml so plain
// qmltestrunner can test it (tests/qml/tst_tray.qml): those files import
// Quickshell, which qmltestrunner cannot load.

// Blueman has its own panel control (the Bluetooth pill).
const hiddenIds = ["blueman", "blueman-applet"];

// The tray items to draw. An app whose window is already a running-apps
// button (Steam, with its window open) would otherwise show twice side by
// side, so its tray icon is hidden until the window closes to the tray.
// A running app's class is WM_CLASS's class, lowercased by the state bridge;
// a StatusNotifierItem id is the app's own name for itself, which for the
// apps that matter (steam, discord, telegramdesktop) is the same word.
function visibleTrayItems(items, runningApps) {
    const running = {};
    for (let i = 0; i < runningApps.length; i++)
        running[runningApps[i].appClass] = true;

    return items.filter(function(item) {
        const id = (item.id || "").toLowerCase();
        return hiddenIds.indexOf(id) === -1 && !(id.length > 0 && running[id]);
    });
}

// A DBusMenu label marks its access key with "_" ("_Library"); "__" is a
// literal underscore. The menu is driven by the pointer, so drop the marks.
function menuLabel(text) {
    return (text || "").replace(/_(.)/g, "$1").replace(/_$/, "");
}

// The check mark column for a checkbox or radio entry, "" for a plain one.
// buttonType and checkState are QsMenuButtonType (0 none, 1 checkbox,
// 2 radio) and Qt.CheckState (0 unchecked, 1 partial, 2 checked).
function checkDetail(buttonType, checkState) {
    if (buttonType === 1)
        return checkState === 2 ? "[x]" : checkState === 1 ? "[-]" : "[ ]";
    if (buttonType === 2)
        return checkState === 2 ? "(*)" : "( )";
    return "";
}

// A separator with nothing to separate: first, last, or right after another
// (Steam's menu sends two in a row). The row is not drawn.
function redundantSeparator(entries, index) {
    if (!entries[index].isSeparator)
        return false;
    if (index === 0 || index === entries.length - 1 || entries[index - 1].isSeparator)
        return true;
    return false;
}
