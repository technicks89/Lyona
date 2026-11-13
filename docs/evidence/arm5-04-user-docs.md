# ARM5-04: ARM user documentation

ARM Sprint 5 item ARM5-04 (issue #21). Written 2026-11-12. Documentation and
the bug report form; no new runs. Each instruction is taken from the evidence
of the run that validated it, or from the code it describes.

## What changed

- `docs/src/install.md`, new "Install on ARM (aarch64)":
  - a table of machines, what to use and their status (as `SPEC.md` section 4),
    and where the aarch64 images are published and how to check them;
  - **the generic aarch64 image:** writing it, Secure Boot off, UEFI only, no
    boot menu, at least 1.5 GiB of memory, the wizard's differences, and the
    virtual machines validated (`arm2-05-generic-image.md`,
    `arm6-02-live-medium.md`);
  - **Snapdragon X laptops:** the XPS 13 9345 steps (the copy into memory and
    the short black screen, the internal drive holding Windows, what the
    install adds), its known gaps, and that other laptops do not boot after an
    install yet (`arm6-01` to `arm6-06`, `scripts/lyona-snapdragon.sh`);
  - **the Raspberry Pi image:** writing it with Raspberry Pi Imager or
    `xzcat | dd`, the first boot and its wizard, and the Pi 4's Picom, Suspend
    and `custom.txt` (`arm3-02-pi-first-boot.md`, `arm3-06-raspberry-pi.md`,
    `rpi/lyona-firstboot.sh`);
  - **what is different on ARM** and **reporting a problem on ARM**.
  The existing-system section's Arch Linux ARM paragraph links to it.
- `docs/src/troubleshooting.md`, new "ARM (aarch64)": the generic image not
  booting (Secure Boot, too little memory, a Pi), the slow start on a
  Snapdragon laptop, another Snapdragon laptop not booting after the install,
  no sound on the XPS, the device-tree hook's warning after a kernel update,
  systemd-networkd on Arch Linux ARM (`arm1-06` F-1), the locale (F-3),
  `lyona-update` before an aarch64 release (#53), and harmless messages
  (`arm3-06`, `arm6-06`).
- `.github/ISSUE_TEMPLATE/bug_report.yaml`: "Architecture and session" is
  split into an architecture dropdown (`x86_64`, `aarch64`), the machine or
  board (with the commands that print it), what it was installed from, and
  the kernel and session.
- `docs/RELEASING.md`: the Raspberry Pi image's heading no longer says
  "experimental" (missed by ARM5-03).

## A correction to ARM5-03

ARM5-03 described the other Snapdragon X laptops as "should work, not tested",
from the sprint plan. Writing these steps showed that this holds for the
medium only: it carries every `x1e*` and `x1p*` device tree with systemd's
hardware-ID table, but the install's step (`lyona_snapdragon_dtb` in
`scripts/lyona-snapdragon.sh`) maps only `Dell Inc.|XPS 13 9345`, as
`arm6-03-installed-device-tree.md` says under "Not tested". On another laptop
the installed system has no device tree and will most likely not boot. Their
status stays experimental; the `SPEC.md` row, the install guide and the
troubleshooting page now say so.

## Acceptance

"A user can install each target from the docs alone." Checked by reading the
new sections against the runs: every step a supported target needs (download,
check, write, firmware settings, the wizard or first boot, what to expect
afterwards) is in the guide. Not checked by a person following the docs alone
on each target.

## Not tested

- No install was run from these docs. The Raspberry Pi Imager steps and the
  `xzcat | dd` command were not run for this item; the Pi was written with
  Imager in ARM3-06.
- The bug report form was not rendered on GitHub: no YAML parser was
  installed here, so it was checked by reading. It renders only from the
  default branch.
- The mdBook build of `docs/src` (mdBook is not installed here). The new
  pages' internal anchors were checked against their headings with a script
  that follows mdBook's slug rules: none missing.
- The device-tree hook's warning and the rollback to the previous kernel
  package in the troubleshooting page are from the code, not seen on the
  hardware (as `arm6-03` says).
