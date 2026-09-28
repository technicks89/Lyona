# S12-11 -- install and update correctness

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-11-install-and-update-correctness`.
Issue `#174`. Item 2's approach was decided with the maintainer on 2026-09-28: refuse
and list the fix, with no privileged package installation.

## Change

1. **No partial upgrade after enabling multilib** (`install.sh`). The step now runs
   `pacman -Syu`, announced, instead of `pacman -Sy`.
   - `scripts/lyona-cachyos` also runs `pacman -Sy`, at lines 218 and 259; neither
     is changed.
     - Line 259 is deliberate: the live ISO syncs so it can install a fresh system.
     - Line 218 is the CachyOS bootstrap: sync, then install only the keyring and
       mirrorlist packages, which have no library dependencies. The same function
       then runs `pacman -Syu` on an installed system. That is a short window, not a
       lasting partial upgrade.
2. **`lyona-update apply` checks the release's packages** before it builds.
   - `check_release_packages` reads the package map of the release being installed
     (its own `scripts/dwm-packages.sh`), so a dependency the release adds is
     included.
   - It asks `pacman -T` (deptest), which resolves provides the way an install
     would.
   - A missing package in `build`, `x11` or `runtime-required` stops the update
     before the build, with nothing changed. The message names the packages and
     the command: `sudo pacman -S --needed <packages>`.
   - A missing `desktop` package only warns. The install profile is not recorded,
     and a user may have left some out on purpose.
   - A release without the map (an older format) is not checked, with a warning.
3. **Rollback swaps the user trees in whole.** `restore_user_tree` unpacks the
   backup beside the target, checks it holds exactly the expected folder, moves the
   current tree aside and the restored one in, and deletes the old one only then.
   If the swap fails, it puts the old tree back. Unpacking over the current tree
   used to leave behind files a newer version had added.
4. **The checksum is matched by exact file name.**
   - It used to be `$0 ~ want"$"`, a pattern with an unescaped "." and no anchor at
     the start.
   - The plan's suggested `$2 == want` would have broken real releases.
     `lyona-release` hashes absolute paths, so the published `SHA256SUMS` names the
     asset by its build path; the last release has `./lyona-...iso`.
   - The fix strips sha256sum's `*` and any directory, then compares exactly.
   - Checked on sample lines: the path, `./` and `*` forms match;
     `xlyona-2026.09.0.tar.gz`, `lyona-2026a09.0.tar.gz` and `...tar.gz.sig` do not.
5. **`make install-user` skips `config/polkit`**, the system action templates with
   `@PREFIX@` unexpanded. `config/systemd/user/wm-graphical-session.service` is still
   seeded: autostart starts that unit from `~/.config/systemd/user`.
6. **Offline install.**
   - `apply --file PATH --version V --sha256 HASH` verifies against the given hash,
     with no network access. The hash is 64 hex digits, and it is refused without
     `--file`.
   - The "could not reach the update server" hint now names that command.
   - Before, `--file` looked the checksum up online and refused without it, so the
     suggested offline install could not work.
7. **ISO installer credentials** (`archiso/airootfs/root/lyona-install.sh`). The new
   `write_credentials_json` builds the file with `jq -n --arg`, and the password is
   hashed with `openssl passwd -6 -stdin`, never in argv.

## Results (2026-09-28, CachyOS, working tree, nothing committed)

Each new test fails against the old code:

| Test | Checks | Against the old code |
|---|---|---|
| `tests/test-install-multilib.sh` (new, `make check-install-multilib`) | The multilib function, extracted and run with stubs: `pacman -Syu`, announced, never `-Sy`; a failed upgrade is reported | "multilib was not followed by pacman -Syu" |
| `tests/test-lyona-update.sh`: checksum | A look-alike name (`xlyona-2026a09.0.tar.gz`) listed first with a wrong hash, the real asset by an absolute path | "the checksum of a look-alike file name was used" |
| `tests/test-lyona-update.sh`: `--sha256` | Offline `--file` with the right hash completes a dry run; a wrong one is a mismatch; `--sha256` without `--file` is refused; the offline hint names it | (runs after the checksum case) |
| `tests/test-lyona-update.sh`: rollback | `restore_user_tree` extracted: backup content back, a newer file gone, no staging left, a missing target created, a bad archive refused with the tree kept | Extract-over fails "a file the newer version added is gone" |
| `tests/test-lyona-update.sh`: packages | With a `pacman -T` stub: a missing `xdotool` stops the update before the build with the fix command; a missing `picom` only warns | With the check disabled: "an update with a missing required package went ahead" |
| `tests/test-install-preservation.sh` | A fresh `install-user` leaves no `~/.config/polkit`, and seeds the systemd user unit | "install-user seeded the polkit action templates" |
| `tests/test-iso-install-credentials.sh` (new, `make check-iso-install-credentials`) | `write_credentials_json` extracted: eight passphrases (`"`, `\`, `\n\tA` as text, `'`, JSON, non-ASCII, spaces) come back exactly; no passphrase is written without encryption; openssl reads the password from stdin | The old installer has no such function, and interpolated the values |

- `check-archiso`: PASS.
- ShellCheck on `lyona-install.sh`: the same 13 notes as `main`, none in the changed
  lines.
- `check-shell` and `check-format`: PASS.
- `test-install-preservation.sh` needs a built checkout (`make all`), because
  `install-system` checks for `dwm-window-thumb` first. That is unchanged.

## Not verified

- **A real install from the ISO** with such a passphrase (the JSON is checked, not
  archinstall reading it).
- **A real rollback** through the privileged helper (the swap function is tested on
  its own).
- **The dependency check against the real `pacman -T`** on a system that lacks a
  package; the tests use a stub.
