"""Update rows and plans, snapshot generations, the operation stream, and journal recovery."""

from __future__ import annotations

import hashlib
import os
import time
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from typing import Callable, Iterable, Protocol, Sequence

from . import operation_journal, packagekit, shared


MAX_LIST_BYTES = 3 * 1024 * 1024

MAX_OPERATION_PROGRESS_RECORDS = 252
MAX_OPERATION_MISMATCH_SAMPLES = 128

# PackageKit's InfoEnum is shared across every backend (alpm included) — this
# is not Fedora-specific vocabulary.
UPDATE_INFO = {
    0: ("unknown", "installable"),
    2: ("unknown", "installable"),
    3: ("low", "installable"),
    4: ("enhancement", "installable"),
    5: ("normal", "installable"),
    6: ("bugfix", "installable"),
    7: ("important", "installable"),
    8: ("security", "installable"),
    9: ("unknown", "blocked"),
    26: ("critical", "installable"),
}
PLAN_INFO = {
    # The protocol accepts transaction-result classifications only. PackageKit
    # intent enums INSTALL/REMOVE/OBSOLETE/DOWNGRADE (27-30) stay rejected.
    11: "update",
    12: "install",
    13: "remove",
    15: "obsolete",
    19: "reinstall",
    20: "downgrade",
}
RESTART_INFO = {
    1: (0, False, "none"),
    2: (1, False, "application"),
    3: (2, False, "session"),
    4: (3, False, "system"),
    5: (2, True, "security-session"),
    6: (3, True, "security-system"),
}

# Arch-only fallback: package names that, if pending, mean a restart is
# almost certainly required even when the backend reports no RequireRestart
# signal at all. See _restart_heuristic_hint() for why this exists.
RESTART_HEURISTIC_NAMES = {"systemd", "glibc", "dbus"}


@dataclass(frozen=True)
class Package:
    info: int
    package_id: str
    summary: str


@dataclass(frozen=True)
class TransactionResult:
    packages: tuple[Package, ...]
    restart_types: tuple[int, ...] = ()


@dataclass(frozen=True)
class RecoveryEvidence:
    """Finite exact-object evidence; absence is distinct from a failed lookup."""
    present: bool
    state: str | None = None
    failure: shared.SnapshotFailure | None = None
    restart_types: tuple[int, ...] = ()
    status: int = 0
    allow_cancel: bool = False
    percent: int | None = None
    terminal_monotonic: int | None = None


def validate_transaction_list(values: object) -> tuple[str, ...]:
    if not isinstance(values, (list, tuple)) or len(values) > 256:
        raise shared.SnapshotFailure("malformed", "PackageKit active transaction list is malformed")
    seen = set()
    size = 0
    for path in values:
        if not isinstance(path, str) or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path) is None or path in seen:
            raise shared.SnapshotFailure("malformed", "PackageKit active transaction identity is malformed")
        seen.add(path)
        size += len(path.encode("utf-8"))
        if size > 65536:
            raise shared.SnapshotFailure("malformed", "PackageKit active transaction list exceeds its byte budget")
    return tuple(values)


def validate_history_record(values: object) -> tuple[str, bool, int, int]:
    """Discard package data and command lines; retain only exact typed identity."""
    if not isinstance(values, (list, tuple)) or len(values) != 8:
        raise shared.SnapshotFailure("malformed", "PackageKit history record is malformed")
    path, timespec, succeeded, role, duration, data, uid, command = values
    if (
        not isinstance(path, str) or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path) is None
        or type(succeeded) is not bool
        or any(type(value) is not int or not 0 <= value <= shared.G_MAXUINT for value in (role, duration, uid))
        or any(not isinstance(value, str) for value in (timespec, data, command))
        or len(timespec) > 128
    ):
        raise shared.SnapshotFailure("malformed", "PackageKit history identity is malformed")
    return path, succeeded, role, uid


def match_update_history(records: Sequence[tuple[str, bool, int, int]], path: str, uid: int) -> bool | None:
    """A wrong owner or duplicate exact match is ambiguity, never negative history."""
    if len(records) > 64:
        raise shared.SnapshotFailure("malformed", "PackageKit history exceeds its record budget")
    matches = [record for record in records if record[0] == path]
    if not matches:
        return None
    if len(matches) != 1 or matches[0][2:] != (22, uid):
        raise shared.SnapshotFailure("malformed", "PackageKit history does not uniquely identify this update")
    return matches[0][1]


@dataclass(frozen=True)
class UpdateRow:
    package_id: str
    severity: str
    installability: str
    name: str
    version: str
    summary: str

    def fields(self) -> tuple[str, ...]:
        return (
            "update",
            self.package_id,
            self.severity,
            self.installability,
            self.name,
            self.version,
            self.summary,
        )


@dataclass(frozen=True)
class PlanRow:
    package_id: str
    action: str
    name: str
    version: str
    summary: str

    def fields(self) -> tuple[str, ...]:
        return (
            "package-change",
            self.package_id,
            self.action,
            self.name,
            self.version,
            self.summary,
        )

    def generation_fields(self) -> tuple[str, ...]:
        return (self.action, self.package_id, self.name, self.version, self.summary)


