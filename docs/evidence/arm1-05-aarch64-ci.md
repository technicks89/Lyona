# ARM1-05: aarch64 CI

ARM Sprint 1 item ARM1-05 (issue #5), 2026-10-13. Decision A-9: a GitHub
`ubuntu-24.04-arm` runner running the suite in an Arch Linux ARM container, on
the manual Full suite workflow first.

## What runs

- **`.github/workflows/full-suite.yml`** gains the job `full-suite-aarch64`,
  behind a new `aarch64` input (on by default). It is manual like the rest of
  the workflow: no push or pull-request trigger yet.
- **The image:** Arch Linux ARM publishes no container image, and
  `archlinux:base-devel` has no aarch64 build. `scripts/ci-archlinuxarm-image.sh`
  builds one from Arch Linux ARM's own `ArchLinuxARM-aarch64-latest.tar.gz`:
  - downloaded over HTTPS from the first mirror that answers
    (`ca.us`, `fl.us`, `de3`; the redirector `mirror.archlinuxarm.org` has no
    valid certificate);
  - its signature must be a good one by the Arch Linux ARM Build System key,
    `68B3537F39A313B3E574D06777193F152BDBE6A6`, pinned in the script; the
    public key is `scripts/ci-archlinuxarm.asc` (taken from
    `archlinuxarm-keyring`; no expiry);
  - its `.md5`, published beside it, must match; the SHA-256 and the
    signature's date are printed for the record;
  - imported without `/boot`, kernel modules and firmware (about 1.3 GB of
    the 2 GB a container never uses);
  - then pacman's keyring is initialised, the kernel and firmware packages are
    removed, the system is upgraded and `base-devel` is installed.
  - pacman's download sandbox is off in the image (`DisableSandbox`): its
    Landlock rules and switch to the `alpm` user are refused inside
    `docker build`. Packages are still checked against their signatures.
  - `LANG=C.UTF-8`, as `archlinux:base-devel` sets it: without a locale Qt
    prints a warning into output the Quickshell tests compare.
- **The suite:** `scripts/ci-local.sh --base-image lyona-archlinuxarm:base-devel`,
  the local twin of the x86_64 job. The same package profile (resolved for
  aarch64), security options, unprivileged `nobody` runner and
  `scripts/run-tests make TARGET`, plus the clang build when `clang` is ticked.
  For the whole suite (`check`) it passes `--each`, so every target runs on
  its own and every failure is listed, instead of stopping at the first.
  The job has no package list of its own; `check-ci-parity` checks that.
  It uploads the whole log directory: `each.log` and one log per target.
- **x86_64:** the x86_64 job gives the `nobody` runner `SHELL=/bin/bash`, as
  `ci-local.sh` now does: `script` otherwise runs `nobody`'s `nologin`.
  Nothing else in it changes. (Its `fetch-depth: 0`, which
  `check-shell-contracts` needs, came from Lyona in the sync.)

## Checks that need x86_64

Every target runs on aarch64. These test x86_64-only features or fixtures, so
they are pinned to x86_64 and run there as on an x86_64 host:

| Target | Why | Pinned with |
| --- | --- | --- |
| `check-legacy-nvidia` | The legacy NVIDIA drivers are x86_64 only | `ARCH`, `DWM_AUR_ARCH` |
| `check-archiso` | The install medium is x86_64; its aarch64 counterpart is ARM Sprint 2 | `ARCH` |
| `check-cachyos` | CachyOS is x86_64 only | a `uname -m` stub and `DWM_MACHINE`; a new aarch64 case checks that `add-repos` is refused and `pacman.conf` is left alone |
| `check-install-yay`, `check-topgrade-install` | The fixtures are x86_64 PKGBUILDs | `DWM_AUR_ARCH` |

For each pin, setting it to `aarch64` reproduces the error the aarch64 job
reported before it was added.

Checked for the host instead:

- `check-aur-policy` resolves the package map for aarch64 against Arch Linux
  ARM's `core`, `extra` and `alarm` (127 packages), without the x86_64 install
  medium's lists (`iso` and `archiso/packages.x86_64`; ARM2-04).
- `check-arch-packages` accepts Arch Linux ARM through `is_arch_family`.

Skipped on aarch64:

- `check-shell`: ShellCheck is not packaged for aarch64. The x86_64 job runs
  it.

## Runs

The Full suite workflow on `arm/arm1-05-aarch64-ci`, `target=check`, `clang`
and `aarch64` ticked. The image is the Arch Linux ARM root filesystem signed
2026-08-05, SHA-256
`42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319`.

| Run | Commit | aarch64 | x86_64 |
| --- | --- | --- | --- |
| 38448354948 | `10fd2bb` | lint failures | lint failures |
| 38452645429 | `588bebd` | stopped at `check-build-config` (`nologin`) | the same |
| 38454795171 | `125fc32` | 157 targets, 25 failed | stopped at `check-shell-contracts` (shallow checkout) |
| 38470044538 | `56c96ba` | 8 failed | stopped at `check-quickshell-settings-xvfb` |
| 38487943145 | `e4b0f30` | 151 passed, 6 failed | stopped at `check-quickshell-settings-xvfb` |
| 38506069215 | `59a121e` | 153 passed, 4 failed | stopped at `check-picom-xvfb` |
| 38557298342 | `e0a0c74` | 157 targets, 0 failed | stopped at `check-xvfb-runtime` |

The clang build passed in every run from 38454795171. The two root-helper
jobs passed from 38506069215, the first run after the Lyona sync.

Before the sync, each remaining Xvfb failure was also run alone, on both
architectures (38474830294, 38474861312, 38476264056, 38476777065,
38477448752):

| Target | x86_64 | aarch64 |
| --- | --- | --- |
| `check-quickshell-settings-xvfb` | fails | fails: "leaving the page stops their watchers" |
| `check-dwm-activate-xvfb` | fails | fails: a popup asking for the keyboard loses it from the window inside it |
| `check-dwm-bar-docks-xvfb` | fails (the Python test segfaults) | fails: switching the workspace from the panel does not hide the client |
| `check-quickshell-idle-watchers-xvfb` | fails | fails: `nmcli monitor` is not running |
| `check-quickshell-system-management-xvfb` | fails | fails: the regional preflight harness |
| `check-desktop-smoke-xvfb` | passes | passes (failed once inside the full run) |

These five failed the same way on x86_64, and on Lyona `main`. Lyona fixed
them (technicks89/Lyona#381, #382), and Lyona-ARM synced those fixes
(technicks89/Lyona@107d68a, #29). The two root-helper jobs were fixed in the
same sync: the backups container runs with `--init`, and the display test no
longer inherits `LYONA_NO_TRUSTED_HELPERS`.

After the sync, these failed once each. Two were this branch's own merge
mistake. The other three tests are the same as on Lyona `main`, and fail
intermittently on both architectures:

- `check-install-yay` and `check-aur-policy` (38506069215): the merge of
  `main` into this branch dropped their ARM1-05 changes. `e0a0c74` restored
  them.
- `check-dwm-activate-xvfb` (38506069215, aarch64): in the two-monitor case,
  "dwm did not manage a window". The one-monitor case passed.
- `check-picom-xvfb` (38506069215, both architectures): the helper could not
  open the display. The test starts Xvfb without `-noreset`, and no client
  stays connected between helper calls, so the server resets after each one.
  The next call can arrive during the reset.
- `check-xvfb-runtime` (38557298342, x86_64): "window 0x600001 did not become
  active". It passed in every earlier x86_64 run that reached it.

## Not tested

- The x86_64 suite past `check-xvfb-runtime` in the last run: that job stops at
  its first failure. Every target past it passed on aarch64 in the same run.
- `check-release-workflows` skips on aarch64 because PyYAML is not installed.
  No package profile installs it, so it may skip on x86_64 too.
- A push or pull-request trigger: the job is manual.
- Running the desktop on ARM hardware: ARM1-06 and ARM Sprints 3 and 4.
