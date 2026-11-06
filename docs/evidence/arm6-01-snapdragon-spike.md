# ARM6-01: Snapdragon X spike on the Dell XPS 13 9345

Status: PARTLY RUN (2026-11-05, 2026-11-06). Two captures from the XPS, both of an
*installed* lyona system (root on btrfs, GRUB), not the live medium. Rows with
no entry were not observed. Plan: `docs/sprints/ARM-SPRINT-6-SNAPDRAGON-X.md`.

## Procedure

1. Build the generic medium on the Pi 4:
   `sudo scripts/build-lyona-arch-iso.sh --arch aarch64`; write the ISO to a
   USB stick. Record its sha256.
2. XPS firmware: Secure Boot off. Windows is left alone on the internal drive.
3. Boot the stick. At the systemd-boot menu press `e` and add the device tree
   (or add a `devicetree` line to a test entry on the stick):
   `devicetree /dtbs/qcom/x1e80100-dell-xps13-9345.dtb`. If the medium does
   not carry `/dtbs`, say so here: that is the first thing ARM6-02 adds.
   Record every kernel argument the boot needed.
4. On the live system run `scripts/lyona-snapdragon-spike DIR` and copy DIR
   off the machine. It is read-only.
5. By hand: internal display, keyboard, touchpad, Wi-Fi (join a network),
   USB-C (storage, and charging), sound from the speakers, suspend and
   resume, the lid, brightness keys, the battery's percentage.