class UpdateBackend(Protocol):
    def last_refresh_age(self) -> int:
        """Return PackageKit's seconds-since-refresh value."""

    def updates(self) -> TransactionResult:
        """Return the complete bounded GetUpdates result."""

    def simulate(self, package_ids: Sequence[str]) -> TransactionResult:
        """Return the complete bounded SIMULATE|ONLY_TRUSTED plan."""


def canonical_identity(value: object) -> str:
    text = str(value)
    if shared.clean_text(text, truncate=False) != text:
        raise shared.SnapshotFailure("malformed", "PackageKit returned an unsafe identity")
    if not text:
        raise shared.SnapshotFailure(
            "malformed", "PackageKit returned an empty package identity"
        )
    return text


def package_display_fields(package_id: str) -> tuple[str, str]:
    parts = package_id.split(";", 3)
    if len(parts) != 4 or not parts[0] or not parts[1]:
        raise shared.SnapshotFailure(
            "malformed", "PackageKit returned a malformed package identity"
        )
    return shared.clean_text(parts[0]), shared.clean_text(parts[1])


def encoded_record_size(fields: Iterable[str]) -> int:
    return len(("\t".join(fields) + "\n").encode("utf-8"))


def enforce_list_budget(rows: Sequence[UpdateRow] | Sequence[PlanRow]) -> None:
    if len(rows) > shared.MAX_LIST_RECORDS:
        raise shared.SnapshotFailure(
            "malformed", "PackageKit returned too many package records"
        )
    if sum(encoded_record_size(row.fields()) for row in rows) > MAX_LIST_BYTES:
        raise shared.SnapshotFailure(
            "malformed", "PackageKit package records exceeded the protocol budget"
        )


def normalize_updates(packages: Sequence[Package]) -> list[UpdateRow]:
    rows: list[UpdateRow] = []
    seen: set[str] = set()
    for package in packages:
        package_id = canonical_identity(package.package_id)
        if package_id in seen:
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned a duplicate update identity"
            )
        seen.add(package_id)
        try:
            severity, installability = UPDATE_INFO[int(package.info)]
        except (KeyError, TypeError, ValueError) as error:
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned an unsupported update classification"
            ) from error
        name, version = package_display_fields(package_id)
        rows.append(
            UpdateRow(
                package_id,
                severity,
                installability,
                name,
                version,
                shared.clean_text(package.summary),
            )
        )
    rows.sort(key=lambda row: row.package_id.encode("utf-8"))
    enforce_list_budget(rows)
    return rows


def normalize_plan(
    packages: Sequence[Package], requested_ids: Sequence[str]
) -> list[PlanRow]:
    rows: list[PlanRow] = []
    seen: set[str] = set()
    for package in packages:
        package_id = canonical_identity(package.package_id)
        if package_id in seen:
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned a duplicate plan identity"
            )
        seen.add(package_id)
        try:
            action = PLAN_INFO[int(package.info)]
        except (KeyError, TypeError, ValueError) as error:
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned an unsupported plan classification"
            ) from error
        name, version = package_display_fields(package_id)
        rows.append(
            PlanRow(package_id, action, name, version, shared.clean_text(package.summary))
        )

    requested = set(requested_ids)
    # DNF5 GetUpdates includes install actions as well as upgrades. Preserve
    # those simulated actions, but do not admit an unrequested update identity.
    represented = {row.package_id for row in rows
                   if row.package_id in requested and row.action in {"install", "update"}}
    if requested != represented or any(
        row.action == "update" and row.package_id not in requested for row in rows
    ):
        raise shared.SnapshotFailure(
            "malformed", "PackageKit returned an incomplete update plan"
        )
    rows.sort(
        key=lambda row: tuple(
            field.encode("utf-8") for field in row.generation_fields()
        )
    )
    enforce_list_budget(rows)
    return rows


def aggregate_restart(restart_types: Sequence[int]) -> str:
    scope = 0
    security = False
    for value in restart_types:
        try:
            item_scope, item_security, _label = RESTART_INFO[int(value)]
        except (KeyError, TypeError, ValueError) as error:
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned an unsupported restart requirement"
            ) from error
        scope = max(scope, item_scope)
        security = security or item_security
    if security and scope >= 3:
        return "security-system"
    if security and scope >= 2:
        return "security-session"
    return {0: "none", 1: "application", 2: "session", 3: "system"}[scope]


