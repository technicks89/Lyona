// The keyboard layout switch key and its LED (#473, upstream dwm-titus #385,
// a2f77813): XKB "grp:" and "grp_led:" options inside a keyboard's Modifier
// options value, which the presets change and preview like any edit of it.
// Space chords (Super/Alt/Ctrl+Space) and Left Super are left out on purpose:
// XKB would switch the layout while dwm still runs its own binding on the
// same keys, and Super is dwm's modifier.
.pragma library

const switchPrefix = "grp:";
const ledPrefix = "grp_led:";

const switchChoices = [
    { value: "grp:alt_shift_toggle", label: "Alt+Shift" },
    { value: "grp:ctrl_shift_toggle", label: "Ctrl+Shift" },
    { value: "grp:caps_toggle", label: "Caps Lock" },
    { value: "grp:shift_caps_toggle", label: "Shift+Caps Lock" },
    { value: "grp:shifts_toggle", label: "Both Shifts" },
    { value: "grp:toggle", label: "Right Alt" },
    { value: "grp:rctrl_toggle", label: "Right Ctrl" },
    { value: "grp:menu_toggle", label: "Menu" },
    { value: "", label: "None" }
];

const ledChoices = [
    { value: "", label: "Off" },
    { value: "grp_led:caps", label: "Caps Lock" },
    { value: "grp_led:scroll", label: "Scroll Lock" },
    { value: "grp_led:num", label: "Num Lock" }
];

function tokens(options) {
    return String(options || "").split(",").map(item => item.trim()).filter(item => item.length > 0);
}

// The option with this prefix, "" when there is none.
function current(options, prefix) {
    const found = tokens(options).filter(item => item.indexOf(prefix) === 0);
    return found.length > 0 ? found[0] : "";
}

// Every option with this prefix replaced by VALUE ("" removes them); the rest
// keep their order.
function withChoice(options, prefix, value) {
    const kept = tokens(options).filter(item => item.indexOf(prefix) !== 0);
    if (value) kept.push(value);
    return kept.join(",");
}

// How many layouts a Keyboard layout value names ("us,de" is 2); 0 when it
// is not known.
function layoutCount(layout) {
    return typeof layout === "string" ? tokens(layout).length : 0;
}

// What the chosen switch key costs, when it costs something. With one layout
// there is nothing to switch to (#529): the presets are hidden, and this says
// how to add a second.
function hint(options, layouts) {
    if (layouts === 1)
        return "One keyboard layout: add a second to Keyboard layout (for example us,de) to choose a switch key and its LED.";
    const key = current(options, switchPrefix);
    if (key === "grp:caps_toggle") return "Caps Lock switches layouts; Shift+Caps Lock is Caps Lock.";
    if (key === "grp:shift_caps_toggle") return "Shift+Caps Lock switches layouts; Caps Lock stays Caps Lock.";
    if (key === "grp:toggle") return "Right Alt switches layouts and no longer works as Alt or AltGr.";
    if (key === "grp:rctrl_toggle") return "Right Ctrl switches layouts and no longer works as Ctrl.";
    if (key === "grp:menu_toggle") return "Menu switches layouts; Shift+Menu is Menu.";
    if (key === "") return "No switch key: switch with the keyboard layout pill in the panel.";
    return "";
}
