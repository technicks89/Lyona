.pragma library

// Peripheral batteries (#243): which UPower devices are peripherals, what to
// call them, how to word their charge, and when to warn. Pure, so
// tests/qml/tst_peripheral_batteries.qml can feed it plain objects in place of
// Quickshell's UPowerDevice; PowerModel.qml turns each device into one:
//
//   { key, kind, model, powerSupply, isLaptopBattery, present, ready,
//     percent (0-100, or -1 when unknown), state, level }
//
// kind is PowerModel.peripheralKind()'s key for the UPower device type. state is
// "charging", "discharging", "full", "pending", "empty" or "unknown". level is
// the kernel's coarse capacity_level ("Critical", "Low", "Normal", "High",
// "Full") for a device that reports only that, and "" otherwise.

const LOW_PERCENT = 15;

const KIND_LABELS = {
    "mouse": "Mouse",
    "keyboard": "Keyboard",
    "headset": "Headset",
    "headphones": "Headphones",
    "speakers": "Speakers",
    "gaming": "Game controller",
    "tablet": "Tablet",
    "pen": "Pen",
    "touchpad": "Touchpad",
    "phone": "Phone",
    "media": "Media player",
    "remote": "Remote control",
    "wearable": "Wearable",
    "toy": "Toy",
    "camera": "Camera",
    "printer": "Printer",
    "scanner": "Scanner",
    "audio": "Audio device",
    "video": "Video device",
    "bluetooth": "Bluetooth device",
    "battery": "Battery",
    "other": "Device"
};

// Never peripherals: power sources, and the machine itself.
const EXCLUDED_KINDS = {
    "line-power": true,
    "ups": true,
    "monitor": true,
    "computer": true,
    "network": true,
    "modem": true
};

const COARSE_LEVELS = ["Critical", "Low", "Normal", "High", "Full"];

function coarseLevel(device) {
    return COARSE_LEVELS.indexOf(device.level) >= 0 ? device.level : "";
}

function hasCharge(device) {
    return coarseLevel(device).length > 0 || (typeof device.percent === "number" && device.percent >= 0);
}

// A battery-powered device that is not the machine's own supply. The laptop
// battery (powerSupply, isLaptopBattery) is never one, so peripherals cannot
// change the system battery or the panel indicator. UPower's IsPresent is only
// meaningful for the battery kind, so only that kind must be present.
function isPeripheral(device) {
    if (!device || device.powerSupply === true || device.isLaptopBattery === true) return false;
    if (device.ready !== true) return false;
    if (device.kind === "battery" && device.present !== true) return false;
    if (EXCLUDED_KINDS[device.kind] === true) return false;
    return hasCharge(device);
}

function kindLabel(kind) {
    return KIND_LABELS[kind] || KIND_LABELS["other"];
}

// The model name (or vendor and model) the device reports, else its kind.
function name(device) {
    const model = typeof device.model === "string" ? device.model.trim() : "";
    return model.length > 0 ? model : kindLabel(device.kind);
}

// A coarse level stays a word: no made-up percentage.
function value(device) {
    const level = coarseLevel(device);
    return level.length > 0 ? level : Math.round(device.percent) + "%";
}

function stateText(state) {
    if (state === "charging") return "Charging";
    if (state === "full") return "Fully charged";
    if (state === "empty") return "Empty";
    return "";
}

// Low: a coarse Critical or Low, or under LOW_PERCENT, and not charging.
function isLow(device) {
    if (device.state === "charging" || device.state === "full") return false;
    const level = coarseLevel(device);
    if (level.length > 0) return level === "Critical" || level === "Low";
    return device.percent < LOW_PERCENT;
}

// Charged back up: at LOW_PERCENT or more, or a coarse Normal, High or Full.
// Charging alone is not enough: a device plugged in at 5% and unplugged at 6%
// is still the same low spell.
function isRecovered(device) {
    const level = coarseLevel(device);
    if (level.length > 0) return level === "Normal" || level === "High" || level === "Full";
    return device.percent >= LOW_PERCENT;
}

// The peripherals to show, sorted by name, as the rows the shell draws.
function select(devices) {
    const rows = [];
    for (const device of devices || []) {
        if (!isPeripheral(device)) continue;
        const low = isLow(device);
        const detail = [kindLabel(device.kind), stateText(device.state)].filter(part => part.length > 0);
        rows.push({
            "key": device.key,
            "name": name(device),
            "kind": device.kind,
            "value": value(device),
            "detail": detail.join(" / "),
            "charging": device.state === "charging",
            "low": low,
            "recovered": isRecovered(device),
            "statusState": low ? "partial" : "available"
        });
    }
    rows.sort((a, b) => a.name.localeCompare(b.name) || String(a.key).localeCompare(String(b.key)));
    return rows;
}

// Warn once per low spell: the rows that are low now and were not warned about
// yet. `warned` maps keys already warned about; a key is forgotten only once its
// device has recovered (isRecovered), not merely started charging, so it warns
// again after a real recharge. A device that disconnects keeps its key, so
// reconnecting while still low does not repeat the warning.
// Returns { warn: rows, warned: map }.
function lowWarnings(rows, warned) {
    const next = Object.assign({}, warned || {});
    const warn = [];
    for (const row of rows) {
        if (row.low) {
            if (next[row.key] !== true) {
                next[row.key] = true;
                warn.push(row);
            }
        }
    }
    for (const row of rows) {
        if (row.recovered) delete next[row.key];
    }
    return { "warn": warn, "warned": next };
}
