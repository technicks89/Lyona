"""Native operation ownership, regional and delegated runs, and PackageKit mutations."""

from __future__ import annotations

import contextlib
import signal
import time
from dataclasses import replace
from datetime import datetime, timezone
from typing import Callable, Mapping, Sequence

from . import (
    delegated_tools,
    operation_journal,
    packagekit,
    regional_settings,
    shared,
    update_plans,
)


# PkInfoEnum (Package) and PkStatusEnum (ItemProgress) are distinct enums.
PACKAGEKIT_INFO_PHASE = {10: "downloading", 11: "updating", 12: "installing",
                        13: "removing", 14: "cleaning", 15: "removing"}


class NativeOperationOwner:
    """Checkpoint one leased native owner before publishing its operation stream."""

    def __init__(self, journal: operation_journal.JournalDescriptorSet, operation: operation_journal.JournalOperation,
                 write: Callable[[str], object]) -> None:
        self.journal, self.operation = journal, operation
        self.stream = None
        self.output_error = self.persistence_error = None
        self.terminal = None
        try:
            self.stream = update_plans.OperationStream(operation.operation_id, operation.action_id,
                operation.started_at, operation.detail, write)
        except Exception as error:
            # Admission and its lease already exist. A partial first bundle
            # cannot be retried or replaced with an unadmitted request.
            self.output_error = error

    def current(self):
        current = operation_journal.load_writable_journal_state(self.journal).active
        if current != self.operation or current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            raise operation_journal.JournalAdmissionError("Native operation ownership changed")
        return current

    def output(self, callback):
        if self.output_error is None:
            try:
                callback()
            except Exception as error:
                if self.stream is not None and not self.stream.faulted:
                    raise
                self.output_error = error

    def checkpoint(self, state, detail):
        if self.persistence_error is not None:
            raise self.persistence_error
        try:
            with operation_journal.lock_writable_journal(self.journal):
                current = self.current()
                self.operation = operation_journal.advance_journal_operation(self.journal, current,
                    replace(current, state=state, detail=detail))
        except (OSError, operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalAdmissionError) as error:
            self.persistence_error = error
            raise
        self.output(lambda: self.stream.transition(state, detail))

    def finish(self, state, failure=None, *, success_detail=None):
        if self.persistence_error is not None:
            raise self.persistence_error
        if failure is None and self.operation.kind == "delegate" and success_detail is None:
            raise update_plans.OperationProtocolError("Delegated completion requires an explicit launch-only result")
        detail = (success_detail if failure is None and success_detail is not None else
                  "Regional change verified; sign out and back in for applications to use the locale"
                  if failure is None and self.operation.kind == "locale" else
                  "Regional change verified" if failure is None else failure.detail)
        with operation_journal.lock_writable_journal(self.journal):
            current = self.current()
            terminal = replace(current, state=state,
                finished_at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                error_code=None if failure is None else failure.code, detail=detail)
            operation_journal.advance_journal_operation(self.journal, current, terminal)
            operation_journal.complete_journal_terminal(self.journal)
        self.terminal = terminal
        self.output(lambda: self.stream.finish(terminal))
        return terminal


class RegionalCommandInterrupted(shared.SnapshotFailure):
    """An explicit local stop, not cancellation of a dispatched system change."""


def regional_interruption_failure(client) -> RegionalCommandInterrupted:
    """Distinguish an unsent preflight stop from an unconfirmed dispatched change."""
    return RegionalCommandInterrupted("interrupted",
        "Regional observation was interrupted after dispatch; the change may still complete. Refresh state before a new confirmation"
        if client.sent else "Regional preflight was interrupted; no change was sent")


def run_interruptible_regional(client: regional_settings.RegionalMutation, retained: contextlib.ExitStack):
    """Stop the GLib observer cooperatively and preserve durable caller cleanup."""
    interrupted = False
    observing = True
    stop_source = 0
    client.local_interrupted = False

    def stop_observation():
        nonlocal stop_source
        stop_source = 0
        client.fail(regional_interruption_failure(client))
        return client.GLib.SOURCE_REMOVE

    def stop(_signum, _frame):
        nonlocal interrupted, stop_source
        if interrupted:
            return
        interrupted = True
        client.local_interrupted = True
        # Exceptions raised inside GLib callbacks can be swallowed. A queued
        # stop also avoids losing quit in the gap before MainLoop.run().
        if observing:
            stop_source = client.GLib.idle_add(stop_observation, priority=client.GLib.PRIORITY_HIGH)

    try:
        for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            previous = signal.signal(signum, stop)
            # The caller registers its native lease later, so LIFO cleanup
            # releases that lease before restoring these handlers.
            retained.callback(signal.signal, signum, previous)
        if interrupted:
            raise regional_interruption_failure(client)
        return client.run()
    except SystemExit as error:
        # The fixed locale collector owns and reaps its subprocess before
        # restoring our handlers and exiting with the received signal code.
        if (client.action != "locale-set" or client.started
                or error.code not in (128 + signal.SIGTERM, 128 + signal.SIGINT, 128 + signal.SIGHUP)):
            raise
        stop(error.code - 128, None)
    finally:
        observing = False
        if stop_source:
            client.GLib.source_remove(stop_source)
        if interrupted:
            raise regional_interruption_failure(client)