def _restart_heuristic_hint(update_rows: Sequence[UpdateRow]) -> str:
    """Arch-only fallback for a backend that reports no restart signal at all.

    Fedora's PackageKit backend always emits RequireRestart. Whether the alpm
    backend does the same is unverified (docs/SYNC-P2-UPDATE-SNAPSHOT.md
    section 5); this only runs when a transaction succeeded with pending
    updates but zero RequireRestart signals were seen. Reporting "none" in
    that situation would tell a user it is safe to skip a reboot after a
    kernel or glibc update — the one failure mode worth designing against.
    Restrict the guess to well-known core packages; report "unknown" for
    everything else rather than fabricate "no restart needed".
    """
    for row in update_rows:
        if row.name in RESTART_HEURISTIC_NAMES or row.name == "linux" or row.name.startswith("linux-"):
            return "system"
    return "unknown"


def snapshot_generation(update_ids: Sequence[str], plan: Sequence[PlanRow]) -> str:
    digest = hashlib.sha256(b"lyona-update-plan-v1")
    for package_id in sorted(update_ids, key=lambda value: value.encode("utf-8")):
        encoded = package_id.encode("utf-8")
        digest.update(b"U")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
    for row in sorted(
        plan,
        key=lambda value: tuple(
            field.encode("utf-8") for field in value.generation_fields()
        ),
    ):
        digest.update(b"P")
        for field in row.generation_fields():
            encoded = field.encode("utf-8")
            digest.update(len(encoded).to_bytes(8, "big"))
            digest.update(encoded)
    return digest.hexdigest()


def confirmed_update_plan(backend: UpdateBackend, generation: str) -> tuple[tuple[str, ...], tuple[PlanRow, ...]]:
    """Revalidate a confirmation using fresh bounded read-only transactions."""
    if not isinstance(generation, str) or shared.JOURNAL_GENERATION_PATTERN.fullmatch(generation) is None:
        raise shared.SnapshotFailure("malformed", "Confirmed update generation is invalid")
    updates = normalize_updates(backend.updates().packages)
    package_ids = tuple(row.package_id for row in updates if row.installability == "installable")
    preview = tuple(normalize_plan(backend.simulate(package_ids).packages, package_ids)) if package_ids else ()
    if any(row.action in {"reinstall", "downgrade"} for row in preview):
        raise shared.SnapshotFailure("unsupported", "PackageKit preview requires unsupported reinstall or downgrade flags", "unsupported")
    if snapshot_generation(package_ids, preview) != generation:
        raise shared.SnapshotFailure("conflict", "The update plan changed; refresh the preview and confirm again")
    if not package_ids:
        raise shared.SnapshotFailure("conflict", "There are no installable updates; refresh the preview")
    return package_ids, preview


def read_boot_id() -> str:
    """Read only the bounded kernel boot identity, never a caller-selected path."""
    try:
        with open("/proc/sys/kernel/random/boot_id", "rb") as source:
            data = source.read(37)
        value = data.removesuffix(b"\n").decode("ascii")
    except (OSError, UnicodeError) as error:
        raise shared.SnapshotFailure("internal", "Kernel boot identity is unavailable", "unavailable") from error
    if shared.BOOT_ID_PATTERN.fullmatch(value) is None:
        raise shared.SnapshotFailure("malformed", "Kernel boot identity is malformed")
    return value


class OperationProtocolError(ValueError):
    """An operation stream would violate its closed lifecycle or field bounds."""


