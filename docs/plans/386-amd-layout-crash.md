# #386: layout changes by other tools on AMD

Issue `#386`: a display layout changed by a tool other than Settings, such as
autorandr on hotplug or a plain `xrandr`, can still crash Xorg on AMD while
Picom runs. This is the investigation and the plan only: no package, installer,
Xorg configuration or product code changes here. Written on 2026-10-16.

## Background

The fix in `e169fe4` ("Fixed the crash on rotate screen", 2026-10-12, see
`CHANGELOG.md`) made Settings stop a running Picom around each live layout
change (`apply_layout` in `scripts/dwm-settings-display`). Its comment and the
CHANGELOG describe the cause as: the resize under Picom's queued page flip
failed the flip, and xf86-video-amdgpu 25.0 crashed Xorg while aborting it.
Nothing else that changes the layout goes through that path:

- autorandr on hotplug (udev rule, then `autorandr.service`, which runs
  `autorandr --batch --change` for each X user). The login-time
  `autorandr --change` in `scripts/autostart.sh` runs before Picom starts, so it
  is not exposed.
- `xrandr`, `arandr`, or any other RandR client.
- dwm cannot help: it learns of a change from `RRScreenChangeNotify`, after the
  server has already resized. Nothing in the event loop can pre-empt it.

lyona installs `xf86-video-amdgpu` for AMD GPUs (`arch:gpu-amd` in
`scripts/dwm-packages.sh`), and `dwm-settings-picom` picks the GLX backend on an
accelerated AMD renderer.

## What the research found

### The likely real cause: an xorg-server 21.1.25-1 ABI break, already fixed

Arch shipped `xorg-server` 21.1.25-1 on 2026-10-07 and 21.1.25-2 on 2026-10-14
(in `extra` on 2026-10-15). The lyona workaround landed on 2026-10-12, inside
that window.

- 21.1.25 backported a damage-list fix (xserver MR !2277, in the 21.1.25
  backport MR !2336). It added a member, `pListHead`, before
  `DamageRec.damage` in the installed SDK header, which moved `damage` and
  `damage.data` by 8 bytes while the video driver ABI version stayed 25.2.
  Binary `xf86-video-amdgpu` 25.0.0 (built against 21.1.18) reads
  `damage->damage` directly in `amdgpu_screen_damage_report()`, the callback for
  its TearFree scanout buffers, and crashes in `RegionUninit()`
  (xserver MR !2351 explains the offsets).
- The callback only exists while TearFree is on for a CRTC. The amdgpu man page
  says TearFree's default, `auto`, is on for rotated outputs, outputs with a
  RandR transform (such as `--scale-from`), RandR 1.4 secondary outputs and
  outputs with VariableRefresh. So on 21.1.25-1, rotating an output turns
  TearFree on and the next damage on the screen crashes the server. That
  matches "rotate crashes, landscape works" in every report below, and "stopping
  Picom around the rotation helped" is consistent with it (Picom's GLX flips are
  a steady source of the Present flip and damage traffic that reaches the
  callback), but that last part is not proven.
- Reports with the same signature: xf86-video-amdgpu issue 87 (Arch, Cezanne,
  `xrandr --output DVI-D-0 --rotate right` with Openbox, 21.1.24 works, backtrace
  `amdgpu_screen_damage_report` -> `RegionUninit`); xserver issue 1930 (Arch,
  RX 5700 XT, TearFree on, crash after the first Present flip); Arch packaging
  issue 12 (TearFree and VariableRefresh); the Arch forum and CachyOS threads
  (rotation and `--scale-from` crash, downgrade to 21.1.24 fixes it).
- Upstream reverted the backport on the 21.1 branch (xserver MR !2355, merged
  2026-10-14, "Closes: #1930"). Arch's 21.1.25-2 carries the revert as
  `0001-Revert_damage_Unlink_a_damage_from_the_list_it_was_actually.patch`
  ("fix ABI breakage - solves #12"). Users in the Arch and CachyOS threads
  confirm 21.1.25-2 fixes rotation.

If the lyona crash was this one, it is fixed on any up-to-date Arch system,
for Settings and for autorandr and xrandr alike, with or without Picom, and no
driver change is needed. This has to be confirmed on the AMD machine (see the
test plan): the lyona diagnosis of a failed queued flip may have been an
inference from the symptom, and no backtrace from it is in the repository.

### Older flip-related amdgpu reports