def run_regional_mutation(
    journal: operation_journal.JournalDescriptorSet, action: str, argument: str, generation: str,
    write: Callable[[str], object], *, on_admission: Callable[[], None] | None = None,
) -> operation_journal.JournalOperation:
    """Own confirmed native execution, retaining liveness but not a service-wait lock."""
    argument = regional_settings.validate_regional_argument(action, argument)
    if not isinstance(generation, str) or shared.JOURNAL_GENERATION_PATTERN.fullmatch(generation) is None:
        raise shared.SnapshotFailure("malformed", "Invalid regional confirmation generation")
    if not callable(write):
        raise ValueError("Regional operation requires an output writer")
    with operation_journal.lock_writable_journal(journal):
        operation_journal.prepare_journal_admission(journal)
    owner = None
    failure = None
    with contextlib.ExitStack() as retained:
        def before_send(preview):
            nonlocal owner
            # The service client has just checked fresh configuration, choices,
            # compatibility and confirmation. Admission closes concurrent starts.
            with operation_journal.lock_writable_journal(journal):
                operation_journal.prepare_journal_admission(journal)
                if on_admission is not None:
                    on_admission()
                operation = operation_journal.begin_journal_operation(journal, action,
                    datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    f"Preparing {action}: {preview.target}")
                retained.enter_context(operation_journal.retain_native_journal_owner(journal, operation))
            owner = NativeOperationOwner(journal, operation, write)
            if owner.output_error is not None:
                raise owner.output_error
            owner.checkpoint("authorizing", "Regional authorization is pending; a sent change cannot be canceled")
            if owner.output_error is not None:
                raise owner.output_error

        def after_reply():
            owner.checkpoint("running", "Regional service accepted the change; verifying current state")

        client = regional_settings.RegionalMutation(action, argument, generation, before_send, after_reply)
        try:
            run_interruptible_regional(client, retained)
        except shared.SnapshotFailure as error:
            if owner is None:
                raise client.hook_error or error
            if owner.persistence_error is not None:
                raise owner.persistence_error
            if client.hook_error is not None and client.hook_error is not owner.output_error:
                raise client.hook_error
            failure = (shared.SnapshotFailure("internal", "Regional output was unavailable before dispatch; no change was sent")
                       if not client.sent and owner.output_error is not None else error)
        if owner is None:
            raise shared.SnapshotFailure("interrupted", "Regional execution ended without an admitted owner")
        if failure is None and (not client.sent or not client.acknowledged or owner.operation.state != "running"):
            failure = shared.SnapshotFailure("interrupted", "Regional execution ended without verified service completion")
        state = ("succeeded" if failure is None else
                 "interrupted" if client.sent and failure.code in {"timeout", "interrupted"} else
                 "permission-denied" if failure.code == "permission-denied" and owner.operation.state == "authorizing" else
                 "failed")
        terminal = owner.finish(state, failure)
    if (client.sent and failure is not None and failure.code in {"timeout", "interrupted"}
            and not client.local_interrupted):
        # The terminal/handoff is durable and the native lease is released
        # before this independent read. Its outcome cannot reclassify the call.
        # Settings will publish its own fresh snapshot on origin completion.
        # Explicit local stops must return after durable cleanup rather than
        # entering another service wait. Their caller still needs fresh state.
        with contextlib.suppress(shared.SnapshotFailure, InterruptedError):
            regional_settings.run_interruptible_read(regional_settings.RegionalRead(client.kind))
    if owner.output_error is not None:
        raise owner.output_error
    return terminal


