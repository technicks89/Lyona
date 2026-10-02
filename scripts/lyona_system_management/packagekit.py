"""The PackageKit backend."""

from __future__ import annotations

import os
import re
import signal
import time
from typing import Callable, Sequence

from . import native_operations, operation_journal, shared, update_plans


READ_DEADLINE_SECONDS = 120
REFRESH_AGE_DEADLINE_SECONDS = 10
CANCEL_GRACE_SECONDS = 5

PACKAGEKIT_STATUS_PHASE = {8: "downloading", 9: "installing", 10: "updating",
                          6: "removing", 11: "cleaning", 12: "removing"}

ROLE_REFRESH_CACHE = 13


class PackageKitBackend:
    """Small direct D-Bus client with transaction-wide monotonic deadlines."""

    def __init__(self) -> None:
        try:
            import gi

            gi.require_version("Gio", "2.0")
            gi.require_version("PackageKitGlib", "1.0")
            from gi.repository import Gio, GLib, PackageKitGlib
        except (ImportError, ValueError) as error:
            raise shared.SnapshotFailure(
                "missing-provider",
                "System Python GObject bindings are unavailable",
                "unavailable",
            ) from error
        self.Gio = Gio
        self.GLib = GLib
        # PackageKit's D-Bus arguments are bitfields, not raw enum values. Let
        # the installed API perform the stable enum-to-bitfield conversion.
        self.filter_none = PackageKitGlib.filter_bitfield_from_string("none")
        self.flags_simulate_only_trusted = (
            PackageKitGlib.transaction_flag_bitfield_from_string(
                "simulate;only-trusted"
            )
        )
        self.flags_only_trusted = PackageKitGlib.transaction_flag_bitfield_from_string("only-trusted")
        try:
            self.connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        except GLib.Error as error:
            raise self._dbus_failure(error) from error

    def _timeout_ms(self, deadline: float) -> int:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise shared.SnapshotFailure(
                "timeout", "PackageKit request timed out", "unavailable"
            )
        return max(1, min(int(remaining * 1000), 2_147_483_647))

    def _call(
        self,
        path: str,
        interface: str,
        method: str,
        parameters: object,
        deadline: float,
    ) -> object:
        try:
            return self.connection.call_sync(
                shared.PACKAGEKIT_NAME,
                path,
                interface,
                method,
                parameters,
                None,
                self.Gio.DBusCallFlags.NONE,
                self._timeout_ms(deadline),
                None,
            )
        except self.GLib.Error as error:
            if time.monotonic() >= deadline:
                raise shared.SnapshotFailure(
                    "timeout", "PackageKit request timed out", "unavailable"
                ) from error
            raise self._dbus_failure(error) from error

    def _dbus_failure(self, error: Exception) -> shared.SnapshotFailure:
        name = self.Gio.dbus_error_get_remote_error(error)
        if name in {"org.freedesktop.DBus.Error.ServiceUnknown",
                    "org.freedesktop.DBus.Error.NameHasNoOwner",
                    "org.freedesktop.DBus.Error.UnknownObject"}:
            return shared.SnapshotFailure(
                "missing-provider", "PackageKit service is unavailable", "unavailable"
            )
        if name in {"org.freedesktop.DBus.Error.AccessDenied",
                    "org.freedesktop.DBus.Error.AuthFailed",
                    "org.freedesktop.PackageKit.Transaction.RefusedByPolicy"}:
            return shared.SnapshotFailure(
                "permission-denied",
                "PackageKit denied the request",
                "restricted",
            )
        if name in {"org.freedesktop.DBus.Error.UnknownMethod",
                    "org.freedesktop.DBus.Error.UnknownInterface"}:
            return shared.SnapshotFailure(
                "unsupported",
                "PackageKit does not support the required method",
                "unsupported",
            )
        if name in {"org.freedesktop.DBus.Error.InvalidArgs",
                    "org.freedesktop.DBus.Error.InvalidSignature"}:
            return shared.SnapshotFailure("malformed", "PackageKit rejected the method arguments")
        if name in {"org.freedesktop.DBus.Error.Timeout",
                    "org.freedesktop.DBus.Error.TimedOut",
                    "org.freedesktop.DBus.Error.NoReply"} or (
                name is None and callable(getattr(error, "matches", None))
                and error.matches(self.Gio.io_error_quark(), self.Gio.IOErrorEnum.TIMED_OUT)):
            return shared.SnapshotFailure(
                "timeout", "PackageKit request timed out", "unavailable"
            )
        return shared.SnapshotFailure(
            "internal", "PackageKit D-Bus request failed", "unavailable"
        )

    def session_started(self) -> int:
        """Read session evidence, including user-service launches, within one deadline."""
        deadline = time.monotonic() + 10

        def call(path: str, interface: str, method: str, parameters: object, signature: str,
                 allow_no_session: bool = False) -> object:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise shared.SnapshotFailure("timeout", "Current logind session read timed out; restart guidance is retained", "unavailable")
            try:
                reply = self.connection.call_sync(
                    "org.freedesktop.login1", path, interface, method, parameters,
                    None, self.Gio.DBusCallFlags.NONE,
                    max(1, min(int(remaining * 1000), 10000)), None)
            except self.GLib.Error as error:
                name = self.Gio.dbus_error_get_remote_error(error)
                if allow_no_session and name == "org.freedesktop.login1.NoSessionForPID" and time.monotonic() < deadline:
                    return None
                if time.monotonic() >= deadline or name in {"org.freedesktop.DBus.Error.Timeout", "org.freedesktop.DBus.Error.TimedOut", "org.freedesktop.DBus.Error.NoReply"}:
                    raise shared.SnapshotFailure("timeout", "Current logind session read timed out; restart guidance is retained", "unavailable") from error
                if name == "org.freedesktop.DBus.Error.AccessDenied":
                    raise shared.SnapshotFailure("permission-denied", "Current logind session read was denied; restart guidance is retained", "restricted") from error
                code = {
                    "org.freedesktop.DBus.Error.ServiceUnknown": "missing-provider",
                    "org.freedesktop.DBus.Error.NameHasNoOwner": "missing-provider",
                    "org.freedesktop.DBus.Error.UnknownObject": "missing-provider",
                    "org.freedesktop.login1.NoSessionForPID": "missing-provider",
                    "org.freedesktop.DBus.Error.InvalidArgs": "malformed",
                }.get(name, "internal")
                raise shared.SnapshotFailure(code, "Current logind session is unavailable; restart guidance is retained", "unavailable") from error
            if time.monotonic() >= deadline:
                raise shared.SnapshotFailure("timeout", "Current logind session read timed out; restart guidance is retained", "unavailable")
            if reply.get_type_string() != signature:
                raise shared.SnapshotFailure("malformed", "Current logind session reply is malformed")
            return reply

        def display_session(user_path: str) -> tuple[str, str]:
            reply = call(user_path, shared.PROPERTIES_INTERFACE, "Get",
                         self.GLib.Variant("(ss)", ("org.freedesktop.login1.User", "Display")), "(v)")
            value = reply.get_child_value(0).get_variant()
            if value.get_type_string() != "(so)":
                raise shared.SnapshotFailure("malformed", "Logind display session reply is malformed")
            identity = value.unpack()
            if (not isinstance(identity, (tuple, list)) or len(identity) != 2
                    or not isinstance(identity[0], str) or not identity[0] or len(identity[0]) > 256):
                raise shared.SnapshotFailure("missing-provider", "No primary graphical session is available; restart guidance is retained", "unavailable")
            return tuple(identity)

        reply = call("/org/freedesktop/login1", "org.freedesktop.login1.Manager", "GetSessionByPID",
                     self.GLib.Variant("(u)", (os.getpid(),)), "(o)", allow_no_session=True)
        user_path = None
        display_identity = None
        if reply is None:
            # A managed shell launched by systemd --user is outside session scopes.
            # Use logind's primary display, never an environment-supplied session ID.
            reply = call("/org/freedesktop/login1", "org.freedesktop.login1.Manager", "GetUser",
                         self.GLib.Variant("(u)", (os.getuid(),)), "(o)")
            user_path = reply.unpack()[0]
            if not isinstance(user_path, str) or re.fullmatch(r"/org/freedesktop/login1/user/[A-Za-z0-9_]{1,128}", user_path) is None:
                raise shared.SnapshotFailure("malformed", "Current logind user path is malformed")
            display_identity = display_session(user_path)
            path = display_identity[1]
        else:
            path = reply.unpack()[0]
        if not isinstance(path, str) or len(path) > 256 or re.fullmatch(r"/org/freedesktop/login1/session/[A-Za-z0-9_]+", path) is None:
            raise shared.SnapshotFailure("malformed", "Current logind session path is malformed")
        if user_path is not None:
            reply = call(path, shared.PROPERTIES_INTERFACE, "GetAll",
                         self.GLib.Variant("(s)", ("org.freedesktop.login1.Session",)), "(a{sv})")
            state = reply.unpack()[0]
            owner = state.get("User") if isinstance(state, dict) else None
            if (not isinstance(owner, (tuple, list)) or len(owner) != 2
                    or type(owner[0]) is not int or owner[0] != os.getuid() or owner[1] != user_path
                    or state.get("Id") != display_identity[0] or state.get("Type") != "x11"
                    or state.get("Class") != "user" or state.get("State") != "active"
                    or state.get("Active") is not True or state.get("Remote") is not False):
                raise shared.SnapshotFailure("missing-provider", "Primary display is not an active local X11 session for this user; restart guidance is retained", "unavailable")
        reply = call(path, shared.PROPERTIES_INTERFACE, "Get",
                     self.GLib.Variant("(ss)", ("org.freedesktop.login1.Session", "TimestampMonotonic")), "(v)")
        value = reply.get_child_value(0).get_variant()
        if value.get_type_string() != "t":
            raise shared.SnapshotFailure("malformed", "Current logind session timestamp is not unsigned 64-bit")
        timestamp = value.unpack()
        if type(timestamp) is not int or not 0 <= timestamp <= shared.JOURNAL_SEQUENCE_MAX:
            raise shared.SnapshotFailure("malformed", "Current logind session timestamp is malformed")
        if user_path is not None and display_session(user_path) != display_identity:
            raise shared.SnapshotFailure("missing-provider", "Primary display session changed during discovery; restart guidance is retained", "unavailable")
        return timestamp

    def last_refresh_age(self) -> int:
        deadline = time.monotonic() + REFRESH_AGE_DEADLINE_SECONDS
        reply = self._call(
            shared.PACKAGEKIT_PATH,
            shared.PACKAGEKIT_INTERFACE,
            "GetTimeSinceAction",
            self.GLib.Variant("(u)", (ROLE_REFRESH_CACHE,)),
            deadline,
        )
        values = reply.unpack()
        if len(values) != 1 or not isinstance(values[0], int):
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned a malformed refresh age"
            )
        return values[0]

    def require_mutation_safe(self) -> None:
        """Keep discovery readable while rejecting an unknown or vulnerable daemon.

        Arch has no RPM database and no distribution backport to
        disambiguate (92ec6e2:docs/SYNC-P2-UPDATE-SNAPSHOT.md#3b-the-rpm-version-gate).
        The running daemon's own D-Bus version properties are the whole gate;
        Arch ships PackageKit 1.3.6 in `extra`, above the floor.
        """
        try:
            values = self._call(shared.PACKAGEKIT_PATH, shared.PROPERTIES_INTERFACE, "GetAll",
                self.GLib.Variant("(s)", (shared.PACKAGEKIT_INTERFACE,)), time.monotonic() + 10).unpack()
            if len(values) != 1 or not isinstance(values[0], dict):
                raise ValueError
            properties = values[0]
            version = tuple(properties.get(key) for key in ("VersionMajor", "VersionMinor", "VersionMicro"))
            if not all(type(value) is int for value in version) or version < (1, 3, 5):
                raise ValueError
        except (OSError, ValueError, TypeError, KeyError) as error:
            raise shared.SnapshotFailure("unsupported", "PackageKit 1.3.5 or newer is required", "unsupported") from error

    def create_mutation(self) -> str:
        """Create and configure an empty transaction, without invoking package work."""
        deadline = time.monotonic() + 10
        result = self._call(shared.PACKAGEKIT_PATH, shared.PACKAGEKIT_INTERFACE, "CreateTransaction", None, deadline).unpack()
        if len(result) != 1 or not isinstance(result[0], str) or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(result[0]) is None:
            raise shared.SnapshotFailure("malformed", "PackageKit returned an invalid operation path")
        path = result[0]
        self._call(path, shared.TRANSACTION_INTERFACE, "SetHints",
                   self.GLib.Variant("(as)", (["background=false", "interactive=true"],)), deadline)
        return path

    def _recovery_call(self, path: str, interface: str, method: str,
                       parameters: object, deadline: float, signature: str, *,
                       destination: str = shared.PACKAGEKIT_NAME) -> object:
        """Dispatch signals in order during a bounded request; validate its reply locally.

        Local signature validation keeps a wrong reply type classified as
        malformed instead of a GIO-generated transport or argument error.
        """
        wait_ms = self._timeout_ms(deadline)
        loop = self.GLib.MainLoop()
        request = self.Gio.Cancellable()
        live = True
        reply = None
        failure = None
        source = 0

        def completed(connection, result, _data):
            nonlocal reply, failure
            if not live:
                return
            try:
                reply = connection.call_finish(result)
            except self.GLib.Error as error:
                failure = error
            loop.quit()

        def expired():
            nonlocal source
            source = 0
            loop.quit()
            return self.GLib.SOURCE_REMOVE

        try:
            source = self.GLib.timeout_add(wait_ms, expired)
            self.connection.call(destination, path, interface, method, parameters,
                None, self.Gio.DBusCallFlags.NONE,
                wait_ms, request, completed, None)
            if reply is None and failure is None and source:
                loop.run()
        finally:
            live = False
            request.cancel()
            if source:
                self.GLib.source_remove(source)
        if time.monotonic() >= deadline or (reply is None and failure is None):
            raise shared.SnapshotFailure("timeout", "PackageKit recovery lookup timed out")
        if failure is not None:
            raise self._dbus_failure(failure) from failure
        if reply.get_type_string() != signature:
            raise shared.SnapshotFailure("malformed", "PackageKit recovery reply is malformed")
        return reply

    def cancel_operation(self, operation: operation_journal.JournalOperation, before_send: Callable[[], object],
                         on_dispatch: Callable[[], object]) -> None:
        """Request cancellation from one pinned peer; never infer its final result."""
        operation_journal.encode_journal_operation(operation)
        if operation.kind not in {"refresh", "update"} or operation.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")
        deadline = time.monotonic() + 10
        reply = self._recovery_call("/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner",
            self.GLib.Variant("(s)", (shared.PACKAGEKIT_NAME,)), deadline, "(s)", destination="org.freedesktop.DBus")
        peer = reply.unpack()[0]
        if not isinstance(peer, str) or re.fullmatch(r":[0-9]+\.[0-9]+", peer) is None:
            raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")
        fields = ("Role", "Uid", "Status", "AllowCancel")
        observed = {}
        pending = {}
        snapshot_applied = False
        blocked = False
        live = True
        subscriptions = []

        def changed(_connection, _sender, _path, interface, member, variant, _data):
            nonlocal blocked
            if not live:
                return
            try:
                if interface == "org.freedesktop.DBus":
                    blocked = blocked or variant.get_type_string() != "(sss)" or variant.unpack()[1] != variant.unpack()[2]
                elif interface == shared.TRANSACTION_INTERFACE:
                    if member in {"Finished", "Destroy"}:
                        blocked = True
                elif interface == shared.PROPERTIES_INTERFACE:
                    if variant.get_type_string() != "(sa{sv}as)":
                        raise ValueError
                    owner, values, invalidated = variant.unpack()
                    if owner != shared.TRANSACTION_INTERFACE or not isinstance(values, dict):
                        raise ValueError
                    target = observed if snapshot_applied else pending
                    for key in fields:
                        if key in invalidated:
                            target[key] = None
                        elif key in values:
                            target[key] = values[key] if type(values[key]) in {int, bool} else None
            except (TypeError, ValueError, IndexError):
                blocked = True

        def require_available():
            expected_role = 13 if operation.kind == "refresh" else 22
            if (blocked or type(observed.get("Role")) is not int or observed["Role"] != expected_role
                    or type(observed.get("Uid")) is not int or observed["Uid"] != os.getuid()
                    or type(observed.get("Status")) is not int or not 0 <= observed["Status"] <= 36
                    or observed["Status"] == 18 or observed.get("AllowCancel") is not True):
                raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")

        try:
            subscriptions.append(self.connection.signal_subscribe(peer, shared.TRANSACTION_INTERFACE, None,
                operation.transaction_path, None, self.Gio.DBusSignalFlags.NONE, changed, None))
            subscriptions.append(self.connection.signal_subscribe(peer, shared.PROPERTIES_INTERFACE, "PropertiesChanged",
                operation.transaction_path, shared.TRANSACTION_INTERFACE, self.Gio.DBusSignalFlags.NONE, changed, None))
            subscriptions.append(self.connection.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus",
                "NameOwnerChanged", "/org/freedesktop/DBus", shared.PACKAGEKIT_NAME, self.Gio.DBusSignalFlags.NONE, changed, None))
            values = self._recovery_call(operation.transaction_path, shared.PROPERTIES_INTERFACE, "GetAll",
                self.GLib.Variant("(s)", (shared.TRANSACTION_INTERFACE,)), deadline, "(a{sv})", destination=peer).unpack()[0]
            if not isinstance(values, dict):
                raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")
            observed.update({key: values.get(key) if type(values.get(key)) in {int, bool} else None for key in fields})
            observed.update(pending)
            pending.clear()
            snapshot_applied = True
            require_available()
            before_send()  # Revalidate journal ownership without holding a lock across D-Bus.
            # Dispatch queued property revocations after the bounded journal lock.
            # A noisy peer cannot turn this finite control into an unbounded watcher.
            context = self.GLib.MainContext.default()
            for _ in range(64):
                if not context.pending():
                    break
                context.iteration(False)
            else:
                raise operation_journal.CancelTargetUnavailable("cancel target is unavailable")
            require_available()
            self._timeout_ms(deadline)
            on_dispatch()
            try:
                self._recovery_call(operation.transaction_path, shared.TRANSACTION_INTERFACE, "Cancel",
                    None, deadline, "()", destination=peer)
            except shared.SnapshotFailure as failure:
                cause = failure.__cause__
                if isinstance(cause, self.GLib.Error) and self.Gio.dbus_error_get_remote_error(cause) in {
                        shared.TRANSACTION_INTERFACE + ".NotRunning", shared.TRANSACTION_INTERFACE + ".NoRole",
                        shared.TRANSACTION_INTERFACE + ".CannotCancel", shared.TRANSACTION_INTERFACE + ".NoSuchTransaction",
                        "org.freedesktop.DBus.Error.UnknownObject"}:
                    raise operation_journal.CancelTargetUnavailable("cancel target is unavailable") from failure
                raise
        finally:
            live = False
            for subscription in subscriptions:
                self.connection.signal_unsubscribe(subscription)

    def probe_operation(self, operation: operation_journal.JournalOperation, *,
                        on_restart: Callable[[int], object] | None = None,
                        on_running: Callable[[], object] | None = None,
                        watch: bool = False,
                        on_progress: Callable[[update_plans.RecoveryEvidence], object] | None = None) -> update_plans.RecoveryEvidence:
        """Bound adoption; optionally keep its verified subscriptions until completion."""
        operation_journal.encode_journal_operation(operation)
        if operation.kind not in {"refresh", "update"} or operation.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            raise shared.SnapshotFailure("malformed", "PackageKit recovery target is not active")
        path = operation.transaction_path
        deadline = time.monotonic() + 10
        live = True
        present = False
        destroyed = False
        listed = ()
        status = 0
        allow_cancel = False
        percent = None
        saw_running = False
        uncertain_status = False
        cancel_blocked = False
        terminal_state = None
        terminal_time = None
        transaction_failure = None
        malformed = None
        checkpoint_failure = None
        restarts = set()
        subscriptions = []
        identity_verified = None
        snapshot_applied = False
        pending_properties = {}
        watch_loop = None
        connection_closed = None

        def evidence(*, progress=False):
            # A current display phase is not proof that earlier execution was
            # excluded. Preserve uncertainty in terminal recovery evidence.
            observed_status = status if progress else 3 if saw_running else 0 if uncertain_status else status
            return update_plans.RecoveryEvidence(not destroyed and (present or path in listed), terminal_state, transaction_failure,
                tuple(sorted(restarts)), observed_status,
                allow_cancel and not cancel_blocked and not destroyed, percent, terminal_time)

        def watch_changed():
            if watch_loop is None:
                return
            if terminal_state is not None or destroyed or malformed is not None or checkpoint_failure is not None:
                watch_loop.quit()
            elif identity_verified is True:
                checkpoint(on_progress, evidence(progress=True))
                if checkpoint_failure is not None:
                    watch_loop.quit()

        def checkpoint(callback, *args):
            nonlocal checkpoint_failure
            if callback is not None and checkpoint_failure is None:
                try:
                    callback(*args)
                except Exception as error:
                    checkpoint_failure = error

        def properties(values):
            nonlocal status, allow_cancel, percent, saw_running, uncertain_status, cancel_blocked, checkpoint_failure
            if not isinstance(values, dict):
                raise ValueError
            if "Status" in values:
                value = values["Status"]
                status = value if type(value) is int and 0 <= value <= 36 else 0
                uncertain_status = uncertain_status or status == 0
                if not saw_running and status not in {0, 1, 2, 18, 31}:
                    saw_running = True
                    if identity_verified is True:
                        checkpoint(on_running)
            if "AllowCancel" in values:
                allow_cancel = values["AllowCancel"] if type(values["AllowCancel"]) is bool else False
                cancel_blocked = False if watch and snapshot_applied else cancel_blocked or not allow_cancel
            if "Percentage" in values:
                value = values["Percentage"]
                percent = value if type(value) is int and 0 <= value <= 100 else None

        def signal_received(_connection, _sender, _path, interface, signal, variant, _data):
            nonlocal terminal_state, terminal_time, transaction_failure, malformed, present, destroyed, checkpoint_failure
            if not live or identity_verified is False or malformed is not None or checkpoint_failure is not None or time.monotonic() >= deadline:
                return
            if interface != shared.PROPERTIES_INTERFACE and signal not in {"RequireRestart", "ErrorCode", "Finished", "Destroy"}:
                return
            if terminal_state is not None:
                if signal == "Finished":
                    malformed = shared.SnapshotFailure("malformed", "PackageKit recovery completion is duplicated")
                return
            previous = evidence(progress=True)
            try:
                values = variant.unpack()
                if interface == shared.PROPERTIES_INTERFACE:
                    if variant.get_type_string() != "(sa{sv}as)" or values[0] != shared.TRANSACTION_INTERFACE:
                        raise ValueError
                    changed = dict(values[1])
                    for key in values[2]:
                        changed[key] = None
                    if not snapshot_applied:
                        # Coalesce only three fields; never retain package or
                        # arbitrary property payloads while identity is pending.
                        for key in ("Status", "AllowCancel", "Percentage"):
                            if key in changed:
                                value = changed[key]
                                pending_properties[key] = value if type(value) is (bool if key == "AllowCancel" else int) else None
                    properties(changed)
                elif signal == "RequireRestart":
                    if variant.get_type_string() != "(us)":
                        raise ValueError
                    value = values[0] if values[0] in {1, 2, 3, 4, 5, 6} else 0
                    if value in restarts:
                        return
                    if identity_verified is True:
                        checkpoint(on_restart, value)
                        if checkpoint_failure is not None:
                            return
                    restarts.add(value)
                elif signal == "ErrorCode":
                    if variant.get_type_string() != "(us)":
                        raise ValueError
                    transaction_failure = transaction_failure or self._transaction_failure(values[0], "")
                elif signal == "Finished":
                    if variant.get_type_string() != "(uu)" or terminal_state is not None:
                        raise ValueError
                    terminal_time = time.monotonic_ns() // 1000
                    if transaction_failure is not None:
                        terminal_state = {"permission-denied": "permission-denied", "canceled": "canceled"}.get(transaction_failure.code, "failed")
                    elif values[0] == shared.EXIT_SUCCESS:
                        terminal_state = "succeeded"
                    elif values[0] == 3:
                        terminal_state = "canceled"
                        transaction_failure = shared.SnapshotFailure("canceled", "PackageKit canceled the transaction")
                    else:
                        terminal_state = "failed"
                        transaction_failure = shared.SnapshotFailure("internal", "PackageKit transaction did not succeed")
                elif signal == "Destroy":
                    if variant.get_type_string() != "()":
                        raise ValueError
                    destroyed = True
                    present = False
            except (TypeError, ValueError, IndexError):
                malformed = shared.SnapshotFailure("malformed", "PackageKit recovery signal is malformed")
            finally:
                if malformed is not None or checkpoint_failure is not None or evidence(progress=True) != previous:
                    watch_changed()

        def service_changed(_connection, _sender, _path, _interface, _signal, variant, _data):
            nonlocal malformed
            if live and variant.get_type_string() == "(sss)":
                values = variant.unpack()
                if values[0] == shared.PACKAGEKIT_NAME and values[1] != values[2]:
                    malformed = shared.SnapshotFailure("missing-provider", "PackageKit changed during recovery; retry the lookup")
                    watch_changed()

        def bus_closed(*_args):
            nonlocal malformed
            if live:
                malformed = shared.SnapshotFailure("missing-provider", "PackageKit connection closed; retry recovery")
                watch_changed()

        try:
            if watch:
                connection_closed = self.connection.connect("closed", bus_closed)
            subscriptions.append(self.connection.signal_subscribe(shared.PACKAGEKIT_NAME, shared.TRANSACTION_INTERFACE, None, path, None, self.Gio.DBusSignalFlags.NONE, signal_received, None))
            subscriptions.append(self.connection.signal_subscribe(shared.PACKAGEKIT_NAME, shared.PROPERTIES_INTERFACE, "PropertiesChanged", path, shared.TRANSACTION_INTERFACE, self.Gio.DBusSignalFlags.NONE, signal_received, None))
            subscriptions.append(self.connection.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus", shared.PACKAGEKIT_NAME, self.Gio.DBusSignalFlags.NONE, service_changed, None))
            try:
                reply = self._recovery_call(path, shared.PROPERTIES_INTERFACE, "GetAll",
                    self.GLib.Variant("(s)", (shared.TRANSACTION_INTERFACE,)), deadline, "(a{sv})")
            except shared.SnapshotFailure as failure:
                cause = failure.__cause__
                if not isinstance(cause, self.GLib.Error) or self.Gio.dbus_error_get_remote_error(cause) not in {
                        "org.freedesktop.DBus.Error.UnknownObject", "org.freedesktop.DBus.Error.UnknownMethod"}:
                    raise
                # No object identity was established. Discard buffered signals
                # and ignore later ones; only the bounded list/history may help.
                identity_verified = False
                restarts.clear()
                destroyed = False
                saw_running = False
                status, allow_cancel, percent = 0, False, None
                terminal_state, terminal_time, transaction_failure = None, None, None
            else:
                values = reply.unpack()[0]
                role, uid = values.get("Role"), values.get("Uid")
                expected_role = 13 if operation.kind == "refresh" else 22
                allowed_roles = {expected_role, 0} if operation.state in {"pending", "authorizing"} else {expected_role}
                if type(role) is not int or role not in allowed_roles or type(uid) is not int or uid != os.getuid():
                    raise shared.SnapshotFailure("malformed", "PackageKit active object does not match the recorded operation")
                if malformed is not None:
                    raise malformed
                # Before this point callbacks collect only a fixed-size status
                # tuple and at most seven restart enums, never journal writes.
                identity_verified = True
                if saw_running:
                    checkpoint(on_running)
                for value in sorted(restarts):
                    checkpoint(on_restart, value)
                properties({"Status": None, **values})
                snapshot_applied = True
                properties(pending_properties)
                pending_properties.clear()
                present = not destroyed and status != 18
                if watch:
                    checkpoint(on_progress, evidence(progress=True))
            if checkpoint_failure is not None:
                raise checkpoint_failure
            if terminal_state is None:
                try:
                    reply = self._recovery_call(shared.PACKAGEKIT_PATH, shared.PACKAGEKIT_INTERFACE, "GetTransactionList", None, deadline, "(ao)")
                    if terminal_state is None:
                        listed = update_plans.validate_transaction_list(reply.unpack()[0])
                except shared.SnapshotFailure:
                    # Finished may arrive while the secondary request is in
                    # flight. Its exact result does not depend on that lookup.
                    if terminal_state is None:
                        raise
            if malformed is not None:
                raise malformed
            if watch and terminal_state is None and evidence().present:
                if identity_verified is not True:
                    raise shared.SnapshotFailure("interrupted", "Active PackageKit object could not be verified; retry recovery")
                # Only attachment has a deadline. A verified live transaction
                # has no silence watchdog, polling timer, or reinvocation.
                deadline = float("inf")
                watch_loop = self.GLib.MainLoop()
                watch_changed()
                if checkpoint_failure is None:
                    watch_loop.run()
                if malformed is not None:
                    raise malformed
                if terminal_state is None and not destroyed and checkpoint_failure is None:
                    raise shared.SnapshotFailure("interrupted", "PackageKit watch ended without terminal evidence")
            return evidence()
        finally:
            live = False
            for subscription in subscriptions:
                self.connection.signal_unsubscribe(subscription)
            if connection_closed is not None:
                self.connection.disconnect(connection_closed)
            if checkpoint_failure is not None:
                raise checkpoint_failure

    def operation_history(self) -> tuple[tuple[str, bool, int, int], ...]:
        """Collect no more than 64 old transactions under an independent deadline."""
        deadline = time.monotonic() + 10
        reply = self._recovery_call(shared.PACKAGEKIT_PATH, shared.PACKAGEKIT_INTERFACE, "CreateTransaction", None, deadline, "(o)")
        path = reply.unpack()[0]
        if not isinstance(path, str) or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path) is None:
            raise shared.SnapshotFailure("malformed", "PackageKit returned an invalid history transaction")
        loop = self.GLib.MainLoop()
        records = []
        finished = None
        failure = None
        live = True
        discarding = False
        source = 0

        def signal_received(_connection, _sender, _path, _interface, signal, variant, _data):
            nonlocal finished, failure
            if not live:
                return
            if discarding:
                # Grace consumes only stop-observing evidence, never a late
                # history result that could turn expiry into success.
                if signal == "Finished" and variant.get_type_string() == "(uu)":
                    finished = variant.unpack()[0]
                    loop.quit()
                return
            if time.monotonic() >= deadline:
                return
            if finished is not None:
                if signal == "Finished":
                    failure = shared.SnapshotFailure("malformed", "PackageKit history completion is duplicated")
                return
            try:
                if signal == "Transaction":
                    if variant.get_type_string() != "(osbuusus)" or len(records) >= 64:
                        raise shared.SnapshotFailure("malformed", "PackageKit history exceeds its typed record budget")
                    records.append(update_plans.validate_history_record(variant.unpack()))
                elif signal == "ErrorCode":
                    if variant.get_type_string() != "(us)":
                        raise shared.SnapshotFailure("malformed", "PackageKit history error is malformed")
                    failure = failure or self._transaction_failure(variant.unpack()[0], "")
                elif signal == "Finished":
                    if variant.get_type_string() != "(uu)" or finished is not None:
                        raise shared.SnapshotFailure("malformed", "PackageKit history completion is malformed")
                    finished = variant.unpack()[0]
                    loop.quit()
            except shared.SnapshotFailure as error:
                failure = error
                loop.quit()

        def expired():
            nonlocal source
            source = 0
            loop.quit()
            return self.GLib.SOURCE_REMOVE

        subscription = self.connection.signal_subscribe(shared.PACKAGEKIT_NAME, shared.TRANSACTION_INTERFACE, None, path, None, self.Gio.DBusSignalFlags.NONE, signal_received, None)
        try:
            try:
                self._recovery_call(path, shared.TRANSACTION_INTERFACE, "GetOldTransactions",
                    self.GLib.Variant("(u)", (64,)), deadline, "()")
                if finished is None and failure is None:
                    source = self.GLib.timeout_add(self._timeout_ms(deadline), expired)
                    loop.run()
                if finished is None and failure is None:
                    raise shared.SnapshotFailure("timeout", "PackageKit recovery history timed out")
                if failure is not None:
                    raise failure
                if finished != shared.EXIT_SUCCESS:
                    raise shared.SnapshotFailure("internal", "PackageKit recovery history did not succeed")
                return tuple(records)
            except shared.SnapshotFailure:
                if finished is None:
                    discarding = True
                    self._cancel_with_grace(path, loop, lambda: finished is not None)
                raise
        finally:
            live = False
            if source:
                self.GLib.source_remove(source)
            self.connection.signal_unsubscribe(subscription)

    def execute_mutation(self, owner: native_operations.PackageKitMutation, package_ids: Sequence[str]) -> None:
        """Observe the exact object through Finished; a missing reply is not a result."""
        path = owner.operation.transaction_path
        method = "RefreshCache" if owner.operation.kind == "refresh" else "UpdatePackages"
        parameters = self.GLib.Variant("(b)", (True,)) if method == "RefreshCache" else self.GLib.Variant("(tas)", (self.flags_only_trusted, list(package_ids)))
        loop = self.GLib.MainLoop()
        request = self.Gio.Cancellable()
        active = True
        cancel_sent = False
        call_failure: shared.SnapshotFailure | None = None
        subscriptions = []

        def stop(state: str, failure: shared.SnapshotFailure | None = None,
                 *, invocation_rejected: bool = False) -> None:
            nonlocal active
            if not active:
                return
            active = False
            try:
                owner.finish(state, failure, invocation_rejected=invocation_rejected)
            finally:
                loop.quit()

        def cancel_faulted() -> None:
            nonlocal cancel_sent
            if not active or cancel_sent or not owner.allow_cancel or not (owner.persistence_error or owner.failure):
                return
            deadline = time.monotonic() + CANCEL_GRACE_SECONDS
            try:
                reply = self._call(path, shared.PROPERTIES_INTERFACE, "Get",
                    self.GLib.Variant("(ss)", (shared.TRANSACTION_INTERFACE, "AllowCancel")), deadline).unpack()
                allowed = len(reply) == 1 and type(reply[0]) is bool and reply[0]
                owner.allow_cancel = bool(allowed)
                if allowed:
                    cancel_sent = True
                    if owner.persistence_error is None:
                        if owner.operation.state == "running":
                            owner._checkpoint("cancel-requested")
                        owner.journal.validate()
                    try:
                        self._call(path, shared.TRANSACTION_INTERFACE, "Cancel", None, deadline)
                    finally:
                        owner.after_send()
            except (shared.SnapshotFailure, operation_journal.JournalFileError):
                pass

        def signal_received(_connection, _sender, _path, interface, signal, values, _data):
            if not active:
                return
            try:
                unpacked = values.unpack()
                if interface == shared.PROPERTIES_INTERFACE:
                    if len(unpacked) != 3 or unpacked[0] != shared.TRANSACTION_INTERFACE or not isinstance(unpacked[1], dict):
                        raise ValueError
                    properties = dict(unpacked[1])
                    if not isinstance(unpacked[2], (list, tuple)):
                        raise ValueError
                    # Never retain an invalidated cancellation permission.
                    for key in unpacked[2]:
                        if key in {"Status", "Percentage", "AllowCancel"}:
                            properties[key] = None
                    owner.on_properties(properties)
                elif signal in {"Package", "Packages"}:
                    packages = [unpacked] if signal == "Package" else unpacked[0] if len(unpacked) == 1 else None
                    if not isinstance(packages, (list, tuple)):
                        raise ValueError
                    for item in packages:
                        if len(item) != 3:
                            raise ValueError
                        owner.on_package(item[0], item[1])
                elif signal == "ItemProgress":
                    if len(unpacked) == 3 and isinstance(unpacked[0], str):
                        phase = PACKAGEKIT_STATUS_PHASE.get(unpacked[1], "working") if type(unpacked[1]) is int else "working"
                        percent = unpacked[2] if type(unpacked[2]) is int and 0 <= unpacked[2] <= 100 else None
                        owner.on_item_progress(unpacked[0], phase, percent)
                elif signal == "RequireRestart":
                    if len(unpacked) != 2 or type(unpacked[0]) is not int:
                        raise ValueError
                    owner.on_restart(unpacked[0])
                elif signal == "ErrorCode":
                    if len(unpacked) != 2 or type(unpacked[0]) is not int:
                        raise ValueError
                    owner.failure = owner.failure or self._transaction_failure(unpacked[0], "")
                elif signal == "Finished":
                    if len(unpacked) != 2 or type(unpacked[0]) is not int:
                        raise ValueError
                    failure = owner.failure
                    if failure is not None:
                        state = "permission-denied" if failure.code == "permission-denied" else "canceled" if failure.code == "canceled" else "failed"
                        stop(state, failure)
                    elif unpacked[0] == shared.EXIT_SUCCESS:
                        stop("succeeded")
                    elif unpacked[0] == 3:
                        stop("canceled", shared.SnapshotFailure("canceled", "PackageKit canceled the transaction"))
                    else:
                        stop("failed", shared.SnapshotFailure("internal", "PackageKit transaction did not succeed"))
                elif signal == "Destroy":
                    stop("interrupted", call_failure or shared.SnapshotFailure("interrupted", "PackageKit object disappeared without a terminal result; refresh status before retrying"))
                cancel_faulted()
            except (TypeError, ValueError, IndexError):
                owner.failure = shared.SnapshotFailure("malformed", "PackageKit sent malformed transaction evidence")
                if signal == "Finished":
                    stop("interrupted", owner.failure)
                else:
                    cancel_faulted()

        def owner_changed(_connection, _sender, _path, _interface, _signal, values, _data):
            unpacked = values.unpack()
            if len(unpacked) == 3 and unpacked[0] == shared.PACKAGEKIT_NAME and unpacked[1] != unpacked[2]:
                stop("interrupted", shared.SnapshotFailure("missing-provider", "PackageKit service changed; transaction outcome is unknown"))

        def method_finished(connection, result, _data):
            nonlocal call_failure
            try:
                connection.call_finish(result)
            except self.GLib.Error as error:
                if active:
                    call_failure = self._dbus_failure(error)
                    if call_failure.code == "permission-denied":
                        stop("permission-denied", call_failure)
                    elif self.Gio.dbus_error_get_remote_error(error) in {
                        "org.freedesktop.DBus.Error.UnknownMethod",
                        "org.freedesktop.DBus.Error.InvalidArgs",
                        "org.freedesktop.DBus.Error.UnknownInterface",
                        "org.freedesktop.DBus.Error.UnknownObject",
                    }:
                        stop("failed", call_failure, invocation_rejected=True)
                    else:
                        owner.progress_warning = "PackageKit method reply failed; still observing the exact transaction"
                        owner._progress()

        closed_handler = self.connection.connect("closed", lambda *_args: stop("interrupted", shared.SnapshotFailure("missing-provider", "System bus connection closed; transaction outcome is unknown")))
        try:
            subscriptions.append(self.connection.signal_subscribe(shared.PACKAGEKIT_NAME, shared.TRANSACTION_INTERFACE, None, path, None, self.Gio.DBusSignalFlags.NONE, signal_received, None))
            subscriptions.append(self.connection.signal_subscribe(shared.PACKAGEKIT_NAME, shared.PROPERTIES_INTERFACE, "PropertiesChanged", path, shared.TRANSACTION_INTERFACE, self.Gio.DBusSignalFlags.NONE, signal_received, None))
            subscriptions.append(self.connection.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus", shared.PACKAGEKIT_NAME, self.Gio.DBusSignalFlags.NONE, owner_changed, None))
            owner.before_send()
            try:
                self.connection.call(shared.PACKAGEKIT_NAME, path, shared.TRANSACTION_INTERFACE, method, parameters,
                    self.GLib.VariantType.new("()"), self.Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION,
                    60000, request, method_finished, None)
            finally:
                owner.after_send()
            cancel_faulted()
            if active:
                # Silence is not terminal evidence: authorization or a package
                # script can remain quiet while the exact backend is still live.
                # An idle watchdog must not clear admission by terminalizing it.
                loop.run()
        finally:
            active = False
            request.cancel()
            for subscription in subscriptions:
                self.connection.signal_unsubscribe(subscription)
            self.connection.disconnect(closed_handler)

    def updates(self) -> update_plans.TransactionResult:
        return self._transaction(
            "GetUpdates", self.GLib.Variant("(t)", (self.filter_none,))
        )

    def simulate(self, package_ids: Sequence[str]) -> update_plans.TransactionResult:
        return self._transaction(
            "UpdatePackages",
            self.GLib.Variant(
                "(tas)",
                (self.flags_simulate_only_trusted, list(package_ids)),
            ),
        )

    def _transaction(self, method: str, parameters: object) -> update_plans.TransactionResult:
        deadline = time.monotonic() + READ_DEADLINE_SECONDS
        created = self._call(
            shared.PACKAGEKIT_PATH,
            shared.PACKAGEKIT_INTERFACE,
            "CreateTransaction",
            None,
            deadline,
        ).unpack()
        if (
            len(created) != 1
            or not isinstance(created[0], str)
            or not created[0].startswith("/")
        ):
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned a malformed transaction path"
            )
        path = created[0]
        packages: list[update_plans.Package] = []
        restart_types: list[int] = []
        error_code: tuple[int, str] | None = None
        finished_exit: int | None = None
        collection_failure: shared.SnapshotFailure | None = None
        loop = self.GLib.MainLoop()

        def signal_received(
            _connection: object,
            _sender: str,
            _path: str,
            _interface: str,
            signal: str,
            values: object,
            _data: object,
        ) -> None:
            nonlocal collection_failure, error_code, finished_exit
            try:
                unpacked = values.unpack()
                if collection_failure is not None and signal != "Finished":
                    return
                if signal == "Package":
                    if len(unpacked) != 3:
                        raise ValueError
                    packages.append(update_plans.Package(int(unpacked[0]), unpacked[1], unpacked[2]))
                elif signal == "Packages":
                    if len(unpacked) != 1:
                        raise ValueError
                    for item in unpacked[0]:
                        if len(item) != 3:
                            raise ValueError
                        info, package_id, summary = item
                        packages.append(update_plans.Package(int(info), package_id, summary))
                elif signal == "RequireRestart":
                    if len(unpacked) != 2:
                        raise ValueError
                    restart_types.append(int(unpacked[0]))
                elif signal == "ErrorCode":
                    if len(unpacked) != 2:
                        raise ValueError
                    error_code = (int(unpacked[0]), shared.clean_text(unpacked[1]))
                elif signal == "Finished":
                    if len(unpacked) != 2:
                        raise ValueError
                    finished_exit = int(unpacked[0])
                    loop.quit()
            except (TypeError, ValueError):
                if collection_failure is None:
                    collection_failure = shared.SnapshotFailure(
                        "malformed", "PackageKit sent a malformed transaction signal"
                    )
                loop.quit()
                return
            if len(packages) > shared.MAX_LIST_RECORDS and collection_failure is None:
                collection_failure = shared.SnapshotFailure(
                    "malformed", "PackageKit returned too many package records"
                )
                loop.quit()

        subscription = self.connection.signal_subscribe(
            shared.PACKAGEKIT_NAME,
            shared.TRANSACTION_INTERFACE,
            None,
            path,
            None,
            self.Gio.DBusSignalFlags.NONE,
            signal_received,
            None,
        )
        timeout_source = 0
        try:
            try:
                self._call(
                    path,
                    shared.TRANSACTION_INTERFACE,
                    "SetHints",
                    self.GLib.Variant(
                        "(as)",
                        (
                            [
                                "background=true",
                                "interactive=false",
                                "cache-age=4294967295",
                            ],
                        ),
                    ),
                    deadline,
                )
                self._call(path, shared.TRANSACTION_INTERFACE, method, parameters, deadline)
            except shared.SnapshotFailure as failure:
                if failure.code == "timeout":
                    self._cancel_with_grace(
                        path, loop, lambda: finished_exit is not None
                    )
                raise

            def timed_out() -> bool:
                nonlocal timeout_source
                timeout_source = 0
                loop.quit()
                return self.GLib.SOURCE_REMOVE

            if collection_failure is None and finished_exit is None:
                try:
                    wait_ms = self._timeout_ms(deadline)
                except shared.SnapshotFailure:
                    self._cancel_with_grace(
                        path, loop, lambda: finished_exit is not None
                    )
                    raise
                timeout_source = self.GLib.timeout_add(wait_ms, timed_out)
                loop.run()
            if collection_failure is not None:
                self._cancel_with_grace(path, loop, lambda: finished_exit is not None)
                raise collection_failure
            if finished_exit is None:
                self._cancel_with_grace(path, loop, lambda: finished_exit is not None)
                raise shared.SnapshotFailure("timeout", "PackageKit transaction timed out")
        finally:
            if timeout_source:
                self.GLib.source_remove(timeout_source)
            self.connection.signal_unsubscribe(subscription)

        if error_code is not None:
            raise self._transaction_failure(*error_code)
        if finished_exit != shared.EXIT_SUCCESS:
            raise shared.SnapshotFailure("internal", "PackageKit transaction did not succeed")
        return update_plans.TransactionResult(tuple(packages), tuple(restart_types))

    def _cancel_with_grace(self, path: str, loop: object, finished: object) -> None:
        grace_deadline = time.monotonic() + CANCEL_GRACE_SECONDS
        allow_cancel = False
        try:
            reply = self._call(
                path,
                shared.PROPERTIES_INTERFACE,
                "Get",
                self.GLib.Variant("(ss)", (shared.TRANSACTION_INTERFACE, "AllowCancel")),
                grace_deadline,
            ).unpack()
            allow_cancel = (
                reply[0] if len(reply) == 1 and isinstance(reply[0], bool) else False
            )
            if allow_cancel:
                self._call(path, shared.TRANSACTION_INTERFACE, "Cancel", None, grace_deadline)
        except shared.SnapshotFailure:
            pass
        if finished():
            return

        def grace_expired() -> bool:
            nonlocal source
            source = 0
            loop.quit()
            return self.GLib.SOURCE_REMOVE

        try:
            grace_ms = self._timeout_ms(grace_deadline)
        except shared.SnapshotFailure:
            return
        source = self.GLib.timeout_add(grace_ms, grace_expired)
        try:
            loop.run()
        finally:
            if source:
                self.GLib.source_remove(source)

    @staticmethod
    def _transaction_failure(code: int, _detail: str) -> shared.SnapshotFailure:
        if code == 2:
            return shared.SnapshotFailure("network", "PackageKit could not reach the network")
        if code in {18, 19, 28, 33, 37, 43, 64}:
            return shared.SnapshotFailure("repository", "PackageKit repository access failed")
        if code in {13, 26, 35, 36, 61, 67}:
            return shared.SnapshotFailure("conflict", "PackageKit reported a package conflict")
        if code in {5, 30, 31, 50, 51}:
            return shared.SnapshotFailure(
                "signature", "PackageKit rejected package trust data"
            )
        if code == 48:
            return shared.SnapshotFailure(
                "permission-denied", "PackageKit denied the transaction", "restricted"
            )
        if code == 3:
            return shared.SnapshotFailure(
                "unsupported",
                "PackageKit does not support the transaction",
                "unsupported",
            )
        if code in {17, 65}:
            return shared.SnapshotFailure("canceled", "PackageKit transaction was canceled")
        if code in {6, 14}:
            return shared.SnapshotFailure(
                "malformed", "PackageKit rejected the transaction input"
            )
        if code in {
            7,
            8,
            9,
            10,
            20,
            27,
            29,
            32,
            38,
            39,
            40,
            41,
            42,
            45,
            46,
            49,
            55,
            56,
            57,
            58,
            59,
            60,
        }:
            return shared.SnapshotFailure("package", "PackageKit package processing failed")
        return shared.SnapshotFailure("internal", "PackageKit transaction failed internally")
