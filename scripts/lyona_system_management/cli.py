"""The command line: subcommands, usage and main."""

from __future__ import annotations

import fcntl
import io
import os
import sys
from datetime import datetime, timezone
from typing import Callable, Sequence

from . import (
    native_operations,
    operation_journal,
    packagekit,
    regional_settings,
    shared,
    snapshots,
    update_plans,
    watch_commands,
)


def ntp_sample_command() -> int:
    return finite_status_command(regional_settings.ntp_sample_output)


def stdout_writable() -> bool:
    """Detect a closed, readonly, or absent stdout without attempting a write.

    Checked ahead of read_output() below so an unavailable stream fails
    before the (D-Bus) read runs at all, matching upstream's
    control_output_writers()-based ordering even though Lyona does not
    port that abstraction itself -- verified empirically against every
    failure mode its own test suite exercises: a closed file descriptor
    (fcntl.F_GETFL raises OSError), a readonly file descriptor (its
    O_ACCMODE excludes write), a Python-level sys.stdout.close() (.closed
    is True), and a detached/headless sys.stdout of None.
    """
    if sys.stdout is None or sys.stdout.closed:
        return False
    try:
        descriptor = sys.stdout.fileno()
    except io.UnsupportedOperation:
        return True  # In-memory test consumers have no kernel descriptor to check.
    except ValueError:
        return False
    try:
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
    except OSError:
        return False
    return (flags & os.O_ACCMODE) in (os.O_WRONLY, os.O_RDWR)


def finite_status_command(read_output: Callable[[], tuple[str, int]]) -> int:
    """Write one finite status read or scoped error, synchronously.

    Sync Sprint 1 S1-07 (#271, generalized by #273): upstream wraps this
    write in control_output_writers(), a nonblocking-descriptor abstraction
    Lyona declined during Sync Phase 9 (see control_output_writer()'s own
    docstring) -- this command's synchronous sys.stdout.write()/flush() path
    never sets O_NONBLOCK on the inherited descriptor in the first place, so
    it was never exposed to the bug that abstraction exists to fix, matching
    every other command wrapper in this file (native_command(),
    update_command()).

    A ValueError here (not just OSError) is a controlled failure too: a
    Python-level sys.stdout.close() before this runs raises ValueError, not
    OSError -- verified empirically, not assumed.
    """
    if not stdout_writable():
        return 1
    try:
        output, code = read_output()
        sys.stdout.write(output)
        sys.stdout.flush()
        return code
    except (OSError, ValueError):
        return 1


def operation_control(command: str, operation_id: str) -> int:
    """Keep stale control rejection stream-free and watch failure distinct."""
    started = False
    cancel_dispatched = False

    def dispatched():
        nonlocal cancel_dispatched
        cancel_dispatched = True

    def write(chunk):
        nonlocal started
        started = True
        sys.stdout.write(chunk)
        sys.stdout.flush()

    try:
        boot_id = update_plans.read_boot_id()
        with operation_journal.open_journal_directory() as chain, operation_journal.retain_writable_journal(chain) as journal:
            if command == "watch-operation":
                watch_commands.watch_journal_operation(journal, operation_id, write, boot_id=boot_id)
            elif command == "updates-cancel":
                watch_commands.cancel_journal_operation(journal, operation_id, boot_id=boot_id,
                    on_dispatch=dispatched, backend_factory=packagekit.PackageKitBackend)
            else:
                watch_commands.control_journal_target(journal, operation_id, boot_id)
                with operation_journal.lock_writable_journal(journal):
                    operation_journal.acknowledge_journal_handoff(journal, operation_id)
        return 0
    except (shared.SnapshotFailure, operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalAdmissionError, OSError, update_plans.OperationProtocolError) as error:
        if command == "updates-cancel":
            if cancel_dispatched and not isinstance(error, operation_journal.CancelTargetUnavailable):
                print("cancellation request could not be confirmed; observe the existing operation", file=sys.stderr)
                return 1
            print("cancel target is unavailable", file=sys.stderr)
            return 3
        if started:
            if isinstance(error, BrokenPipeError):
                # Avoid a second buffered flush at interpreter shutdown changing
                # the exit status or writing an unraisable-exception diagnostic.
                with open(os.devnull, "w") as sink:
                    os.dup2(sink.fileno(), sys.stdout.fileno())
            print("operation observation was interrupted", file=sys.stderr)
            return 1
        print("watch target is unavailable" if command == "watch-operation" else "ack target is unavailable", file=sys.stderr)
        return 3