class OperationStream:
    """Emit bounded progress and one validated terminal/audit/completion bundle.

    The owner supplies only durably reached lifecycle states. This formatter
    never starts a service call or commits a journal frame. A failed output
    write poisons the stream so callers cannot retry a possibly partial record.
    """

    def __init__(
        self, operation_id: str, action_id: str, started_at: str, detail: str,
        write: Callable[[str], object],
    ) -> None:
        if (
            not isinstance(operation_id, str)
            or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(operation_id) is None
            or not isinstance(action_id, str)
            or action_id not in shared.JOURNAL_OPERATION_ACTION_KINDS
            or not callable(write)
        ):
            raise OperationProtocolError("operation stream identity is invalid")
        operation_journal._validate_journal_timestamp(started_at, "operation start")
        operation_journal._validate_journal_detail(detail)
        self.operation_id = operation_id
        self.action_id = action_id
        self.kind = shared.JOURNAL_OPERATION_ACTION_KINDS[action_id]
        self.started_at = started_at
        self.state = "pending"
        self.progress_records = 0
        self.item_records = 0
        self._last_item = None
        self.closed = False
        self.faulted = False
        self._write = write
        self._last_progress: tuple[str, bool, str] | None = ("unknown", False, detail)
        self._send([
            f"system-management-protocol\t{shared.PROTOCOL_MAJOR}\t{shared.PROTOCOL_MINOR}",
            self._operation_line("pending", "unknown", False, detail),
        ])

    def item_progress(self, name: str, phase: str, percent: int | None) -> None:
        """Bounded, ephemeral UI evidence; never part of the durable audit."""
        if self.closed or self.faulted:
            raise OperationProtocolError("operation stream is no longer writable")
        operation_journal._validate_journal_detail(name)
        if (self.kind not in {"update", "refresh"} or self.state not in {"running", "cancel-requested"}
                or phase not in {"working", "downloading", "installing", "updating", "removing", "cleaning"}
                or (percent is not None and (type(percent) is not int or not 0 <= percent <= 100))):
            raise OperationProtocolError("invalid package progress")
        item = (name, phase, "unknown" if percent is None else str(percent))
        if item == self._last_item or self.item_records > 4096:
            return
        # At the display budget, clear stale package data rather than freezing it.
        if self.item_records == 4096:
            item = ("", "working", "unknown")
        self._send(["\t".join(("package-progress", self.operation_id, *item))])
        self._last_item = item
        self.item_records += 1

    def _send(self, lines: Sequence[str]) -> None:
        if self.closed or self.faulted:
            raise OperationProtocolError("operation stream is no longer writable")
        try:
            self._write("\n".join(lines) + "\n")
        except BaseException:
            self.faulted = True
            raise

    def _operation_line(
        self, state: str, percent: str, cancelable: bool, detail: str,
    ) -> str:
        return "\t".join((
            "operation", self.operation_id, self.action_id, self.kind, state,
            percent, "yes" if cancelable else "no", detail,
        ))

    def transition(
        self, state: str, detail: str, *, percent: int | None = None,
        cancelable: bool = False,
    ) -> bool:
        """Emit a reached state; coalesce and cap only repeated progress rows."""
        if self.closed or self.faulted:
            raise OperationProtocolError("operation stream is no longer writable")
        if (
            not isinstance(state, str)
            or state not in shared.JOURNAL_TRANSITIONS[self.state]
            or state in shared.JOURNAL_OPERATION_TERMINAL_STATES
            or type(cancelable) is not bool
            or (percent is not None and (type(percent) is not int or not 0 <= percent <= 100))
        ):
            raise OperationProtocolError("operation progress or transition is invalid")
        operation_journal._validate_journal_detail(detail)
        percentage = "unknown" if percent is None else str(percent)
        progress = (percentage, cancelable, detail)
        repeated = state == self.state
        if repeated and (
            progress == self._last_progress
            or self.progress_records >= MAX_OPERATION_PROGRESS_RECORDS
        ):
            return False
        self._send([self._operation_line(state, percentage, cancelable, detail)])
        self.state = state
        self._last_progress = progress
        if repeated:
            self.progress_records += 1
        return True

    def progress(self, detail: str, *, percent: int | None = None, cancelable: bool = False) -> bool:
        """Update current-state fields without inventing a lifecycle transition."""
        if self.closed or self.faulted:
            raise OperationProtocolError("operation stream is no longer writable")
        if type(cancelable) is not bool or (percent is not None and (type(percent) is not int or not 0 <= percent <= 100)):
            raise OperationProtocolError("operation progress is invalid")
        operation_journal._validate_journal_detail(detail)
        percentage = "unknown" if percent is None else str(percent)
        progress = (percentage, cancelable, detail)
        if progress == self._last_progress or self.progress_records >= MAX_OPERATION_PROGRESS_RECORDS:
            return False
        self._send([self._operation_line(self.state, percentage, cancelable, detail)])
        self._last_progress = progress
        self.progress_records += 1
        return True

    def finish(self, operation: operation_journal.JournalOperation, *, detail: str | None = None) -> None:
        """Publish only an exact terminal record after the owner's durable handoff."""
        if self.closed or self.faulted:
            raise OperationProtocolError("operation stream is no longer writable")
        operation_journal.encode_journal_operation(operation)
        if (
            operation.operation_id != self.operation_id
            or operation.action_id != self.action_id
            or operation.kind != self.kind
            or operation.started_at != self.started_at
            or operation.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES
            or operation.state not in shared.JOURNAL_TRANSITIONS[self.state]
        ):
            raise OperationProtocolError("operation terminal identity or transition is invalid")
        terminal_detail = operation.detail if detail is None else detail
        operation_journal._validate_journal_detail(terminal_detail)
        lines = []
        if operation.error_code is not None:
            owner = (
                "updates" if self.kind in {"refresh", "update"}
                else "regional" if self.kind in {"timezone", "ntp", "locale"}
                else {"accounts-open": "accounts", "password-open": "accounts",
                      "printers-open": "printers", "sources-open": "sources"}[self.action_id]
            )
            lines.append(f"error\t{owner}\t{operation.error_code}\t{operation.detail}")
        lines.extend([
            self._operation_line(operation.state, "unknown", False, terminal_detail),
            "\t".join(("audit", self.operation_id, self.action_id, self.kind,
                       operation.state, self.started_at, operation.finished_at, terminal_detail)),
            "complete\toperation",
        ])
        self._send(lines)
        self.state = operation.state
        self.closed = True


