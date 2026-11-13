# #92: the installed system's device tree on any Snapdragon X laptop

Issue #92, found while writing ARM5-04 (#21). Written 2026-11-12.

## The problem

The generic aarch64 medium boots any Snapdragon X laptop with a mainline
device tree: its kernel carries every `x1e*` and `x1p*` tree with systemd's
hardware-ID table, and systemd-stub picks the laptop's tree at boot (A-10,
ARM6-02). The install's step, `install_snapdragon_support` in
`archiso/airootfs/root/lyona-postinstall.sh`, asked `lyona_snapdragon_dtb`
(`scripts/lyona-snapdragon.sh`) for the tree, and that function knew one DMI
entry, the XPS 13 9345. On any other laptop the step added nothing, and the
installed system booted without a device tree.

## The change

`lyona_snapdragon_dtb` now names the tree in two ways, in this order:

1. The DMI table, unchanged: the XPS 13 9345, validated in ARM6-06. An entry
   there also overrides way 2.
2. The tree the medium booted with. The running kernel's
   `/sys/firmware/devicetree/base/compatible` starts with the board's name
   (for example `lenovo,thinkpad-t14s`). Among the new system's
   `/boot/dtbs/qcom/x1e*.dtb` and `x1p*.dtb`, leaving out the `-el2` trees,
   the one whose root `compatible` starts with the same name is the answer,
   when exactly one does. None, or more than one, gives nothing, as before.

The root `compatible` of a tree is read by a new helper,
`scripts/lyona-dtb-compatible`: a flattened-device-tree reader in Python's
standard library (the live medium has Python for archinstall). It is not
installed: the postinstall runs it from the medium's embedded checkout. It
reads only the root node's properties, so a child node's `compatible` is never
taken for the board's. The rest of the step was already the same for every
Snapdragon X laptop (the `soc-snapdragon` firmware, the kernel arguments, the
GRUB hook and the pacman check), and is unchanged.

A machine with no running device tree (a virtual machine, an ACPI server) is
unchanged, as is any device-tree machine whose board has no Snapdragon X tree.

## Validation

- `tests/test-snapdragon.sh` (`make check-snapdragon`), with real flattened
  device trees written by the test: a ThinkPad T14s gets its tree and not its
  `-el2` one; an X Plus laptop (`x1p*`) gets its tree; a board named only by a
  child node, a non-Snapdragon board and x86_64 get nothing; two trees for one
  board give nothing; the XPS's DMI entry wins over the running tree; a file
  that is not a device tree is skipped. The postinstall step, run against a
  staged target as the XPS case is, installs the firmware, writes the kernel
  arguments and a GRUB hook naming the T14s's tree. Pass.
- A mutation check: with the `-el2` filter removed, the test fails ("the T14s
  did not get its device tree").
- The helper against real kernel trees: the maintainer's Raspberry Pi 4
  (`linux-rpi`, 28 trees under `/boot`). It read all 28; the running board,
  `raspberrypi,4-model-b`, matched exactly `bcm2711-rpi-4-b.dtb`, and
  `raspberrypi,5-model-b` matched three trees, the case where the lookup
  declines to guess. The helper was streamed to `python3` over SSH; nothing
  was written on the Pi.
- `make check-archiso`: pass. ShellCheck on the changed scripts: clean.

## Not tested

- Any Snapdragon laptop but the XPS 13 9345: there is no other one to test.
  Other laptops stay experimental (`SPEC.md` section 4).
- The new path on the XPS itself, on the live medium: it was not reachable on
  2026-11-12. The XPS takes way 1, unchanged, so its validated install path is
  the same.
- The helper against Arch Linux ARM's `linux-aarch64` Snapdragon trees: only
  against the Pi's trees and the test's.
- shfmt: not installed here; CI runs it.
