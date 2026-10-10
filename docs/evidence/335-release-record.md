# #335: the release record catches up with the published beta.6, validated

Branch `release-record-335`, uncommitted, on `main` at `eb3b2df` (PR 2 of 4
from the 2026-10-10 review, `docs/reviews/2026-10-10-whole-repo-review.md`).

## What changed

- `CHANGELOG.md`: the entries for #317 to #328, which the published
  `v2026.10.0-beta.6` (`1bfafac`) contains, moved from Unreleased into the
  beta.6 section, now dated 2026-10-10 with a note on the two cuts; a line for
  `install.sh --skip-yay` (#328) added with them; the stray blank lines inside
  the Changed list and the #324 bullet removed; a Changed entry for #335.
  Unreleased keeps #333 and #334.
- `docs/RELEASE-NOTES-2026.10.0-beta.6.md`: a section for what the published
  cut added (#317 to #328), one line in the intro, and the 2026-10-10 VM run in
  the qualification status.
- `SPEC.md` 5.5 and `docs/src/install.md`: the base system is fetched as
  CachyOS baseline builds and raised to the CPU's level afterwards, which
  downloads the base packages again; `sudo lyona-cachyos raise-level` is the
  recovery. `SPEC.md` 5.2: the panel is the bar by its strut (`exclusiveZone`).
- `docs/src/updating.md`: step 6 names the unprivileged `config.h` build and
  what it needs; the rollback section lists what the system half holds.
- `docs/src/troubleshooting.md`: a bar of your own needs a strut; an update
  failing with "Permission denied" from a `config.h` include.
- `docs/roadmap/ROADMAP.md` (images to beta.6, the 2026-10-10 run),
  `docs/roadmap/TASKS.md` (Settings was opened in the VM), `CONTRIBUTING.md`
  (the default `/usr/local` layout), `docs/AUR-PACKAGES.md` (the postinstall
  builds yay too), `docs/PATCH-OWNERSHIP.md` (the tray host is found by class).
- `docs/sprints/SYNC-SPRINT-9-OVERVIEW-POLISH.md` moved to `completed/`, with
  every reference repointed (`UPSTREAM-SYNC.md`, `sync-sprints-github.sh`, the
  completed Sprint 6, 7, 8 and 10 records, the four `s9-*` evidence docs, and
  the file's own links).
- `dwm.c`: `altbarclass` is `traywinclass`, with a comment: only the tray host
  is found by its class since #322.
- `tests/test-changelog-record.sh` and `make check-changelog-record`: when the
  tag for `config.mk`'s `VERSION` exists, `CHANGELOG.md` must have a dated
  section for it and `docs/RELEASE-NOTES-VERSION.md` must exist; Unreleased
  must always exist. Without the tag, only the Unreleased check applies.

## Tests

Run through `scripts/run-tests`, each on its own:

| Check | Result |
| --- | --- |
| `make check-changelog-record` (tag `v2026.10.0-beta.6` present, so the dated-section check ran) | PASS |
| `make check-shell-contracts` (every cited `docs/` path exists after the move) | PASS |
| `make clean all` (dwm builds after the rename) | exit 0, no warnings |
| `make check-aur-policy` (reads `docs/AUR-PACKAGES.md`) | PASS |
| `shellcheck`, `shfmt -d` on the new test | clean (the `SC2154` note on `repo` from the sourced library is the same as every test) |

## Not tested

- The user documentation was not rendered with mdbook; no page was added or
  removed, so `SUMMARY.md` is unchanged.
- No VM or X11 session: the changes are to records and one C identifier.
