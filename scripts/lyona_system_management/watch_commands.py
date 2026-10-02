"""Output writers and the watch commands: mounts, services, updates, regional settings, accounts, journal."""

from __future__ import annotations

import contextlib
import ctypes
import fcntl
import io
import os
import re
import selectors
import signal
import socket
import stat
import struct
import subprocess
import sys
import threading
import time
from dataclasses import replace
from typing import Callable

from . import (
    event_monitors,
    operation_journal,
    packagekit,
    regional_settings,
    shared,
    update_plans,
)


NATIVE_WATCH_SECONDS = 120


def control_output_writer(output, resources: contextlib.ExitStack) -> Callable[[bytes], int] | None:
    """Never set file-status flags on an inherited open-file description.

    Sync Phase 9 (docs/SYNC-P9-REGIONAL-MUTATION.md §4): ported from upstream's
    0eae066d, promoted from "general robustness, out of scope" to required --
    the plain os.set_blocking(fd, False) this replaces mutates the *shared*
    open-file description an inherited stdout pipe/tty points at, which is
    visible to (and disrupts) any other holder of that same writer, including
    a parent shell group. Opening a private descriptor via /proc/self/fd
    avoids that. control_output_writers() (the signal-handling stdout+stderr
    pair upstream also ships) is not ported: operation_control() keeps its
    own simpler, already-tested synchronous sys.stdout.write()/flush() path,
    which never sets O_NONBLOCK on the inherited descriptor in the first
    place and so was never exposed to this class of bug.
    """
    try:
        descriptor = output.fileno()
    except io.UnsupportedOperation:
        return None  # In-memory test consumers have no kernel writer.
    original = os.fstat(descriptor)
    flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
    if (flags & os.O_ACCMODE) not in (os.O_WRONLY, os.O_RDWR):
        raise OSError("Operation output is not writable")
    if stat.S_ISFIFO(original.st_mode) or stat.S_ISCHR(original.st_mode):
        # dup would still share O_NONBLOCK with the parent. Opening the retained
        # proc descriptor gives pipes/terminals a separate open-file description.
        descriptor = os.open(f"/proc/self/fd/{descriptor}",
            os.O_WRONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOCTTY)
        resources.callback(os.close, descriptor)
        if stat.S_ISFIFO(original.st_mode) and flags & os.O_DIRECT:
            # Packet mode is set after opening a pipe, on this private OFD only.
            fcntl.fcntl(descriptor, fcntl.F_SETFL, fcntl.fcntl(descriptor, fcntl.F_GETFL) | os.O_DIRECT)
        current = os.fstat(descriptor)
        identity = lambda value: (value.st_dev, value.st_ino, value.st_mode, value.st_rdev)
        if identity(current) != identity(original):
            raise OSError("Operation output identity changed")
    elif stat.S_ISSOCK(original.st_mode):
        # Sockets cannot be reopened through proc. MSG_DONTWAIT is per-call,
        # unlike O_NONBLOCK, and does not affect another holder of this socket.
        libc = ctypes.CDLL(None, use_errno=True)
        libc.send.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
        libc.send.restype = ctypes.c_ssize_t

        def send(payload):
            count = libc.send(descriptor, payload, len(payload), socket.MSG_DONTWAIT | socket.MSG_NOSIGNAL)
            if count < 0:
                raise OSError(ctypes.get_errno(), "Operation socket output failed")
            return count

        return send
    elif not stat.S_ISREG(original.st_mode):
        raise OSError("Unsupported operation output type")
    # Regular files retain their original shared offset and append semantics.
    # O_NONBLOCK cannot impose a storage-I/O deadline on a regular file.
    return lambda payload: os.write(descriptor, payload)


# This fresh, single-threaded child arms parent-death cleanup before replacing
# itself with findmnt. Recheck the original parent to close the startup race.
# Popen closes inherited nonstandard descriptors before the isolated interpreter.
MOUNT_MONITOR_EXEC = """
import ctypes, os, signal, sys
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
    sys.exit(1)
if os.getppid() != int(sys.argv[1]):
    sys.exit(1)
os.execv('/usr/bin/findmnt', ['findmnt', '--poll', '--raw', '--noheadings', '--output', 'ACTION'])
"""
MOUNT_ACTIONS = frozenset((b"mount", b"umount", b"move", b"remount"))


