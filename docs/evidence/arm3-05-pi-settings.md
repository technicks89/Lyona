# ARM3-05: Settings on a Raspberry Pi

ARM Sprint 3 item ARM3-05 (issue #16), built 2026-10-27 on the maintainer's
x86_64 host: the changes, their tests, and a read of every Settings pane for
what a Pi lacks. No Pi ran it: the image with these changes is ARM3-06's
run, and the list at the end says what it has to look at.

## What a Pi lacks, pane by pane

| Pane, row | On a Pi before | Now |
| --- | --- | --- |
| System Information, Board | No row; the device tree's model was read only as the processor's fallback, which a Pi 4 or 5 never reaches (Lyona names their Cortex-A72 and A76 cores) | A Board row with the device tree's model ("Raspberry Pi 5 Model B Rev 1.0") |
| System Information, temperature | None in Settings; only System Health's "Thermal sensors" check, the highest of every zone | A Processor temperature row from the `cpu-thermal` zone, in degrees Celsius |
| Privacy and security status, Secure Boot | "Unknown", in the warning colour, "Information source is absent" | "Not supported", in the caption colour: "This machine did not start through UEFI firmware, so it has no Secure Boot" |
| Power, Suspend | From logind's `CanSuspend`: "Suspend is not supported by this system" when logind says so; the power menu leaves Suspend out then | Unchanged |
| Power, hibernate | Settings never offers it: the lid policy row shows logind's `HandleLidSwitch` settings read-only, and the power menu has no Hibernate | Unchanged |
| Power, laptop lid | UPower's `LidIsPresent`: "No lid hardware is present" | Unchanged |
| Firmware and boot entries | Settings has no such pane | Nothing to hide |
| Backlight | Settings has no backlight control; an HDMI display's brightness is the display's own | Nothing to hide |
| Updates | `lyona-update` installs with `make install-system`, and package updates go through PackageKit and pacman; neither has a bootloader step (`grub-mkconfig`, `bootctl`, `efibootmgr`). `linux-rpi` writes its kernel, device trees and initramfs to `/boot` from its own package files and mkinitcpio hook | Unchanged |

## The two new rows

1. **Board** (`board-model`): `/sys/firmware/devicetree/base/model`, read
   with a 256-byte cap, its trailing NUL taken off, and shown only as
   printable UTF-8. There is no SMBIOS fallback, as the processor's has: a
   UEFI machine's firmware name is already Hardware model, from hostname1.
   Without a device tree the state is `unsupported` and Settings leaves the
   row out.
2. **Processor temperature** (`cpu-temperature`): the first of
   `/sys/class/thermal/thermal_zone0` to `thermal_zone31` whose `type` is
   `cpu-thermal` (a Pi 4's bcm2711 and a Pi 5's bcm2712 device trees name
   their only zone so), `soc-thermal`, their underscore spellings, or
   `x86_pkg_temp` (Intel). Other zones (ACPI, Wi-Fi, a battery) are not the
   processor and are skipped; an AMD processor reports through hwmon, not a
   thermal zone, so the row is left out there. The value is the kernel's
   millidegrees, as canonical decimal text, which Settings shows as "48.3 C"
   (ASCII, as System Health writes it). It is read once per snapshot, like
   the memory and uptime rows, with no polling.

Neither row's absence degrades the System information provider: an
`unsupported` Board or Processor temperature is sent, but leaves the
provider's status `available` (`INFORMATION_OPTIONAL_IDS`, `snapshots.py`),
as a machine without a device tree is not a failed read. A failed read of
either (denied, malformed, an I/O error) degrades it as any other row does.

Any other `unsupported` state now reads "Not supported" in the caption
colour, rather than "Unknown" in the warning colour: it is the machine's,
not a failed read. "Unknown" stays for a partial, restricted or unavailable
read.

## Tests

- `tests/test-system-management.py`: `BoardAndTemperatureTests` (the
  device tree's model and never SMBIOS, the byte cap, undisplayable names,
  the first processor zone, zones that are not the processor, the 32-zone
  bound, malformed and denied readings); the local reader's fixtures gain a
  device tree and a `cpu-thermal` zone; the snapshot's state count is 23;
  `test_optional_rows_a_machine_lacks_leave_its_provider_available`; the
  Secure Boot wording without UEFI.
- `tests/qml/tst_system_information_protocol.qml`: the two identifiers and
  canonical millidegrees (no `-0`, leading zero, decimal point or sign).
- `tests/qml/SystemInformationUi.qml` (`make
  check-quickshell-information-ui-xvfb`): the Board row left out without a
  device tree and shown with one, the temperature in degrees, "Not
  supported", and a required row never left out.
- `tests/test-quickshell-system-management-xvfb.sh`: the fixture provider
  sends both rows.

On this host (AMD, UEFI) the real readers return `unsupported` for both
rows (its one thermal zone is `iwlwifi_1`) and Secure Boot `disabled`.

## Not tested

- A Pi: the device tree's model, the `cpu-thermal` zone and the missing
  `/sys/firmware/efi` on a Pi 4 and a Pi 5 come from the kernel's sources,
  not from the boards. ARM3-06 checks each pane opens without an error and
  records what it shows.
- What logind's `CanSuspend` answers on a Pi under `linux-rpi`, and whether
  a suspend then resumes: ARM3-06 records it. Settings follows logind's
  answer either way.
- A kernel update on a Pi through Settings' updates, and a reboot into it:
  ARM3-06's "an update and a rollback".
- An Intel machine's `x86_pkg_temp` zone: from a fixture only.
