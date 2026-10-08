# #243: peripheral battery levels, checked with real devices

Issue `#243`. Design: `docs/plans/243/README.md`.

## Machine (2026-10-08)

Development machine: Arch Linux, UPower 1.91.5, Quickshell 0.3.1, kernel
7.2.9-cachyos. Devices UPower reported:

| Device | Native path | UPower kind | Power supply | UPower reading |
| --- | --- | --- | --- | --- |
| Logitech MX Master 2S, on its USB receiver | `hidpp_battery_3` | mouse | no | `battery-level: full`, `percentage: 100% (should be ignored)` |
| CyberPower CP1500PFCLCDa UPS, USB | `.../usbmisc/hiddev1` | ups | yes | `percentage: 100%` |

The mouse is the coarse-level case: its kernel power supply has
`capacity_level` (`Full`) and no `capacity` file, and UPower itself says to
ignore its percentage.

## What the shell made of them

This branch's `PowerModel` in a separate Quickshell instance on an Xvfb
display, reading the real UPower service on the system bus:

```
rows: [{"key":"hidpp_battery_3","name":"MX Master 2S","kind":"mouse","value":"Full",
        "detail":"Mouse / Fully charged","charging":false,"low":false,"statusState":"available"}]
```

- The mouse is listed by its model name, with the word **Full**, not UPower's
  "ignore me" 100%.
- The UPS is not listed (a power supply, and a UPS).
- The system battery value was unchanged by the change: it still reads
  `UPower.displayDevice`.
- No low-battery notification: the mouse is full.

The real Settings > Power pane, rendered in the same way, shows a **Devices**
section under "Battery and external power" with one card: "MX Master 2S",
"Full", "Mouse / Fully charged", in the normal status colour (dark theme).

## Found on the way, not changed

UPower folds the UPS into its display device, so on this desktop without a
laptop battery the existing "Battery" card and panel indicator show 100%. That
is how `UPower.displayDevice` has always been used here, not part of #243.

## Not tested

- A Bluetooth device's battery (none was available), a device that is
  charging, a percentage-reporting peripheral, and a real drop below 15% (the
  warning rule is covered by `tests/qml/tst_peripheral_batteries.qml`).
- A device connecting and disconnecting while the shell runs: it follows from
  `UPower.devices` being a live model, and was not exercised by hand.
- The Control Center rows were not rendered: they show the same rows with the
  standard `MenuRow`, and lint and the static test cover the wiring.
- The light theme was not rendered: the new cards use the same `StatusCard` and
  theme colours as the rest of the pane.
