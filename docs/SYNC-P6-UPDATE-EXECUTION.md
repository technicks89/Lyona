# Sync Phase 6 — confirmed update execution and recovery

Upstream: [`#226`](https://github.com/ChrisTitusTech/dwm-titus/pull/226)
through [`#234`](https://github.com/ChrisTitusTech/dwm-titus/pull/234)
(`e5e45ceb` … `aa326d59`), plus
[`#231`](https://github.com/ChrisTitusTech/dwm-titus/pull/231) (`e9721bbc`).
Nine commits, roughly 2,100 helper lines. Index:
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 5](SYNC-P5-OPERATION-JOURNAL.md).

Turns the journal into a working execution owner: `updates-refresh` and
`updates-install-all` actually run, stream bounded progress, can be cancelled,
and survive a shell restart. Still **CLI-only** —
[Phase 7](SYNC-P7-OPERATION-SURFACE.md) puts a button on it.

---

## Files

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | `OperationStream`, `PackageKitMutation`, `run_packagekit_mutation`, `recover_journal_active`, `read_recovery_snapshot`, `build_managed_snapshot`, operation-control commands |
| `tests/test-system-management.py` | ~2,000 lines |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | 14 lines (`#231`) — recovery reconciliation |
| `config/quickshell/shell.qml` | 4 lines (`#231`) |

---

## Sub-boundaries

| | Upstream | Delivers |
| --- | --- | --- |
| E1 | `#226` `e5e45ceb` | `OperationStream`, observed update summaries |
| E2 | `#227` `bc65994c` | Journaled PackageKit execution owner |
| E3 | `#228` `94ca1a4d` | Revalidate confirmed plans before execution |
| E4 | `#229` `900a39ec` | Recover exact operation evidence |
| E5 | `#230` `7747f952` | `watch-operation` / `ack-operation` |
| E6 | `#231` `e9721bbc` | Reconcile durable recovery in finite snapshots |
| E7 | `#232` `0fa2ef41` | DNF5 install-preview correction — **evaluate, likely N/A** |
| E8 | `#233` `976792fa` | Exact-operation cancellation |
| E9 | `#234` `aa326d59` | The confirmed CLI commands |

`#232` is DNF5-specific. Read the five-line diff and either port it with a
recorded Arch justification or exclude it explicitly in
`docs/P6-SYSTEM-MANAGEMENT.md`. Do not port it reflexively.

---

## 1. The command surface this phase adds

```text
dwm-system-management updates-refresh
dwm-system-management updates-install-all GENERATION
dwm-system-management watch-operation OPERATION_ID
dwm-system-management ack-operation OPERATION_ID
dwm-system-management updates-cancel OPERATION_ID
```

Argument validation happens in `main()` before anything else runs, against the
patterns from [Phase 5](SYNC-P5-OPERATION-JOURNAL.md):

```python
    if len(argv) == 2 and argv[0] == "updates-install-all" and JOURNAL_GENERATION_PATTERN.fullmatch(argv[1]):
        return update_command("updates-install-all", argv[1])
    if len(argv) == 2 and argv[0] in {"watch-operation", "ack-operation", "updates-cancel"} \
            and JOURNAL_OPERATION_ID_PATTERN.fullmatch(argv[1]):
        return operation_control(argv[0], argv[1])
```

`GENERATION` is a 64-hex-character SHA-256 of the confirmed plan
(`snapshot_generation()`, `:4972`). **`updates-install-all` without a
generation matching a freshly re-simulated plan is refused.** That is E3, and
it is the mechanism that stops "confirm at 10:00, install a different set at
10:05".

## 2. `OperationStream` — the output contract

One protocol header, bounded progress, then exactly one terminal bundle:

```python
class OperationStream:
    """Emit bounded progress and one validated terminal/audit/completion bundle.

    The owner supplies only durably reached lifecycle states. This formatter
    never starts a service call or commits a journal frame. A failed output
    write poisons the stream so callers cannot retry a possibly partial record.
    """
```

Three properties to preserve exactly:

- **`MAX_OPERATION_PROGRESS_RECORDS = 252`.** Progress is capped. A pathological
  transaction cannot flood the QML parser.
- **The formatter never commits.** It writes what the owner has already made
  durable. Separating "reached this state" from "told the shell about it" is
  what makes the journal the source of truth rather than the pipe.
- **A failed write poisons the stream** (`self.faulted = True`). A partially
  delivered record can never be retried into a duplicate.

The stream's own identity validation refuses an `action_id` outside
`JOURNAL_OPERATION_ACTION_KINDS` — so a typo cannot produce a record with an
unrecognised kind that the model would then have to guess about.

## 3. `update_command()` — the rule that matters

```python
def update_command(action_id: str, generation: str | None = None) -> int:
    """Own an explicit CLI request; never replace a possibly admitted operation."""
```

Read that docstring as the specification. The error path below it is the
important part:

```python
                except (...) as error:
                    if admission_started or output_started:
                        raise
                    # This ID represents only the rejected request. No active,
                    # terminal, handoff, or restart payload is fabricated for it.
                    with lock_writable_journal(journal):
                        operation_id = generate_journal_operation_id(load_writable_journal_state(journal))
                    ...
                    reject_unadmitted_operation(operation_id, action_id, started_at, failure, write)
                    return 1
```

Once admission has started **or a single byte has been written**, a failure is
re-raised rather than converted into a clean rejection — because at that point
the operation may really exist, and reporting "rejected" would be a lie. Only
a failure that provably happened before either is reported as a rejection, and
even then the synthesized ID is explicitly *not* written into the journal.

The outermost handler is the same principle at the process boundary:

```python
        print("operation result could not be confirmed; refresh status and observe the existing operation", file=sys.stderr)
        return 1
```

**"Could not be confirmed" is the honest terminal answer.** This is the same
rule that becomes a named contract exception in
[Phase 9](SYNC-P9-REGIONAL-MUTATION.md): never fabricate success, never
fabricate cancellation.

## 4. Recovery

`recover_journal_active()` (`:5874`) and `read_recovery_snapshot()` (`:5315`)
answer, on every snapshot, "is the operation the journal says is active
actually still running?" — by probing the exact recorded transaction path, not
by looking for *an* operation. `RecoveryEvidence` (`:4719`) distinguishes
**absent** from **failed to look up**:

```python
@dataclass(frozen=True)
class RecoveryEvidence:
    """Finite exact-object evidence; absence is distinct from a failed lookup."""
    present: bool
    state: str | None = None
    failure: SnapshotFailure | None = None
    ...
```

`build_managed_snapshot()` (`:5581`) then folds recovery into the snapshot and
computes the **mutation blocker** — the single string that tells the shell why
the install action is unavailable:

```python
    if recovery.failures or state is None:
        mutation_blocker = "Complete durable recovery evidence is required; reload status and inspect recovery errors"
    elif state.active is not None or state.handoff is not None:
        mutation_blocker = "An operation or its unacknowledged result still owns the update workflow"
    else:
        try:
            backend.require_mutation_safe()
        except SnapshotFailure as failure:
            mutation_failure = failure
            mutation_blocker = failure.detail
```

Note the comment upstream attached to it:

```python
    # This is advisory availability, not admission. The mutation command repeats
    # its security, journal-ownership, session, and generation checks at dispatch.
```

Snapshot availability is a hint for the UI. It is never authorization. Every
originating command re-checks. Port that discipline, and port the comment.

**Lyona adaptation for `require_mutation_safe()`**: see
[Phase 2 §3b](SYNC-P2-UPDATE-SNAPSHOT.md#3b-the-rpm-version-gate) — the RPM
gate is replaced by the daemon's D-Bus version properties. That change lands in
Phase 2; this phase only consumes it.

## 5. Cancellation and acknowledgement

- `updates-cancel OPERATION_ID` (`#233`) cancels **that exact operation**, not
  "the current one". A stale ID is refused (`CancelTargetUnavailable`), which
  is why the QML side must always pass the ID it observed.
- `CANCEL_GRACE_SECONDS = 5` bounds how long a cancel waits before the result
  is reported ambiguous.
- A terminal result stays in its slot until `ack-operation` — an
  **unacknowledged handoff blocks the next operation**. A user cannot start a
  second update without having been shown the first one's result. That is
  deliberate; do not relax it for convenience.

## 6. Restart guidance folding

`build_managed_snapshot` rewrites `state<TAB>update-restart` from the journal's
`JournalRestart` record rather than from the live transaction, so guidance
survives the operation ending, and `prune_journal_restart()` clears it once a
reboot has satisfied it (matched on `boot_id`).

Carry [Phase 5](SYNC-P5-OPERATION-JOURNAL.md#unknown-must-be-a-legal-restart-value)'s
`unknown` value through this fold. Upstream's code already has the shape:

```python
    if state is None and value == "none":
        value = "unknown"
```

Arch needs `unknown` to win in more cases than that, per
[Phase 2](SYNC-P2-UPDATE-SNAPSHOT.md#restart-requirements).

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-system-management
scripts/run-tests make check-quickshell-system-management
```

Manual, on a **disposable** CachyOS VM — this phase installs packages:

- `dwm-system-management updates-refresh` completes and journals a terminal
  result. A second one is refused until `ack-operation`.
- `dwm-system-management snapshot` → take the `snapshot-generation`, then
  `updates-install-all <generation>`. Progress streams; the result is
  journaled.
- Re-run `updates-install-all` with a **stale** generation. It is refused. Then
  install a package by hand, re-snapshot, and confirm the generation changed.
- Start an install, then `updates-cancel <id>` from another terminal. The
  operation reaches `canceled`, not `failed`.
- Start an install and `kill -9` the helper mid-transaction. The next
  `snapshot` reports the operation with honest evidence — `interrupted` or
  still-running, never a fabricated `succeeded`. **This is the phase's central
  claim; verify it explicitly.**
- Reboot with restart guidance outstanding, then snapshot: guidance is pruned.
- Run every command with the journal directory made read-only: each fails
  cleanly with a `conflict`/`internal` code and no traceback.

## Closes

Phase 6's `ROADMAP.md` exit criterion *"Interrupted updates and failed
delegated tools produce actionable recovery guidance rather than ambiguous
success"*, for the update half.
