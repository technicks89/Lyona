# #336 and #337: root helper hardening and the release-tree contract, validated

Branch `root-helper-hardening-336-337`, uncommitted, on `main` at `4dac7f9`
(PR 3 of 4 from the 2026-10-10 review,
`docs/reviews/2026-10-10-whole-repo-review.md`).

## What changed

- `scripts/lyona-update-root` (#336): dwm is built as `lyona-build`, lyona's
  own system user, never as the shared `nobody`; the build refuses to start
  while any process runs as that user (`pgrep -u`); only `*.c`, `*.h`, `*.o`,
  `Makefile` and `config.mk` are copied into the build directory, so only
  `dwm.o` is compiled; `make` is `/usr/bin/make` through `trusted_file`, as
  `cosign` and `setpriv` are; the backup `tar` takes its file list with
  `--verbatim-files-from`; the downgrade guard dies when the installed or the
  requested version cannot be ranked.
- `scripts/lyona-update-root` (#337): root builds the release's `all-root`
  target, falling back to the old variable expression for a release before this
  one; the GTK themes to back up come from `GTK_THEME_IDS`, falling back to the
  old awk for an older release.
- `config/systemd/lyona-update.conf`: the sysusers entry for `lyona-build`
  (no home, `nologin`). `Makefile`: `install-system` installs it under
  `/usr/lib/sysusers.d/` and, unless `DESTDIR` is set, runs `systemd-sysusers`
  on it (`useradd -r` where that tool is missing); `uninstall` removes the file
  and leaves the account; the install manifest lists the file.
- `Makefile` (#337): `GTK_THEME_IDS` is computed once and used by `uninstall`,
  `remove-legacy-shared-data` and the install manifest, where the same awk was
  written three times (the fourth copy was the helper's); `all-root` builds
  every program and object that never includes `config.h`.
- `dwm.c`: `watchdock()` is the one rule for a dock left unmanaged, used by
  `leavedock()` and the two scan sites that repeated it.
- `SPEC.md` 6: "The release-tree contract" freezes the target and variable
  names an installed helper reads from a new release's tree, and the record's
  layout fields. `SPEC.md` 5.10: the build identity and the fixed tool paths.
  Decision D-36 in `docs/sprints/UPSTREAM-SYNC.md`. `docs/src/updating.md` and
  `docs/src/troubleshooting.md` name `lyona-build`. `CHANGELOG.md`.
- Tests: `tests/test-update-root-contract.sh` (`make
  check-update-root-contract`) runs the previous release's helper's Makefile
  reads against the current tree (when HEAD is itself a release, the release
  before it, the one that updates to HEAD), checks the four targets exist, that
  `all-root`'s prerequisites in make's database hold every object but `dwm.o`
  and the three helper programs and neither `dwm` nor `dwm.o`, that only
  `dwm.c` includes `config.h`, and
  that `stamp-system` still writes the record fields the helper reads.
  `tests/test-lyona-update.sh` orders ten version pairs, both ways, through
  `version_rank` and `release_rank`, refuses the same malformed versions through
  both, and pins the helper's and Makefile's shape. `tests/test-lyona-update-root-backups.sh`
  (root) checks the sysusers file and the account after `install-system`, an
  unrankable installed version refused with "cannot compare", a process
  running as `lyona-build` refusing the build, and the `config.h` include test
  now as `lyona-build`.

## Tests

Run through `scripts/run-tests`, each on its own:

| Check | Result |
| --- | --- |
| `make clean all` | exit 0, no warnings |
| `make check-lyona-update` | PASS |
| `make check-update-root-contract` (previous release `v2026.10.0-beta.6`, its helper's five reads all expand) | PASS |
| `make check-install-manifest` (the sysusers file in the staged install, uninstall symmetry) | PASS |
| `make check-legacy-shared-data` (`remove-legacy-shared-data` with `GTK_THEME_IDS`) | PASS |
| `make check-dwm-bar-docks-xvfb` (`watchdock`: banner, narrow dock, strut set late and cleared) | PASS |
| `make check-shell-contracts`, `make check-ci-parity` | PASS |
| `shellcheck`, `shfmt -d` on the helper and the three tests | clean (the `SC2154` notes on sourced variables are pre-existing) |

The trimmed build copy was dry-run as the building user, outside the helper:
`make all-root` in a tree from `git archive`, then `cp -a` of `*.c *.h *.o
Makefile config.mk` into an empty directory and `env -i ... make -C dir dwm`.
It built `dwm`, compiling only `dwm.o`, with nothing on stderr.

## Not tested

- `tests/test-lyona-update-root-backups.sh` part 2 needs root in an
  `archlinux:base-devel` container (`make check-update-root-backups`): not run
  here. That is where `systemd-sysusers` creating the account, the `pgrep`
  refusal, the fail-closed guard, and the `lyona-build` build with a real
  `setpriv` are exercised.
- No VM: no real update through polkit with the new helper.
- `useradd -r` fallback (a system without `systemd-sysusers`): not run.