def mount_baseline_ready(process, identity) -> bool:
    """Observe only the live, unreaped child's exact mountinfo descriptor."""
    if regional_settings.locale_process_status(process) is not None:
        raise OSError("Mount monitor exited before readiness")
    directory = f"/proc/{process.pid}"
    current = os.stat(directory)
    if (current.st_dev, current.st_ino) != identity:
        raise OSError("Mount monitor identity changed")
    with os.scandir(directory + "/fd") as entries:
        for entry in entries:
            if not entry.name.isdecimal():
                continue
            try:
                if os.readlink(entry.path) == directory + "/mountinfo":
                    # Some util-linux builds open their temporary parsing
                    # descriptor with CLOEXEC, but poll_table's persistent
                    # fopen("r") does not. Merely seeing mountinfo can race
                    # the first parse.
                    with open(directory + "/fdinfo/" + entry.name, "r", encoding="ascii") as info:
                        fields = info.read(4096).splitlines()
                    flags = [line.split(":", 1)[1].strip() for line in fields if line.startswith("flags:")]
                    if len(flags) == 1 and re.fullmatch(r"[0-7]+", flags[0]):
                        if not int(flags[0], 8) & os.O_CLOEXEC:
                            return True
            except FileNotFoundError:
                pass  # An unrelated startup descriptor may have just closed.
    return False


def watch_mount_events() -> int:
    """Supervise one pane-owned fixed mount event stream without idle polling."""
    if (threading.current_thread() is not threading.main_thread()
            or signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL):
        return 1
    process = None
    handlers = {}
    interrupted = 0
    code = 1
    failure_detail = b"Mount monitoring is unavailable; reload storage status explicitly\n"

    def terminate(number, _frame):
        nonlocal interrupted
        interrupted = interrupted or number

    try:
        with contextlib.ExitStack() as resources:
            output_descriptor = sys.stdout.fileno()
            output_mode = os.fstat(output_descriptor).st_mode
            if (not stat.S_ISFIFO(output_mode)
                    or fcntl.fcntl(output_descriptor, fcntl.F_GETFL) & os.O_ACCMODE != os.O_WRONLY):
                # Only a write-only pipe gives this owner an idle reader-loss
                # event. Sockets can half-close silently; O_RDWR FIFOs retain a
                # reader themselves. Quickshell supplies the supported pipe.
                failure_detail = b"Mount monitoring requires write-only pipe output; use a pipe consumer\n"
                raise OSError("Unsupported mount monitor output")
            writer = control_output_writer(sys.stdout, resources)
            if writer is None:
                raise OSError("Mount monitor requires a descriptor")

            def emit(payload):
                if writer(payload) != len(payload):
                    raise OSError("Incomplete mount event output")

            wake_read, wake_write = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
            resources.callback(os.close, wake_read)
            resources.callback(os.close, wake_write)
            previous_wake = signal.set_wakeup_fd(wake_write)
            resources.callback(signal.set_wakeup_fd, previous_wake)
            for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                handlers[number] = signal.signal(number, terminate)
            try:
                deadline = time.monotonic() + 1
                process = subprocess.Popen(["/usr/bin/python3", "-I", "-c", MOUNT_MONITOR_EXEC,
                    str(os.getpid())], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, start_new_session=True, close_fds=True,
                    env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"})
                identity = os.stat(f"/proc/{process.pid}")
                identity = (identity.st_dev, identity.st_ino)
                pidfd = os.pidfd_open(process.pid)
                resources.callback(os.close, pidfd)
                with selectors.DefaultSelector() as selector:
                    selector.register(wake_read, selectors.EVENT_READ)
                    selector.register(pidfd, selectors.EVENT_READ)
                    if stat.S_ISFIFO(output_mode):
                        # A write-end pipe reports EPOLLERR when its last reader
                        # disappears. Read interest avoids a writable idle spin.
                        selector.register(output_descriptor, selectors.EVENT_READ)
                    for stream in (process.stdout, process.stderr):
                        os.set_blocking(stream.fileno(), False)
                        selector.register(stream, selectors.EVENT_READ)
                    ready = False
                    pending = bytearray()
                    while not interrupted:
                        if not ready:
                            observed = mount_baseline_ready(process, identity)
                            if time.monotonic() >= deadline:
                                raise OSError("Mount monitor readiness timed out")
                            if observed:
                                emit(b"mount-monitor-ready\n")
                                ready = True
                        # Readiness has one bounded startup probe. Once ready,
                        # pipes, pidfd, and the signal wakeup are the only events.
                        events = selector.select(None if ready else min(0.01, max(0, deadline - time.monotonic())))
                        for key, _events in events:
                            if interrupted:
                                break
                            if key.fd == wake_read:
                                os.read(wake_read, 4096)
                                continue
                            if key.fd == pidfd:
                                raise OSError("Mount monitor exited unexpectedly")
                            if key.fd == output_descriptor:
                                raise OSError("Mount monitor consumer disappeared")
                            if not ready and key.fileobj is process.stdout:
                                continue  # Retain early events until baseline acknowledgment.
                            chunk = os.read(key.fd, 4096)
                            if not chunk or key.fileobj is process.stderr:
                                raise OSError("Mount monitor output failed")
                            pending.extend(chunk)
                            while b"\n" in pending:
                                line, _, pending = pending.partition(b"\n")
                                if len(line) > 256 or bytes(line) not in MOUNT_ACTIONS:
                                    raise OSError("Malformed mount event")
                                emit(b"mount-change\t" + line + b"\n")
                            if len(pending) > 256:
                                raise OSError("Oversized mount event")
            finally:
                if process is not None:
                    regional_settings.close_locale_process(process)
    except (OSError, ValueError, shared.SnapshotFailure):
        pass
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)
    if interrupted:
        return 128 + interrupted
    try:
        with contextlib.ExitStack() as resources:
            writer = control_output_writer(sys.stderr, resources)
            if writer is not None:
                writer(failure_detail)
    except (OSError, ValueError):
        pass
    return code