def native_command(action: str, argument: str = "", generation: str = "") -> int:
    """Own an explicit CLI request for one fixed regional or delegated origin."""
    admission_started = False
    output_started = False
    delegated = action in shared.DELEGATED_ACTIONS
    family = "administration" if delegated else "regional"

    def admitted():
        nonlocal admission_started
        admission_started = True

    def write(chunk):
        nonlocal output_started
        output_started = True  # A failed write may already have delivered bytes.
        sys.stdout.write(chunk)
        sys.stdout.flush()

    try:
        boot_id = update_plans.read_boot_id()
        with operation_journal.open_journal_directory() as chain:
            operation_journal.initialize_journal_layout(chain.directory_descriptor, boot_id)
            with operation_journal.retain_writable_journal(chain) as journal:
                started_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                try:
                    terminal = (native_operations.run_delegated_launch(journal, action, write, on_admission=admitted)
                                if delegated else native_operations.run_regional_mutation(journal, action, argument, generation,
                                                                       write, on_admission=admitted))
                    return 0 if terminal.state == "succeeded" else 1
                except (shared.SnapshotFailure, operation_journal.JournalFrameError, operation_journal.JournalRecordError,
                        operation_journal.JournalAdmissionError, OSError, update_plans.OperationProtocolError) as error:
                    if admission_started or output_started:
                        raise
                    # This ID represents only the rejected request. No active,
                    # terminal, or handoff payload is fabricated for it.
                    with operation_journal.lock_writable_journal(journal):
                        operation_id = operation_journal.generate_journal_operation_id(operation_journal.load_writable_journal_state(journal))
                    if isinstance(error, shared.SnapshotFailure):
                        failure = error
                    elif isinstance(error, (operation_journal.JournalAdmissionError, operation_journal.JournalLockError)):
                        failure = shared.SnapshotFailure("conflict", "Another operation or recovery state blocks this request; refresh state before retrying")
                    elif isinstance(error, (operation_journal.JournalFrameError, operation_journal.JournalRecordError, update_plans.OperationProtocolError)):
                        failure = shared.SnapshotFailure("malformed", family.capitalize() + " preflight is malformed; refresh state and inspect recovery guidance")
                    else:
                        failure = shared.SnapshotFailure("internal", family.capitalize() + " preflight failed; check journal storage and refresh state before retrying")
                    update_plans.reject_unadmitted_operation(operation_id, action, started_at, failure, write)
                    return 1
    except (shared.SnapshotFailure, operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalAdmissionError,
            OSError, update_plans.OperationProtocolError) as error:
        if isinstance(error, BrokenPipeError):
            with open(os.devnull, "w") as sink:
                os.dup2(sink.fileno(), sys.stdout.fileno())
        print(family + " result could not be confirmed; refresh state and observe the existing operation", file=sys.stderr)
        return 1


def update_command(action_id: str, generation: str | None = None) -> int:
    """Own an explicit CLI request; never replace a possibly admitted operation."""
    admission_started = False
    output_started = False

    def admitted():
        nonlocal admission_started
        admission_started = True

    def write(chunk):
        nonlocal output_started
        output_started = True  # A failed write may already have delivered bytes.
        sys.stdout.write(chunk)
        sys.stdout.flush()

    try:
        boot_id = update_plans.read_boot_id()
        with operation_journal.open_journal_directory() as chain:
            operation_journal.initialize_journal_layout(chain.directory_descriptor, boot_id)
            with operation_journal.retain_writable_journal(chain) as journal:
                started_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                try:
                    with operation_journal.lock_writable_journal(journal):
                        # A reboot satisfies restart guidance before any backend
                        # work. Never clear an active owner or unacknowledged
                        # handoff to make a replacement command admissible.
                        operation_journal.prepare_journal_admission(journal)
                        operation_journal.prune_journal_restart(journal, boot_id, None)
                    terminal = native_operations.run_packagekit_mutation(journal, packagekit.PackageKitBackend(), action_id, write,
                        boot_id=boot_id, generation=generation, on_admission=admitted)
                    return 0 if terminal.state == "succeeded" else 1
                except (shared.SnapshotFailure, operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalAdmissionError,
                        OSError, update_plans.OperationProtocolError) as error:
                    if admission_started or output_started:
                        raise
                    # This ID represents only the rejected request. No active,
                    # terminal, handoff, or restart payload is fabricated for it.
                    with operation_journal.lock_writable_journal(journal):
                        operation_id = operation_journal.generate_journal_operation_id(operation_journal.load_writable_journal_state(journal))
                    if isinstance(error, shared.SnapshotFailure):
                        failure = error
                    elif isinstance(error, (operation_journal.JournalAdmissionError, operation_journal.JournalLockError)):
                        failure = shared.SnapshotFailure("conflict", "Another operation or recovery state blocks this request; refresh status before retrying")
                    elif isinstance(error, (operation_journal.JournalFrameError, operation_journal.JournalRecordError, update_plans.OperationProtocolError)):
                        failure = shared.SnapshotFailure("malformed", "Operation preflight is malformed; refresh status and inspect recovery guidance")
                    else:
                        failure = shared.SnapshotFailure("internal", "Operation preflight failed; check journal storage and refresh status before retrying")
                    update_plans.reject_unadmitted_operation(operation_id, action_id, started_at, failure, write)
                    return 1
    except (shared.SnapshotFailure, operation_journal.JournalFrameError, operation_journal.JournalRecordError, operation_journal.JournalAdmissionError,
            OSError, update_plans.OperationProtocolError) as error:
        if isinstance(error, BrokenPipeError):
            with open(os.devnull, "w") as sink:
                os.dup2(sink.fileno(), sys.stdout.fileno())
        print("operation result could not be confirmed; refresh status and observe the existing operation", file=sys.stderr)
        return 1