def reject_unadmitted_operation(operation_id: str, action_id: str, started_at: str,
                               failure: shared.SnapshotFailure, write: Callable[[str], object]) -> None:
    """Report a rejected request without inventing a durable transaction or result."""
    if (not isinstance(action_id, str) or action_id not in {
            "updates-refresh", "updates-install-all", "timezone-set", "ntp-set", "locale-set", *shared.DELEGATED_ACTIONS}
            or not isinstance(failure, shared.SnapshotFailure) or failure.code not in shared.JOURNAL_ERROR_CODES):
        raise OperationProtocolError("rejected operation request is invalid")
    operation_journal._validate_journal_detail(failure.detail)
    finished_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    regional = action_id in {"timezone-set", "ntp-set", "locale-set"}
    provider_id, mutation = ("regional", "regional") if regional else ("updates", "package")
    detail = f"Request rejected before operation admission; no {mutation} mutation was dispatched"
    if action_id in shared.DELEGATED_ACTIONS:
        provider_id = {"accounts-open": "accounts", "password-open": "accounts",
                       "printers-open": "printers", "sources-open": "sources"}[action_id]
        detail = "Request rejected before operation admission; no administration tool was launched"
    stream = OperationStream(operation_id, action_id, started_at, detail, write)
    stream._send([
        f"error\t{provider_id}\t{failure.code}\t{failure.detail}",
        stream._operation_line("failed", "unknown", False, failure.detail),
        "\t".join(("audit", operation_id, action_id, stream.kind, "failed", started_at, finished_at, failure.detail)),
        "complete\toperation",
    ])
    stream.state = "failed"
    stream.closed = True


def replay_terminal_operation(
    operation: operation_journal.JournalOperation, write: Callable[[str], object],
) -> None:
    """Replay exact retained evidence without opening a service or relaunching a tool."""
    operation_journal.encode_journal_operation(operation)
    if operation.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES:
        raise OperationProtocolError("operation replay requires a terminal record")
    stream = OperationStream(
        operation.operation_id, operation.action_id, operation.started_at,
        "Replaying retained result; observed package comparison is unavailable"
        if operation.kind == "update" else "Replaying retained operation result",
        write,
    )
    if operation.state == "permission-denied":
        stream.transition("authorizing", "Replaying the retained authorization result")
    elif operation.state == "succeeded":
        stream.transition("running", "Replaying the retained completion result")
    stream.finish(operation)


class ObservedUpdateSummary:
    """Bounded, nonpersistent comparison of actual PackageKit signals to a preview.

    Preview membership is bounded by the discovery contract. Unexpected package
    IDs never enter an unbounded set: only 128 distinct samples are retained.
    Counts and the digest describe signal observations, not an atomic frozen plan.
    """

    actions = ("install", "update", "remove", "obsolete", "unknown")

    def __init__(self, preview: Sequence[PlanRow]) -> None:
        if len(preview) > shared.MAX_LIST_RECORDS:
            raise shared.SnapshotFailure("malformed", "Observed comparison preview is oversized")
        self._preview: dict[str, str] = {}
        self._inbound: set[tuple[str, str]] = set()
        for row in preview:
            if (
                not isinstance(row, PlanRow)
                or row.action not in self.actions[:-1]
                or not isinstance(row.package_id, str)
                or row.package_id in self._preview
            ):
                raise shared.SnapshotFailure("malformed", "Observed comparison preview is invalid")
            name, architecture = self._package_key(row.package_id)
            self._preview[row.package_id] = row.action
            if row.action == "update":
                self._inbound.add((name, architecture))
        enforce_list_budget(preview)
        self.counts = dict.fromkeys(self.actions, 0)
        self.samples: list[tuple[str, str]] = []
        self._matched: set[str] = set()
        self._different = False
        self._unknown = False
        self._digest = hashlib.sha256(b"lyona-update-observed-v1")

    @staticmethod
    def _package_key(package_id: str) -> tuple[str, str]:
        if not isinstance(package_id, str):
            raise shared.SnapshotFailure("malformed", "Observed package identity is invalid")
        try:
            package_id.encode("utf-8")
        except UnicodeEncodeError as error:
            raise shared.SnapshotFailure("malformed", "Observed package identity is invalid") from error
        canonical_identity(package_id)
        parts = package_id.split(";")
        if len(parts) != 4 or not all(parts[:3]) or "\0" in package_id:
            raise shared.SnapshotFailure("malformed", "Observed package identity is invalid")
        return parts[0], parts[2]

    def observe(self, info: int, package_id: str) -> bool:
        """Digest one accepted action in arrival order, excluding phase-only signals."""
        if type(info) is not int or not 0 <= info <= shared.G_MAXUINT:
            raise shared.SnapshotFailure("malformed", "Observed package classification is invalid")
        key = self._package_key(package_id)
        if info == 10 or (info == 14 and key in self._inbound):
            return False
        action = {11: "update", 12: "install", 13: "remove", 15: "obsolete"}.get(info)
        if info == 14 and self._preview.get(package_id) == "obsolete":
            action = "obsolete"
        if action is None:
            action = "unknown"
            self._unknown = True
        if self.counts[action] == shared.JOURNAL_SEQUENCE_MAX:
            self._unknown = True
        else:
            self.counts[action] += 1
        for field in (action, package_id):
            encoded = field.encode("utf-8")
            self._digest.update(len(encoded).to_bytes(8, "big"))
            self._digest.update(encoded)
        if self._preview.get(package_id) == action:
            self._matched.add(package_id)
        else:
            self._different = True
            sample = (action, package_id)
            if len(self.samples) < MAX_OPERATION_MISMATCH_SAMPLES and sample not in self.samples:
                self.samples.append(sample)
        return True

    def comparison(self, *, final: bool = False) -> str:
        """Keep incomplete or unclassified evidence explicitly unknown."""
        if self._unknown:
            return "unknown"
        if self._different or (final and len(self._matched) != len(self._preview)):
            return "yes"
        return "no" if final else "unknown"

    def detail(self, *, final: bool = False) -> str:
        """Return a fixed-size aggregate suitable for one operation detail field."""
        counts = " ".join(f"{action}={self.counts[action]}" for action in self.actions)
        return (f"Observed signals: {counts}; sha256={self._digest.hexdigest()}; "
                f"different={self.comparison(final=final)}; mismatch-samples={len(self.samples)}")