def watch_service_events(service_kind: str | None = None) -> int:
    """Stream bounded change records for updates or one of the Phase 9 domains."""
    output_writer = None

    def emit(record: str) -> None:
        payload = (record + "\n").encode("ascii")
        # Each fixed row fits PIPE_BUF. Never block GLib callbacks behind a
        # stalled reader or queue unbounded notifications. Overflow is an
        # explicit monitoring failure; the consumer must refresh finite state.
        if output_writer(payload) != len(payload):
            raise OSError("Incomplete event output")

    try:
        import gi

        gi.require_version("Gio", "2.0")
        gi.require_version("GLibUnix", "2.0")
        from gi.repository import Gio, GLib, GLibUnix

        with contextlib.ExitStack() as resources:
            output_writer = control_output_writer(sys.stdout, resources)
            if output_writer is None:
                raise OSError("Event output requires a file descriptor")
            if service_kind is None:
                monitor = event_monitors.UpdateEventMonitor(Gio, GLib, GLibUnix, emit)
            elif service_kind == "accounts":
                monitor = event_monitors.AccountEventMonitor(Gio, GLib, GLibUnix, emit)
            elif service_kind == "time-discovery":
                monitor = event_monitors.TimeEventMonitor(Gio, GLib, GLibUnix, emit)
            elif service_kind in shared.WATCH_UNIT_SETS:
                monitor = event_monitors.UnitEventMonitor(service_kind, Gio, GLib, GLibUnix, emit)
            else:
                monitor = event_monitors.RegionalEventMonitor(service_kind, Gio, GLib, GLibUnix, emit)
            code = monitor.run()
    except (ImportError, ValueError, OSError):
        code = 1
    if code:
        try:
            with contextlib.ExitStack() as resources:
                error_writer = control_output_writer(sys.stderr, resources)
                if error_writer is not None:
                    label = ("PackageKit" if service_kind is None else "Account" if service_kind == "accounts"
                             else "Unit" if service_kind in shared.WATCH_UNIT_SETS else "Regional")
                    error_writer((label + " live change monitoring is unavailable; reload status explicitly\n").encode("ascii"))
        except (OSError, ValueError):
            # Exit status remains authoritative when even diagnostics cannot
            # be delivered (including stderr sharing the full stdout pipe).
            pass
    return code


def watch_update_events() -> int:
    return watch_service_events()


def watch_regional_events(kind: str) -> int:
    return watch_service_events(kind)


def watch_account_events() -> int:
    return watch_service_events("accounts")


def control_journal_target(journal: operation_journal.JournalDescriptorSet, operation_id: str, boot_id: str) -> operation_journal.JournalOperation:
    """Complete interrupted terminal commits, then select only the exact control ID."""
    with operation_journal.lock_writable_journal(journal):
        state = operation_journal.load_writable_journal_state(journal)
        if state.active is not None and state.active.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            operation_journal.complete_journal_terminal(journal, boot_id=boot_id)
            state = operation_journal.load_writable_journal_state(journal)
        if state.active is None:
            return operation_journal.retained_journal_operation(journal, operation_id)
        # Sync Phase 9: this target is no longer restricted to update/refresh
        # -- watch-operation/ack-operation must also reach a regional or
        # delegated active/terminal operation. cancel_journal_operation below
        # keeps its own separate update/refresh-only restriction; only that
        # family is cancelable.
        if state.active.operation_id != operation_id:
            raise operation_journal.JournalAdmissionError("journal control target is unavailable")
        return state.active


