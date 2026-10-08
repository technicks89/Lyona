import QtQuick
import QtTest
import "../../config/quickshell/power/PeripheralBatteries.js" as Peripherals

/*
 * Peripheral batteries (#243): the selection, naming, wording and low-battery
 * rules of PeripheralBatteries.js, fed plain objects in place of Quickshell's
 * UPowerDevice (PowerModel.qml imports Quickshell, which plain qmltestrunner
 * cannot load).
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "PeripheralBatteries"

    function device(overrides) {
        return Object.assign({
            "key": "dev",
            "kind": "mouse",
            "model": "",
            "powerSupply": false,
            "isLaptopBattery": false,
            "present": true,
            "ready": true,
            "percent": 50,
            "state": "discharging",
            "level": ""
        }, overrides);
    }

    function devices() {
        return [
            device({ "key": "mouse", "kind": "mouse", "model": "MX Master 2S", "percent": 40 }),
            device({ "key": "keyboard", "kind": "keyboard", "model": "K270", "percent": -1, "level": "Low" }),
            // The laptop's own battery: never a peripheral.
            device({ "key": "BAT0", "kind": "battery", "model": "5B10W13930", "powerSupply": true,
                     "isLaptopBattery": true, "percent": 80 }),
            device({ "key": "AC", "kind": "line-power", "percent": -1 })
        ];
    }

    function test_selects_the_peripherals_only() {
        const rows = Peripherals.select(devices());
        compare(rows.map(row => row.key), ["keyboard", "mouse"]);
    }

    function test_empty_list_gives_no_rows() {
        compare(Peripherals.select([]).length, 0);
        compare(Peripherals.select(undefined).length, 0);
        compare(Peripherals.select([device({ "key": "BAT0", "kind": "battery", "powerSupply": true })]).length, 0);
    }

    function test_percentage_and_coarse_level_wording() {
        const rows = Peripherals.select(devices());
        const mouse = rows.find(row => row.key === "mouse");
        const keyboard = rows.find(row => row.key === "keyboard");
        compare(mouse.name, "MX Master 2S");
        compare(mouse.value, "40%");
        compare(mouse.detail, "Mouse");
        // A device that reports only a level shows the word, not a number.
        compare(keyboard.value, "Low");
        compare(keyboard.detail, "Keyboard");
    }

    function test_name_falls_back_to_kind() {
        compare(Peripherals.select([device({ "kind": "gaming", "model": "  " })])[0].name, "Game controller");
        compare(Peripherals.select([device({ "kind": "something-new" })])[0].name, "Device");
    }

    function test_charging_state_is_shown() {
        const row = Peripherals.select([device({ "kind": "headset", "percent": 72, "state": "charging" })])[0];
        compare(row.detail, "Headset / Charging");
        compare(row.charging, true);
        compare(Peripherals.select([device({})])[0].charging, false);
        compare(Peripherals.select([device({ "state": "full", "percent": 100 })])[0].detail, "Mouse / Fully charged");
    }

    function test_not_present_not_ready_or_without_charge_is_hidden() {
        compare(Peripherals.select([device({ "present": false })]).length, 0);
        compare(Peripherals.select([device({ "ready": false })]).length, 0);
        compare(Peripherals.select([device({ "percent": -1, "level": "" })]).length, 0);
        compare(Peripherals.select([device({ "percent": -1, "level": "Unknown" })]).length, 0);
    }

    function test_low_battery() {
        compare(Peripherals.select([device({ "percent": 14 })])[0].low, true);
        compare(Peripherals.select([device({ "percent": 15 })])[0].low, false);
        compare(Peripherals.select([device({ "percent": 5, "state": "charging" })])[0].low, false);
        compare(Peripherals.select([device({ "percent": -1, "level": "Critical" })])[0].low, true);
        compare(Peripherals.select([device({ "percent": -1, "level": "Normal" })])[0].low, false);
        compare(Peripherals.select([device({ "percent": 10 })])[0].statusState, "partial");
        compare(Peripherals.select([device({ "percent": 90 })])[0].statusState, "available");
    }

    function test_low_warning_once_per_low_spell() {
        let rows = Peripherals.select([device({ "key": "m", "percent": 12 })]);
        let result = Peripherals.lowWarnings(rows, {});
        compare(result.warn.length, 1);
        // Still low on the next update: no second warning.
        rows = Peripherals.select([device({ "key": "m", "percent": 11 })]);
        result = Peripherals.lowWarnings(rows, result.warned);
        compare(result.warn.length, 0);
        // Gone (disconnected) and back while still low: still no repeat.
        result = Peripherals.lowWarnings([], result.warned);
        result = Peripherals.lowWarnings(Peripherals.select([device({ "key": "m", "percent": 10 })]), result.warned);
        compare(result.warn.length, 0);
        // Charged above the threshold, then low again: warned again.
        result = Peripherals.lowWarnings(Peripherals.select([device({ "key": "m", "percent": 60 })]), result.warned);
        compare(result.warn.length, 0);
        result = Peripherals.lowWarnings(Peripherals.select([device({ "key": "m", "percent": 9 })]), result.warned);
        compare(result.warn.length, 1);
    }
}
