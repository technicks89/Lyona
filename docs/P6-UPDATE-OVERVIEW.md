# Phase 6 — Update Path: Overview and Architecture

Once lyona is installed there is no supported way to move to a newer version.
This document records what the installed system actually looks like today, the
architecture chosen to fix that, and the ordered review boundaries.

Detail lives in three companion plans:

| Boundary | Document | Delivers |
| --- | --- | --- |
| UPDATE-001 | [`P6-UPDATE-PROVENANCE.md`](P6-UPDATE-PROVENANCE.md) | An installed system that can state what it is running |
| UPDATE-002 | [`P6-UPDATE-HELPER.md`](P6-UPDATE-HELPER.md) | `lyona-update` — check, stage, apply, roll back |
| UPDATE-003 | [`P6-UPDATE-SURFACE.md`](P6-UPDATE-SURFACE.md) | Settings and Control Center surfaces over that helper |

> **Sequencing.** `AGENTS.md` forbids beginning the next phase in a change
> scoped to complete the current one, and Phase 5 is still active
> (`ROADMAP.md:301`). These are plans; implementing UPDATE-001 must wait until
> Phase 5 closes. The ROADMAP/TASKS edits described below belong to the commit
> that opens Phase 6, not to this planning document.

---

## What an installed system looks like today

This is the part that shapes every decision below, so it was verified rather
than assumed.

### There is no version marker anywhere on an installed system

`/etc/lyona-iso-release` is written into the **live medium's** airootfs by
`scripts/build-lyona-arch-iso.sh:341-349`. The target root is built by
`pacstrap`, and `archiso/airootfs/root/lyona-postinstall.sh` never copies that
stamp across. Neither `make install-system` nor `make install-user` nor
`install.sh` writes one either.

The only provenance on a running machine is `dwm -v` — the `VERSION` string
compiled in from `config.mk` (`dwm.c:5833`). That covers the C binary alone. The
scripts, QML, and config — the parts that change most between releases — carry
no version at all, and a half-applied install is indistinguishable from a clean
one.

**Nothing can report "you are behind" until this is fixed**, which is why
UPDATE-001 comes first.

### The two install paths leave different trees behind

| Install path | `~/.local/share/lyona` holds | `.git` present |
| --- | --- | --- |
| Arch ISO | the **complete source tree** — C sources, `Makefile`, `config/`, `scripts/`, `tests/`, `docs/` | **No** |
| Existing system, cloned elsewhere | `config/` and `scripts/` only (`Makefile:241-245`) | No (the clone elsewhere has it) |
| Existing system, cloned into the data dir | the complete checkout | Yes |

The ISO path is the notable one. `lyona-postinstall.sh:215,236` copies the
staged checkout to `$target_home/.local/share/lyona` and runs `install.sh` from
there — so the sources *are* on disk — but
`scripts/build-lyona-arch-iso.sh:294-303` stages that tree with
`rsync --exclude='.git/'`. An ISO-installed machine has full sources and no
history.

`make install-user` already anticipates this overlap: the data-dir sync is
skipped when the checkout *is* the data dir
(`Makefile:242`, `if [ "$(realpath .)" != "$(realpath ${DATA_DIR})" ]`).

### What already exists and should be reused, not rebuilt

`scripts/dev-sync-install.sh` is roughly 80% of an update engine already. It
builds from a clean object state, skips work when every managed file matches,
backs up the live install, runs the full system+user install, verifies
installed commands and generated files against the checkout, restarts
Quickshell when safe, and reports whether dwm needs a session restart.

In particular `backup_live_install()` (`dev-sync-install.sh:244-300`) already
writes, to `$XDG_STATE_HOME/lyona/live-update-backups/<UTC-stamp>-<pid>/`:

- `quickshell.tar` — the managed Quickshell config tree
- `lyona-data.tar` — the whole data dir
- `system-files.tar` — binary, man page, xsession, every installed command,
  the privileged helper, cursor themes and licences
- `checkout.txt` — commit, branch, prefix, data root, config/data homes
- `SHA256SUMS` over every archive