class NativeJournalEvents:
    """One inode watch, retained before recovery; notifications are hints only."""

    # IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_DELETE_SELF | IN_MOVE_SELF.
    mask = 0x0002 | 0x0004 | 0x0008 | 0x0400 | 0x0800

    def __init__(self, journal: operation_journal.JournalDescriptorSet) -> None:
        self.journal = journal
        self.descriptor = None
        self.selector = None

    def __enter__(self):
        try:
            self.journal.validate()
            libc = ctypes.CDLL(None, use_errno=True)
            libc.inotify_init1.argtypes = [ctypes.c_int]
            libc.inotify_init1.restype = ctypes.c_int
            libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
            libc.inotify_add_watch.restype = ctypes.c_int
            descriptor = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
            if descriptor < 0:
                raise OSError(ctypes.get_errno(), "native journal event setup failed")
            self.descriptor = descriptor
            path = f"/proc/self/fd/{self.journal.descriptor('active')}".encode("ascii")
            self.watch = libc.inotify_add_watch(descriptor, path, self.mask)
            if self.watch < 0:
                raise OSError(ctypes.get_errno(), "native journal inode watch failed")
            self.selector = selectors.DefaultSelector()
            self.selector.register(descriptor, selectors.EVENT_READ)
            self.journal.validate()
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_args):
        try:
            if self.selector is not None:
                self.selector.close()
        finally:
            if self.descriptor is not None:
                descriptor, self.descriptor = self.descriptor, None
                os.close(descriptor)  # Also frees the instance's inode watch.

    def wait(self, deadline: float) -> None:
        while time.monotonic() < deadline:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                continue
            try:
                data = os.read(self.descriptor, 65536)
            except BlockingIOError:
                continue
            # A file-only watch has fixed 16-byte events and no filename.
            # Overflow, unmount, lost watches, and malformed events fail closed.
            if not data or len(data) % 16:
                raise shared.SnapshotFailure("interrupted", "Native journal notifications are incomplete")
            for offset in range(0, len(data), 16):
                watch, mask, cookie, length = struct.unpack_from("=iIII", data, offset)
                if watch != self.watch or not mask or mask & ~self.mask or cookie or length:
                    raise shared.SnapshotFailure("interrupted", "Native journal monitoring was lost")
            return  # Coalesce one bounded batch into one validated recovery read.


def watch_native_journal_operation(
    journal: operation_journal.JournalDescriptorSet, original: operation_journal.JournalOperation,
    write: Callable[[str], object], *, boot_id: str,
) -> None:
    """Observe durable native checkpoints, never the service or its target value."""
    deadline = time.monotonic() + NATIVE_WATCH_SECONDS
    identity = ("operation_id", "action_id", "started_at", "kind", "generation",
                "transaction_path", "boot_id", "slot")
    with NativeJournalEvents(journal) as events:
        stream = update_plans.OperationStream(original.operation_id, original.action_id,
                                 original.started_at, original.detail, write)
        while True:
            # Also run after the deadline: Linux can notify close before freeing
            # flock. A final fresh probe bounds recovery of that last-event race.
            state, _evidence, failure = update_plans.recover_journal_active(journal, None,
                boot_id=boot_id, expected_operation=original)
            if failure is not None:
                raise failure
            current = state.active
            if current is None:
                current = next((item for item in state.terminals
                    if item is not None and item.operation_id == original.operation_id), None)
            if current is None or any(getattr(current, key) != getattr(original, key) for key in identity):
                raise operation_journal.JournalAdmissionError("native journal watch owner changed")
            if current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
                if current.state == "succeeded" and stream.state in {"pending", "authorizing"}:
                    stream.transition("running", current.detail)
                elif current.state == "permission-denied" and stream.state == "pending":
                    stream.transition("authorizing", current.detail)
                elif current.state == "canceled" and stream.state == "running":
                    stream.transition("cancel-requested", current.detail)
                stream.finish(current)
                return
            if current.state == "cancel-requested" and stream.state in {"pending", "authorizing"}:
                stream.transition("running", current.detail)
            if current.state != stream.state:
                stream.transition(current.state, current.detail)
            else:
                stream.progress(current.detail)
            if time.monotonic() >= deadline:
                raise shared.SnapshotFailure("timeout", "Native owner remains active; refresh and observe its result")
            events.wait(deadline)


