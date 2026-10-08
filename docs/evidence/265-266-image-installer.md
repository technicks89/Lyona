# #265, #266: the image installer's keyboard and recovery, in a VM

Issues `#265` (the chosen keyboard layout was not used for the passwords) and
`#266` (a failed archinstall had no recovery menu; no way back in the wizard).
Branch `iso-keymap-recovery`.

## The image (2026-10-08)

| | |
| --- | --- |
| Image | `lyona-2026.10.0-beta.5-x86_64.iso`, built from this branch's working tree |
| SHA-256 | `30733ec7d1171b466a1b833bb003743fe0e8fa8c658a03ba4366ecd2a279be03` |
| Build host | Arch Linux, kernel 7.2.9-1-cachyos, archiso 91-1, squashfs-tools 4.6.1-2 (releng copy with `-Xbcj x86` only) |
| Architecture | x86_64 |
| VM | QEMU 11.1.2 (qemu-base), KVM, q35, 4 GB, 4 CPUs, OVMF (UEFI), `-vga std`, virtio disk 24 GB, user networking |
| GPU and driver path | QEMU standard VGA; no NVIDIA GPU, so no driver question |

The wizard was driven on the VM's own console with QEMU monitor `sendkey`,
which sends physical keys (scancodes), not characters, as a user's keyboard
does. Screens were checked with `screendump`.

## #265: the keyboard

- The keyboard screen is a searchable list: the common layouts by name
  ("French (fr)", "Swedish (sv-latin1)", "Turkish (trq)", "Slovenian
  (slovene)"), then every console keymap. Typing `French` filtered it.
- **French chosen, applied at once.** The username was typed with the physical
  keys `a n i c k` and showed `qnick`: the console was AZERTY from then on (the
  second console too, `tty2`). Before the change it would have shown `anick`.
- **Both passwords typed with the physical keys `a q z w m l k`** (`qawz,lk` on
  AZERTY, `aqzwmlk` on US), for LUKS and for the user.
- **Installed, then booted from the disk alone:** the same physical keys at
  the boot-time LUKS prompt unlocked the disk, and at LightDM logged in to the
  lyona desktop. Before the change, the wizard's US-typed passwords would not
  have matched what the same keys type at either prompt.

## #266: going back, changing an answer, and Retry

- **Timezone:** "No", then Esc in the list: the first Esc leaves the search
  field (gum's own behaviour), the second returns to "Detected timezone:
  America/New_York. Is this correct?". The wizard did not end.
- **Mirrors:** "Choose another", then Esc twice: back at "Download packages
  from mirrors in United States?".
- **Summary:** the choices are Cancel (first, selected), Change an answer...,
  Wipe /dev/vda and install. Change an answer... > Hostname > `frtest`: the
  summary came back with `Hostname: frtest`.
- **Retry:** while archinstall ran, it was killed from `tty2`
  (`pkill archinstall`) after it had opened the LUKS volume and mounted it on
  `/mnt` (`lsblk`: `vda2` > `root` crypt on `/mnt`, `vda1` on `/mnt/boot`).
  The wizard showed "lyona-install failed (exit 143)", the end of the log, the
  hint "/dev/vda may already be erased and partly installed; nothing else on
  this machine was changed. Retry runs archinstall again with your answers."
  and Retry / View full log / Exit to shell. Retry released `/mnt` and the
  LUKS volume and ran archinstall again with the same answers, without asking
  anything; it was past its disk steps 90 s later.

That first VM's disk image was on the session's RAM-backed `/tmp`, which
filled during the retried install, so that run was stopped there. The
install above, reaching LUKS and LightDM, was a second run with the same
answers (without Esc, Change an answer... or Retry), its disk under
`~/tmp`; it completed in 280 s.

## Found, and changed after the run

- The "Keyboard set to fr: the passwords below are typed with it." line was
  cleared by the next screen at once. The password prompts now name the
  layout instead ("Password (keyboard: fr):"); covered by
  `tests/test-iso-install-recovery.sh`, not seen in a VM.

## Found, not changed

- After Esc in a list, gum prints "nothing selected" at the left edge.
- When Retry runs archinstall again, the failed run's output stays on the
  screen above the new progress line.

## Not tested

- Legacy BIOS; real hardware; an NVIDIA GPU.
- Other layouts in a VM (German, a non-Latin one); the list's names are
  checked against `localectl list-keymaps` by the test.
- `loadkeys` failing (covered by the test); Exit to shell after a failure in
  a VM (covered by the test).
- A postinstall failure in steps 1-7 (the hint is checked statically).