That is a complete rollback substrate. **What is missing is a restore path** —
nothing in the repo reads those archives back. UPDATE-002 adds it and uses the
same directory and format, so one rollback serves both developer syncs and user
updates.

Also reusable: `verify_install()` / `verify_tree()` / `runtime_verify()`
(`dev-sync-install.sh:169-236,301`), the privileged-helper pattern
(`PRIVILEGED_HELPER_DIR = ${PREFIX}/libexec/lyona`, `Makefile:87-88`) with
`scripts/dwm-polkit` for authentication, and
`tests/test-install-preservation.sh` for the do-not-clobber contract.

---

## Architecture

### Decision 1 — Ship updates as signed release tarballs, not `git pull`

The obvious idea is `git pull && make install`. It does not work here: the ISO
path has no `.git`, which is the majority install path for new users. The
alternatives were:

| Option | Verdict |
| --- | --- |
| Ship `.git` in the ISO | Rejected. Inflates the image, and `rsync --exclude='.git/'` is deliberate. |
| `git clone` on first update | Rejected. Re-materialises history over a tree the user may have edited, and fails on a metered or offline machine with no fallback. |
| **Release tarball + SHA-256** | **Chosen.** |

`make release` already produces `release/lyona-VERSION.tar.gz`, `lyona-release`
already uploads it to GitHub Releases, and `docs/RELEASING.md` step 9 already
requires the SHA-256 to be recorded in the release notes. The distribution
mechanism exists; only the consuming end is missing.

Git remains the *developer* path. `dev-sync-install.sh` is untouched by this
work, and `lyona-update --from-checkout DIR` covers users who did clone.

### Decision 2 — Stage and build outside the live tree

The data dir is read by a **running** shell: `Commands.helperCommand`
(`config/quickshell/core/Commands.qml:8-11`) resolves
`$XDG_DATA_HOME/lyona/scripts/<helper>` first for nearly every helper. Swapping
that directory underneath a live session is precisely the class of change that
breaks a desktop mid-use.

So the update never swaps trees in place. It stages to
`$XDG_STATE_HOME/lyona/updates/<version>/`, builds there, and then runs the
*existing* `make install-system` + `make install-user`, which already know how
to refresh `PREFIX` and the data dir safely and how to preserve user files.
No new placement mechanism is invented.

### Decision 3 — Channels follow the existing calendar versioning

`config.mk` carries one `VERSION` (`2026.08.0-beta.1` today), and
`lyona-release` publishes any `-alpha.N`/`-beta.N`/`-rc.N` suffix to GitHub with
`--prerelease` so it is never promoted to Latest (`docs/RELEASING.md`). That
gives two channels for free:

- **`stable`** (default) — the GitHub *Latest* release; pre-releases excluded by
  construction.
- **`preview`** — the newest release including pre-releases.

Channel lives in `~/.config/lyona/update.conf`, seeded but never overwritten,
following the existing `test -f … || install` idiom at `Makefile:274-277`.

### Decision 4 — One confirmed privileged step, never a silent sudo

`make install-system` writes `${PREFIX}/bin`, `${MANPREFIX}`, `${XSESSIONSDIR}`
and `${PREFIX}/libexec/lyona` — all root-owned. The Phase 6 exit criteria
require every privileged action to be "allowlisted, confirmed, auditable, and
cancelable" (`ROADMAP.md`).

`lyona-update` therefore runs unprivileged: it checks, downloads, verifies,
builds and stages with user rights only, prints exactly what the privileged
phase will touch, and escalates once — through the established
`${PREFIX}/libexec/lyona` + `dwm-polkit` pattern — for the system install
alone. Declining leaves a staged, verified, uninstalled update and a non-zero
exit, not a half-applied system.

### Decision 5 — lyona updates and Arch package updates stay separate

Phase 6 also wants Arch update status and installation. That is a different
risk profile (`pacman -Syu` can require reboots, break drivers, and is
already well served by existing tooling), a different authorisation story, and
a different failure mode. `lyona-update` covers the desktop itself only. The
Arch side belongs in its own Phase 6 boundary; UPDATE-003 leaves room for it in
the Settings section but does not implement it.