@dataclass(frozen=True)
class RecoverySnapshot:
    """Finite validated journal projection; no open descriptors escape it."""

    state: operation_journal.JournalState | None = None
    evidence: RecoveryEvidence | None = None
    prior_restart: operation_journal.JournalRestart | None = None
    failures: tuple[shared.SnapshotFailure, ...] = ()


def read_recovery_snapshot(backend: packagekit.PackageKitBackend) -> RecoverySnapshot:
    """Recover and prune before display, without holding locks over service calls."""
    prior_restart = None
    failures = []
    session_read = False
    session_started = None

    def read_session():
        nonlocal session_read, session_started
        if not session_read:
            session_read = True
            try:
                session_started = backend.session_started()
                operation_journal._encode_journal_uint64(session_started, "session start")
            except (shared.SnapshotFailure, operation_journal.JournalRecordError) as error:
                session_started = None
                failures.append(error if isinstance(error, shared.SnapshotFailure) else
                    shared.SnapshotFailure("malformed", "Session start evidence is malformed; restart guidance is retained"))
        return session_started

    try:
        boot_id = read_boot_id()
        with operation_journal.open_journal_directory() as chain:
            try:
                operation_journal.initialize_journal_layout(chain.directory_descriptor, boot_id)
            except OSError:
                # A read-only filesystem can still supply trustworthy prior
                # guidance even though initialization/pruning is unavailable.
                try:
                    prior_restart = operation_journal.load_journal_state(chain).restart
                except (OSError, operation_journal.JournalFrameError, operation_journal.JournalRecordError):
                    pass
                raise
            prior_restart = operation_journal.load_journal_state(chain).restart
            with operation_journal.retain_writable_journal(chain) as journal:
                state, evidence, failure = recover_journal_active(journal, backend,
                    boot_id=boot_id, session_reader=read_session)
                if failure is not None:
                    failures.append(failure)
                # The finite PackageKit attachment comes first. The same
                # cached logind result also prunes journal-only recovery paths.
                read_session()
                with operation_journal.lock_writable_journal(journal):
                    operation_journal.prune_journal_restart(journal, boot_id, session_started)
                    current = operation_journal.load_writable_journal_state(journal)
                    if current.active is not None and current.active.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
                        operation_journal.complete_journal_terminal(journal, boot_id=boot_id, session_started=session_started)
                        current = operation_journal.load_writable_journal_state(journal)
                    if current.active != state.active:
                        evidence = None
                    return RecoverySnapshot(current, evidence, prior_restart, tuple(failures))
    except (shared.SnapshotFailure, operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalAdmissionError, OSError) as error:
        if isinstance(error, shared.SnapshotFailure):
            failure = error
        elif isinstance(error, (operation_journal.JournalLockError, operation_journal.JournalAdmissionError)):
            failure = shared.SnapshotFailure("conflict", "Journal recovery could not obtain stable ownership; refresh status before retrying")
        elif isinstance(error, operation_journal.JournalCommitError) or not isinstance(error, (operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalFileError)):
            failure = shared.SnapshotFailure("internal", "Journal storage is unavailable; check free space, mount writability, and permissions before refreshing. Prior guidance is retained")
        else:
            failure = shared.SnapshotFailure("malformed", f"Journal recovery failed: {error}. Keep the journal intact; reboot before moving a legacy journal aside, then refresh and inspect diagnostics")
        return RecoverySnapshot(prior_restart=prior_restart, failures=tuple(failures + [failure]))


