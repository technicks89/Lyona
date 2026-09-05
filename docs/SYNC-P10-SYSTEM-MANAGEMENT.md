# Sync Phase 10 — system management (OS package updates)

Upstream: `#207`–`#228` (merged) and
[PR #229](https://github.com/ChrisTitusTech/dwm-titus/pull/229)
`feat(system): recover exact PackageKit operation evidence` (open at survey time).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

**Planned, scheduled after Lyona's own Phase 6.** This is the largest single body of
upstream work — ~12,200 lines, roughly half of everything upstream landed after the
fork — and it is the one place where a straight port is impossible: the whole thing
is written against PackageKit on Fedora.

This document plans the Arch port properly, so the work is ready to start when its
prerequisites land.

## Position in the sequence

```
Sync Phases 1–9              close Lyona's Phase 5
        ↓
UPDATE-001  P6-UPDATE-PROVENANCE.md   an installed system states what it runs
UPDATE-002  P6-UPDATE-HELPER.md       lyona-update: check, stage, apply, roll back
UPDATE-003  P6-UPDATE-SURFACE.md      Settings + Control Center over that helper
        ↓
Sync Phase 10 (this document)         OS package updates, SM-001 … SM-007
```

Lyona's Phase 6 comes first for a reason that is not sequencing dogma: an installed
Lyona system currently has **no version marker at all**
([`P6-UPDATE-OVERVIEW.md`](P6-UPDATE-OVERVIEW.md) verifies this —
`/etc/lyona-iso-release` is written into the live medium's airootfs and never copied
to the target root), and nothing ever reads back the checksummed backup
`dev-sync-install.sh:244-300` already writes. A user cannot update Lyona at all. A
CachyOS user can already run `pacman -Syu`. The thing that does not work goes first.

`AGENTS.md` also forbids opening the next phase inside a change scoped to complete
the current one, so SM-001 cannot start while Phase 5 is active (`ROADMAP.md:301`).

### Relationship to `lyona-update`

They are different products and must not be merged:

| | `lyona-update` (UPDATE-002) | `dwm-system-management` (this phase) |
| --- | --- | --- |
| Updates | Lyona itself — C binary, scripts, QML, config | Distribution packages |
| Source | GitHub Releases | Arch / CachyOS repositories |
| Rollback | `backup_live_install()` restore | `pacman` cache + `/var/log/pacman.log` |
| Privilege | Unprivileged, one confirmed step | Root, polkit-mediated |

They **share one surface**: Settings → System. UPDATE-003 builds that pane; SM-004
adds a second section to it rather than a second pane. Design UPDATE-003's pane with
that in mind — a section list, not a single-purpose view.

---

## The key finding: upstream already has the seam

The stack is not a monolith. It has a clean three-layer split, and only the bottom
layer is PackageKit-specific:

| Layer | Lines | Location | Port disposition |
| --- | --- | --- | --- |
| **Journal** — frame codec, record codecs, directory chain, atomic commit, locking, state load/validate, admission, operation IDs | ~2,780 | `dwm-system-management:186-2780` | **Provider-agnostic.** Ports as-is bar two renames |
| **Snapshot / plan model** — `Package`, `UpdateRow`, `PlanRow`, `build_snapshot`, `confirmed_update_plan`, protocol emission | ~950 | `:2790-3730` | Ports with an enum-vocabulary decision |
| **Provider** — `PackageKitBackend`, `PackageKitMutation`, D-Bus, GLib error classification | ~670 | `:3734-4406` | **Replaced entirely** by `PacmanBackend` |

The seam is an explicit `Protocol` at `dwm-system-management:2845` — three methods:

```python
class UpdateBackend(Protocol):
    def last_refresh_age(self) -> int:
        """Return PackageKit's seconds-since-refresh value."""

    def updates(self) -> TransactionResult:
        """Return the complete bounded GetUpdates result."""

    def simulate(self, package_ids: Sequence[str]) -> TransactionResult:
        """Return the complete bounded SIMULATE|ONLY_TRUSTED plan."""
```

`build_snapshot(backend)` (`:3286`) and `confirmed_update_plan(backend, generation)`
(`:3018`) take that Protocol, not a PackageKit object. **A `PacmanBackend`
implementing three methods drops into both unchanged.** That is what makes this port
tractable rather than a rewrite.

---

## Couplings to break

Four places where PackageKit leaked past the seam. Fix these in SM-002, before any
Arch code is written on top of them.

### 1. `JournalOperation.transaction_path`

`:248` carries a PackageKit object path, validated against
`JOURNAL_PACKAGEKIT_PATH_PATTERN` at `:968` and `:1010`:

```python
        if (
            not isinstance(record.transaction_path, str)
            or JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(record.transaction_path) is None
        ):
            raise JournalRecordError("journal PackageKit path is invalid")
```

Rename the field and widen the pattern — a mechanical sweep through the codec, the
`_journal_operation_fields()` tuple, and `tests/test-system-management.py`:

```diff
-    transaction_path: str | None
+    transaction_ref: str | None
```
```diff
-JOURNAL_PACKAGEKIT_PATH_PATTERN = re.compile(r"...")
+# An opaque, provider-issued operation reference. PackageKit supplies an object
+# path; pacman supplies the transaction's log anchor. The journal only needs it
+# to be bounded, printable, and stable for the life of the operation.
+JOURNAL_TRANSACTION_REF_PATTERN = re.compile(r"[!-~]{1,128}")
```

**Do not synthesize a fake PackageKit path from pacman.** The journal is a durable
record read after a crash; a fabricated identifier is worse than an honest opaque
one.

### 2. `package_id` format

`package_display_fields()` (`:2828`) splits PackageKit's four-field identity:

```python
    parts = package_id.split(";", 3)
    if len(parts) != 4 or not parts[0] or not parts[1]:
```

`name;version;arch;data` maps onto pacman's fields with no loss —
`name;version;arch;repo`. **Keep the format and have `PacmanBackend` emit it.** That
leaves the entire snapshot layer, the protocol, and the QML model untouched, and it
is the single cheapest decision in this port.

### 3. `Package.info` and `TransactionResult.restart_types` enums

Both are PackageKit integer enums (`INFO_*`, `RESTART_*`). `PacmanBackend` maps onto
the same integers rather than introducing a parallel vocabulary — same reasoning as
above. Document the mapping in `docs/P6-SYSTEM-MANAGEMENT.md` so the constants are
not mistaken for a live PackageKit dependency.

### 4. Operator-facing strings

`SnapshotFailure` messages say "PackageKit returned an oversized identity"
(`:2862`, `:2874`, `:2886`, `:2898`, …). These reach the Settings pane. Sweep to the
provider's own name; the failure taxonomy (`malformed`, `unsupported`, …) stays.

---

## Two semantics Arch genuinely does not have

These are not translation problems. Report them honestly rather than faking a value.

### Security severity

`packagekit_security_floor()` (`:3446`) classifies updates by PackageKit's
`INFO_SECURITY`. **The pacman sync database carries no security classification.**
There is no field to read.

- **Default:** every `UpdateRow.severity` is `unknown`, and the security floor is
  reported `unsupported` through the capability record. The pane shows an update
  count with no security breakdown, which is the truth.
- **Optional:** `arch-audit` queries the Arch Security Tracker for CVEs against
  installed packages. If present, wire it behind its own capability — it is a
  network call, so it must never block the bounded snapshot, and it must degrade to
  `unknown` when offline. Its data covers Arch proper; CachyOS's own packages are
  not tracked, which the capability detail must say.

### Restart requirements

PackageKit reports `RESTART_SYSTEM` / `SESSION` / `APPLICATION` per transaction.
Pacman reports nothing.

Derive a heuristic, and — this is the part that matters — make it produce
**`unknown`**, not `no`, outside the cases it actually covers:

| Update set contains | `system_restart` |
| --- | --- |
| `linux`, `linux-*`, `linux-cachyos*` | `yes` |
| `systemd`, `glibc`, `dbus` | `yes` |
| anything else | `unknown` |

`JOURNAL_RESTART_SYSTEM_VALUES` and `JOURNAL_RESTART_SESSION_VALUES` must gain
`unknown` for this. A heuristic that guesses `no` tells a user it is safe not to
reboot after a glibc-adjacent update, which is the one failure mode worth designing
against. `needrestart` is the mature version of this heuristic and is worth
evaluating at SM-006 rather than reimplementing.

---

## `PacmanBackend`

New, replacing `PackageKitBackend` (`:3734-4406`). Roughly 300 lines against
upstream's 670 — no D-Bus, no GLib error taxonomy, no transaction object lifecycle.

```python
class PacmanBackend:
    """Read-only update discovery over the pacman sync databases.

    Nothing here acquires the live pacman lock or writes to /var/lib/pacman.
    checkupdates(8) maintains its own database copy under the user's cache and
    symlinks the real local database into it read-only, which is what makes a
    rootless, non-mutating snapshot possible at all.
    """

    def last_refresh_age(self) -> int:
        """Seconds since the *least* recently synced repository database.

        The oldest database is the honest answer: reporting the newest would
        hide a repository that failed to sync during the last -Sy.
        """

    def updates(self) -> TransactionResult:
        """Bounded `checkupdates` result, as name;version;arch;repo rows."""

    def simulate(self, package_ids: Sequence[str]) -> TransactionResult:
        """Bounded dependency-resolved plan, rootless, against the checkupdates
        database copy."""
```

### `updates()` — settled

`checkupdates` from `pacman-contrib`. It copies the sync databases to
`${CHECKUPDATES_DB:-$XDG_CACHE_HOME/checkup-db-$UID}`, syncs *that* copy, and never
touches `/var/lib/pacman/sync` or takes the live lock. Rootless and non-mutating,
which is exactly the property upstream's bounded snapshot requires. Output is
`name oldver -> newver`; the repository comes from `pacman -Sy --dbpath` on the copy
or from `expac`.

Bound it the way upstream bounds PackageKit: a wall-clock deadline, a maximum record
count, and rejection of oversized or non-printable identities via the existing
`clean_text` / `canonical_identity` helpers (`:2851-2886`), which port unchanged.

### `simulate()` — needs verification before SM-002 is written

The plan must include dependencies that are not themselves upgrades, so `pacman -Qu`
is insufficient. The intended approach:

```
pacman -Sup --print-format '%n %v %r' --dbpath "$CHECKUPDATES_DB"
```

against the `checkupdates` database copy — the lock lives in that dbpath, so it
should resolve rootless without touching the system database.

> **Verify this on a real CachyOS install before writing SM-002.** It is the one
> mechanism in this plan not confirmed against a live system, and the whole
> read-only guarantee rests on it. If `--dbpath` still demands root or the live
> lock, the fallback is a polkit-mediated read-only helper — which changes SM-002's
> privilege model, so it must be settled first, not discovered mid-implementation.

---

## Boundaries

Each is one reviewable commit, in order.

| | Delivers | Upstream | Approx. lines |
| --- | --- | --- | --- |
| **SM-001** | Contract: `docs/P6-SYSTEM-MANAGEMENT.md` rewritten for pacman, `arch:system-management` package profile, `install.sh` wiring, capability records | `#207` | ~900 |
| **SM-002** | `scripts/dwm-system-management` snapshot layer + `PacmanBackend`; the four decouplings above | `#208` adapted | ~1,300 |
| **SM-003** | `config/quickshell/systemmanagement/SystemManagementModel.qml` | `#209` | ~590 |
| **SM-004** | Read-only update section in Settings → System | `#210` | ~390 |
| **— decision point —** | See below | | |
| **SM-005** | Durable operation journal | `#211`–`#223` | ~2,780 |
| **SM-006** | Execution owner, restart evidence | `#224`–`#228` | ~1,300 |
| **SM-007** | Operation UI, recovery surfaces | `#229` + upstream's remaining work | ~700 |

### The decision point after SM-004

**SM-001 → SM-004 is read-only and independently valuable**: roughly 3,200 lines
that report what updates are available, with no ability to apply them. That sits
naturally beside `lyona-update` and carries none of the journal machinery.

Before starting SM-005, decide whether the journal is warranted at all. Upstream's
~2,780-line journal exists to make *PackageKit D-Bus transactions* durable across a
crash — to answer "did that transaction commit?" when the daemon is gone and the
only evidence is a transient object path.

Pacman answers that question itself:

- `/var/log/pacman.log` is an append-only transaction record with timestamps.
- `/var/cache/pacman/pkg` holds every previously installed version, so a downgrade
  is `pacman -U` against the cache.
- `pacman -Qu` after a crash is authoritative about what is still pending.

So the honest options at that point are:

1. **Stop at SM-004.** Read-only reporting; applying updates stays a terminal task
   or `lyona-update`'s job. Smallest surface, no root path, no journal.
2. **SM-005-lite.** Skip the journal; implement SM-006's execution over a polkit
   action, and reconstruct state from `pacman.log` after a crash instead of from a
   private journal. Perhaps 400 lines in place of 4,000.
3. **Full port.** Only if a concrete failure is found that `pacman.log` and the
   package cache cannot answer.

**The recommendation is option 2**, revisited with SM-004 shipped and real usage
behind it. Record the decision here when it is made.

---

## Packages

`scripts/dwm-packages.sh` — Lyona has no `pacman-contrib` today, so `checkupdates`
is absent:

```diff
+	arch:system-management)
+		# checkupdates(8) from pacman-contrib is what makes a rootless,
+		# non-mutating update snapshot possible: it syncs its own database
+		# copy instead of /var/lib/pacman/sync.
+		printf '%s\n' pacman-contrib
+		;;
+	arch:system-management-optional)
+		# arch-audit adds CVE severity, which the pacman database does not
+		# carry. Optional: it needs the network and does not cover CachyOS
+		# packages.
+		printf '%s\n' arch-audit
+		;;
```

```diff
 	arch:recommended)
 		dwm_packages "$family" desktop
+		dwm_packages "$family" system-management
 		dwm_packages "$family" screenshot-optional
```

```diff
 	arch:optional)
 		dwm_packages "$family" theme-optional
 		dwm_packages "$family" desktop-optional
+		dwm_packages "$family" system-management-optional
```

Plus `archiso/packages.x86_64`, `scripts/check-deps.sh`, and assertions in
`tests/test-arch-packages.sh`.

Upstream's `fedora:system-management` also pulls `accountsservice`, `cups`,
`system-config-printer`, `lxqt-admin` and `dnfdragora` — unrelated to updates, part
of their broader "system management" grouping. **Not ported.** Lyona's profile covers
updates only.

`python3-gobject` / `python3-rpm` are PackageKit dependencies and are not needed;
`PacmanBackend` shells out to `checkupdates` and `pacman` rather than binding a
library.

---

## Testing

`tests/test-system-management.py` is 5,134 lines and Lyona's only Python test. It
runs through `scripts/run-tests`, matching upstream.

Port disposition mirrors the layer split:

| Upstream tests for | Disposition |
| --- | --- |
| Journal codecs, layout, recovery, admission (the bulk) | Port with SM-005, if SM-005 happens. Provider-agnostic, high value, exercises the atomic-commit paths that are hardest to get right |
| Snapshot bounds, malformed-identity rejection, protocol emission | Port with SM-002, retargeted at `PacmanBackend` |
| PackageKit D-Bus fixtures, GLib error classification, transaction adoption | **Discard.** Replaced by `checkupdates` and `pacman --print` fixtures |

Fixtures for `PacmanBackend` are ordinary files — a fake `checkupdates` on `PATH`,
a temporary `CHECKUPDATES_DB`, a stub `pacman` — which is markedly easier to test
than a D-Bus daemon. Upstream's own qualification needed a live Fedora box; SM-002's
should not.

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-shell
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-arch-packages
scripts/run-tests make check-quickshell-system-management
scripts/run-tests make check-quickshell-system-management-xvfb
```

Manual, per boundary, on a real CachyOS install:

**SM-002 — prove it is read-only.** This is the boundary's whole claim:

```bash
sudo cp -a /var/lib/pacman/sync /tmp/sync-before
dwm-system-management snapshot
sudo diff -r /var/lib/pacman/sync /tmp/sync-before   # must be identical
```

Also confirm `/var/lib/pacman/db.lck` is never created, and that the snapshot runs
as an unprivileged user with no polkit prompt.

**SM-002 — bounds and degradation.** Snapshot with the network down (stale age
reported, not a hang); with `pacman-contrib` uninstalled (capability `unavailable`,
no traceback); against a repository with several hundred pending updates (record cap
enforced, deadline honoured).

**SM-003 / SM-004.** Open Settings → System with updates pending and with none.
Confirm the pane coexists with UPDATE-003's `lyona-update` section rather than
replacing it. Closed-CPU baseline with the pane open — the snapshot must be
on-demand, not polled.

**Kernel case.** With a `linux-cachyos` update pending, confirm the restart
requirement reads `yes`; with only a leaf application pending, confirm it reads
`unknown` and not `no`.

---

## Open decisions

Settle each before the boundary that depends on it:

| # | Decision | Needed by |
| --- | --- | --- |
| 1 | Does `pacman -Sup --dbpath "$CHECKUPDATES_DB"` resolve rootless on CachyOS? | SM-002 |
| 2 | AUR / `paru` updates in scope? Lyona ships no AUR helper today; recommendation is **out of scope** — an AUR rebuild is not comparable to a repository update | SM-001 |
| 3 | CachyOS `v3`/`v4` ISA repositories — does the snapshot need to report which is active? `scripts/lyona-cachyos` already detects it | SM-002 |
| 4 | Journal, lite, or stop at read-only (options 1–3 above) | SM-005 |
| 5 | Does upstream's Phase 6 close, and does it stay on PackageKit? Re-survey before SM-001 | SM-001 |

## Re-survey before starting

Upstream was mid-flight at survey time. PR #229's own summary:

> This is one provider recovery boundary, not Phase 6 completion. Snapshot/control
> integration, root-scoped operation ownership and confirmation, regional/delegated
> entry points, information/recovery surfaces, and combined qualification remain in
> TASKS.md.

Public mutation commands and the operation UI were still disabled. Re-read
`docs/P6-SYSTEM-MANAGEMENT.md` in the upstream tree before SM-001 — 1,664 lines of
protocol contract, and the only document explaining why the journal is shaped as it
is. Read it before the code.