---

## Flow

```
lyona-update check
    │  read installed state  ── UPDATE-001 provenance stamp
    │  query release index   ── GitHub Releases for the configured channel
    └─ report: current / behind / ahead / unknown, plus target version

lyona-update apply [--version V]
    ├─ 1. download   lyona-VERSION.tar.gz  →  $XDG_STATE_HOME/lyona/updates/
    ├─ 2. verify     SHA-256 against the release asset digest
    ├─ 3. stage      unpack, preserve local config.h
    ├─ 4. build      make all, in the staging tree, unprivileged
    ├─ 5. back up    backup_live_install()  ── existing, dev-sync-install.sh:244
    ├─ 6. install    make install-system   ── one confirmed privileged step
    │                make install-user     ── unprivileged, preserves user files
    ├─ 7. verify     verify_install()      ── existing, dev-sync-install.sh:189
    ├─ 8. stamp      rewrite the provenance record
    └─ 9. restart    Quickshell when safe; report if dwm needs a session restart

lyona-update rollback [--backup ID]
    └─ restore the newest (or named) backup, verify, re-stamp
```

Steps 5, 7 and 9 are existing code. Step 6 is the existing Makefile targets.
The genuinely new work is 1-4, 8, and the rollback restore.

---

## What must survive an update

The update inherits the installer's preservation contract and must not weaken
it. `tests/test-install-preservation.sh` is the existing guard and gains update
cases in UPDATE-002.

- `config.h` — local build configuration. Explicitly *not* in the release
  tarball path (`build-lyona-arch-iso.sh:298` already excludes it); the staging
  step copies the live one in before building.
- `~/.config/lyona/{hotkeys,themes,window-rules}.toml` — seeded only when
  absent (`Makefile:274-277`).
- `~/.xinitrc` — preserved when it exists (`Makefile:235-239`).
- Symlinked config directories — preserved (`Makefile:250-253`).
- Everything under `~/.config/lyona/` written by the settings helpers:
  `panel-widgets.conf`, `wallpaper.conf`, `font.conf`, `dpi.Xresources`,
  `xsettingsd.conf`, `cursor.Xresources`, `theme-env.sh`.
- The managed Quickshell tree at `~/.config/quickshell` is *replaced* by design
  (`Makefile:264-267`) — it is project-owned. The backup in step 5 is what makes
  that reversible.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Update interrupted mid-install leaves a mixed tree | Back up before touching anything (step 5); `verify_install()` detects mixed state; `rollback` restores. The stamp is written **last**, so an interrupted update never claims success. |
| User is offline or GitHub is unreachable | `check` degrades to reporting installed version only; `apply --file PATH` accepts a locally downloaded tarball. |
| Update applied while the desktop is running | Same model as `dev-sync-install.sh`: restart Quickshell when safe, otherwise report that a session restart is required. dwm itself is never restarted under the user. |
| Downgrade or sideways move | Allowed but explicit — `apply --version` accepts any published version; `check` labels it a downgrade and `apply` requires `--allow-downgrade`. |
| Tarball tampering | SHA-256 verified against the GitHub release asset digest before unpacking; a mismatch aborts before anything is staged. |
| A release that cannot boot the session | Rollback is the answer, and it must be provable offline — UPDATE-002's acceptance includes rolling back from a TTY with no desktop running. |

---

## ROADMAP and TASKS

The commit that opens Phase 6 should add an `UPDATE-001` task group to
`TASKS.md` under a new active phase, and mark Phase 6 active in `ROADMAP.md`
once Phase 5 exits. The three boundaries above map to that group directly:

- UPDATE-001 — provenance and install-path convergence.
- UPDATE-002 — `lyona-update` check/apply/rollback with backup restore.
- UPDATE-003 — Settings and Control Center surfaces.

Phase 6's stated exit criteria already cover this work: every privileged action
allowlisted, confirmed, auditable and cancelable; read-only status available
when authorisation is denied; interrupted updates producing actionable recovery
guidance rather than ambiguous success.
