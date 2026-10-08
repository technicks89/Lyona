# #243: peripheral battery levels

Issue `#243`. Branch `peripheral-batteries`, one commit: "Show peripheral
battery levels (#243)". Written with the change; the code is in the diff, and
this records the design and the decisions behind it.

## Decisions (2026-10-08)

- Included from the issue's optional items: the low-battery warning and the
  level in the Control Center. Not included: a panel indicator.
- The real-device check uses the development machine's Logitech MX Master 2S on
  its receiver (`hidpp_battery_3`), which reports only a coarse level. The
  machine had no UPower service; the maintainer installed `upower` for the check.

## Where the data comes from

Quickshell's UPower service: `UPower.devices` is a live model, and each
`UPowerDevice` signals its own changes (`percentage`, `state`, `ready`,
`isPresent`, `model`, `type`). Nothing polls, and `upower` output is never
parsed (AGENTS.md).

Quickshell does not expose UPower's `BatteryLevel`, the coarse level the issue
asks to show as a word. UPower reads it from the kernel's `capacity_level` for
the same power supply, which the device's `nativePath` names (for example
`hidpp_battery_3`). So for a device whose native path is a power-supply name,
the shell reads `/sys/class/power_supply/NAME/capacity` and `capacity_level`
with two `FileView`s: no `capacity` file means a coarse device, and its
`capacity_level` is shown. Both files are read when the device appears and
again only when UPower signals a change for it (sysfs cannot be watched). A
device is not shown until that check is done, and a coarse one until its level
has been read too, so it never flashes UPower's approximate percentage (which
UPower itself says to ignore). A device without a `capacity` file and without a
readable level has no reading and is not shown. Bluetooth devices (native path `/org/bluez/...`) report a
percentage through BlueZ and have no such files.

## The pieces

| File | What |
| --- | --- |
| `config/quickshell/power/PeripheralBatteries.js` | Pure: which devices are peripherals, their name, value and detail, low detection, and the warn-once rule |
| `config/quickshell/power/PowerModel.qml` | One watcher per UPower device (`Variants` over `UPower.devices.values`), the `peripherals` rows, and the low-battery notification |
| `config/quickshell/settings/PowerSettingsPane.qml` | "Devices" section under "Battery and external power", hidden when empty |
| `config/quickshell/controlcenter/ControlCenterWindow.qml` | Read-only rows at the end of the power page, hidden when empty |
| `tests/qml/tst_peripheral_batteries.qml` | Fake device lists: mouse at 40%, keyboard with a coarse level, a laptop battery and line power that must be excluded, an empty list, naming, charging, low and warn-once |
| `tests/test-quickshell-power-model.sh` | Static: UPower device list, no Timer/Process/file watch, the views hide when empty, #310's `scope != "Device"` rule intact |

The rules:

- **A peripheral** is a ready device with a charge reading (and, for the
  battery kind only, present: UPower's IsPresent means nothing for the others)
  that is not
  the machine's own supply (`powerSupply`, `isLaptopBattery`) and not line
  power, a UPS, a monitor, a computer, a network device or a modem. So the
  laptop battery is never listed, and peripherals never change the system
  battery value or the panel indicator, which still read
  `UPower.displayDevice`.
- **Name:** the model UPower reports, else the kind ("Mouse", "Game
  controller", ..., "Device").
- **Low:** under 15%, or a coarse Critical or Low, and not charging or full.
- **Warning:** one `notify-send` through the session's notification server
  when a device becomes low; not again until it has recovered, that is reached
  15% or a coarse Normal, High or Full. Charging alone does not reset it, so a
  device plugged in at 5% and unplugged at 6% is still the same low spell. A device
  that disconnects while low keeps its "warned" mark, so reconnecting it does
  not repeat the warning. The process is started with `Quickshell.execDetached`
  only at that moment: nothing resident.
- **Idle cost:** one shared `PowerModel`, as before. Its watchers hold no
  timers or processes; they react to UPower's signals.
- **#310:** `scripts/dwm-settings-display-profiles` is untouched; it still
  ignores `scope=Device` batteries when deciding whether this is a laptop.

## Docs

SPEC.md (Settings requirement list), `docs/src/control-center.md`,
`docs/src/troubleshooting.md` (BlueZ's experimental battery provider, which
lyona does not turn on for the user), CHANGELOG.

## Validation

- `tests/qml/tst_peripheral_batteries.qml` (Qt 6 `qmltestrunner`, also run by
  `make check` through `tests/test-quickshell-system-discovery-cycle.sh`).
- `tests/test-quickshell-power-model.sh`, `tests/test-quickshell-plain-text.sh`,
  `make check-quickshell-qml` (no warnings in the changed files).
- `scripts/run-tests make -k check`.
- The real devices: `docs/evidence/243-peripheral-batteries.md`.
