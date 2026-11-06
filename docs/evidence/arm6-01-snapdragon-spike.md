# ARM6-01: Snapdragon X spike on the Dell XPS 13 9345

Status: PARTLY RUN (2026-11-05). Two captures from the XPS, both of an
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

- A-10 (medium): not answered; the live medium was not booted with the
  XPS's device tree in these captures.
- A-11 (installed system): (a) works. A `devicetree` line in GRUB, with the
  kernel arguments above, boots the installed system. `install_snapdragon_support`
  in `archiso/airootfs/root/lyona-postinstall.sh` writes both.
- Confirmed DMI strings for `scripts/lyona-snapdragon.sh`: `Dell Inc.` /
  `XPS 13 9345`.

## Size of ARM6-02 to ARM6-05

- ARM6-02: not sized (A-10 open).
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

## Brightness keys

Not tested, and not pursued: the XPS 13 9345's function row is touch-sensitive,
which few laptops share (maintainer's note). The backlight device itself is
present (`dp_aux_backlight`, 717 of 1023), so brightness is settable from
software; whether the touch keys send key events is unrecorded.

## Not tested

The live medium on the XPS, ACPI boot, USB-C storage, suspend's resume time
and drain,
the touchpad's gestures, sound, external displays, whether
`systemd.tpm2_wait=0` removes the 90 s wait, and a kernel update.
