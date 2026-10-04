# S11-05 -- dependencies and install profiles page

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-05-document-desktop-dependencies-and-install-profiles-for-arch`. Issue `#156`.

## Change

- `docs/src/dependencies.md` (new): installer profiles (`core`, `recommended`, `full`),
  how `required`, `recommended`, `optional` and `full` are composed, then each group with
  a one-line purpose and its packages. The lists come from
  `dwm_packages arch <group>`; the purposes are hand-written from the map's comments and
  `install.md`.
- `docs/src/SUMMARY.md` and `docs/src/install.md` link to it.
- `tests/test-arch-packages.sh`: collects every package `full`, `iso`, `terminal`,
  `terminal-primary`, `lightdm`, `qml-development` and `qml-validation` can install and
  fails if any is missing from the page. The misses go into a variable and are tested
  afterwards, because an `exit` inside a pipeline only leaves its subshell.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `make check-arch-packages`: PASS (67 packages resolved, plus the new check).
- Mutation: removing `gum` from the page fails with `docs/src/dependencies.md does not
  mention: gum`.
- `shellcheck`: 1 finding, the same as before the change; `shfmt -d` clean. The page is
  ASCII.

## Not verified

- The mdBook build (`mdbook` is not installed here); the page is plain Markdown with one
  relative link.
- The purposes of `desktop-optional`, `system-management` and similar groups were written
  from the map and `install.md`, not from installing each package.