def watch_journal_operation(
    journal: operation_journal.JournalDescriptorSet, operation_id: str, write: Callable[[str], object], *,
    boot_id: str, backend_factory: Callable[[], packagekit.PackageKitBackend] = packagekit.PackageKitBackend,
) -> None:
    """Replay a retained result or observe one exact live owner without reinvocation."""
    original = control_journal_target(journal, operation_id, boot_id)
    if original.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
        update_plans.replay_terminal_operation(original, write)
        return
    if original.kind not in {"update", "refresh"}:
        # A native operation has no separate PackageKit-style transaction to
        # attach to. watch_native_journal_operation()'s own recover_journal_active()
        # call handles the no-live-owner case: an abandoned/stranded operation
        # is terminalized as "interrupted" on its first recovery pass and that
        # transition is streamed like any other, never rejected upfront.
        watch_native_journal_operation(journal, original, write, boot_id=boot_id)
        return
    detail = "Observing recovered PackageKit operation; package comparison is unavailable"
    stream = update_plans.OperationStream(original.operation_id, original.action_id, original.started_at, detail, write)

    def progress(evidence):
        with operation_journal.lock_writable_journal(journal):
            current = operation_journal.load_writable_journal_state(journal).active
            identity = ("operation_id", "action_id", "started_at", "kind", "generation", "transaction_path", "boot_id", "slot")
            if current is None or any(getattr(current, key) != getattr(original, key) for key in identity) or current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
                raise operation_journal.JournalAdmissionError("journal watch owner changed")
            if current.state == "pending" and evidence.status == 31:
                current = operation_journal.advance_journal_operation(journal, current, replace(current, state="authorizing", detail=detail))
        target = current.state
        if target in {"running", "cancel-requested"} and stream.state in {"pending", "authorizing"}:
            stream.transition("running", detail)
        if target != stream.state:
            stream.transition(target, detail, percent=evidence.percent, cancelable=evidence.allow_cancel)
        else:
            stream.progress(detail, percent=evidence.percent, cancelable=evidence.allow_cancel)

    progress(update_plans.RecoveryEvidence(True))
    backend = backend_factory()
    state, evidence, failure = update_plans.recover_journal_active(journal, backend, boot_id=boot_id,
        session_reader=backend.session_started, watch=True, expected_operation_id=operation_id, on_progress=progress)
    if state.active is not None:
        raise failure or shared.SnapshotFailure("interrupted", "PackageKit observation ended without terminal evidence")
    terminal = next((item for item in state.terminals if item is not None and item.operation_id == operation_id), None)
    if terminal is None:
        raise operation_journal.JournalAdmissionError("journal watch result is unavailable")
    if terminal.state == "succeeded" and stream.state in {"pending", "authorizing"}:
        stream.transition("running", detail)
    elif terminal.state == "permission-denied" and stream.state == "pending":
        stream.transition("authorizing", detail)
    elif terminal.state == "canceled" and stream.state == "running":
        stream.transition("cancel-requested", detail)
    stream.finish(terminal, detail=shared.clean_text(f"{terminal.detail}; recovered package comparison is unavailable")
                  if terminal.kind == "update" else terminal.detail)


def cancel_journal_operation(journal: operation_journal.JournalDescriptorSet, operation_id: str, *, boot_id: str,
                             on_dispatch: Callable[[], object],
                             backend_factory: Callable[[], packagekit.PackageKitBackend] = packagekit.PackageKitBackend) -> None:
    """Cancel only one active identity, leaving completion to its observer."""
    identity = ("operation_id", "action_id", "started_at", "kind", "generation", "transaction_path", "boot_id", "slot")
    with operation_journal.lock_writable_journal(journal):
        original = operation_journal.load_writable_journal_state(journal).active
        if (original is None or original.operation_id != operation_id or original.kind not in {"refresh", "update"}
                or original.state in shared.JOURNAL_OPERATION_TERMINAL_STATES
                or (original.kind == "update" and original.boot_id != boot_id)):
            raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")

    def before_send():
        with operation_journal.lock_writable_journal(journal):
            current = operation_journal.load_writable_journal_state(journal).active
            if (current is None or current.state in shared.JOURNAL_OPERATION_TERMINAL_STATES
                    or any(getattr(current, key) != getattr(original, key) for key in identity)):
                raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")

    backend_factory().cancel_operation(original, before_send, on_dispatch)
    with operation_journal.lock_writable_journal(journal):
        current = operation_journal.load_writable_journal_state(journal).active
        if (current is not None and current.state == "running"
                and all(getattr(current, key) == getattr(original, key) for key in identity)):
            operation_journal.advance_journal_operation(journal, current, replace(current, state="cancel-requested",
                detail="Cancellation requested; waiting for PackageKit completion"))
