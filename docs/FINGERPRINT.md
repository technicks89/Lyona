# Fingerprint authentication

Settings > Fingerprint (#483) enrolls fingers and chooses where a finger is
accepted instead of the password. It is listed while fprintd reports a reader,
and while any use is still on without one (#522): then it shows only the uses,
so they can be turned off. Nothing changes until the user asks: installing fprintd changes no PAM
file, and every use starts off.

## Getting it

- `install.sh --with-fingerprint` (or `DWM_INSTALL_FINGERPRINT=true`) adds the
  `fingerprint` capability, `fprintd`, to the recommended and full installs.
  It is never part of the default `optional` set. On a running system,
  `sudo pacman -S fprintd` does the same.
- The section appears when fprintd finds a reader libfprint supports. With no
  reader, or a reader libfprint does not list, there is no section and nothing
  else changes, unless a use is still on (see above).

## Fingers

The pane lists the user's enrolled fingers, enrolls one of the ten others, and
deletes one (asked twice). Enrolling and deleting go through fprintd's own
clients (`fprintd-enroll`, `fprintd-delete`): fprintd ties a device claim to
one D-Bus connection, so separate calls cannot claim, enroll and release. Their
result lines carry fprintd's status names unchanged, and the pane shows each
scan's result in plain words. fprintd's polkit policy asks for the user's own
password, and remembers it for a while. The reader and the fingers are read
from fprintd over D-Bus.

While any use is on, or set up outside Lyona, enrolling asks for the
**administrator password** instead (#535): `lyona-fingerprint-pam` keeps
`/etc/polkit-1/rules.d/50-lyona-fingerprint-enroll.rules`, which raises
fprintd's `net.reactivated.fprint.device.enroll` to `auth_admin`, while one is,
and removes it when none is. Otherwise someone at an unlocked session could
add a finger of their own within the remembered window, and it would then work
wherever fingerprint is on. The install writes or removes the rule to match
the uses already set.

A finger enrolled **outside Settings** (with `fprintd-enroll`, say) is shown at
the top of the pane, "Added outside Settings", until **I Added It** is chosen
or the finger is deleted (#535). Settings keeps the fingers it enrolled in
`~/.local/state/lyona/fingerprint-fingers`; the first time it reads the reader,
it takes the fingers enrolled then as known.

Opening Settings reads only the PAM files once a reader has been found (#532),
so fprintd is not started for every Settings window; the Fingerprint section
itself reads the reader and the fingers.

## Uses

| Use | PAM file | What it covers |
|---|---|---|
| Login and lock screen | `/etc/pam.d/lightdm` | The LightDM login, and light-locker's lock screen, which authenticates through the same service |
| Administrator prompts | `/etc/pam.d/polkit-1` | polkit prompts. Created over the system's `/usr/lib/pam.d/polkit-1` when that is the only one, and removed again when the use is turned off |
| sudo in a terminal | `/etc/pam.d/sudo` | `sudo` |

Turning a use on asks for the administrator password (polkit action
`com.lyona.fingerprint.manage`, which runs only
`PREFIX/libexec/lyona/dwm-settings-fingerprint-root`). The root helper accepts
only `enable`, `disable` or `remove-external` on these three uses, and runs the
installed, root-owned `lyona-fingerprint-pam` against `/` with a clean
environment.

`enable` adds two lines right after the `#%PAM-1.0` header, and nothing else:

```text
# lyona-fingerprint: added by Lyona Settings > Fingerprint; turn it off there
-auth      sufficient  pam_fprintd.so timeout=10 max-tries=3
```

- `sufficient`: a recognised finger is enough. A finger that fails, or no
  finger within 10 seconds, falls through to the password prompt, so the
  password works at every step. PAM handles one prompt at a time, so the
  password prompt comes once the finger step ends.
- The leading `-` makes PAM skip the line if `pam_fprintd` is ever
  uninstalled, so a removed fprintd cannot break a login.
- The original file is kept in `/var/lib/lyona/fingerprint` (root only),
  with the checksum of what was written. `disable` puts the original back byte
  for byte while the file is still exactly what was written. If it was edited
  since, only the two lines are removed, after a copy of the file is kept
  there (`USE.before-disable.TIME`).

While the polkit use is on, `/etc/pam.d/polkit-1` shadows
`/usr/lib/pam.d/polkit-1`: a change polkit's package makes to its own PAM file
does not take effect, and pacman makes no `.pacnew` for it, because the `/etc`
file is not a packaged one. The use's detail says when the two differ, apart
from Lyona's two lines (#524). What to do depends on where the `/etc` file came
from (as root, `/var/lib/lyona/fingerprint` says):

- **Lyona made it and nobody has edited it** (`polkit.absent` is there):
  turning the use off removes it, and turning it on again makes a new copy
  from polkit's current file.
- **It was there before Lyona** (`polkit.orig`), **or was edited since**:
  turning the use off keeps it, so turning it off and on does not follow
  polkit's file. Compare it with `/usr/lib/pam.d/polkit-1` and carry over the
  changes you want by hand.

A `pam_fprintd` line Lyona did not add, such as one added by hand, shows as
"Set up outside Lyona". Turning the use on or off is refused for it. **Remove
the Line Added Outside Lyona** (asked twice) removes such lines, after keeping
a copy of the file (`USE.external.TIME`). Afterwards the use can be turned on
from Settings.

## Security trade-offs

A finger is a convenience, not a stronger factor than the password. What each
use gives up:

- **sudo.** With the sudo use on, any program running as you can start `sudo`
  in the background and wait for you to touch the reader for something else;
  a terminal shows nothing about what a touch approves. fprintd's maintainers
  advise fingerprint for polkit and the login screen, not for sudo or a text
  console, and the pattern is the subject of CVE-2024-37408 (disputed by
  fprintd, Red Hat and Ubuntu). Only touch the reader when you have just typed
  `sudo` yourself. Lyona leaves the choice to you; it is off until you turn it
  on.
- **Administrator prompts.** With the polkit use on, a finger answers every
  polkit administrator prompt, including Lyona's own: updates, the display
  helper, and Settings > Fingerprint itself (so a finger can turn the sudo use
  on).
- **No lockout.** The line comes before `system-auth` and `system-login`, so
  `pam_faillock` neither counts nor blocks fingerprint attempts; each prompt
  allows three tries, and prompts can repeat. The account checks (expiry,
  `pam_nologin`, `pam_access`) still run.
- **Match-on-chip readers.** libfprint takes the "match" a match-on-chip
  sensor (such as the Goodix `27c6:6594` below) reports over USB as given;
  published research has shown that attack on such sensors with physical
  access and custom hardware.

## The keyring

**A finger does not unlock the login keyring.** `pam_fprintd` is
`sufficient`, so a finger ends the auth stack before `pam_gnome_keyring`
captures a password, and there is no password to unlock the keyring with.
After a fingerprint login, applications that use saved passwords ask for the
keyring password. The login switch says so. A session opened with the
password has its keyring unlocked already, so a finger at the lock screen,
polkit or sudo loses nothing. Lyona never empties the keyring's password to
work around this.

## Recovery

Every change keeps the password working. If a PAM file still needs repair, from
a text console (Ctrl+Alt+F3) or a root shell:

```sh
sudo /usr/local/libexec/lyona/lyona-fingerprint-pam status
sudo /usr/local/libexec/lyona/lyona-fingerprint-pam disable lightdm
```

The copies in `/var/lib/lyona/fingerprint` can also be put back by hand.

### After a rollback

`lyona-update rollback` to a release before 2026.11.0-beta.2 removes Settings >
Fingerprint and `lyona-fingerprint-pam`, but cannot take the lines out of the
PAM files, so a use that was on stays on. The rollback says which uses are on
before it asks (#523). Turn them off in Settings before rolling back. If they
are still there afterwards, the password keeps working, and they can be
removed by hand as root:

1. In `/etc/pam.d/sudo` and `/etc/pam.d/lightdm`, delete the two lines that
   begin with `# lyona-fingerprint:` and `-auth      sufficient  pam_fprintd.so`.
2. For `/etc/pam.d/polkit-1`, look in `/var/lib/lyona/fingerprint` first. If
   `polkit.absent` is there, Lyona created the file: delete it, and polkit uses
   `/usr/lib/pam.d/polkit-1` again. Otherwise (`polkit.orig`, or neither file),
   the file was there before: keep it, and delete only the same two lines.

Or update again: the release that added the lines can turn them off.

## Validation

- `make check-fingerprint-pam`: the PAM tool against a fake root seeded with
  real PAM files. On, off and byte-for-byte restore; the enrolment rule written
  and removed with the uses; mode kept; an edited file
  loses only Lyona's lines; polkit's `/etc` copy created and removed, and a
  change to polkit's own file reported; external
  lines reported, refused, and removed only on request; a missing module;
  symlinks; bad input.
- `make check-settings-fingerprint`: the Settings helper against stand-ins for
  fprintd (reader, no reader, no fprintd, fingers, enroll, delete), and `set`
  never reaching pkexec without the trusted root helper.
- `make check-quickshell-fingerprint-settings-xvfb`: the section is listed
  with a reader, or while a use is on without one; the pane loads; enrolling shows progress; a use is asked to
  change; bad requests never reach the helper.
- `make check-shell-contracts` holds the root helper's copy of the trust checks
  to `scripts/dwm-trust.sh`.

Seen by hand before this work (2026-11-12, a ThinkPad with a Goodix
`27c6:6594` reader): a LightDM login by finger in slick-greeter works, and a
failed or timed-out finger falls through to the password. Not yet tried with
`pam_fprintd`: mate-polkit, i3lock and slock.
