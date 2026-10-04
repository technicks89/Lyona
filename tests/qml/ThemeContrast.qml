import QtQuick
import Quickshell
import qs.core

// Runtime harness for Sync Sprint 11 S11-01 (docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md).
// tests/test-quickshell-theme-contrast-xvfb.sh replaces __PRESETS__ with one
// colour map per preset in config/themes.toml, built with the same key mapping
// scripts/dwm-settings-appearance uses. For every preset this loads the real
// Theme singleton and checks that each text role reads on the surface it is
// drawn on at 4.5:1 (WCAG AA). The contrast maths here is independent of Theme's
// own helpers so a mistake in them cannot hide itself.
ShellRoot {
    id: root

    property int assertions: 0
    readonly property var presets: __PRESETS__

    // [text role, surface role, applies to: "all", "light" or "dark"]
    readonly property var pairs: [
        ["menuHoverText", "menuHoverBackground", "all"],
        ["controlHoverText", "controlHoverFill", "all"],
        ["controlFocusText", "controlFocusFill", "all"],
        ["controlNormalText", "controlNormalFill", "all"],
        ["controlSelectedText", "controlSelectedFill", "all"],
        ["menuSelectedText", "menuSelectedBackground", "all"],
        ["accentHoverText", "accentSecondary", "all"],
        ["menuActionText", "menuBackground", "all"],
        // Light palettes keep one text role across a fill that changes on hover.
        ["menuText", "menuBackground", "light"],
        ["menuText", "menuHoverBackground", "light"],
        ["menuMutedText", "menuBackground", "light"],
        ["menuMutedText", "menuHoverBackground", "light"],
        ["controlNormalText", "controlHoverFill", "light"]
    ]

    function lum(color) {
        const rgb = color.length === 9 ? color.slice(3) : color.slice(1);
        const c = [0, 2, 4].map(function(o) {
            const v = parseInt(rgb.slice(o, o + 2), 16) / 255;
            return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    }

    function ratio(a, b) {
        const x = root.lum(a);
        const y = root.lum(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }

    function checkPreset(preset, failures) {
        Theme.applyAppearanceColors(preset.colors, preset.dark);
        for (const pair of root.pairs) {
            if (pair[2] === "light" && preset.dark) continue;
            if (pair[2] === "dark" && !preset.dark) continue;
            const foreground = String(Theme[pair[0]]);
            const surface = String(Theme[pair[1]]);
            const value = root.ratio(foreground, surface);
            root.assertions++;
            if (!(value >= 4.5))
                failures.push(preset.name + ": " + pair[0] + " " + foreground + " on " + pair[1] + " " + surface
                    + " is " + value.toFixed(2) + ":1");
        }
    }

    function run() {
        const failures = [];
        for (const preset of root.presets)
            root.checkPreset(preset, failures);

        // Switching palettes in one process re-evaluates every role (the bindings
        // are live), so check a dark preset followed by a light one, and back.
        const dark = root.presets.filter(function(p) { return p.dark; })[0];
        const light = root.presets.filter(function(p) { return !p.dark; })[0];
        root.checkPreset(dark, failures);
        root.checkPreset(light, failures);
        root.checkPreset(dark, failures);

        if (failures.length > 0) {
            console.error("Theme contrast FAILED (" + failures.length + " of " + root.assertions + "):\n  "
                + failures.join("\n  "));
        } else {
            console.info("Theme contrast tests: PASS (" + root.assertions + " assertions, "
                + root.presets.length + " presets)");
        }
        Qt.quit();
    }

    Component.onCompleted: Qt.callLater(root.run)
}
