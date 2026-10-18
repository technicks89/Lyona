# #380: bluetooth.service enabled at install

Issue `#380`: Bluetooth was inactive after a reboot; `bluez` was installed with
the desktop but `bluetooth.service` was never enabled. Validated on 2026-10-16
with the branch `fix/bluetooth-service-enable` (based on `main` at `107d68a`).

## Change

- `archiso/airootfs/root/lyona-postinstall.sh`: the target's last chroot
  enables `bluetooth.service` when `systemctl list-unit-files` knows it, as it
  does for `lightdm.service`.
- `install.sh` (recommended and full): `bluetooth_state` and
  `configure_bluetooth` enable and start the unit when it is installed and
  not enabled, leave a masked or missing one alone, and defer to the image
  installer in its chroot. The summary lists the Bluetooth line.

## Static and unit tests

- `tests/test-arch-iso-builder.sh` (`make check-archiso`, dev host, through
  `scripts/run-tests`): PASS. The new case runs the postinstall's service
  block against a `systemctl` stub: `enable bluetooth.service` with the unit
  present, no bluetooth call without it. It fails against the postinstall on
  `main`.
- `tests/test-install-summary.sh`: PASS, in an Arch Linux ARM container with
  `/etc/os-release` set to `ID=arch` (the dev host is aarch64 Ubuntu, and
  the `archlinux:base-devel` image has no aarch64 build, so
  `scripts/ci-local.sh` could not run). Cases: off (enabled with
  `enable --now`), already enabled, masked, `not-found`, `LYONA_SOURCE=iso`
  and a chroot; the recommended summary has the Bluetooth line, core does not.
- `make check-install-step-timing`: PASS.
- ShellCheck 0.10.0 and shfmt 3.10.0 (their container images) on the changed
  scripts: shfmt clean; ShellCheck reports only findings that predate this
  change.

## Not tested

- An image install or an existing-system install in a VM, and a reboot to
  confirm `systemctl is-enabled bluetooth.service` and an adapter in the panel.
- Real hardware with a Bluetooth adapter.
- The x86_64 CI container (`scripts/ci-local.sh`).