def run_delegated_launch(journal: operation_journal.JournalDescriptorSet, action: str, write: Callable[[str], object],
                         *, on_admission: Callable[[], None] | None = None) -> operation_journal.JournalOperation:
    """Journal only a fixed tool's accepted launch, retaining no ownership of its later work."""
    if not isinstance(action, str) or action not in shared.DELEGATED_ACTIONS or not callable(write):
        raise shared.SnapshotFailure("malformed", "Invalid delegated administration request")
    with operation_journal.lock_writable_journal(journal):
        operation_journal.prepare_journal_admission(journal)
    command, label = delegated_tools.delegated_command(action)
    with contextlib.ExitStack() as retained:
        with operation_journal.lock_writable_journal(journal):
            operation_journal.prepare_journal_admission(journal)
            if on_admission is not None:
                on_admission()
            operation = operation_journal.begin_journal_operation(journal, action,
                datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "Preparing " + label)
            retained.enter_context(operation_journal.retain_native_journal_owner(journal, operation))
        owner = NativeOperationOwner(journal, operation, write)
        failure = None
        if owner.output_error is None:
            owner.checkpoint("running", "Opening " + label + "; administration remains in that tool")
        if owner.output_error is not None:
            failure = shared.SnapshotFailure("internal", "Administration output was unavailable; no tool was launched")
        else:
            try:
                delegated_tools.launch_delegated_tool(command)
            except shared.SnapshotFailure as error:
                failure = error
        terminal = owner.finish("succeeded" if failure is None else
            "interrupted" if failure.code == "interrupted" else "failed", failure,
            success_detail=label + " launch accepted; continue in the tool. Its changes and authorization are not tracked here")
    if owner.output_error is not None:
        raise owner.output_error
    return terminal


