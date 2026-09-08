# Sync Phase 5 — durable operation journal

Upstream: [`#211`](https://github.com/ChrisTitusTech/dwm-titus/pull/211)
through [`#225`](https://github.com/ChrisTitusTech/dwm-titus/pull/225)
(`ab8ca856` … `c8585a80`) — fifteen commits, roughly 2,800 helper lines and
4,000 test lines. Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 2](SYNC-P2-UPDATE-SNAPSHOT.md) for the helper's existence,
and on the decision recorded after
[Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#closes).

**This phase is the whole cost of the mutation half of the port.** It ships no
user-visible behaviour at all: it is the crash-durable record that
[Phase 6](SYNC-P6-UPDATE-EXECUTION.md) writes into and that lets a shell
restarted mid-update say what happened instead of guessing.

---

## Read this before starting

[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#the-decision-point-after-phase-4) frames
the choice. In short: a private durable journal exists upstream because a
PackageKit D-Bus transaction leaves *no* evidence once the daemon is gone — the
only identifier is a transient object path. The question for Lyona is whether
`/var/log/pacman.log`, `/var/cache/pacman/pkg` and `pacman -Qu` already answer
"did that commit?" well enough to make 2,800 lines unnecessary.

They partly do, and partly do not:

| Question | `pacman.log` answers it? |
| --- | --- |
| Did the transaction commit? | **Yes** — append-only, timestamped |
| What was installed, at what version? | **Yes** |
| Can I downgrade? | **Yes** — `pacman -U` against the package cache |
| Is something still pending? | **Yes** — `pacman -Qu` |
| Did *this shell's* confirmed operation dispatch, and is the running one mine? | **No** |
| Was the result acknowledged by a user, or is it still unseen? | **No** |
| Does a reboot requirement from three operations ago still stand? | **No** |
| Was a `timezone-set` dispatched but never confirmed? | **No** — nothing writes to `pacman.log` |

The last four are what the journal is actually for, and the last one is not
about packages at all — [Phase 9](SYNC-P9-REGIONAL-MUTATION.md)'s regional
mutations reuse this same journal and have no package-manager log to fall back
on. **A "lite" journal that only reconstructs from `pacman.log` cannot serve
Phase 9.** Decide with that in mind.

If the answer is "not worth it", the honest outcome is to close Phases 5–7 as
declined, keep Phases 8–9's *read-only* half only, and record it here.

---

## Files

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | ~2,800 lines: frame codec, record codecs, directory chain, atomic commit, locking, state load/validate, admission, operation IDs |
| `tests/test-system-management.py` | ~4,000 lines. The bulk of upstream's suite. Port it — this is where it earns its keep |
| `config/quickshell/settings/SettingsModel.qml` | 17 lines (`#224`) — refresh sequencing |

---

## Sub-boundaries

Unlike Phases 1–4 this is not one commit. Upstream's fifteen are already
minimal and reviewable; keep them as the commit series rather than squashing:

| | Upstream | Delivers |
| --- | --- | --- |
| J1 | `#211` `ab8ca856` | Frame codec |
| J2 | `#212` `10ea44d6` | File commit primitives |
| J3 | `#213` `e07d546f`, `#214` `e42f4717` | Layout initialization, state-path anchoring |
| J4 | `#215` `7564b01f` | Partial-layout recovery |
| J5 | `#216` `4a4c632b`, `#217` `292d7de0` | Control and operation record codecs |
| J6 | `#218` `2ae83a46`, `#219` `053b1969` | State validation and safe load |
| J7 | `#220` `555c0c62`, `#223` `b6cee00b` | Writable descriptor retention, commit validation |
| J8 | `#221` `5b43dbbc`, `#222` `97bf6eff` | Admission, collision-safe operation IDs |
| J9 | `#224` `6662576c`, `#225` `c8585a80` | Lifecycle completion, ownership across service waits |

---

## 1. The frame

Fixed 8,192-byte frames, two per file, alternating — the classic
double-buffered atomic commit. A torn write damages the frame being written,
never the one being read.

```python
JOURNAL_MAGIC = b"DWMJNL1\0"
JOURNAL_FRAME_MAJOR = 1
JOURNAL_FRAME_MINOR = 0
JOURNAL_FRAME_SIZE = 8192
JOURNAL_PAYLOAD_OFFSET = 64
JOURNAL_PAYLOAD_MAX = JOURNAL_FRAME_SIZE - JOURNAL_PAYLOAD_OFFSET
JOURNAL_FILE_SIZE = JOURNAL_FRAME_SIZE * 2
JOURNAL_SEQUENCE_MAX = (1 << 64) - 1
```

```python
    header = struct.pack("<8sHHIQQ", JOURNAL_MAGIC, JOURNAL_FRAME_MAJOR,
                         JOURNAL_FRAME_MINOR, len(encoded), sequence, 0)
    digest = hashlib.sha256(header + encoded).digest()
    return header + digest + encoded + bytes(JOURNAL_PAYLOAD_MAX - len(encoded))
```

`decode_journal_frame` rejects, in order: wrong size, wrong magic, unsupported
version, **nonzero reserved bytes**, over-long payload length, zero sequence,
**nonzero padding after the payload**, digest mismatch, non-UTF-8, and
forbidden bytes (`\0`, `\r`, `\n`) in the decoded text.

The two padding checks are not paranoia for its own sake — they are what makes
"a partially written frame" distinguishable from "a valid frame with a short
payload", which is the entire recovery story. Port every check; do not
simplify.

`select_journal_frame` (`:2548`) picks the higher valid sequence of the two.

## 2. The layout

```python
JOURNAL_DIRECTORY_SUFFIX = ("dwm-titus", "system-management")
JOURNAL_TERMINAL_COUNT = 32
JOURNAL_DATA_NAMES = ("active", "restart", "handoff",
                      *(f"terminal-{index:02d}" for index in range(JOURNAL_TERMINAL_COUNT)))
JOURNAL_NAMES = (*JOURNAL_DATA_NAMES, JOURNAL_CURSOR_NAME)
```

Thirty-six files of 16 KiB each under
`${XDG_STATE_HOME:-$HOME/.local/state}/dwm-titus/system-management/`, plus a
`cursor` file naming which terminal slot is next.

**Lyona rename** — the one mandatory global substitution here:

```diff
-JOURNAL_DIRECTORY_SUFFIX = ("dwm-titus", "system-management")
+JOURNAL_DIRECTORY_SUFFIX = ("lyona", "system-management")
```

That follows the standing rule in
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#global-adaptation-rules)
(`~/.config/dwm-titus/…` → `~/.config/lyona/…`), extended to `XDG_STATE_HOME`.
The *helper* keeps its `dwm-` name, per the same table.

`journal_directory_path()` (`:2213`) resolves it, refusing a relative
`XDG_STATE_HOME`, a bare `/`, and a `//` prefix, then falling back to `HOME`.
`open_journal_directory_chain()` (`:2440`) opens **every component root-to-leaf
as a descriptor** and `validate_journal_directory_chain()` (`:2415`) checks
each one for symlinks and group/other-writability. All later I/O is
`openat`-relative to a held descriptor, so the path cannot be swapped between
validation and use.

This is a real hardening property Lyona's own security audit
(`SECURITY-001`, done — see `CHANGELOG.md`) would have asked for. Do not
replace it with path-string operations.

## 3. The records

```python
@dataclass(frozen=True)
class JournalOperation:
    operation_id: str
    action_id: str
    started_at: str
    finished_at: str | None
    kind: str
    state: str
    error_code: str | None
    detail: str
    generation: str | None
    transaction_path: str | None
    system_restart: str | None
    session_restart: str | None
    application_restart: bool | None
    boot_id: str | None
    terminal_monotonic: int | None
    slot: int
```

Vocabularies, all ported verbatim:

```python
JOURNAL_OPERATION_ACTION_KINDS = {
    "updates-refresh": "refresh",   "updates-install-all": "update",
    "timezone-set": "timezone",     "ntp-set": "ntp",  "locale-set": "locale",
    "accounts-open": "delegate",    "password-open": "delegate",
    "printers-open": "delegate",    "sources-open": "delegate",
}
JOURNAL_OPERATION_STATES = frozenset((
    "pending", "authorizing", "running", "cancel-requested",
    "permission-denied", "canceled", "failed", "interrupted", "succeeded"))
JOURNAL_OPERATION_TERMINAL_STATES = frozenset(
    ("permission-denied", "canceled", "failed", "interrupted", "succeeded"))
JOURNAL_ERROR_CODES = frozenset((
    "network", "repository", "conflict", "signature", "package", "unsupported",
    "malformed", "missing-provider", "permission-denied", "canceled", "timeout",
    "interrupted", "internal"))
```

`interrupted` is a **first-class terminal state**, distinct from `failed` and
from `canceled`. That is the single most important thing in this list and it
is what [Phase 9](SYNC-P9-REGIONAL-MUTATION.md) depends on.

### The one coupling to break

`transaction_path` carries a PackageKit object path, validated at `:968` and
`:1010` against:

```python
JOURNAL_PACKAGEKIT_PATH_PATTERN = re.compile(
    # PackageKit CreateTransaction returns a root-level ID (e.g. /18_adcbcaed),
    # not a child of the manager's /org/freedesktop/PackageKit object.
    r"/[0-9]{1,20}_[A-Za-z0-9_]{1,64}"
)
```

Under **Option A** this is *correct on Arch* — PackageKit is the provider and
issues the same paths. **Leave it alone.** This reverses the rename that
`SYNC-P10-SYSTEM-MANAGEMENT.md` proposed as its coupling #1, which assumed the
provider was being replaced.

Under **Option C**, or if a native pacman backend is ever added, widen it —
but widen it honestly, and never synthesize a fake PackageKit path:

```diff
-JOURNAL_PACKAGEKIT_PATH_PATTERN = re.compile(r"/[0-9]{1,20}_[A-Za-z0-9_]{1,64}")
+# An opaque, provider-issued operation reference. PackageKit supplies an object
+# path; a native backend supplies the transaction's log anchor. The journal only
+# needs it to be bounded, printable, and stable for the life of the operation.
+JOURNAL_TRANSACTION_REF_PATTERN = re.compile(r"[!-~]{1,128}")
```
```diff
-    transaction_path: str | None
+    transaction_ref: str | None
```

A mechanical sweep through the codec, `_journal_operation_fields()` (`:2744`),
and the tests. The journal is read after a crash; a fabricated identifier is
worse than an honest opaque one.

### `unknown` must be a legal restart value

[Phase 2](SYNC-P2-UPDATE-SNAPSHOT.md#restart-requirements) established that
Arch cannot always answer the restart question. `JOURNAL_RESTART_SYSTEM_VALUES`
and `JOURNAL_RESTART_SESSION_VALUES` derive from strength maps at `:99` and
`:106`; both need an `unknown` member, ordered above `none` and below any real
requirement, so that folding `unknown` with `none` yields `unknown` rather
than `none`.

## 4. Locking and admission

- `_journal_lock()` (`:3273`) — `flock` with a 5-second deadline
  (`JOURNAL_LOCK_DEADLINE_SECONDS`), shared for reads, exclusive for commits.
  Lyona's own convention (`flock -w 5 -x 9`, see
  [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#lyona-only-assets-the-port-must-reuse-rather-than-duplicate))
  is the same discipline with the same timeout.
- `prepare_journal_admission()` (`:4412`) — validates state, checks there is
  no active owner and no unacknowledged handoff, checks commit headroom, and
  picks a reusable terminal slot. It **neither commits nor retains a lease**;
  it is advisory. Every originating command re-checks at dispatch.
- `generate_journal_operation_id()` (`:4363`) — `op-` plus 32 hex characters,
  with `JOURNAL_OPERATION_ID_ATTEMPTS = 4` retries on collision against the
  live state.
- `JOURNAL_ACTIVE_ADMISSION_COMMITS = 12` — a hard bound on how many commits a
  single operation may make before it is refused. Prevents a stuck operation
  from writing forever. The comment at `:165` derives the number; port the
  comment too, it is the only place the derivation is recorded.

## 5. Testing

Upstream's `#211`–`#225` add roughly 4,000 test lines and they are the highest
value in the whole suite: they exercise torn frames, truncated files, wrong
digests, symlinked directory components, group-writable parents, sequence
wraparound, lock contention and slot reuse. **Port them.** These paths cannot
be exercised by hand, and a journal without them is worse than no journal.

Notably, none of this test surface is PackageKit-specific — it is all files,
descriptors and bytes, which is why it ports cleanly.

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-system-management
scripts/run-tests make check-quickshell-qml
```

Manual, on a real CachyOS install:

```bash
ls -la "${XDG_STATE_HOME:-$HOME/.local/state}/lyona/system-management"
# expect 36 files, 16384 bytes each, mode 0600, in a 0700 directory
```

- Corrupt one frame of `active` with `dd` and confirm the helper reads the
  other frame and reports a complete state.
- Corrupt **both** frames and confirm the snapshot reports the `recovery`
  provider as `partial` with a journal-integrity `error` record — and that the
  update list is still readable. Readable state must survive a broken journal.
- Make the journal directory group-writable and confirm the helper refuses it
  rather than using it.
- Point `XDG_STATE_HOME` at a relative path and confirm it falls back to
  `HOME` rather than creating a directory in the working directory.

## Closes

Nothing user-visible. Its evidence is entirely in
`tests/test-system-management.py` and in
[Phase 6](SYNC-P6-UPDATE-EXECUTION.md)'s ability to recover.