def usage() -> int:
    print(f"usage: {sys.argv[0]} snapshot | snapshot-core | snapshot-without-storage | "
          "ntp-sample | time-status | watch-domains | watch-mounts | watch-time | "
          "watch-updates | updates-refresh | "
          "updates-install-all GENERATION | watch-operation OPERATION_ID | "
          "ack-operation OPERATION_ID | updates-cancel OPERATION_ID | "
          "regional-choices timezone|locale | regional-preview ACTION VALUE | "
          "timezone-set ZONE GENERATION | ntp-set enabled|disabled GENERATION | "
          "locale-set LANG=LOCALE GENERATION | accounts-open | password-open | "
          "printers-open | sources-open | watch-regional time|locale | "
          "watch-accounts | watch-units printers|security", file=sys.stderr)
    return 2


def main(argv: Sequence[str]) -> int:
    if argv and argv[0] == "watch-domains":
        return watch_commands.watch_domains() if len(argv) == 1 else usage()
    if argv and argv[0] == "watch-mounts":
        return watch_commands.watch_mount_events() if len(argv) == 1 else usage()
    if argv and argv[0] == "time-status":
        return finite_status_command(regional_settings.time_status_output) if len(argv) == 1 else usage()
    if argv and argv[0] == "watch-time":
        return watch_commands.watch_service_events("time-discovery") if len(argv) == 1 else usage()
    if argv and argv[0] == "ntp-sample":
        return ntp_sample_command() if len(argv) == 1 else usage()
    if argv and argv[0] == "watch-units":
        return watch_commands.watch_service_events(argv[1]) if len(argv) == 2 and argv[1] in shared.WATCH_UNIT_SETS else usage()
    if argv and argv[0] == "watch-accounts":
        return watch_commands.watch_account_events() if len(argv) == 1 else usage()
    if argv and argv[0] == "watch-regional":
        return watch_commands.watch_regional_events(argv[1]) if len(argv) == 2 and argv[1] in ("time", "locale") else usage()
    if argv and argv[0] in {"timezone-set", "ntp-set", "locale-set"}:
        if len(argv) != 3 or shared.JOURNAL_GENERATION_PATTERN.fullmatch(argv[2]) is None:
            return usage()
        try:
            regional_settings.validate_regional_argument(argv[0], argv[1])
        except shared.SnapshotFailure:
            return usage()
        return native_command(*argv)
    if argv and argv[0] in shared.DELEGATED_ACTIONS:
        return native_command(argv[0]) if len(argv) == 1 else usage()
    if argv and argv[0] in {"regional-choices", "regional-preview"}:
        try:
            output, code = regional_settings.regional_preflight_output(argv[0], argv[1:])
        except ValueError:
            return usage()
        try:
            sys.stdout.write(output)
            sys.stdout.flush()
        except BrokenPipeError:
            # Prevent the shutdown flush from replacing the controlled status
            # or emitting an unraisable-exception diagnostic for a closed pane.
            with open(os.devnull, "w") as sink:
                os.dup2(sink.fileno(), sys.stdout.fileno())
            return 1
        return code
    if list(argv) == ["watch-updates"]:
        return watch_commands.watch_update_events()
    if list(argv) == ["updates-refresh"]:
        return update_command("updates-refresh")
    if len(argv) == 2 and argv[0] == "updates-install-all" and shared.JOURNAL_GENERATION_PATTERN.fullmatch(argv[1]):
        return update_command("updates-install-all", argv[1])
    if len(argv) == 2 and argv[0] in {"watch-operation", "ack-operation", "updates-cancel"} and shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(argv[1]):
        return operation_control(argv[0], argv[1])
    if len(argv) != 1 or argv[0] not in {"snapshot", "snapshot-core", "snapshot-without-storage"}:
        return usage()
    try:
        backend = packagekit.PackageKitBackend()
    except shared.SnapshotFailure as failure:
        # Backend construction can fail before a usable source exists. Reuse the
        # normal snapshot shape so consumers still receive every mandatory ID.
        class FailedBackend:
            def __init__(self, backend_failure: shared.SnapshotFailure) -> None:
                self.failure = backend_failure

            def last_refresh_age(self) -> int:
                raise self.failure

            def updates(self) -> update_plans.TransactionResult:
                raise self.failure

            def simulate(self, _package_ids: Sequence[str]) -> update_plans.TransactionResult:
                raise self.failure

            def session_started(self) -> int:
                raise self.failure

            def probe_operation(self, _operation, **_kwargs):
                raise self.failure

            def operation_history(self):
                raise self.failure

        backend = FailedBackend(failure)
    # Required recovery never starts optional information probes. A failed or
    # pending mount handshake leaves other information readable without opening
    # the filesystem inventory's unmonitored initialization gap.
    information_sources = None if argv[0] == "snapshot-core" else snapshots.InformationSnapshotSources(
        storage_ready=argv[0] == "snapshot")
    lines = snapshots.build_managed_snapshot(backend, native_sources=snapshots.NativeSnapshotSources(),
        information_sources=information_sources)
    print("\n".join(lines))
    return 0