class PackageKitMutation:
    """Own one exact journaled transaction; callbacks never hold a service-wait lock."""

    def __init__(
        self, journal: operation_journal.JournalDescriptorSet, operation: operation_journal.JournalOperation,
        write: Callable[[str], object], preview: Sequence[update_plans.PlanRow],
        boot_id: str, session_started: int | None,
    ) -> None:
        self.journal = journal
        self.operation = operation
        self.boot_id = boot_id
        self.session_started = session_started
        self.stream = update_plans.OperationStream(operation.operation_id, operation.action_id,
                                      operation.started_at, operation.detail, write)
        self.observed = update_plans.ObservedUpdateSummary(preview) if operation.kind == "update" else None
        self.sent = False
        self.allow_cancel = False
        self.percent: int | None = None
        self.last_status = 0
        self.progress_warning = ""
        self.failure: shared.SnapshotFailure | None = None
        self.persistence_error: Exception | None = None
        self.output_error: Exception | None = None
        self.terminal: operation_journal.JournalOperation | None = None

    def _current(self) -> operation_journal.JournalOperation:
        current = operation_journal.load_writable_journal_state(self.journal).active
        identity = ("operation_id", "action_id", "kind", "started_at", "generation",
                    "transaction_path", "boot_id", "slot")
        if current is None or any(getattr(current, key) != getattr(self.operation, key) for key in identity):
            raise operation_journal.JournalAdmissionError("PackageKit operation ownership changed")
        if current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            raise operation_journal.JournalAdmissionError("PackageKit operation was terminalized by another observer")
        return current

    def _output(self, callback: Callable[[], object]) -> None:
        if self.output_error is None:
            try:
                callback()
            except Exception as error:
                if not self.stream.faulted:
                    raise
                self.output_error = error

    def _sync_stream(self) -> None:
        target = self.operation.state
        if self.output_error is not None or target == self.stream.state:
            return
        if target == "authorizing":
            self._output(lambda: self.stream.transition("authorizing", self.operation.detail))
        else:
            if self.stream.state in {"pending", "authorizing"}:
                self._output(lambda: self.stream.transition("running", "PackageKit is processing the transaction"))
            if target == "cancel-requested" and self.stream.state != target:
                self._output(lambda: self.stream.transition("cancel-requested", "PackageKit cancellation requested"))

    def _checkpoint(self, state: str | None = None, **changes: object) -> None:
        if self.persistence_error is not None:
            return
        try:
            with operation_journal.lock_writable_journal(self.journal):
                current = self._current()
                target = state or current.state
                if target in {"authorizing", "running"} and current.state == "cancel-requested":
                    target = current.state
                if target == "authorizing" and current.state == "running":
                    target = current.state
                for key, strength in (("system_restart", shared.JOURNAL_RESTART_SYSTEM_STRENGTH),
                                      ("session_restart", shared.JOURNAL_RESTART_SESSION_STRENGTH)):
                    if key in changes:
                        changes[key] = max(getattr(current, key), changes[key], key=strength.__getitem__)
                if target != current.state and "detail" not in changes:
                    changes["detail"] = "PackageKit cancellation requested" if target == "cancel-requested" else "PackageKit is processing the transaction"
                following = replace(current, state=target, **changes)
                self.operation = operation_journal.advance_journal_operation(self.journal, current, following)
            self._sync_stream()
        except (operation_journal.JournalFileError, operation_journal.JournalRecordError, operation_journal.JournalFrameError, operation_journal.JournalAdmissionError) as error:
            self.persistence_error = error

    def before_send(self) -> None:
        self._checkpoint("authorizing", detail="PackageKit authorization is pending")
        if self.persistence_error is not None:
            raise self.persistence_error
        if self.output_error is not None:
            raise self.output_error
        self.journal.validate()
        self.sent = True

    def after_send(self) -> None:
        try:
            self.journal.validate()
        except operation_journal.JournalFileError as error:
            self.persistence_error = error

    def _detail(self) -> str:
        detail = self.observed.detail() if self.observed is not None else "PackageKit metadata refresh is running"
        return shared.clean_text(f"{detail}; {self.progress_warning}" if self.progress_warning else detail)

    def _progress(self) -> None:
        if self.persistence_error is None and self.operation.state in {"running", "cancel-requested"}:
            self._output(lambda: self.stream.transition(self.operation.state, self._detail(),
                                                       percent=self.percent, cancelable=self.allow_cancel))

    def on_properties(self, properties: Mapping[str, object]) -> None:
        old_progress = (self.percent, self.allow_cancel, self.progress_warning)
        if "AllowCancel" in properties:
            value = properties["AllowCancel"]
            self.allow_cancel = value if type(value) is bool else False
            if type(value) is not bool:
                self.progress_warning = "PackageKit cancellation state is malformed"
        if "Percentage" in properties:
            value = properties["Percentage"]
            self.percent = value if type(value) is int and 0 <= value <= 100 else None
            if type(value) is not int or not 0 <= value <= 101:
                self.progress_warning = "PackageKit percentage is malformed; progress is unknown"
        if "Status" in properties:
            status = properties["Status"]
            if type(status) is int and 0 <= status <= 36:
                self.last_status = status
                if status not in {0, 1, 2, 18, 31} and self.operation.state not in {"running", "cancel-requested"}:
                    self._checkpoint("running")
            else:
                self.last_status = 0
                self.progress_warning = "PackageKit phase is unknown"
        if old_progress != (self.percent, self.allow_cancel, self.progress_warning):
            # A cooperating cancel control may have checkpointed while the
            # transaction was running. Reconcile its exact identity once here.
            self._checkpoint()
            self._progress()

    def on_package(self, info: int, package_id: str) -> None:
        if self.observed is None or self.persistence_error is not None:
            return
        previous = (self.observed.comparison(), len(self.observed.samples))
        try:
            self.observed.observe(info, package_id)
        except shared.SnapshotFailure as error:
            self.failure = self.failure or error
            return
        if self.operation.state not in {"running", "cancel-requested"}:
            self._checkpoint("running")
        if previous != (self.observed.comparison(), len(self.observed.samples)):
            self._progress()
        phase = PACKAGEKIT_INFO_PHASE.get(info)
        if phase is not None:
            self.on_item_progress(package_id, phase, None)

    def on_item_progress(self, identity: str, phase: str, percent: int | None) -> None:
        # ItemProgress is optional display evidence, not proof of execution.
        if self.persistence_error is not None or self.operation.state not in {"running", "cancel-requested"}:
            return
        try:
            identity = update_plans.canonical_identity(identity)
            name = update_plans.package_display_fields(identity)[0] if self.operation.kind == "update" else shared.clean_text(identity)
        except shared.SnapshotFailure:
            # Optional display evidence must not change the transaction outcome.
            name, phase, percent = "", "working", None
        self._output(lambda: self.stream.item_progress(name, phase, percent))

    def on_restart(self, value: int) -> None:
        if self.operation.kind != "update" or self.persistence_error is not None:
            return
        changes = {}
        if value == 2:
            changes["application_restart"] = True
        elif value in {3, 5}:
            requested = "security-session" if value == 5 else "session"
            changes["session_restart"] = max(self.operation.session_restart, requested,
                key=shared.JOURNAL_RESTART_SESSION_STRENGTH.__getitem__)
        elif value != 1:
            requested = {4: "system", 6: "security-system"}.get(value, "unknown")
            changes["system_restart"] = max(self.operation.system_restart, requested,
                key=shared.JOURNAL_RESTART_SYSTEM_STRENGTH.__getitem__)
        if changes and any(getattr(self.operation, key) != value for key, value in changes.items()):
            self._checkpoint(**changes)

    def finish(self, state: str, failure: shared.SnapshotFailure | None = None,
               *, invocation_rejected: bool = False) -> None:
        cutoff = time.monotonic_ns() // 1000
        finished_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if self.persistence_error is not None or self.terminal is not None:
            return
        try:
            with operation_journal.lock_writable_journal(self.journal):
                self.operation = self._current()
            self._sync_stream()
            if state == "succeeded":
                self._checkpoint("running")
            elif state == "permission-denied" and self.operation.state in {"running", "cancel-requested"}:
                state = "failed"
            elif state == "canceled" and self.operation.state == "running":
                self._checkpoint("cancel-requested")
            if self.persistence_error is not None:
                return
            with operation_journal.lock_writable_journal(self.journal):
                current = self._current()
                contribution = current.system_restart
                pre_running = current.state in {"pending", "authorizing"}
                excluded = state == "permission-denied" or (pre_running and (
                    invocation_rejected or (state == "canceled" and self.last_status == 31)))
                if current.kind == "update" and self.sent and not excluded and state != "succeeded" and contribution == "none":
                    contribution = "unknown"
                terminal = replace(current, state=state, finished_at=finished_at,
                                   error_code=None if failure is None else failure.code,
                                   detail="PackageKit transaction completed" if failure is None else failure.detail,
                                   system_restart=contribution, terminal_monotonic=cutoff)
                operation_journal.advance_journal_operation(self.journal, current, terminal)
                operation_journal.complete_journal_terminal(self.journal, boot_id=self.boot_id,
                                          session_started=self.session_started)
            self.terminal = terminal
            detail = terminal.detail
            if self.observed is not None:
                detail = shared.clean_text(f"{self.observed.detail(final=True)}; {detail}")
            self._output(lambda: self.stream.finish(terminal, detail=detail))
        except (operation_journal.JournalFileError, operation_journal.JournalRecordError, operation_journal.JournalFrameError, operation_journal.JournalAdmissionError) as error:
            self.persistence_error = error


