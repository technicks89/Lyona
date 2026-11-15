import QtQuick
import QtTest
import "../../config/quickshell/settings/InputOptions.js" as InputOptions

// The layout switch key and LED presets (#473): they change only the grp: or
// grp_led: part of a Modifier options value.
TestCase {
    name: "InputOptions"

    function test_current() {
        compare(InputOptions.current("caps:escape,grp:alt_shift_toggle", InputOptions.switchPrefix), "grp:alt_shift_toggle");
        compare(InputOptions.current("grp_led:caps", InputOptions.switchPrefix), "", "grp_led: is not a switch key");
        compare(InputOptions.current("grp:caps_toggle,grp_led:caps", InputOptions.ledPrefix), "grp_led:caps");
        compare(InputOptions.current("", InputOptions.switchPrefix), "");
    }

    function test_with_choice() {
        compare(InputOptions.withChoice("caps:escape,grp:alt_shift_toggle,grp_led:caps", InputOptions.switchPrefix, "grp:caps_toggle"),
            "caps:escape,grp_led:caps,grp:caps_toggle", "only the switch key changes, the rest kept in order");
        compare(InputOptions.withChoice("caps:escape,grp:alt_shift_toggle,grp:toggle", InputOptions.switchPrefix, ""),
            "caps:escape", "None removes every switch key");
        compare(InputOptions.withChoice(" caps:escape , ,grp_led:num", InputOptions.ledPrefix, "grp_led:scroll"),
            "caps:escape,grp_led:scroll", "spaces and empty items dropped");
        compare(InputOptions.withChoice("", InputOptions.ledPrefix, ""), "");
    }

    function test_choices_are_valid_options() {
        // What dwm-settings-input accepts for modifier-options.
        const valid = /^[A-Za-z0-9_:+,.-]*$/;
        for (const choice of InputOptions.switchChoices.concat(InputOptions.ledChoices))
            verify(valid.test(choice.value), choice.value);
        for (const choice of InputOptions.switchChoices)
            verify(choice.value.indexOf("space") < 0 && choice.value.indexOf("lwin") < 0, "no Space chord or Left Super: " + choice.value);
    }

    function test_hint() {
        compare(InputOptions.hint("grp:toggle"), "Right Alt switches layouts and no longer works as Alt or AltGr.");
        compare(InputOptions.hint("caps:escape"), "No switch key: switch with the keyboard layout pill in the panel.");
        compare(InputOptions.hint("grp:alt_shift_toggle"), "");
    }
}
