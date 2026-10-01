import QtQuick

/*
 * One preview's countdown to its automatic revert (Sync Sprint 12 S12-14).
 *
 * Five surfaces carried this as their own Timer: theme, wallpaper, font and
 * toolkit in AppearanceModel, and display and input in SettingsModel. Each
 * ticked a "seconds left" property down once a second and asked its helper
 * for the preview's state at zero, since the helper, not the shell, owns the
 * deadline and the rollback. A model aliases its property to `remaining`, so
 * assigning the helper's reported value still works, and handles `expired`.
 */
Timer {
    id: root

    /* Seconds until the helper reverts the preview; the model sets it from
     * the helper's status. */
    property int remaining: 0

    /* Whether this preview is live, and its surface wants the countdown. */
    property bool active: false

    /* The count reached zero: ask the helper what happened. */
    signal expired

    interval: 1000
    repeat: true
    running: root.active && root.remaining > 0

    onTriggered: {
        root.remaining = Math.max(0, root.remaining - 1);
        if (root.remaining === 0)
            root.expired();
    }
}
