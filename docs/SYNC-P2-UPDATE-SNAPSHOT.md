# Sync Phase 2 — bounded read-only update snapshot

Upstream: [`#208`](https://github.com/ChrisTitusTech/dwm-titus/pull/208)
(`bd87fd3c`, +859 helper lines), with the later corrections
[`#232`](https://github.com/ChrisTitusTech/dwm-titus/pull/232) (`0fa2ef41`) and
[`#241`](https://github.com/ChrisTitusTech/dwm-titus/pull/241) (`65138a89`)
folded in. Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md) — the language
decision and the contract document must both be settled first.

Delivers `scripts/dwm-system-management snapshot`: one bounded, read-only,
machine-readable protocol-minor-0 snapshot of pending system updates. No
mutation, no journal, no root, no polkit prompt.

---

## Files

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | **New.** ~900 lines: bounds, codecs, `UpdateBackend`, `PackageKitBackend`, `build_snapshot`, `main` |
| `tests/test-system-management.py` | **New.** Port of upstream's `#208` test block, retargeted |
| `Makefile` | `check-system-management` (registered in Phase 1) |

---

## 1. Bounds come first

Every limit is a module constant, and every one of them is load-bearing —
this helper's whole safety claim is that a hostile or broken package database
cannot make it allocate without limit or run without end.

```python
PROTOCOL_MAJOR = 1
PROTOCOL_MINOR = 0
SNAPSHOT_MINOR = 0          # bumped to 1 by Phase 8
MAX_TEXT_BYTES = 512
MAX_LIST_RECORDS = 4096
MAX_LIST_BYTES = 3 * 1024 * 1024
READ_DEADLINE_SECONDS = 120
REFRESH_AGE_DEADLINE_SECONDS = 10
```

The three helpers that enforce them (`clean_text` `:4828`,
`canonical_identity` `:4843`, `enforce_list_budget` `:4867`) port unchanged.
`clean_text` replaces tab, CR and LF with spaces before truncation, which is
what makes the tab-separated protocol unspoofable from a package summary.

## 2. The seam that makes this port tractable

`UpdateBackend` is an explicit `typing.Protocol` with three methods:

```python
class UpdateBackend(Protocol):
    def last_refresh_age(self) -> int:
        """Return PackageKit's seconds-since-refresh value."""

    def updates(self) -> TransactionResult:
        """Return the complete bounded GetUpdates result."""

    def simulate(self, package_ids: Sequence[str]) -> TransactionResult:
        """Return the complete bounded SIMULATE|ONLY_TRUSTED plan."""
```

`build_snapshot(backend, ...)` (`:5655`) and
`confirmed_update_plan(backend, generation)` (`:4993`) take that Protocol, not
a PackageKit object. Anything implementing three methods drops into both.

**Under Option A this seam is not exercised in this phase** —
`PackageKitBackend` is the backend, because PackageKit's alpm backend is what
Arch ships (verified in
[Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#the-second-finding-that-reframes-the-whole-port)).
Port it as-is. Keep the Protocol anyway: it is what makes the test suite able
to drive the whole snapshot layer from fixtures, without a live bus.

Under **Option C** this seam is the entire phase — implement a `PacmanBackend`
against `checkupdates(8)` and drop `PackageKitBackend`. See §6.

## 3. The four Fedora couplings to break

These are the only places where the platform leaks past the seam. Fix all four
here, before anything is built on top.

### 3a. Platform identity

```diff
 def read_fedora_identity() -> dict[str, str]:
+    # Renamed read_platform_identity in Lyona.
     ...
-        if identity.get("ID") != "fedora":
-            raise SnapshotFailure("unsupported", "System changes are supported only on Fedora", "unsupported")
+        if identity.get("ID") != "arch" and "arch" not in identity.get("ID_LIKE", "").split():
+            raise SnapshotFailure("unsupported", "System changes are supported only on Arch", "unsupported")
         return identity
```

Add `ID_LIKE` to the fixed key set the parser accepts — upstream reads only
`ID` and `VERSION_ID`, and CachyOS reports `ID=cachyos` with
`ID_LIKE="arch"`. Verify the real value on the qualification host rather than
assuming; `scripts/lyona-cachyos` already does this detection for other
purposes and is the reference.

The parser itself (bounded 64 KiB read, `shlex.split` per line, refusal of
duplicate keys, no shell evaluation) ports unchanged and is worth keeping
exactly as written.

### 3b. The RPM version gate

`require_mutation_safe()` (`:6630`) imports `rpm`, queries the RPM database
for PackageKit's NEVR, and compares with `rpm.labelCompare` against `1.3.5`
or Fedora 44's `1.3.4-3.fc44` backport. `packagekit_security_floor()`
(`:5826`) is that comparison.

Arch ships PackageKit 1.3.6 in `extra` — above the floor — and has no RPM
database. Replace the whole mechanism with the daemon's own D-Bus properties,
which upstream already reads in the same function:

```diff
-        import rpm
-        headers = []
-        for header in rpm.TransactionSet().dbMatch("name", "PackageKit"):
-            ...
-        if not packagekit_security_floor(headers[0]["version"], headers[0]["release"],
-                                        identity.get("VERSION_ID", ""), version, rpm.labelCompare):
-            raise ValueError
-        if version == (1, 3, 4):
-            self._require_running_backport_identity()
+        # Arch has no RPM database and no distribution backport to disambiguate.
+        # The running daemon's own version properties are the whole gate.
+        if not all(type(value) is int for value in version) or version < (1, 3, 5):
+            raise ValueError
```

Delete `packagekit_security_floor()` and
`_require_running_backport_identity()` outright rather than leaving dead
Fedora code behind. Keep the surrounding
`SnapshotFailure("unsupported", ...)` shape and retune its message:

```diff
-            "unsupported", "PackageKit requires 1.3.5 or Fedora 44 security backport 1.3.4-3.fc44", "unsupported"
+            "unsupported", "PackageKit 1.3.5 or newer is required", "unsupported"
```

> This is the one place the port *reduces* complexity rather than translating
> it. Do not synthesize an equivalent alpm-database query to "keep parity" —
> there is nothing on Arch that the daemon's own version does not already say.

### 3c. Operator-facing strings

`SnapshotFailure` messages naming "PackageKit" reach the Settings pane and are
correct on Arch too — PackageKit really is the provider. **Do not sweep them.**
This reverses `SYNC-P10-SYSTEM-MANAGEMENT.md`'s coupling #4, which assumed the
provider was being replaced. Only the *Fedora*-naming strings change (§3a,
§3b).

### 3d. DNF5 install previews

`0fa2ef41` (`#232`) is five helper lines preserving install-kind actions in a
DNF5 preview. Read the diff before porting: if the behaviour it preserves is
DNF5-specific, it is **not ported**, and that must be recorded as a deliberate
exclusion in `docs/P6-SYSTEM-MANAGEMENT.md` rather than silently dropped.
Confirm against the alpm backend's actual `SIMULATE` output on the
qualification host.

## 4. What `package_id` means on Arch

`package_display_fields()` (`:4854`) splits PackageKit's four-field identity:

```python
    parts = package_id.split(";", 3)
    if len(parts) != 4 or not parts[0] or not parts[1]:
```

That is `name;version;arch;data`. PackageKit's alpm backend emits the same
four fields, with the repository in `data` — so **nothing here changes**, and
the entire snapshot layer, protocol, and QML model are untouched by the
distribution difference. Verify one real row on the qualification host before
relying on it:

```bash
pkcon --plain get-updates | head
busctl --system call org.freedesktop.PackageKit /org/freedesktop/PackageKit \
  org.freedesktop.PackageKit CreateTransaction   # then GetUpdates on the path
```

## 5. Two semantics to report honestly

### Security severity

`UpdateRow.severity` comes from PackageKit's `INFO_SECURITY`. The alpm backend
has no security classification to report, because the pacman sync databases
carry none. Every row will be `unknown`, which is the truth.

`arch-audit` (`extra`, shipped as `arch:system-management-optional` in Phase 1)
queries the Arch Security Tracker. If it is wired in later it must be behind
its own capability, must never block the bounded snapshot (it is a network
call), must degrade to `unknown` offline, and its capability detail must state
that CachyOS's own packages are not tracked. **Out of scope for this phase** —
land the honest `unknown` first.

### Restart requirements

`TransactionResult.restart_types` comes from PackageKit's `RESTART_*` enums
and `aggregate_restart()` (`:4953`) folds them. Whether the alpm backend
populates them at all is **unverified** and must be checked on the
qualification host before this phase is written.

If it does not, derive a heuristic — and make it produce `unknown`, never
`no`, outside the cases it covers:

| Update set contains | `update-restart` |
| --- | --- |
| `linux`, `linux-*`, `linux-cachyos*` | `yes` |
| `systemd`, `glibc`, `dbus` | `yes` |
| anything else | `unknown` |

A heuristic that guesses `no` tells a user it is safe not to reboot after a
glibc update. That is the one failure mode worth designing against.
`JOURNAL_RESTART_SYSTEM_VALUES` and `JOURNAL_RESTART_SESSION_VALUES` gain
`unknown` for this (they are added in
[Phase 5](SYNC-P5-OPERATION-JOURNAL.md); note the requirement here so it is
not forgotten). `needrestart` is the mature version of this heuristic and is
worth evaluating rather than reimplementing.

## 6. If Option C was chosen — `PacmanBackend`

Roughly 300 lines replacing `PackageKitBackend`'s ~1,100: no D-Bus, no GLib
error taxonomy, no transaction lifecycle.

```python
class PacmanBackend:
    """Read-only update discovery over the pacman sync databases.

    Nothing here acquires the live pacman lock or writes to /var/lib/pacman.
    checkupdates(8) maintains its own database copy under the user's cache,
    which is what makes a rootless, non-mutating snapshot possible at all.
    """

    def last_refresh_age(self) -> int:
        """Seconds since the *least* recently synced repository database.

        The oldest database is the honest answer: reporting the newest would
        hide a repository that failed to sync during the last -Sy.
        """

    def updates(self) -> TransactionResult:
        """Bounded `checkupdates` result, as name;version;arch;repo rows."""

    def simulate(self, package_ids: Sequence[str]) -> TransactionResult:
        """Bounded dependency-resolved plan, rootless, against the
        checkupdates database copy."""
```

`updates()` is settled: `checkupdates` from `pacman-contrib` copies the sync
databases to `${CHECKUPDATES_DB:-$XDG_CACHE_HOME/checkup-db-$UID}`, syncs
*that* copy, and never touches `/var/lib/pacman/sync` or takes the live lock.

`simulate()` is **not** settled. `pacman -Qu` is insufficient — the plan must
include dependencies that are not themselves upgrades. The intended mechanism
is:

```bash
pacman -Sup --print-format '%n %v %r' --dbpath "$CHECKUPDATES_DB"
```

> **Verify on a real CachyOS install before writing any of this.** It is the
> one mechanism here never confirmed against a live system, and the whole
> read-only guarantee rests on it. If `--dbpath` still demands root or the
> live lock, the fallback is a polkit-mediated read-only helper — which
> changes the privilege model and must be settled first, not discovered
> mid-implementation. Tracked as open decision **D-4** in
> [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#open-decisions).

## 7. Tests

Upstream's `tests/test-system-management.py` reaches 11,577 lines at
`dd55e58`. `#208`'s share is roughly 350. Port that share, retargeted:

| Upstream test area | Disposition |
| --- | --- |
| Snapshot bounds, oversized/non-printable identity rejection, list budget | **Port.** Provider-agnostic, high value |
| Protocol record emission and completion marker | **Port** |
| `package_display_fields` four-field parsing | **Port** |
| RPM `labelCompare` security-floor cases | **Discard** with §3b |
| Fedora `/etc/os-release` identity cases | **Rewrite** for `arch` / `ID_LIKE` |
| PackageKit D-Bus fixtures, GLib error classification | **Port** — the same interface exists on Arch |

Fixtures are ordinary files plus a stub bus; upstream's own
`tests/fixtures/system-*-bus.py` pattern is the model, and those fixtures are
Python for the same reason the helper is.

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-system-management
scripts/run-tests make check-install
```

Manual, on a real CachyOS install — **prove it is read-only**, which is this
phase's entire claim:

```bash
sudo cp -a /var/lib/pacman/sync /tmp/sync-before
dwm-system-management snapshot
sudo diff -r /var/lib/pacman/sync /tmp/sync-before   # must be identical
test ! -e /var/lib/pacman/db.lck                      # must never appear
```

Run it as an unprivileged user and confirm **no polkit prompt appears**.

Bounds and degradation:

- Network down — a stale refresh age is reported, not a hang.
- `packagekit` uninstalled — capability `unavailable`, no traceback.
- `python-gobject` uninstalled — `missing-provider` / `unavailable`, no
  traceback. This is the guarded lazy import from
  [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#what-upstream-actually-built-verified-at-dd55e58-2026-09-07)
  and it must be exercised.
- Several hundred pending updates — the record cap is enforced and the
  deadline honoured.

Kernel case: with a `linux-cachyos` update pending, `update-restart` reads
`yes`; with only a leaf application pending it reads `unknown`, **not** `no`.

## Closes

Nothing on its own — the snapshot has no consumer until
[Phase 3](SYNC-P3-SYSTEM-PANE.md). Land them as a pair if a reviewer prefers,
but they are separable and this one carries all the risk.