def recover_journal_active(
    journal: operation_journal.JournalDescriptorSet, backend: packagekit.PackageKitBackend, *,
    boot_id: str, session_started: int | None = None,
    watch: bool = False, expected_operation_id: str | None = None,
    expected_operation: operation_journal.JournalOperation | None = None,
    on_progress: Callable[[RecoveryEvidence], object] | None = None,
    session_reader: Callable[[], int | None] | None = None,
) -> tuple[operation_journal.JournalState, RecoveryEvidence | None, shared.SnapshotFailure | None]:
    """Recover one copied owner without holding a journal lock across service work."""
    if not isinstance(boot_id, str) or shared.BOOT_ID_PATTERN.fullmatch(boot_id) is None:
        raise operation_journal.JournalRecordError("recovery boot identity is invalid")
    if session_started is not None:
        operation_journal._encode_journal_uint64(session_started, "session start")
    identity = ("operation_id", "action_id", "started_at", "kind", "generation", "transaction_path", "boot_id", "slot")
    if expected_operation is not None:
        if (not isinstance(expected_operation, operation_journal.JournalOperation)
                or expected_operation_id not in {None, expected_operation.operation_id}):
            raise operation_journal.JournalAdmissionError("recovery expected identity is invalid")
        expected_operation_id = expected_operation.operation_id
    original = operation_journal.load_journal_state(journal.chain).active
    if expected_operation is not None and original is not None and any(
            getattr(original, field) != getattr(expected_operation, field) for field in identity):
        raise operation_journal.JournalAdmissionError("recovery owner identity changed")
    if expected_operation_id is not None and original is None:
        # Completion can race the watcher's initial target selection. Validate
        # the exact retained result without following a replacement owner.
        with operation_journal.lock_writable_journal(journal):
            terminal = operation_journal.retained_journal_operation(journal, expected_operation_id)
            if expected_operation is not None and any(
                    getattr(terminal, field) != getattr(expected_operation, field) for field in identity):
                raise operation_journal.JournalAdmissionError("recovery terminal identity changed")
            return operation_journal.load_writable_journal_state(journal), None, None
    if expected_operation_id is not None and (original is None or original.operation_id != expected_operation_id):
        raise operation_journal.JournalAdmissionError("recovery target changed")
    if original is None:
        with operation_journal.lock_writable_journal(journal):
            operation_journal.prune_journal_restart(journal, boot_id, session_started)
            return operation_journal.load_writable_journal_state(journal), None, None
    evidence = None
    lookup_failure = None
    history_match = None
    history_used = False

    def checkpoint_running():
        with operation_journal.lock_writable_journal(journal):
            current = operation_journal.load_writable_journal_state(journal).active
            if current is None or any(getattr(current, field) != getattr(original, field) for field in identity) or current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
                raise shared.SnapshotFailure("conflict", "Recovery owner changed; discard the stale observation")
            if current.state in {"pending", "authorizing"}:
                operation_journal.advance_journal_operation(journal, current, replace(current, state="running", detail="PackageKit execution observed during recovery"))
        if watch and on_progress is not None:
            on_progress(RecoveryEvidence(True, status=3))

    def checkpoint_restart(value):
        if original.kind != "update" or original.boot_id != boot_id:
            return
        with operation_journal.lock_writable_journal(journal):
            current = operation_journal.load_writable_journal_state(journal).active
            if current is None or any(getattr(current, field) != getattr(original, field) for field in identity) or current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
                raise shared.SnapshotFailure("conflict", "Recovery owner changed; discard the stale observation")
            changes = {}
            if value == 2:
                changes["application_restart"] = True
            elif value in {3, 5}:
                changes["session_restart"] = max(current.session_restart, "security-session" if value == 5 else "session", key=shared.JOURNAL_RESTART_SESSION_STRENGTH.__getitem__)
            elif value != 1:
                changes["system_restart"] = max(current.system_restart, {4: "system", 6: "security-system"}.get(value, "unknown"), key=shared.JOURNAL_RESTART_SYSTEM_STRENGTH.__getitem__)
            following = replace(current, **changes)
            if following != current:
                operation_journal.advance_journal_operation(journal, current, following)

    if original.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES and original.kind in {"update", "refresh"}:
        try:
            watch_options = dict(watch=True, on_progress=on_progress) if watch else {}
            evidence = backend.probe_operation(original, on_restart=checkpoint_restart, on_running=checkpoint_running, **watch_options)
        except shared.SnapshotFailure as failure:
            lookup_failure = failure
        if original.kind == "update" and (evidence is None or evidence.state is None) and (
                lookup_failure is None or lookup_failure.code == "timeout"):
            try:
                history_match = match_update_history(backend.operation_history(), original.transaction_path, os.getuid())
                # PackageKit inserts history at READY with succeeded=false.
                # That row alone cannot distinguish a live job from failure.
                history_used = history_match is True or (
                    history_match is False and evidence is not None and not evidence.present)
            except shared.SnapshotFailure as failure:
                if failure.code == "malformed" or lookup_failure is None:
                    lookup_failure = failure
    if session_reader is not None and (history_used or (evidence is not None and (
            evidence.state is not None or not evidence.present))):
        # Never delay attachment with an unrelated service lookup. Exact
        # terminal/absence evidence is already captured before reading logind.
        try:
            session_started = session_reader()
        except shared.SnapshotFailure:
            session_started = None
        if session_started is not None:
            operation_journal._encode_journal_uint64(session_started, "session start")
    with operation_journal.lock_writable_journal(journal):
        current_state = operation_journal.load_writable_journal_state(journal)
        current = current_state.active
        if current is None or any(getattr(current, field) != getattr(original, field) for field in identity):
            return current_state, None, None
        # Boot/session satisfaction is independent of the recovered operation.
        # Apply it before comparing a new boot's monotonic terminal cutoff.
        operation_journal.prune_journal_restart(journal, boot_id, session_started)
        current_state = operation_journal.load_writable_journal_state(journal)
        if current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            operation_journal.complete_journal_terminal(journal, boot_id=boot_id, session_started=session_started)
            return operation_journal.load_writable_journal_state(journal), None, None
        if current.kind not in {"update", "refresh"} and operation_journal.native_journal_owner_busy(journal, current):
            # A live RegionalMutation/delegated-launch process still holds the
            # native lease -- this call has no PackageKit-style evidence for
            # that kind at all (the block above never runs for it), so falling
            # through would default to "interrupted" and terminalize an
            # operation its own owning process is still legitimately running.
            return current_state, None, None
        if lookup_failure is not None and (lookup_failure.code == "malformed" or (
                not history_used and (evidence is None or evidence.present))):
            return current_state, evidence, lookup_failure
        if evidence is not None and evidence.status == 3 and current.state in {"pending", "authorizing"}:
            current = operation_journal.advance_journal_operation(journal, current, replace(current, state="running", detail="PackageKit execution observed during recovery"))
            current_state = operation_journal.load_writable_journal_state(journal)
        if evidence is not None and evidence.state is None and evidence.present and not history_used:
            operation_journal.prune_journal_restart(journal, boot_id, session_started)
            return operation_journal.load_writable_journal_state(journal), evidence, lookup_failure
        state = evidence.state if evidence is not None and evidence.state is not None else "succeeded" if history_match is True else "interrupted"
        failure = evidence.failure if evidence is not None and evidence.state is not None else None
        if state == "interrupted":
            failure = shared.SnapshotFailure("interrupted", "Operation observation was interrupted; the platform outcome is unknown. Refresh status and inspect diagnostics before retrying")
        pre_running = current.state in {"pending", "authorizing"}
        if state == "permission-denied" and not pre_running:
            state = "failed"
        if state == "succeeded" and pre_running:
            current = operation_journal.advance_journal_operation(journal, current, replace(current, state="running", detail="Recovered PackageKit completion"))
        elif state == "permission-denied" and current.state == "pending":
            current = operation_journal.advance_journal_operation(journal, current, replace(current, state="authorizing", detail="Recovered PackageKit authorization result"))
        elif state == "canceled" and current.state == "running":
            current = operation_journal.advance_journal_operation(journal, current, replace(current, state="cancel-requested", detail="Recovered PackageKit cancellation"))
        changes = {}
        recovery_boot = None
        if current.kind == "update":
            system, session, application = current.system_restart, current.session_restart, current.application_restart
            if current.boot_id != boot_id:
                system, session, application = "none", "none", False
                recovery_boot = boot_id
            else:
                observed = evidence.restart_types if evidence is not None and evidence.state is not None else ()
                for value in observed:
                    if value == 2:
                        application = True
                    elif value in {3, 5}:
                        session = max(session, "security-session" if value == 5 else "session", key=shared.JOURNAL_RESTART_SESSION_STRENGTH.__getitem__)
                    elif value != 1:
                        system = max(system, {4: "system", 6: "security-system"}.get(value, "unknown"), key=shared.JOURNAL_RESTART_SYSTEM_STRENGTH.__getitem__)
                excluded = pre_running and evidence is not None and evidence.status == 31 and state in {"permission-denied", "canceled"}
                if history_used or (not observed and not excluded):
                    # History or incomplete adoption cannot reconstruct missed
                    # signals. This is uncertainty replacement, not satisfaction.
                    system = "unknown"
                    recovery_boot = boot_id
                elif not excluded and system == "none":
                    # A partial replay containing only lower-scope (or NONE)
                    # signals cannot exclude an earlier missed reboot signal.
                    system = "unknown"
            changes = dict(system_restart=system, session_restart=session, application_restart=application)
        cutoff = evidence.terminal_monotonic if evidence is not None and evidence.state is not None else None
        terminal = replace(current, state=state,
            finished_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            terminal_monotonic=(cutoff if cutoff is not None else time.monotonic_ns() // 1000) if current.kind in {"update", "refresh"} else None,
            error_code=None if failure is None else failure.code,
            detail="Recovered PackageKit completion; missed restart evidence remains unknown" if failure is None else failure.detail,
            **changes)
        operation_journal.advance_journal_operation(journal, current, terminal, recovery_boot_id=recovery_boot)
        operation_journal.complete_journal_terminal(journal, boot_id=boot_id, session_started=session_started)
        return operation_journal.load_writable_journal_state(journal), None, lookup_failure
