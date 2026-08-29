# UPDATE-001 — Install Provenance

First boundary of the Phase 6 update path. Architecture and rationale:
[`P6-UPDATE-OVERVIEW.md`](P6-UPDATE-OVERVIEW.md).

## Context

An installed lyona system cannot state what it is running.

- `/etc/lyona-iso-release` is written only into the live medium's airootfs
  (`scripts/build-lyona-arch-iso.sh:341-349`). The target root is `pacstrap`ped
  and `archiso/airootfs/root/lyona-postinstall.sh` never copies it across.
- `make install-system`, `make install-user` and `install.sh` write no marker.
- `dwm -v` reports the `VERSION` compiled in from `config.mk` (`dwm.c:5833`) —
  the C binary only. Scripts, QML and config carry no version, so a partially
  applied install looks identical to a clean one.

Every later boundary depends on this: nothing can report "an update is
available" without knowing what is installed, and nothing can verify an update
succeeded without a record to compare against.

This boundary is also worth landing on its own merit — it makes
`dwm-diagnostics` and bug reports far more useful than "latest, I think".

## Deliverables

1. A provenance record, written by both install paths.
2. `scripts/lyona-version` — a versioned reader, following the helper protocol
   conventions already used across `scripts/`.
3. Convergence of the ISO and existing-system install paths so both produce the
   same record.

---

## 1. The record

Two scopes, because the install has two scopes.

### System: `/etc/lyona-release`

Written by `make install-system` (root already, no new escalation). Mode `0644`.

```
LYONA_VERSION=2026.08.0-beta.1
LYONA_COMMIT=b85539b8f2c1d4e6a90371fc2b5e8d47a1c09e33
LYONA_SOURCE=iso
LYONA_PREFIX=/usr/local
LYONA_INSTALL_DATE=2026-08-29T14:03:11Z
```

`LYONA_SOURCE` is one of `iso`, `tarball`, `checkout`, or `unknown` — it tells
the update helper whether a git remote is available and whether the tree it
would replace is user-modified.

`LYONA_COMMIT` is `unknown` when git is unavailable, which is the normal case on
an ISO install. The build stamps it instead: `build-lyona-arch-iso.sh:342`
already computes `build_commit` for `/etc/lyona-iso-release`, so the ISO path
can carry a real commit through to the target.

### User: `$XDG_STATE_HOME/lyona/install.state`

Written by `make install-user`. Mode `0600`. Same keys plus the user-scope
paths, so a per-user install on a shared machine is still self-describing:

```
LYONA_VERSION=2026.08.0-beta.1
LYONA_COMMIT=b85539b8f2c1d4e6a90371fc2b5e8d47a1c09e33
LYONA_SOURCE=iso
LYONA_DATA_DIR=/home/user/.local/share/lyona
LYONA_CONFIG_DIR=/home/user/.config
LYONA_SOURCE_TREE=/home/user/.local/share/lyona
LYONA_INSTALL_DATE=2026-08-29T14:03:11Z
```

`LYONA_SOURCE_TREE` records where the sources that produced this install live —
the data dir on an ISO install, the clone path otherwise, empty when the
sources are gone. UPDATE-002 uses it for `--from-checkout` discovery.

### Why two files rather than one

The system and user halves can genuinely diverge: `make install-system` can be
run by root for a machine while a second user has never run `install-user`. A
single file could not express that, and the mismatch is exactly what
`lyona-version status` should surface.

---

## 2. `scripts/lyona-version`

A read-only helper. No mutation, no privileges, safe to call from a panel.

Follows the conventions already established by `dwm-settings-appearance`,
`dwm-panel-settings` and friends: a versioned protocol header, tab-separated
records, a terminating `complete` line, and safe degradation rather than
failure.

```
lyona-version status
```

```
lyona-version-protocol	1	0
state	available	Installed version recorded for system and user
system	2026.08.0-beta.1	b85539b	iso	/usr/local	2026-08-29T14:03:11Z
user	2026.08.0-beta.1	b85539b	iso	/home/user/.local/share/lyona	2026-08-29T14:03:11Z
binary	2026.08.0-beta.1
consistent	yes
complete	status
```

`state` is one of:

| State | Meaning |
| --- | --- |
| `available` | Both records present and readable |
| `partial` | One record present — e.g. system installed, this user never ran `install-user` |
| `defaults` | No record found; pre-provenance install, treat as unknown version |
| `unavailable` | A record exists but is unsafe (symlink, wrong owner, oversized) or malformed |

`binary` is `dwm -v` output, parsed. `consistent` is `yes` only when the system
record, the user record and the binary all agree — this is what catches a
half-applied install, and what UPDATE-002 checks after applying an update.

