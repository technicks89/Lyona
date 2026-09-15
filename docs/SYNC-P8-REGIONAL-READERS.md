# Sync Phase 8 — regional, account, printer, and repository readers

Upstream: [`#242`](https://github.com/ChrisTitusTech/dwm-titus/pull/242)
(`61beab4e`), [`#243`](https://github.com/ChrisTitusTech/dwm-titus/pull/243)
(`1c3249ac`), [`#244`](https://github.com/ChrisTitusTech/dwm-titus/pull/244)
(`75a21ba8`), [`#245`](https://github.com/ChrisTitusTech/dwm-titus/pull/245)
(`0b0d1b59`), [`#246`](https://github.com/ChrisTitusTech/dwm-titus/pull/246)
(`68b6f4df`), [`#248`](https://github.com/ChrisTitusTech/dwm-titus/pull/248)
(`9d05092a`). Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md) for the generic monitor
shape (not used yet — this phase is one-shot reads only) and on the
[decision recorded in Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md) about who
owns `dwm-system-management`.

Adds the four read-only sources protocol minor `1` needs: system timezone and
NTP state, system locale, the local `AccountsService` account list, CUPS's
running state, and the PackageKit repository list. **No mutation, no D-Bus
write of any kind.** Every reader here is a bounded, single-use, read-only
`Gio` transaction with its own deadline — the same `ServiceRead` base class
[Phase 2](SYNC-P2-UPDATE-SNAPSHOT.md)'s update reader already established.

---

## Files

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | `ServiceRead`, `RegionalRead`, `AccountRead`, `CupsRead`, `RepositoryRead` and their validation/decode helpers |
| `tests/fixtures/system-regional-read-bus.py`, `system-locale-process.py`, `system-account-read-bus.py`, `system-cups-read-bus.py`, `system-repository-read-bus.py` | **New** — private-bus/private-process qualification harnesses for each reader |
| `tests/test-system-management.py` | `RegionalValidationTests`, `RegionalReadTests`, `LocaleEnumerationTests`, `AccountReadTests`, `CupsReadTests`, `RepositoryReadTests` |

> **Scope correction, found while implementing.** The original version of
> this table also listed `docs/P6-SYSTEM-MANAGEMENT.md` ("fill in stubs" —
> it was not a stub; already fully written, evidently from earlier work),
> `SystemManagementModel.qml`, `SystemSettingsPane.qml`, and `shell.qml`.
> None of upstream's six Phase 8 PRs (`#242`–`#246`, `#248`) touch the
> snapshot protocol, any QML file, or `shell.qml` at all — they add the five
> readers as standalone classes with **no caller**. The record-emitting
> caller (`NativeSnapshotSources`, `build_native_snapshot()`) that would
> wire these into `snapshot`'s output, add the `timezone-set`/`ntp-set`/
> `locale-set`/`*-open` mutation and delegate actions, and call
> `read_fedora_identity()`-gated `admission()`, exists only much later in
> upstream's history (found at the `dd55e58` full-repo survey point, not in
> any commit these six PRs' own citations name) — it is Sync Phase 9
> material by its own content (mutation actions, `delegate()`, the Fedora
> identity gate), not this phase's. See §7 below.

---

## 1. What each reader actually does (verified at `dd55e58`)

All five are `ServiceRead` subclasses (`scripts/dwm-system-management:1055`
onward) — a bounded async `Gio` call with a deadline timer, never a
blocking/synchronous D-Bus round trip. None of them touch PackageKit.

| Reader | Interface | What it reads |
| --- | --- | --- |
| `RegionalRead("time-state")` | `org.freedesktop.timedate1` (`Get`/property reads) | `Timezone`, `LocalRTC` |
| `NtpRead` | `org.freedesktop.timedate1` (`Properties.Get`, one call per property) | `CanNTP`, `NTPSynchronized` — the two properties that do **not** appear in `PropertiesChanged` and must be polled, not watched |
| `RegionalRead("locale-state")` | `org.freedesktop.locale1` | The full `Locale` string array, parsed into `LANG`/`LC_*` assignments |
| `AccountRead` | `org.freedesktop.Accounts` | `ListCachedUsers` + `FindUserById(getuid())`, then per-account `RealName`/`UserName`/`SystemAccount`/`LocalAccount` properties, concurrency-bounded (`ACCOUNT_PROPERTY_CONCURRENCY`) |
| `CupsRead` | `org.freedesktop.systemd1` `ListUnitsByNames` | `cups.service` + `cups.socket` unit states (`CUPS_UNITS`) — **not** a CUPS IPP connection, just "is the service up" |
| `RepositoryRead` | PackageKit `GetRepoList` | The only one of the five that *does* touch PackageKit — repository id/enabled/description |

Bind them together exactly as upstream's `NativeSnapshotSources` does
(`:5384`) — a class with **no constructor side effects**; each method call is
its own fresh `ServiceRead`, never a cached result:

```python
class NativeSnapshotSources:
    def time_state(self):
        return RegionalRead("time-state").run()
    def locale_state(self):
        return RegionalRead("locale-state").run()
    def accounts(self):
        return AccountRead().run()
    def printers(self):
        return CupsRead().run()
    def repositories(self):
        return RepositoryRead().run()
```

Port this shape, not a merged "read everything at once" function. Each source
fails independently — a `timedate1` outage must not blank the account list.

## 2. `AccountRead`'s bounding rules are the interesting part

`org.freedesktop.Accounts.ListCachedUsers` has no upper bound in the
interface contract. `AccountRead` (`:1507`) refuses to trust it:

- At most `ACCOUNT_LIMIT` candidates are kept, chosen by `bisect.insort`
  against a rolling sorted window — not "the first N returned," which would
  be order-dependent and therefore non-deterministic across daemon versions.
- The current user's own account (`FindUserById(os.getuid())`) is always
  included even if it would otherwise fall outside the window.
- Per-account property reads run at a fixed concurrency
  (`ACCOUNT_PROPERTY_CONCURRENCY`), not unbounded-parallel — this is a local
  systemd service, not a network endpoint, but the same "never let a slow
  remote pin an unbounded number of in-flight calls" rule applies everywhere
  else in this file.
- A **system account** (`SystemAccount == true`, e.g. a daemon UID) is
  **excluded** from the list unless it is the current user — never list every
  UID `>= 1000` machinery as if it were a login user.

Protocol record (already in [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md)'s
grammar table): `account<TAB>object-path<TAB>current|other<TAB>display-name<TAB>login-name`.

## 3. `CupsRead` is a systemd unit query, not a printer enumeration

Do not confuse this with reading the actual print queue. `CupsRead` asks
`systemd1.ListUnitsByNames(["cups.service", "cups.socket"])` — it answers
"is CUPS running," nothing about installed printers or their state. If a unit
does not exist (`org.freedesktop.systemd1.NoSuchUnit`), that is reported as
`load=not-found`, not treated as a connection failure — the honest answer to
"is CUPS installed" is "no," not "unavailable."

The protocol's `state` records for this domain (`cups-service`) reduce the
raw `UnitState` down to a small enum — port `classify_cups()` verbatim rather
than exposing the raw `active`/`sub` strings to QML.

## 4. `RepositoryRead` reuses the exact transaction dance Phase 2 built

`RepositoryRead` (`:728`) is structurally identical to the update snapshot's
PackageKit transaction handling from
[Phase 2](SYNC-P2-UPDATE-SNAPSHOT.md#the-transaction-handshake) — activate on
`NameHasNoOwner`, subscribe before dispatch, verify the owner has not changed
before trusting the collected rows, cancel on any failure after the fetch was
sent. **Do not re-derive this by hand**; extract the shared transaction
scaffolding once Phase 2 and this phase are both ported, rather than
duplicating ~80 lines of D-Bus bookkeeping a second time. Upstream itself
does not share this code between `TransactionResult` (updates) and
`RepositoryRead` (repositories) — that is upstream's own duplication, not a
constraint Lyona has to inherit.

Repository rows use `GetRepoList` with `filter_none` — Lyona's port must call
it against Arch's `alpm` backend the same way; the record shape
(`repository<TAB>id<TAB>enabled|disabled<TAB>description`) does not change
between backends, only the values PackageKit fills in from
`/etc/pacman.d/mirrorlist`/`pacman.conf`'s `[repo]` sections via
`etc/PackageKit/alpm.d/repos.list` ([Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#the-second-finding-that-reframes-the-whole-port)).

## 5. Fedora-specific code in this phase

Two spots, both small:

- `read_fedora_identity()` gate — `AccountRead`/`CupsRead`/`RepositoryRead`
  themselves do **not** call it (verified: it only appears in
  `RegionalMutation.run()` and `NativeSnapshotSources.admission()`, both
  [Phase 9](SYNC-P9-REGIONAL-MUTATION.md) territory). Nothing in this
  read-only phase needs the Arch identity substitution yet.
- Nothing else. The five readers above are entirely distro-neutral D-Bus
  clients against standard interfaces (`timedate1`, `locale1`, `Accounts`,
  `systemd1`, and PackageKit's own D-Bus surface).

## 6. No Settings pane surface in this phase

There is nothing to mount yet. The five readers this phase adds have no
caller — `build_snapshot()`/`build_managed_snapshot()` are untouched, so
`snapshot`'s protocol output carries no `region-state`/`account`/
`state\tcups-service`/`repository` records for them to feed. Wiring
`NativeSnapshotSources`/`build_native_snapshot()` into the snapshot output,
extending `SystemManagementModel.qml` to parse the new record kinds, adding
the `StatusCard` summary rows to `SystemSettingsPane.qml`, and the
`shell.qml` probes below are all [Phase 9](SYNC-P9-REGIONAL-MUTATION.md)'s
job — that function emits the read state *and* the `timezone-set`/
`ntp-set`/`locale-set`/`*-open` actions together, in one pass, so there is
no clean read-only half to split off into this phase without inventing a
snapshot shape upstream never actually shipped. See §5's note above.

```qml
        function systemManagementRegionalState(): string {
            const model = systemManagementModel;
            return model.regionalStatus + ":" + model.timezone + ":" + model.ntpStatus;
        }

        function systemManagementAccountCount(): int {
            return systemManagementModel.accounts.length;
        }

        function systemManagementPrinterState(): string {
            return systemManagementModel.printerState;
        }

        function systemManagementRepositoryCount(): int {
            return systemManagementModel.repositories.length;
        }
```

(Left here for Phase 9 to use directly — the record kinds and status
computation these probes assume are exactly what `build_native_snapshot()`
produces.)

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
```

Each reader also has its own `tests/fixtures/system-*-bus.py`/
`system-locale-process.py` private-bus or private-process qualification
harness, run by `test_real_*_reads_use_an_isolated_private_bus` in the suite
above — none of them touch the host's real `timedate1`/`locale1`/
`Accounts`/`systemd1`/PackageKit. `packagekit`, `accountsservice`, and `cups`
(the `arch:system-management` package group in `scripts/dwm-packages.sh`,
already anticipating this phase) must be installed for `RepositoryRead`'s
and `AccountRead`'s/`CupsRead`'s real-bus tests to run rather than error.

No `make check-quickshell-qml`/`check-quickshell-system-management` entries
here: this phase does not touch any QML file, so both are unaffected and
were re-run only as a regression check, not as new coverage.

Manual, on a real CachyOS install — **there is no pane surface to check
yet** (see §6); this instead exercises the readers directly:

- `python3 -c 'import sys; sys.path.insert(0, "scripts"); ...'`-style ad hoc
  calls to `RegionalRead("time-state").run()`,
  `RegionalRead("locale-state").run()`, `AccountRead().run()`,
  `CupsRead().run()`, and `RepositoryRead().run()` each return real, current
  system state and never throw for common cases (a normal desktop with
  `timedate1`/`locale1`/`Accounts`/`cups`/PackageKit all present and
  running).
- Create a second local user (`useradd`), confirm `AccountRead().run()`'s
  record count updates; delete it and confirm the count drops back.
- `systemctl stop cups`, confirm `CupsRead().run()` reports it without
  raising; `systemctl start cups` to restore it.
- Disable a repository in `/etc/pacman.conf` (comment out a `[repo]`
  section), confirm `RepositoryRead().run()`'s row count reflects it —
  PackageKit re-reads `pacman.conf` on each `GetRepoList`, it does not cache
  across transactions.
- Every reader fails independently — killing `timedate1` (there is no clean
  way to stop it; instead revoke bus access via a polkit rule for testing)
  must not affect `AccountRead`/`CupsRead`/`RepositoryRead` results.
- Repeat Phase 9's own manual checklist once it exists and actually surfaces
  these readers in the pane — this phase's manual checks above are a
  stand-in until then.

## Closes

Nothing in `ROADMAP.md` yet — no protocol record, model property, or pane
row exists for any of these five readers until
[Phase 9](SYNC-P9-REGIONAL-MUTATION.md) wires `NativeSnapshotSources`/
`build_native_snapshot()` in (see §5's and §6's notes above). This phase
only delivers the backend readers themselves, verified in isolation.