6. A-10: does the medium's systemd (`systemd-ukify --version`, `bootctl
   --version`) build a UKI with `.dtbauto` and `.hwids` that boots the XPS?
   Or is `stubble` needed?

## Machine

| Item | Value |
| --- | --- |
| Model, SMBIOS `sys_vendor` / `product_name` | Dell Inc. / XPS 13 9345 (confirms `scripts/lyona-snapdragon.sh`) |
| Firmware version | BIOS 2.7.1 |
| Memory | 32 GB (31469 MiB) |
| Kernel (`uname -r`) | 7.3.1-2-aarch64-ARCH |
| Medium's sha256 | not recorded (medium: `lyona-2026.10.0-beta.7-aarch64.iso`) |
| Storage, Wi-Fi | SanDisk SN740 NVMe; Qualcomm WCN7850 (FastConnect 7800) |
| Boot | GRUB, a `devicetree` line, `efi=noruntime clk_ignore_unused pd_ignore_unused arm64.nopauth cma=128M` |

## Results

Captures: `lyona-snapdragon-spike` run three times, the third with `usbutils` and `mesa-utils` installed. All three are of the same boot's setup: the TPM argument was not yet applied (the third capture's command line lacks `systemd.tpm2_wait=0`, and `systemd-analyze` still shows 1 min 30 s).

| Area | Works? | Notes (dmesg lines, workaround) |
| --- | --- | --- |
| Boots with the device tree | Yes | Needs `efi=noruntime`: without it the boot hung (the maintainer's report, no log kept). Device tree model "Dell XPS 13 9345". |
| Boots with no device tree (ACPI) | Not tested | |
| Internal display | Yes | `eDP-1` 2560x1600 at 60 and 120 Hz (Sharp LQ134Z1). `DP-1`, `DP-2` disconnected. |
| Keyboard, touchpad | Present | Four hid-over-i2c devices; typing was not recorded separately. |
| Wi-Fi (ath12k) | Yes | wcn7850 hw2.0, connected through NetworkManager. |
| USB-C | Charging yes; hub, Ethernet and card reader enumerate | `ucsi` sources report Charging and Discharging per port. `lsusb` (third capture) shows a VIA VL813 hub with a Realtek RTL8153 Ethernet adapter, a Genesys card reader and the internal Goodix fingerprint reader. Storage was not tested. |
| GPU (`glxinfo -B`, driver `msm`) | Yes | Third capture, in an X session: direct rendering yes, freedreno on the Adreno X1-85, Mesa 26.2.6, accelerated, OpenGL 4.6 core, GLES 3.2. First capture: `gen70500_sqe.fw` missing; from the second it loads with `gen70500_gmu.bin`. |
| Battery and charging | Yes | `qcom-battmgr-bat` present; status "Not charging" while `ucsi.02` charged. |
| Audio | No | `aplay`: no soundcards, `No soundcards found` in dmesg, with the ADSP up and the q6apm modules loaded. See below. |
| Suspend, lid | Yes (maintainer's report) | Suspend and resume worked, and closing the lid worked. Not measured: resume time, battery drain asleep. `/sys/power/mem_sleep`: `s2idle [deep]`. |
| What the disabled EC (`&i2c5`) takes away | Not tested | |
| Missing firmware in dmesg | First capture: 3 files. Second: none | First: `qcom/x1e80100/dell/xps13-9345/qcadsp8380.mbn`, `qccdsp8380.mbn`, `qcom/gen70500_sqe.fw`. Second: 0 "Direct firmware load" failures. `linux-firmware-qcom` ships all of them (the XPS directory links the Lenovo 21N1 `.jsn` files). |

Other findings:

- **A 90 second splash at every boot** was `/dev/tpm0` and `/dev/tpmrm0`:
  `systemd-analyze` showed userspace at 1 min 30 s, `tpm2.target` waiting. The
  firmware reports a TPM, the kernel exposes none. systemd 262's
  `systemd-tpm2-generator` adds `tpm2.target` in that case;
  `systemd.tpm2_wait=0` turns it off. Plymouth itself took 0.2 s.
  **Confirmed 2026-11-06:** with the argument in `grub.cfg`, a normal reboot
  shows `Startup finished in 1.131s (kernel) + 1.855s (userspace) = 2.987s`
  (was 1 min 30 s). `/dev/tpm0` still does not exist; the argument only stops
  systemd waiting for it.
- **A bare `devicetree` line at the top level of `grub.cfg` fails.** A
  hand-written `/etc/grub.d/09_dtb` that only printed
  `devicetree /dtbs/qcom/x1e80100-dell-xps13-9345.dtb` looped after GRUB.
  In the generated file `00_header` has already set `root` to the btrfs
  partition, while `/dtbs` is on the EFI partition (`/boot` is vfat), so GRUB
  could not find the file. The same line typed inside a menu entry worked,
  because each entry runs its own `search` for the EFI partition first. The
  hook must call `prepare_grub_to_access_device` (so it emits `insmod fat` and
  a `search` for the EFI partition) before `devicetree`; with that, the XPS
  boots from the regenerated config. `install_snapdragon_support` already
  writes the hook that way, so its code needed no change.
- **No sound: the kernel's device tree for the XPS has no sound card.**
  Read from the running system (`/proc/device-tree`), kernel 7.3.1:
  - There is no `sound` node anywhere, so the machine driver
    (`snd-soc-x1e80100`, present as a module) has nothing to bind to. That is
    why `/proc/asound/cards` is empty and dmesg says `No soundcards found`.
  - All four soundwire controllers (`soundwire@6ab0000`, `6ad0000`, `6b10000`,
    `6d30000`) are `status = "disabled"`, and none has a child: no speaker
    amplifiers or microphone codecs are declared.
  - The audio DSP side is present and healthy: the macro codecs
    (`codec@6aa0000` and its siblings) and the GPR/APM service nodes exist, the
    q6apm modules load, and the ADSP comes up (at 7.7 s, after one
    `timeout waiting for subsystem event response`, which looks like a slow
    start, not a failure). `linux-firmware-qcom` ships the XPS topology
    (`X1E80100-Dell-XPS-13-9345-tplg.bin`), so the firmware side is ready.
  - So this is not a missing package or a Lyona bug. It is missing in the
    mainline device tree. A fix is a change to that device tree (or a
    device-tree overlay), which Lyona would have to carry or wait for
    upstream. Not attempted: it needs the XPS's speaker amplifier wiring.
- Idle: `top` shows 0.4% CPU, 979 MB used with no desktop session.

## Decisions

- A-10 (medium): **(b), systemd-stub's `.dtbauto` and `.hwids`; no `stubble`.**
  Tested 2026-11-06 on the installed XPS (systemd 262.1, Arch Linux ARM), not
  on the live medium:
  - systemd 262.1 ships `/usr/lib/systemd/boot/hwids/aa64/x1e80100-dell-xps13-9345.json`
    (eleven hardware IDs for `dell,xps13-9345`), and `systemd-ukify` 262.1 is
    in the `core` repository. `ukify` reads that directory by default.
  - `ukify build --linux --initrd --devicetree-auto=<xps13-9345 dtb>
    --cmdline ...` produced a 68 MB UKI with `.dtbauto` (212465 bytes),
    `.hwids` (19273 bytes), `.cmdline`, `.initrd`, `.linux` and `.uname`.
  - Booted as a one-shot EFI boot entry straight from the firmware (no GRUB, no
    `devicetree` line), it reached the desktop: `/proc/device-tree/model` is
    `Dell XPS 13 9345`, compatible `dell,xps13-9345`, `qcom,x1e80100`;
    `bootctl status` shows `systemd-stub 262.1-1-arch`; boot took 3.5 s. The
    test entry and `/boot/EFI/lyona-test` were removed afterwards.
  - Not covered: the live medium's own systemd (expected to match, same
    repository, but unchecked), whether the medium can carry `systemd-ukify`
    or needs the UKI built ahead of time, Secure Boot (off, the UKI was
    unsigned), and a machine with no match (ARM6-02 item 2).
- A-11 (installed system): (a) works. A `devicetree` line in GRUB, with the
  kernel arguments above, boots the installed system. `install_snapdragon_support`
  in `archiso/airootfs/root/lyona-postinstall.sh` writes both. Persisting
  them in `grub.cfg` is confirmed by hand on the XPS (2026-11-06): the
  arguments from a `grub.d` drop-in, the device tree from a hook that uses
  `prepare_grub_to_access_device`. The postinstall step itself has still not
  run on a real install.
- Confirmed DMI strings for `scripts/lyona-snapdragon.sh`: `Dell Inc.` /
  `XPS 13 9345`.

## Size of ARM6-02 to ARM6-05

- ARM6-02: A-10 is answered (b), so no new package; the work is building the UKI
  for the medium and checking the medium's systemd, not sized further.
- ARM6-03: small. Written in `install_snapdragon_support`; needs an install on
  the XPS to confirm, and a kernel update.
- ARM6-04: `linux-firmware-qcom` and `-atheros` cover the GPU, DSP and Wi-Fi
  firmware (confirmed). Sound is not a packaging problem (see above); it is
  out of ARM6-04 unless the sprint decides to carry a device-tree change.
- ARM6-05: rendering works (freedreno, accelerated), so the Picom and overview
  measurements can start.

## Sound: decision

Decision (2026-11-05, maintainer): ARM6 ships without speaker support on the
XPS 13 9345 and says so. No device-tree change is carried now.

Upstream state, from a web search on 2026-11-05 (not verified on hardware):

- Mainline has no sound node for the XPS (confirmed on the machine, 7.3.1).
- An RFC series by Abel Vesa (Linaro), 2025-10-21, adds the sound card, a
  right-to-left channel map for the XPS, and the speakers in the device tree.
  No v2 or applied status was found; a reviewer asked for a mixer control and
  UCM instead of a new compatible.
  https://patchew.org/linux/20251021-dell-xps13-9345-enable-audio-v1-0-6f3f6bbd977b@linaro.org
- Out-of-tree patches (speakers and microphones, tested on `linux-next` of
  2025-05-21) plus UCM files from a separate `alsa-ucm-conf` fork:
  https://github.com/alexVinarskis/linux-x1e80100-dell-tributo . Speakers
  there have poor sound quality and swapped channels.
- Reports of no speaker protection in the stack, so a volume cap would be
  needed before shipping it:
  https://discourse.ubuntu.com/t/dell-xps-13-9345-x1e80100-audio-stack-investigation-on-ubuntu-25-10/73248
- Other laptops: not found to benefit from a Lyona-carried change. The
  Inspiron 14 Plus 7441 and Latitude 7455 ship firmware in
  `linux-firmware-qcom`; their audio status is unknown.

Revisit when a series lands, or a kernel Arch Linux ARM ships has the
device-tree change. Headphone and USB-C audio paths were not tested.

## Install on a USB drive (2026-11-06)

A first install of the generic medium onto a 64 GB USB drive (root btrfs on
`sda2`, GRUB, removable path). It is a spike on a throwaway target, not a
validation: see ARM6-06.

- **The medium predates the step.** The stick's ISO was built 2026-11-05 13:34;
  `install_snapdragon_support` landed in commit `9183e39` at 20:51. So this
  install ran without it: no `linux-firmware-qcom`, no `90-lyona-snapdragon.cfg`,
  no `09_lyona_dtb`, and `/var/log/lyona-postinstall.log` has no Snapdragon
  line. DMI read `Dell Inc.` / `XPS 13 9345` and `/boot/dtbs/qcom/` held the
  XPS device tree, so the step would have matched. It has not yet run for real.
- **The live medium needs a menu entry with a `devicetree` line, and
  systemd-boot's editor cannot add one.** `e` edits only `options`. The stick's
  `loader.conf` has `timeout 0`, so the menu also never shows without a held
  key. Booting needed `/dtbs/qcom/x1e80100-dell-xps13-9345.dtb` and an entry
  copied onto the stick's ESP by hand. That is ARM6-02's work.
- **The first USB root errored.** On the first boot of the installed system
  btrfs went read-only after `run_delalloc_nocow failed ... -EIO` repeated for
  two inodes, and the first reboot hung on a blank screen. Another USB port
  and `usbcore.autosuspend=-1` ran clean after that (no btrfs, I/O or USB reset
  lines in the journal); the cause (port, power management or the drive) was
  not isolated.
- **Persisting GRUB by hand works.** `/etc/default/grub.d/90-lyona-snapdragon.cfg`
  (the kernel arguments) and `/etc/grub.d/09_lyona_dtb` (the hook, as the
  postinstall writes it) booted the XPS with no menu edit: the journal shows
  `Machine model: Dell XPS 13 9345` and the arguments once each. A
  `devicetree` line is printed at the top level of `grub.cfg`, so the entry
  editor does not show it.
- **Firmware: `linux-firmware-qcom` resolves** (`core`, 20261019-1, 174 MiB
  download, 562 MiB installed); `pacman -Si` finds it on aarch64. Without it the
  boot log shows `qcadsp8380.mbn`, `qccdsp8380.mbn` and `gen70500_sqe.fw` not
  found; `linux-firmware-atheros` alone gives working ath12k Wi-Fi.
- **With the package installed, the USB-root machine died about one second
  into userspace** (the persistent journal ends at `Starting Coldplug All udev
  Devices`), with a grey screen and no console, also under `nomodeset`. Moving
  `qcom/x1e80100/dell/xps13-9345/` aside offline made it boot. That directory
  holds the DSP images (`qcadsp8380.mbn`, `qccdsp8380.mbn`, `adsp_dtbs.elf`,
  `cdsp_dtbs.elf`), the audio topology **and the GPU's zap shader
  `qcdxkmsuc8380.mbn`**. With the directory gone the GPU failed
  (`Unable to load ... qcdxkmsuc8380.mbn`, `gpu hw init failed: -2`, GMU OOB
  timeout). Putting back only the zap shader gave a clean GPU start
  (`gen70500_sqe.fw`, GMU v4.3.17 and the zap shader all loaded) and a
  booting system, so the hang is tied to starting the ADSP or CDSP, not the
  GPU. Which of the four DSP files matters was not bisected.
  Hypothesis: the DSPs coming up completes `sync_state()` for the
  interconnect, clock and power-domain providers (the log shows it pending on
  both remoteprocs), which disturbs a USB root. **Tested on the NVMe install
  below: the same firmware boots fine there** (both DSPs `running`), so the
  hang was specific to the USB root. The cause on a USB root was not isolated;
  `modprobe.blacklist=qcom_q6v5_pas` (a module, `CONFIG_QCOM_Q6V5_PAS=m`) keeps
  the DSPs from starting for one boot, if it is ever needed.
- **The battery stays unreadable** while the ADSP is down: `qcom-battmgr-*`
  exist, `capacity` does not.
- **Ethernet:** the Realtek dongle logs `r8152 ...: USB reset failed,
  errno=-19` and disappears on every boot (both USB roots tried). Not
  isolated.
- **The first screens had empty boxes for text, a banded wallpaper and a
  terminal that would not open**, while the USB root was erroring. With the
  filesystem healthy there are 718 fonts and `fc-match sans-serif` is Noto
  Sans; whether the panel renders now was not re-checked.

## First run of `install_snapdragon_support` (2026-11-06)

Rebuilt medium (commit `9183e39`, sha256 `899fc32c...`, its postinstall byte-identical
to the commit's), installed onto the XPS's internal NVMe. The closing screen
said: "The Snapdragon X laptop's device tree or firmware was not set up; it
may not boot or lack sound and graphics." (the step returned non-zero).

- **Cause, reproduced from the source (the XPS log was not read):** `run_logged`
  runs each step in a fresh `bash -c`, so only the functions in the
  postinstall's `export -f` list exist there. That list had `dwm_packages`
  but not the helpers it calls, `dwm_aarch64_only` and `dwm_x86_64_only`. In a
  fresh shell `dwm_packages arch soc-snapdragon` prints `dwm_aarch64_only:
  command not found`, returns 127 and no names, so `pacman -S` got no
  targets and the step returned 1. `tests/test-snapdragon.sh` sourced the
  files directly and never saw it.
- **The same gap predates this sprint** (`dwm_x86_64_only`, ARM1-02): the
  NVIDIA driver profiles use it, so a driver install from a `run_logged` step
  would resolve no packages. Shown for `dwm_packages arch gpu-nvidia`; a real
  x86 NVIDIA install was not run.
- **Fix:** the two helpers are added to the `export -f` list, and the test now
  runs the profile in a fresh shell with only the postinstall's exported
  functions. It fails without the fix (the message above) and passes with it.
  Not yet proved on the XPS: that needs a rebuilt medium.
- **Log confirmation (read from the XPS, `/var/log/lyona-postinstall.log`):**
  `[step 9/18] Setting up a Snapdragon X laptop...`, then `environment: line 83:
  dwm_aarch64_only: command not found`, `error: no targets specified`, `failed
  (exit 1) after 1s`. Exactly the reproduced failure.
- **`linux-firmware-qcom` was not installed by the step:** `pacman.log` shows an
  explicit `pacman -S --needed core/linux-firmware-qcom` at 13:52, after the
  install, during the first-boot session.

### The NVMe install, with the firmware and the by-hand GRUB files (2026-11-06)

The step's two GRUB files (`90-lyona-snapdragon.cfg`, `09_lyona_dtb`) written
by hand, `grub-mkconfig` regenerated, then a normal reboot. On the internal
NVMe, root btrfs `rw`, `/boot` the vfat ESP:

- **Boots with no menu edit** (`Machine model: Dell XPS 13 9345`, the arguments
  once each, `systemd.tpm2_wait=0` included).
- **Both DSPs start and the machine stays up:** `remoteproc0 adsp running`,
  `remoteproc1 cdsp running` (`Booting fw image qcom/x1e80100/dell/xps13-9345/...`,
  `remote processor ... is now up`). The USB-root hang did not occur.
- **The battery works:** `qcom-battmgr-bat` reports `energy_now`/`energy_full`
  55 Wh, 12.84 V, 30.5 C, 10 cycles, `status Not charging`; UPower shows 100%,
  fully-charged. The kernel exposes no `capacity` file, so a percentage must
  come from UPower (the shell's `PowerModel.qml` uses `UPower.displayDevice`).
- **The GPU starts cleanly:** `gen70500_sqe.fw`, GMU v4.3.17, `msmdrmfb`,
  `/dev/dri/card0` and `renderD128`; no zap-shader or `gpu hw init` errors.
- **Wi-Fi works** (ath12k, `wlP4p1s0` up). The Ethernet dongle was not plugged
  in, so `r8152` was not exercised.
- **No sound card** (`/proc/asound/cards` empty), as decided above. With the DSPs
  up the log has `qcom-apm ... CMD timeout`, `fastrpc`/`qrtr` endpoint
  failures (`-12`) and `va_macro ... dmic-sample-rate dt entry missing`, which
  are the audio path without a sound node. `autorandr.service` failed to start:
  `ProcessLookupError: [Errno 3] No such process: '/proc/948/environ'`, a race
  in autorandr's session scan while a process exits at login (boot-time, not
  seen to recur; the unit is a sleep-target hook, `WantedBy=sleep.target`).
- **Shell versus apps scale (not ARM-specific; to be filed on Lyona).** The
  panel is 2560x1600 on 288x180 mm (about 226 DPI) but X reports 96 DPI, and
  nothing sets a DPI: no `Xft.dpi` in the X resources, no `Xft/DPI` in
  `xsettingsd.conf`, no `dpi.current`. Quickshell is launched with
  `QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1` (`scripts/autostart.sh:311-319`)
  and `Theme.displayDpi` defaults to 96 (`config/quickshell/core/Theme.qml`),
  so `uiScale` is 1.0 and the shell is drawn at 96-DPI pixels, while the
  terminal (Alacritty, size 11) and other apps pick their own scale. Fix
  direction, untested: derive a default DPI from the panel's physical size, or
  ask on first run, when no DPI is saved.

## Reinstall with the fixed medium (2026-11-06)

Medium rebuilt on the Pi 4 from the working tree with the export fix (not yet
committed): `lyona-2026.10.0-beta.7-aarch64.iso`, sha256
`6f49018c31fbf047d895aa3a911feeb319749dc56d0c4b96aca8c131de1ee96a`, volume ID
`2026-11-06-18-49-36-00`. Its `lyona-postinstall.sh` (sha256 `c9f428ce...`), `lyona-snapdragon.sh`
and `dwm-packages.sh` are byte-identical to the working tree's. Installed onto
the XPS's internal NVMe (the wizard's disk choice, root btrfs, `/boot` the vfat
ESP), with no hand-made GRUB or firmware changes, then rebooted with no edit.

- **The step ran and worked.** `pacman.log`: `pacman -S --noconfirm --needed
  linux-firmware-qcom linux-firmware-atheros` at 15:11:31, right after
  `pacman -Syu`, before NetworkManager. `/etc/default/grub.d/90-lyona-snapdragon.cfg`
  and `/etc/grub.d/09_lyona_dtb` exist, root-owned, with the content the
  step writes. The installer's closing screen was not photographed; the
  maintainer reported no failure.
- **It booted straight through with no GRUB edit:** `Machine model: Dell XPS 13
  9345`, `efi=noruntime clk_ignore_unused pd_ignore_unused arm64.nopauth
  cma=128M systemd.tpm2_wait=0` once each.
- **adsp and cdsp `running`; the battery shows at first boot** (UPower 100%,
  fully-charged, 55 Wh); `/dev/dri/card0` and `renderD128`, no zap-shader or
  GPU init errors; no failed units (`autorandr.service` did not fail this
  time); root btrfs `rw`.
- **The medium's boot looks hung for 2 to 3 minutes** with the debug options
  removed (`quiet loglevel=3`) and `copytoram=y`: nothing is drawn while the
  1.4 GB image is copied from the stick into RAM. ARM6-02 should show progress
  or avoid the silent copy. The first spike entry (`loglevel=8`) printed
  kernel lines over gum's screen, which `quiet loglevel=3` removed.
- Wi-Fi was used for the install. **Ethernet works on this NVMe install**
  (checked afterwards, with the dongle plugged in): the Realtek RTL8153 comes up
  as `enu1u4` through `r8152` (`reset SuperSpeed USB device`, `carrier on`), takes a DHCP lease
  and gets a route beside Wi-Fi. The `USB reset failed, errno=-19` seen on the two USB
  roots did not occur, so that failure belonged to those installs, not to the
  adapter or the kernel.
- **Sound stays a known issue on this model** (maintainer, 2026-11-06): no card
  (`/proc/asound/cards` empty), for the device-tree reason in "Sound: decision",
  with the topology firmware and the DSPs already in place. No change carried; a
  speaker spike would need a volume cap first (no speaker protection in the
  stack) and is not planned.

## Brightness keys

Not tested, and not pursued: the XPS 13 9345's function row is touch-sensitive,
which few laptops share (maintainer's note). The backlight device itself is
present (`dp_aux_backlight`, 717 of 1023), so brightness is settable from
software; whether the touch keys send key events is unrecorded.

## Not tested

ACPI boot (the medium and the install booted from the device tree), USB-C
storage, suspend's resume time and drain, the touchpad's gestures, external
displays, a kernel update, the medium booting
without a held key or a hand-copied entry (ARM6-02), and speakers (see Sound:
decision).
