# S12-02 -- release install hashes and builds one root-owned copy

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-02-release-install-hashes-and-builds-one-root-owned-copy`.
Issue `#165`. Builds on S12-01 (`c5da716`, `6fa43de`).

## Change

- `scripts/lyona-update-root`, `install-system release`:
  - The tarball is read with the invoking user's permissions,
    `runuser -u "$invoking_user" -- cat -- "$tarball_path"`, into a root-owned 0600
    `mktemp` file.
  - The digest is checked on that copy, and `extract_verified_tree` unpacks that copy.
    The user-owned path is never hashed or extracted, so it cannot be swapped between
    reads.
  - `config.h` is read the same way, into the root-owned build tree. It was copied
    with `cp -a` as root after a separate check.
  - Reading as the user means no path, symlink or swap can make root read a file the
    user could not read. Before, a `config.h` swapped for a link to `/etc/shadow`
    between the check and the copy would have been compiled, and the compiler errors
    printed.
  - The comments that claimed the old code "re-hashed" what it extracted now say what
    the code does and what the digest proves.
- `docs/src/updating.md`: the apply steps say the privileged step makes, re-checks and
  rebuilds its own copy (step 4 used to claim the build never runs with elevated
  privileges). A new paragraph says the digest proves the download is intact, not that
  the release is genuine, because releases are not signed (D-14) and the digest comes
  from the unprivileged side (the release page, or `~/.cache/lyona/`). The
  administrator prompt is the boundary.

Not done:

- **Step 3 (signatures):** deferred by D-14.
- **Step 4 (the user's `config.h` compiled into the system-wide dwm):** decided as D-18,
  keep it and document the TOML files as the way to customise. `docs/src/configuration.md`
  now leads with the TOML files (it also still described `rules[]`, `keys[]`,
  `colors[]` and `autostart[]` in `config.h`, none of which exist; window rules live in
  `window-rules.toml`). Documenting it showed that `lyona-update` only found a
  `config.h` next to its own scripts directory, so only a run from a checkout used
  one; Settings and the installed command built from `config.def.h`. **Fixed here, at
  the user's request:** `lyona-update` now uses `~/.config/lyona/config.h` first, then
  a checkout's, says which, and names it when a build fails; `make install-user`
  copies a customised checkout `config.h` there once and never overwrites one.
- **The cache the review flagged:** `~/.cache/lyona/update-index.json` can be edited by
  any program running as the user, and the updater trusts its asset URL and digest.
  Without signatures there is nothing root can check that against, so today it is
  covered only by the documentation above.

## Results (2026-09-27, CachyOS host, Docker, nothing committed)

- `tests/test-lyona-update-root-backups.sh` as root in `lyona-ci:f63532b17846`: PASS.
  Part 2 now also refuses:
  - a wrong digest;
  - a mode-000 tarball the user owns but cannot read (root could);
  - a symlinked tarball;
  - a mode-000 `config.h`;

  and a refused install leaves no system backup. The real install then runs with a
  user `config.h`.
- `scripts/run-tests make check-quickshell-update-model check-shell check-format`:
  PASS. The update-model test pins the single-copy shape, and fails if the helper ever
  hashes or extracts `"$tarball_path"`.
- `config.h` location (D-18): `tests/test-lyona-update.sh` runs a release-path dry run
  from a real source tarball and asserts the staged build used a marked
  `~/.config/lyona/config.h`; `tests/test-install-preservation.sh` asserts
  `install-user` does not copy an unchanged default, copies a customised one, and
  keeps a user-edited copy on reinstall. `check-lyona-update` and
  `check-install-preservation`: PASS. Mutations caught: dropping the
  `~/.config/lyona` lookup; copying unconditionally; overwriting an existing copy.
- Mutation checks. All caught:
  - reading the tarball as root, reading `config.h` as root, and skipping the digest
    comparison (container test);
  - hashing the user path, and extracting the user path (static pins).
- The swap between two reads itself cannot be reproduced reliably, so it is covered by
  the static pins, not by a race test.

## Not verified

- A real polkit prompt and a real published release. A real release cannot be installed
  at all today: see S12-19, issue `#184`.