def run_packagekit_mutation(
    journal: operation_journal.JournalDescriptorSet, backend: packagekit.PackageKitBackend, action_id: str,
    write: Callable[[str], object], *, boot_id: str, session_started: int | None = None,
    generation: str | None = None,
    on_admission: Callable[[], object] | None = None,
) -> operation_journal.JournalOperation:
    """Revalidate and run a confirmed request with write-ahead ownership."""
    if action_id not in {"updates-refresh", "updates-install-all"}:
        raise shared.SnapshotFailure("unsupported", "Unsupported PackageKit mutation", "unsupported")
    if action_id == "updates-install-all":
        if not isinstance(generation, str) or shared.JOURNAL_GENERATION_PATTERN.fullmatch(generation) is None:
            raise shared.SnapshotFailure("malformed", "Confirmed update generation is invalid")
    elif generation is not None:
        raise shared.SnapshotFailure("malformed", "Metadata refresh cannot select packages")
    # Reject existing owners before service work, then repeat admission under
    # the lock after the unlocked preflight to close concurrent-start races.
    with operation_journal.lock_writable_journal(journal):
        operation_journal.prepare_journal_admission(journal)
    backend.require_mutation_safe()
    package_ids, preview = update_plans.confirmed_update_plan(backend, generation) if action_id == "updates-install-all" else ((), ())
    path = backend.create_mutation()
    if not isinstance(path, str) or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path) is None:
        raise shared.SnapshotFailure("malformed", "PackageKit returned an invalid operation path")
    with operation_journal.lock_writable_journal(journal):
        if on_admission is not None:
            operation_journal.prepare_journal_admission(journal)
            on_admission()  # From here, even a failed commit may require recovery.
        operation = operation_journal.begin_journal_operation(journal, action_id,
            datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "Starting PackageKit operation",
            transaction_path=path, generation=generation, boot_id=boot_id)
    owner = PackageKitMutation(journal, operation, write, preview, boot_id, session_started)
    backend.execute_mutation(owner, package_ids)
    if owner.persistence_error is not None:
        raise owner.persistence_error
    if owner.output_error is not None:
        raise owner.output_error
    if owner.terminal is None:
        raise shared.SnapshotFailure("interrupted", "PackageKit observation ended without a durable terminal result")
    return owner.terminal