The xf86-video-amdgpu tracker has no open issue for a crash while aborting a
flip during a RandR resize. Older, closed reports in the area: a flip-path
segfault with a NULL `scanout_damage` (fd.o bug 105736), "flip queue failed"
log floods (drm/amd issue 80, fd.o bug 59903), and Compton's xrender vsync
breaking Present flips (fd.o bug 110417, fixed in the driver). None matches a
25.0 crash on current packages.

### The modesetting driver

- The Arch Wiki AMDGPU page now calls the built-in modesetting driver (glamor)
  "the recommended choice for most Xorg systems using the amdgpu kernel driver"
  and xf86-video-amdgpu "generally not recommended", needed for TearFree or for
  hardware-specific issues such as Southern Islands.
- modesetting is built with the server, so it cannot hit the 21.1.25-1 ABI
  break; the Arch forum thread confirms removing the DDX avoided it.
- TearFree for modesetting (Sultan Alsawaf, xserver MR !1006, made default-on
  by MR !1224) is on xserver master only. It is not in any 21.1.x release:
  the 21.1.25 `modesetting.man` has no TearFree option, so Arch's current
  `xorg-server` 21.1.25 has none. With modesetting, tearing prevention is
  Picom's vsync only; unredirected fullscreen clients can tear.
- modesetting 21.1 has `PageFlip` (DRI3 flips, default on), `VariableRefresh`
  (default off) and `AsyncFlipSecondaries`. It still page-flips through
  Present/DRI3, so a resize with a flip pending is exercised there too; no
  report was found of modesetting crashing in that case, but that is absence of
  evidence, not proof.
- Known modesetting costs: rotation without TearFree uses a shadow and is
  reported slow on some hardware (xserver issues 1629 and 1642); one Arch forum
  user saw tearing and frame-pacing problems with VariableRefresh and
  "Present-flip" warnings. Both drivers use glamor for 2D, so 2D performance is
  not expected to differ much.
- Output names change: amdgpu names outputs `DisplayPort-0`, `HDMI-A-0`;
  modesetting names them `DP-1`, `HDMI-1` (numbering starts at 1). Everything
  that stores output names would no longer match: the managed
  `/etc/X11/xorg.conf.d/90-lyona-display.conf` (its `Monitor-<output>` options,
  and its OutputClass that sets `Driver "amdgpu"`), lyona saved layouts in
  `~/.config/lyona/display-profiles`, and autorandr profiles.
  `scripts/dwm-display-setup` already maps an amdgpu kernel driver to
  `modesetting` when that is the active driver, and reports TearFree as
  unavailable.

### Narrower mitigations that keep xf86-video-amdgpu

- `Option "TearFree" "false"` (or `xrandr --output OUT --set TearFree off`
  before rotating): avoids the scanout-damage callback that the 21.1.25-1 crash
  goes through. Costs tearing prevention on rotated or transformed outputs.
  Note that `dwm-display-setup` offers TearFree on by default when the driver
  exposes it.
- `Option "EnablePageFlip" "off"`: the Arch Wiki's latency tweak (with TearFree
  false). It disables DRI2 page flipping, so Picom's GLX frames are copied
  instead of flipped; "may cause tearing and short-lived artifacts". It is not
  shown to avoid any known crash.
- `AsyncFlipSecondaries`: reported to stop "flip failed" log floods on
  multi-display setups; not a crash fix.
- Picom: the XRender backend, or `vsync = false`, changes how Picom presents
  (XRender with vsync also uses Present). Both are per-user and visible to the
  user; neither is shown to avoid a crash.
- autorandr hooks: autorandr runs executable `preswitch` and `postswitch`
  scripts, and every file in `preswitch.d/` and `postswitch.d/`, from
  `~/.config/autorandr/` and system-wide from `/etc/xdg/autorandr/`; a user
  file of the same name wins. A package-owned
  `/etc/xdg/autorandr/preswitch.d/50-lyona-picom` and
  `postswitch.d/50-lyona-picom` could stop and restart Picom around every
  autorandr switch without touching user files. Open points: on hotplug the
  hooks run from `autorandr.service` (`--batch`), so a Picom started from
  `postswitch` would live in that unit's cgroup, not the user session, and
  needs the session's `DISPLAY`, `XAUTHORITY` and bus; the hook must always exit
  0; and it covers autorandr only, not `xrandr` or `arandr`.

## Known and unknown

Known:

