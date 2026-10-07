# #250: install step timing and the smaller install costs

Issue `#250`, part 6/6 of the install-speed series (#245 to #250).

**Status: the timing is in place; the VM baseline has not been run.** Both
install paths now log each step's duration and end with a table (part A). The
baseline below has to come from a real VM install, which has not been done.
Fill it in **before** #245 to #249 land, then add a column after each one.

## A. Step timing

- Image install: `run_logged` (`archiso/airootfs/root/lyona-ui.sh`) logs
  `[HH:MM:SS] [step N/10] <step>` when a step starts and
  `... done in 42s` (or `failed (exit N) after 42s`) when it ends.
  `/var/log/lyona-postinstall.log` on the new system ends with a `Step times`
  table: the wizard's archinstall step, then the ten postinstall steps.
- `install.sh`: a `[TIME] <section>: done in 42s` line after each section, then
  the same table before the closing banner. In an image install these lines are
  part of the "Running install.sh" step's output, so they appear in the same
  log.
- Tested by `tests/test-install-step-timing.sh` (`make check-install-step-timing`)
  against a stub `gum`.

## Baseline: full image install (not yet run)

One VM, UEFI, no NVIDIA, wired network. Record the medium's build, the host
CPU and disk, the VM's cores and memory, and the network speed.

| Step | Baseline | After #245 | After #247/#248 | After #246 | After #249 |
| --- | --- | --- | --- | --- | --- |
| archinstall | not run | | | | |
| Adding the CachyOS repositories | not run | | | | |
| Updating the new system | not run | | | | |
| Installing the CachyOS kernels | not run | | | | |
| Installing CPU microcode | not run | | | | |
| Installing GPU drivers | not run | | | | |
| Configuring NetworkManager | not run | | | | |
| Checking swap | not run | | | | |
| Checking for a QEMU/KVM hypervisor | not run | | | | |
| Running install.sh --profile full | not run | | | | |
| Building Topgrade | not run | | | | |
| **Total** | not run | | | | |

Copy the `install.sh` section times (`[TIME]` lines) from the same log below
the table.

## B. The smaller costs

Measured on the development machine (12 threads, NVMe, about 300 Mbit/s), not
in a VM. Times on old hardware will be higher.

| Item | Finding | Result |
| --- | --- | --- |
| B1 Meslo Nerd Font | The GitHub `Meslo.zip` is 112,448,359 bytes, downloaded by `install.sh` and again by `install-mybash` when the font was missing. `ttf-meslo-nerd` (extra, 3.5.1-2) is a 5.7 MiB download, and `fc-scan` on its `MesloLGSNerdFont-Regular.ttf` gives the family `MesloLGS Nerd Font`, as the zip does. | **Fixed.** It is in the `fonts` profile (`font-meslo`), installed with the other packages; both downloads are gone. |
| B2 `fc-cache -f` in `make install-user` | `fc-cache -f`: 2.1 s with 219 fonts installed. Plain `fc-cache`: 0.008 s. `make install-user` writes only an alias file (`50-meslolgs-nerd-font-aliases.conf`), which fontconfig reads at lookup time, not from the cache. Pacman's `fontconfig.hook` already refreshes the cache for packaged fonts. | **Fixed.** Plain `fc-cache`. |
| B3 `make clean; make` | 2.1 s for a full rebuild here, and 0.004 s for `make clean`. | **Closed:** seconds even on a slow CPU, not worth an incremental-build rule. Re-check if the old-hardware run says otherwise. |
| B4 Gear Lever and Flatpak at first login | Needs a first login on an image install. | **Open:** not measured. |
| B5 Wallpapers | 85 files, 141 MB at the pinned commit (63 PNG, 22 JPEG). A shallow fetch took 3.8 s here, which is about a minute at 20 Mbit/s. A release tarball would not be smaller: the images are already compressed. | **Open, for a decision:** a smaller default set, with the rest downloaded later, is the only real saving, and choosing which wallpapers stay is a product call. |
| B6 Herdr and yay downloads | Need a VM run, to see them against the other steps. | **Open:** not measured. |
| B7 `pacman -Syu` after archinstall | It runs after the CachyOS repositories are added, so it is probably not a no-op: it can replace stock packages with CachyOS builds. Needs the baseline's log to see what it actually does. | **Open:** not measured. Revisit with #247. |

## Not tested

- No VM or hardware install has been run with the timing code. The table
  format and the log lines are tested only against a stub `gum`.
- `install.sh` has not been run end to end with the change; `--dry-run` and the
  package-map tests pass.
- B1: the font has not been checked on screen in a real session (Alacritty, the
  bar, Quickshell) with only the package installed.