Reuse the existing safety idiom rather than writing a new one: the
`state_file_safe()` shape from the panel-settings helper
(`docs/P5-PANEL-WIDGETS-PORT.md` §1) — regular file, not a symlink, owned by
the reader, single hard link, size-capped, not group/other-writable. A missing
record is a normal `defaults` state, never an error; an unsafe one is reported,
never rewritten.

Also add:

```
lyona-version status --json    # for scripting; same data, JSON object
lyona-version print            # single line: the effective installed version
```

`print` exists so `dwm-diagnostics` and shell prompts have a trivial call.

---

## 3. Install-path convergence

### `Makefile`

Add a `stamp-system` step to `install-system` and `stamp-user` to
`install-user`, both after the files they describe are in place — an
interrupted install must not leave a stamp claiming success.

Commit resolution, in order: `LYONA_COMMIT` from the environment (the ISO build
passes it), else `git -C . rev-parse HEAD`, else `unknown`. Source resolution:
`LYONA_SOURCE` from the environment, else `checkout` when `.git` is present,
else `tarball`.

Add `scripts/lyona-version` to `INSTALL_COMMANDS`, and to the `check-shell` and
`check-format` explicit lists (it has no `.sh` suffix, so the `scripts/*.sh`
glob does not cover it).

Add `/etc/lyona-release` removal to `uninstall`.

### `archiso/airootfs/root/lyona-postinstall.sh`

Pass the ISO's own provenance through to the target install so an ISO-installed
machine records a real commit rather than `unknown`. The values are already
computed for `/etc/lyona-iso-release`; read them from that file on the live
medium and export `LYONA_SOURCE=iso` plus `LYONA_COMMIT` across the `install.sh`
invocation at `lyona-postinstall.sh:243-245`.

Also copy `/etc/lyona-iso-release` itself to the target as
`/etc/lyona-iso-release` — it records which *image* built the machine, which
stays true after later updates and is useful for support even once
`/etc/lyona-release` has moved on.

### `install.sh`

No behaviour change needed — it delegates to the Makefile targets, which now
stamp. Add the resulting version to the completion summary
(`print_install_summary` neighbourhood) so the installer's last line states what
was installed.

---

## Tests

### New: `tests/test-lyona-version.sh`

Following `tests/lib.sh` conventions (`make_workspace`, `assert_line`,
`assert_contains`, `fail`):

| Case | Assertion |
| --- | --- |
| No records | `state defaults`, exit 0, no file created |
| Both records, agreeing | `state available`, `consistent yes` |
| System only | `state partial`, names the missing user record |
| Version mismatch system vs user | `consistent no`, both values reported |
| Binary mismatch | `consistent no` — the half-applied-install case |
| Malformed record | `state unavailable`, file preserved byte-for-byte |
| Symlinked record | `state unavailable`, link target never read or written |
| World-writable record | `state unavailable` |
| `print` with no records | prints `unknown`, exit 0 |
| `--json` | valid JSON, same values as the tab-separated form |

### Extend: `tests/test-install-preservation.sh`

- A stamp is written by `install-system` and `install-user`.
- A **failed** install writes no stamp (stage the failure by making a target
  path unwritable).
- Re-running an install over an existing stamp replaces it rather than
  appending.

### Extend: `tests/test-arch-iso-builder.sh`

It already asserts the staged `/etc/lyona-iso-release`
(`test-arch-iso-builder.sh:644-676`). Add: the postinstall script exports
`LYONA_SOURCE=iso` and a commit into the `install.sh` invocation.

### `Makefile`

`check-lyona-version:` target running the new test; added to `check:` and
`.PHONY`.

---

## Verification

```bash
scripts/run-tests make check-lyona-version
scripts/run-tests make check-install-preservation check-arch-iso-builder
scripts/run-tests make check-shell check-format
scripts/run-tests make check
```

End to end, on a disposable Arch VM (per `docs/RELEASING.md`, not `/tmp`):

1. Fresh existing-system install → `/etc/lyona-release` and
   `~/.local/state/lyona/install.state` both exist, agree, and match `dwm -v`.
   `lyona-version status` reports `available` / `consistent yes`.
2. `lyona-version print` returns the `config.mk` version.
3. Simulate a half-applied install — reinstall only `install-user` from a tree
   with a bumped `config.mk` — and confirm `consistent no` naming both values.
4. On a machine installed from the ISO, confirm `LYONA_SOURCE=iso` and a real
   commit hash, not `unknown`.
5. Confirm a pre-provenance machine (delete both records) reports `defaults`
   and still exits 0 — upgrading *into* provenance must not error.