- 21.1.25-1 crashes xf86-video-amdgpu 25.0 when TearFree is on, which rotation
  turns on; 21.1.25-2 fixes it on Arch.
- The lyona workaround landed while 21.1.25-1 was current.
- modesetting on 21.1.25 has no TearFree and renames outputs.

Unknown (only the AMD machine can answer):

- Which `xorg-server` was installed when the lyona crash happened, and whether
  its backtrace was `amdgpu_screen_damage_report`.
- Whether rotation with Picom (GLX) still crashes on 21.1.25-2 with
  xf86-video-amdgpu 25.0, from Settings with the pause bypassed, from `xrandr`
  and from autorandr.
- If it does: whether TearFree false, EnablePageFlip off, the XRender backend,
  or modesetting avoids it, and what each costs on this card (RX 9070, two
  DisplayPort monitors, per the #369 evidence).

## Options

| Option | What | For | Against |
| --- | --- | --- | --- |
| A. Upstream fix, document | Confirm 21.1.25-2 fixes it; correct the CHANGELOG cause; close #386 | No change to users' systems; covers every tool | Only valid if the hardware test passes |
| B. Switch AMD to modesetting | Stop installing xf86-video-amdgpu, or ship a `Driver "modesetting"` config | Arch Wiki default; immune to DDX ABI breaks | No TearFree on 21.1; output renames break saved layouts, autorandr profiles and the managed Xorg config; slower rotation reported; existing installs need a migration |
| C. Driver option | `TearFree "false"` (or `EnablePageFlip "off"`) in the managed config | Small, reversible, keeps output names | Tearing on rotated outputs; only helps if the crash is that path |
| D. Picom option | XRender backend or `vsync = false` for AMD | Per-user | Worse vsync or performance for everyone on AMD to cover a rare case |
| E. autorandr hooks | System-wide pre/postswitch drop-ins that pause Picom | Covers hotplug, the case #386 names | Not `xrandr`/`arandr`; cgroup and environment issues above; a Picom restart (flicker) on every switch |
| F. Documentation only | Known limitation in the docs | No risk | Leaves the crash if it still exists |

For B, if it were ever chosen:

- New installs: `arch:gpu-amd` without `xf86-video-amdgpu` (mesa and Vulkan
  stay), or keep the package and write an explicit modesetting `Device` section;
  dependency tests and docs updated together.
- Existing installs: never remove the package or rewrite the managed config
  silently. Offer the switch with a preview, back up
  `90-lyona-display.conf`, write a separate drop-in, regenerate the managed
  config with the new output names after the next login, and say that saved
  layouts and autorandr profiles must be saved again.
- Rollback: delete the drop-in and restore the backup; the package is still
  installed.

## Recommendation

A first: run the test plan below before any change. The evidence points to the
21.1.25-1 ABI break, which Arch has already fixed for every layout tool, so the
most likely outcome is that #386 needs no code at all. A modesetting switch
would trade a fixed bug for lost TearFree and broken saved layouts on every AMD
install, so it is the last resort, not the default fix.

If the crash still reproduces on 21.1.25-2: choose by which candidate fixes it
on the hardware, in order of least cost: C (TearFree false) if the backtrace is
still the TearFree path, then E for hotplug, then B with the migration above.
Whatever the outcome, the Settings pause can stay until the hardware result is
in; removing it is a separate decision.

## Test plan (AMD desktop)

Save all work before each step that rotates: a crash ends the session. Run as
the normal user; `sudo` only where shown. Keep a second machine or a TTY
(Ctrl+Alt+F3) ready to undo a configuration file.

### 1. Inventory

```sh
mkdir -p ~/386
pacman -Q linux xorg-server xorg-server-common xf86-video-amdgpu mesa picom autorandr >~/386/versions.txt
uname -r >>~/386/versions.txt
lspci -nnk | grep -A3 -E 'VGA|Display|3D' >~/386/gpu.txt
grep -E 'xorg-server|xf86-video-amdgpu|mesa' /var/log/pacman.log | tail -n 20 >~/386/pacman-history.txt
grep -Hn -E 'Driver|TearFree|VariableRefresh|PageFlip|AsyncFlip' \
  /etc/X11/xorg.conf.d/*.conf /usr/share/X11/xorg.conf.d/*.conf >~/386/xorg-conf.txt
xrandr --verbose | grep -E '^[^ ]| TearFree:' >~/386/xrandr-tearfree.txt
xrandr --listproviders >~/386/providers.txt
dwm-settings-picom status >~/386/picom-status.json
```

`xorg-server` must be 21.1.25-2 or later for step 3; if not, `sudo pacman -Syu`
and log in again first.

### 2. Attribute the original crash

```sh
coredumpctl list /usr/lib/Xorg
coredumpctl info PID >~/386/old-crash.txt   # PID of a crash from 2026-10-07 to 2026-10-15
```

Compare its time with `~/386/pacman-history.txt`. If it happened under
21.1.25-1 and the stack shows `amdgpu_drv.so` near `RegionUninit` or the
damage code, it was the ABI break. (Arch binaries are stripped; with
`debuginfod` enabled, `coredumpctl gdb PID` then `bt` resolves the names.)

### 3. Reproduce on current packages, Picom running

Find the output name (`xrandr | grep ' connected'`), make sure Picom runs with
GLX (`picom-status.json` says running and `glx`), and keep the screen busy so
Picom keeps presenting, for example a terminal running `watch -n0.1 date`.

xrandr directly (bypasses the Settings pause):

```sh
OUT=DisplayPort-0
for i in 1 2 3 4 5; do
  xrandr --output "$OUT" --rotate left; sleep 3
  xrandr --output "$OUT" --rotate normal; sleep 3
done
xrandr --output "$OUT" --scale-from 2560x1440; sleep 3; xrandr --output "$OUT" --scale 1x1
```

(Use the output's real mode for `--scale-from`.) Then the same through
autorandr. Build the profiles with Picom stopped, then switch with it running:

```sh
dwm-settings-picom stop
xrandr --output "$OUT" --rotate left;   autorandr --save test386-rotated
xrandr --output "$OUT" --rotate normal; autorandr --save test386-normal
dwm-settings-picom start
for i in 1 2 3 4 5; do
  autorandr --load test386-rotated; sleep 3
  autorandr --load test386-normal;  sleep 3
done
```

If Docked/Undocked profiles exist, also unplug and replug a monitor a few
times (the real hotplug path). Remove the test profiles afterwards, since
autorandr may otherwise pick them on a hotplug with the same monitors:
`rm -r ~/.config/autorandr/test386-rotated ~/.config/autorandr/test386-normal`.

After any crash, log in again and capture at once:

```sh
cp /var/log/Xorg.0.log.old ~/386/Xorg-crash.log   # rootless startx: ~/.local/share/xorg/Xorg.0.log.old
journalctl -b -o short-precise --since '-15 min' >~/386/journal.txt
journalctl -k -b | grep -iE 'amdgpu|drm' >~/386/kernel.txt
coredumpctl info /usr/lib/Xorg >~/386/crash.txt   # the most recent Xorg dump
```

### 4. Candidate fixes (only if step 3 crashed)

Each is temporary; undo it before the next. Repeat step 3 with each.

a. TearFree off at run time, no file: `xrandr --output "$OUT" --set TearFree off`
   before rotating. Lost at the next X start.

b. TearFree off in a file:

```sh
sudo tee /etc/X11/xorg.conf.d/99-test386-amdgpu.conf >/dev/null <<'EOF'
Section "OutputClass"
	Identifier "test386-amdgpu"
	MatchDriver "amdgpu"
	Option "TearFree" "false"
EndSection
EOF
```

   Log out and in (LightDM restarts X). Undo: `sudo rm
   /etc/X11/xorg.conf.d/99-test386-amdgpu.conf`, log out and in. For
   EnablePageFlip, use `Option "EnablePageFlip" "off"` in the same file instead.

c. Picom XRender: Settings > Appearance > Compositor > backend XRender (undo:
   Automatic), or for one session `dwm-settings-picom stop; PICOM_BACKEND=xrender
   dwm-settings-picom start`.

d. modesetting. The managed config pins `Driver "amdgpu"`, so set it aside first:

```sh
sudo mv /etc/X11/xorg.conf.d/90-lyona-display.conf /etc/X11/90-lyona-display.conf.test386
sudo tee /etc/X11/xorg.conf.d/20-test386-modesetting.conf >/dev/null <<'EOF'
Section "Device"
	Identifier "test386-modesetting"
	Driver "modesetting"
EndSection
EOF
```

   Log out and in. Confirm which driver runs:

```sh
grep -E 'LoadModule: "(amdgpu|modesetting)"|modeset\(0\): glamor|AMDGPU\(0\): glamor' /var/log/Xorg.0.log
xrandr --listproviders      # modesetting shows name:modesetting
xrandr | grep ' connected'  # names now DP-1 style
```

   Output names change, so use the new name for `OUT` and expect saved layouts
   not to apply. Also check tearing in a video, a rotated output's smoothness,
   and Picom starting with GLX. Undo (from a TTY if X does not start):

```sh
sudo rm /etc/X11/xorg.conf.d/20-test386-modesetting.conf
sudo mv /etc/X11/90-lyona-display.conf.test386 /etc/X11/xorg.conf.d/90-lyona-display.conf
sudo systemctl restart lightdm   # or log out and in
```

   and confirm `AMDGPU(0)` lines are back in `/var/log/Xorg.0.log`.

### 5. What each result justifies

| Result | Change |
| --- | --- |
| Step 2 shows the old crash under 21.1.25-1, step 3 passes (10 xrandr and 10 autorandr round trips, plus hotplug) | Option A: correct the CHANGELOG cause, document it, close #386. No driver change. |
| Step 3 crashes with the TearFree damage stack, 4a/4b pass | Option C, through `dwm-display-setup` and documented, plus an upstream report |
| Step 3 crashes in another amdgpu path; only 4d passes | Option B with the migration above, as its own issue; report upstream with `~/386` |
| Only 4c passes | Option D or E, depending on cost seen |
| Everything crashes, modesetting too | Not a DDX problem: report to xserver; Option E or F |

Record the result in `docs/evidence/386-amd-layout-crash.md` with the versions,
GPU, outputs and what was not tested.

## Sources

- Arch Wiki, AMDGPU (driver choice, TearFree, EnablePageFlip):
  https://wiki.archlinux.org/title/AMDGPU
- xf86-video-amdgpu issue 87, rotation crash in `amdgpu_screen_damage_report`
  on 21.1.25: https://gitlab.freedesktop.org/xorg/driver/xf86-video-amdgpu/-/work_items/87
- xserver issue 1930, the same crash after a Present flip:
  https://gitlab.freedesktop.org/xorg/xserver/-/work_items/1930
- xserver MR 2336 (21.1.25 backports): https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/2336
- xserver MR 2351 (ABI analysis): https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/2351
- xserver MR 2355 (revert on 21.1 branch): https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/2355
- Arch xorg-server packaging (21.1.25-2, revert patch) and issue 12:
  https://gitlab.archlinux.org/archlinux/packaging/packages/xorg-server and
  https://gitlab.archlinux.org/archlinux/packaging/packages/xorg-server/-/work_items/12
- Arch package pages: https://archlinux.org/packages/extra/x86_64/xorg-server/ and
  https://archlinux.org/packages/extra/x86_64/xf86-video-amdgpu/
- Arch forum, "Xorg 21.1.25 crashing with VariableRefresh/Tearfree":
  https://bbs.archlinux.org/viewtopic.php?id=315135
- CachyOS forum, rotation crash on 21.1.25:
  https://discuss.cachyos.org/t/new-version-of-xorg-server-crashes-x11-when-you-rotate-the-display-with-xrandr/36748
- amdgpu(4) man page (TearFree auto, EnablePageFlip, AsyncFlipSecondaries):
  https://gitlab.freedesktop.org/xorg/driver/xf86-video-amdgpu/-/blob/master/man/amdgpu.man
- modesetting(4) at 21.1.25 (no TearFree) and master (TearFree):
  https://gitlab.freedesktop.org/xorg/xserver/-/blob/xorg-server-21.1.25/hw/xfree86/drivers/modesetting/modesetting.man
- modesetting TearFree: https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/1006,
  https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/1224,
  https://www.phoronix.com/news/Modesetting-TearFree-Merged
- modesetting rotation performance: https://gitlab.freedesktop.org/xorg/xserver/-/issues/1629,
  https://gitlab.freedesktop.org/xorg/xserver/-/issues/1642
- Older flip reports: https://bugs.freedesktop.org/105736,
  https://gitlab.freedesktop.org/drm/amd/issues/80,
  https://bugs.freedesktop.org/show_bug.cgi?id=110417
- xorg.conf(5), OutputClass precedence: https://gitlab.freedesktop.org/xorg/xserver/-/blob/xorg-server-21.1.25/hw/xfree86/man/xorg.conf.man
- autorandr README, hook scripts: https://github.com/phillipberndt/autorandr#hook-scripts
