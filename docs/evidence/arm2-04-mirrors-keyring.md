# ARM2-04: mirrors, keyring and what the installer skips on ARM

ARM Sprint 2 item ARM2-04 (issue #10). Run 2026-10-24, on the build host and
virtual machine of ARM2-01 to ARM2-03 (`docs/evidence/arm2-03-installer.md`).

## What was there

On aarch64, after ARM2-03:
- **Mirrors.** The wizard asked "Download packages from mirrors in
  Germany?" and offered every country in the world. Nothing it answered was
  used: `rank_mirrors` found no reflector on the medium and logged
  `lyona-install: reflector is not on this medium; keeping the current
  mirrorlist.`, so the install used the medium's mirrorlist as it was, with
  only the geo-balanced `mirror.archlinuxarm.org` enabled.
- **Keyring.** The medium's keyring is filled at boot by releng's
  `pacman-init.service` (`pacman-key --init`, then `--populate`, which loads
  every keyring installed, `archlinuxarm` included). The wizard never waited
  for it, on either architecture. In the new system, ARM2-03's
  `archlinuxarm-keyring` adds the keys from its install script; nothing
  checked that it had.
- **CachyOS.** Already skipped on aarch64 (ARM2-03).
- **Network checks.** The sprint plan names "the name-resolution check
  before each download step (proposed after the 2026-10-10 install
  failure)". It did not exist in Lyona or Lyona-ARM, and no issue or write-up
  of that failure was found. The only network check was the wizard's
  `curl https://archlinux.org`, once, at its start.

Arch Linux ARM's mirrorlist (`pacman-mirrorlist` 20260411) has the
geo-balanced server enabled and 12 mirrors in 7 countries (Denmark, France,
Germany, Greece, Hungary, Taiwan, the United States), commented out under
`### Country` headings. All of them are HTTP only; pacman checks every
package's signature.

## What changed

The wizard (`archiso/airootfs/root/lyona-install.sh`):
- **aarch64 mirror question:** "Download packages from Arch Linux ARM's
  mirrors in Germany?" when the timezone's country has Arch Linux ARM
  mirrors, else "Download packages from Arch Linux ARM's nearest mirror,
  mirror.archlinuxarm.org?". A line says they are used in the order listed,
  not ranked by speed. **Choose another** lists the nearest mirror and the
  countries the mirrorlist has (names mapped to ISO codes through
  `iso3166.tab`); Esc goes back to the question, as on x86_64.
- **`select_alarm_mirrors`**, on aarch64 instead of `rank_mirrors`: the live
  mirrorlist becomes the country's mirrors, then the geo-balanced one as a
  fallback (that one alone with no country). reflector is not run or
  mentioned. The mirrorlist the medium booted with is kept as
  `/etc/pacman.d/mirrorlist.archlinuxarm`, so a Retry of the wizard lists the
  countries again. The marker is set, so the postinstall copies the list to
  the new system, as it does the ranked one.
- **Keyring wait, both architectures:** before anything is downloaded, up to
  about a minute while `pacman-init.service` runs or is queued, then each
  installed keyring (`archlinux`, and `archlinuxarm` on aarch64) is checked
  by its first trusted key. A keyring without its keys is populated once
  more; still without them, the wizard stops and says what to run.
- **Mirror name check, both architectures:** after the mirror step, the
  first mirror's host must resolve (`getent ahosts`). If it does not, the
  screen names the host and the name servers (for systemd-resolved's stub,
  `127.0.0.53`, also the servers it asks) and offers **Retry**, **Continue
  anyway** or **Cancel the installer**. Continue anyway is for a network that
  downloads through a proxy without resolving names locally, and is passed on
  to the postinstall (`LYONA_MIRROR_DNS_SKIP`).

The postinstall (`archiso/airootfs/root/lyona-postinstall.sh`):
- **"Checking the package mirror's name...", both architectures:** the first
  step, before the CachyOS step's downloads: the new system's first mirror
  must resolve, else the step fails and the Retry screen shows the host and
  name servers. Skipped after Continue anyway.
- **"Checking Arch Linux ARM's keys...", aarch64:** before the first system
  update, `pacman-key --list-keys` in the new system for the first trusted
  key of `archlinuxarm-keyring`; missing, `pacman-key --populate
  archlinuxarm`, and still missing, the step fails.
- 13 steps (17 on aarch64), instead of 12 (15).

## Tests

`tests/test-iso-install-aarch64.sh` checks, with every command a stub:
- the mirrorlist read (countries with codes, a country not in `iso3166.tab`
  left out, the geo-balanced server);
- the question for a country with mirrors and one without, the summary
  line, Choose another with Esc and back, the list offered, the nearest
  mirror, Esc on the question cancelling;
- the mirrorlist written for a country, for none, and for a country without
  mirrors, again after a first choice (from the kept copy), and that
  reflector neither runs nor is mentioned;
- the keyring wait: ready, still activating (waits, says so), keys missing
  and populated, keys still missing (stops before downloading), and x86_64
  checking `archlinux` only;
- the name check: resolving (nothing asked), Retry checking again, Continue
  anyway passed on, Cancel and Esc cancelling, the name servers shown
  (systemd-resolved's included), and x86_64 checking its own first mirror;
- the postinstall's two steps: resolving, not resolving (with the name
  servers), skipped after Continue anyway, a mirrorlist with no server; the
  keys present, missing and added, still missing, no keyring package;
- where each runs: the keyring wait and name check between the summary and
  the first download, the mirror step by architecture, the name step first
  in the postinstall, the keys step on aarch64 just before the update.

Each new check was shown to fail on a broken product (in a scratch copy:
no geo fallback, no wait, Continue anyway not passed on, the keyring wait not
called, countries listed twice, the postinstall name check always passing, no
populate). `test-iso-install-mirrors.sh` and `test-iso-install-recovery.sh`
now run the wizard as x86_64 (`ARCH=x86_64`): their answers are for the
x86_64 question, which an aarch64 host would otherwise not ask. The
`rank_mirrors` order check accepts the call's deeper indent. The
step-count test counts the new steps.

On aarch64 in the Arch Linux ARM CI container: `check-iso-install-aarch64`,
`-mirrors`, `-recovery`, `-warnings` and `check-archiso` passed; the whole
suite is below. shellcheck 0.10.0 (`-S warning`): no new warning; shfmt
3.10.0: no diff.

## Virtual machine

The medium, built from this branch (on `main` at `c6ed50c`, with the
changes uncommitted): `lyona-2026.10.0-beta.6-aarch64.iso`, 1,436,829,696
bytes, SHA-256
`614eeff59b5a98163c213659154a8eb7b68a1dbb348931c6205706d717d4805c`. Its
wizard and postinstall matched the branch's by SHA-256. Machine as in
ARM2-03: QEMU 8.2.2 with KVM, `virt`, 8 vCPUs, 8 GiB, the ISO as a USB stick
without `bootindex`, a fresh 32 GiB virtio disk, fresh AAVMF 2024.02
variables, no Secure Boot.

| Run | Result |
| --- | --- |
| ext4, Europe/Berlin, the mirror question answered Yes | Asked "Download packages from Arch Linux ARM's mirrors in Germany?". The keyring was ready (`pacman-init.service` active); "Using 3 Arch Linux ARM mirrors in DE, then mirror.archlinuxarm.org."; `de3.mirror.archlinuxarm.org` resolved. archinstall 1 m 46 s; all 17 postinstall steps, 4 m 00 s, with Arch Linux ARM's keys already in the new system's keyring. No line mentions reflector in either log; the CachyOS lines are the two "x86_64 only" notes and `install.sh`'s own step; the closing screen had no warnings. The new system's mirrorlist: de3, de, de4, then `mirror.archlinuxarm.org`. `pacman-key -l` there lists "Arch Linux ARM Build System" with full trust. The reboot started `Boot0008 "lyona"` and reached the lyona greeter |
| An unresolvable mirror, then Retry, then Cancel | A fresh disk; `broken.mirror.invalid` added first under Germany in the kept mirrorlist, to give a name that cannot resolve while the network works. The screen said "The package mirror's name does not resolve: broken.mirror.invalid", with the name servers; Retry checked again; Cancel ended the wizard with "Nothing on the disk was changed", and the disk had no partitions. The name servers read "127.0.0.53" alone; the message now names the servers systemd-resolved asks ("127.0.0.53, systemd-resolved, which asks: 10.0.2.3"), checked by repeating the run with the changed wizard |

## Not tested

- Continue anyway in a VM, and a network behind a proxy (the tests cover
  passing it on and the postinstall skipping its check).
- The keyring wait on a real slow or failed `pacman-init.service`: on the
  VM it had finished long before the summary. The tests cover waiting,
  populating and stopping.
- The postinstall's name check failing in a VM (the tests cover it).
- A country other than Germany, and the nearest mirror alone, in a VM.
- x86_64 in a VM: the keyring wait and name check are new there too. The
  Full suite's x86_64 job runs the tests; an x86_64 install has not been
  run with them.
- btrfs, LUKS (ARM2-03 ran LUKS before these changes), UTM and Parallels,
  real hardware, Secure Boot (ARM2-05).
