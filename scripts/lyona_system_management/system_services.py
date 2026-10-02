"""Package repositories, systemd units, CUPS and firewall units."""

from __future__ import annotations

import contextlib
import re
import socket
import time
from dataclasses import dataclass, replace
from typing import Mapping

from . import packagekit, regional_settings, shared, system_information, update_plans


REPOSITORY_READ_SECONDS = 30

CUPS_READ_SECONDS = 10
UNIT_REPLY_TYPE = "(a(ssssssouso))"


@dataclass(frozen=True)
class RepositoryRow:
    repository_id: str
    enabled: bool
    description: str

    def fields(self) -> tuple[str, ...]:
        return ("repository", self.repository_id,
                "enabled" if self.enabled else "disabled", self.description)


def decode_repository_row(values: object) -> RepositoryRow:
    """Bound serialized fields before copying a RepoDetail into Python."""
    if values.get_type_string() != "(ssb)" or values.get_size() > 2 * shared.MAX_TEXT_BYTES + 16:
        raise shared.SnapshotFailure("malformed", "Invalid PackageKit repository record")
    for index in (0, 1):
        if values.get_child_value(index).get_size() > shared.MAX_TEXT_BYTES + 1:
            raise shared.SnapshotFailure("malformed", "Oversized PackageKit repository field")
    repository_id, description, enabled = values.unpack()
    return RepositoryRow(update_plans.canonical_identity(repository_id), enabled,
                         shared.clean_text(description, truncate=False))


class RepositoryRead(shared.ServiceRead):
    """Collect one complete fixed GetRepoList transaction, never a mutation."""

    label = "Repository"
    seconds = REPOSITORY_READ_SECONDS

    def __init__(self, Gio=None, GLib=None) -> None:
        super().__init__(Gio, GLib)
        try:
            import gi
            gi.require_version("PackageKitGlib", "1.0")
            from gi.repository import PackageKitGlib
        except (ImportError, ValueError) as error:
            raise shared.SnapshotFailure("missing-provider", "PackageKit bindings are unavailable", "unavailable") from error
        self.filter_none = PackageKitGlib.filter_bitfield_from_string("none")
        self.stage = "connect"
        self.owner = self.path = self.match_rule = ""
        self.subscription = self.closed_handler = 0
        self.fetch_sent = self.acknowledged = self.finished = False
        self.rows: dict[str, RepositoryRow] = {}
        self.row_bytes = 0

    def request(self, stage, method, parameters=None, signature="()", *, bus=False, manager=False):
        if not self.pending():
            return
        self.stage = stage
        destination = "org.freedesktop.DBus" if bus else self.owner
        path = "/org/freedesktop/DBus" if bus else shared.PACKAGEKIT_PATH if manager else self.path
        interface = "org.freedesktop.DBus" if bus else shared.PACKAGEKIT_INTERFACE if manager else shared.TRANSACTION_INTERFACE
        self.connection.call(destination, path, interface, method, parameters,
            self.GLib.VariantType.new(signature), self.Gio.DBusCallFlags.NONE,
            max(1, min(int((self.deadline - time.monotonic()) * 1000), self.seconds * 1000)),
            self.cancellable, self.replied, stage)

    def connected(self, _source, result, _data):
        if not self.pending() or self.stage != "connect":
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            if not self.pending():
                return
            self.connection.set_exit_on_close(False)
            self.closed_handler = self.connection.connect("closed", self.connection_closed)
            self.request("owner", "GetNameOwner",
                self.GLib.Variant("(s)", (shared.PACKAGEKIT_NAME,)), "(s)", bus=True)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def connection_closed(self, *_args):
        if self.pending():
            self.fail(shared.SnapshotFailure("missing-provider", "Repository service bus disconnected", "unavailable"))

    def bus_failure(self, error):
        if time.monotonic() < self.deadline:
            name = self.Gio.dbus_error_get_remote_error(error)
            if name == "org.freedesktop.PackageKit.Transaction.RefusedByPolicy":
                return shared.SnapshotFailure("permission-denied", "PackageKit denied repository discovery", "restricted")
            if name == "org.freedesktop.PackageKit.Transaction.NotSupported":
                return shared.SnapshotFailure("unsupported", "PackageKit cannot list repositories", "unsupported")
        return super().bus_failure(error)

    def replied(self, connection, result, stage):
        if not self.pending() or stage != self.stage:
            return
        try:
            reply = connection.call_finish(result)
            if not self.pending():
                return
            signature = {"start": "(u)", "owner": "(s)", "owner-after-start": "(s)", "verify-owner": "(s)",
                         "create": "(o)"}.get(stage, "()")
            if reply.get_type_string() != signature or reply.get_size() > 256:
                raise shared.SnapshotFailure("malformed", "Invalid repository transaction reply")
            if stage == "start":
                if reply.unpack()[0] not in (1, 2):
                    raise shared.SnapshotFailure("malformed", "Invalid PackageKit activation reply")
                self.request("owner-after-start", "GetNameOwner", self.GLib.Variant("(s)", (shared.PACKAGEKIT_NAME,)), "(s)", bus=True)
            elif stage in ("owner", "owner-after-start", "verify-owner"):
                owner = reply.unpack()[0]
                if re.fullmatch(r":[0-9]+\.[0-9]+", owner) is None:
                    raise shared.SnapshotFailure("malformed", "Invalid PackageKit service identity")
                if stage != "verify-owner":
                    self.owner = owner
                    self.request("create", "CreateTransaction", signature="(o)", manager=True)
                else:
                    if owner != self.owner:
                        raise shared.SnapshotFailure("conflict", "PackageKit changed during repository discovery")
                    rows = tuple(self.rows[key] for key in sorted(self.rows, key=lambda key: key.encode("utf-8")))
                    if self.pending():
                        self.finish(rows)
            elif stage == "create":
                path = reply.unpack()[0]
                if shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path) is None:
                    raise shared.SnapshotFailure("malformed", "Invalid repository transaction path")
                self.path = path
                self.subscription = connection.signal_subscribe(self.owner, shared.TRANSACTION_INTERFACE,
                    None, self.path, None, self.Gio.DBusSignalFlags.NO_MATCH_RULE, self.received, None)
                self.match_rule = f"type='signal',sender='{self.owner}',interface='{shared.TRANSACTION_INTERFACE}',path='{self.path}'"
                # An explicit acknowledgment makes bus policy denial observable.
                self.request("match", "AddMatch", self.GLib.Variant("(s)", (self.match_rule,)), bus=True)
            elif stage == "match":
                self.request("hints", "SetHints", self.GLib.Variant("(as)",
                    (["background=true", "interactive=false", "cache-age=4294967295"],)))
            elif stage == "hints":
                self.fetch_sent = True
                self.request("fetch", "GetRepoList", self.GLib.Variant("(t)", (self.filter_none,)))
            elif stage == "fetch":
                self.acknowledged = True
                self.stage = "wait"
                self.maybe_complete()
        except self.GLib.Error as error:
            if (stage == "owner" and self.pending()
                    and self.Gio.dbus_error_get_remote_error(error) == "org.freedesktop.DBus.Error.NameHasNoOwner"):
                # Activate only an absent daemon, once, within the same deadline.
                try:
                    self.request("start", "StartServiceByName",
                        self.GLib.Variant("(su)", (shared.PACKAGEKIT_NAME, 0)), "(u)", bus=True)
                except self.GLib.Error as activation_error:
                    self.fail(self.bus_failure(activation_error))
                return
            self.fail(self.bus_failure(error))
        except (shared.SnapshotFailure, TypeError, ValueError) as error:
            if self.pending():
                self.fail(error if isinstance(error, shared.SnapshotFailure) else
                          shared.SnapshotFailure("malformed", "Malformed repository transaction reply"))

    def maybe_complete(self):
        if self.acknowledged and self.finished and self.stage == "wait":
            self.request("verify-owner", "GetNameOwner",
                self.GLib.Variant("(s)", (shared.PACKAGEKIT_NAME,)), "(s)", bus=True)

    def received(self, _connection, sender, path, interface, member, values, _data):
        if (not self.pending() or sender != self.owner or path != self.path
                or interface != shared.TRANSACTION_INTERFACE or self.finished
                or member not in ("RepoDetail", "ErrorCode", "Finished", "Destroy")):
            return
        try:
            if self.stage not in ("fetch", "wait"):
                raise shared.SnapshotFailure("malformed", "Premature repository transaction signal")
            if member == "RepoDetail":
                if len(self.rows) >= shared.REPOSITORY_MAX_ROWS:
                    raise shared.SnapshotFailure("malformed", "Too many PackageKit repositories")
                row = decode_repository_row(values)
                size = update_plans.encoded_record_size(row.fields())
                if row.repository_id in self.rows or self.row_bytes + size > shared.REPOSITORY_MAX_BYTES:
                    raise shared.SnapshotFailure("malformed", "Duplicate or oversized repository result")
                if self.pending():
                    self.rows[row.repository_id] = row
                    self.row_bytes += size
            elif member == "ErrorCode":
                if (values.get_type_string() != "(us)" or values.get_size() > shared.MAX_TEXT_BYTES + 16
                        or values.get_child_value(1).get_size() > shared.MAX_TEXT_BYTES + 1):
                    raise shared.SnapshotFailure("malformed", "Invalid PackageKit repository error")
                raise packagekit.PackageKitBackend._transaction_failure(values.get_child_value(0).unpack(), "")
            elif member == "Finished":
                if values.get_type_string() != "(uu)" or values.get_size() != 8:
                    raise shared.SnapshotFailure("malformed", "Invalid repository completion signal")
                self.finished = True
                if values.unpack()[0] != shared.EXIT_SUCCESS:
                    raise shared.SnapshotFailure("internal", "Repository transaction did not succeed")
                self.maybe_complete()
            else:
                if values.get_type_string() != "()":
                    raise shared.SnapshotFailure("malformed", "Invalid repository destruction signal")
                raise shared.SnapshotFailure("missing-provider", "Repository transaction disappeared", "unavailable")
        except (shared.SnapshotFailure, TypeError, ValueError) as error:
            if self.pending():
                self.fail(error if isinstance(error, shared.SnapshotFailure) else
                          shared.SnapshotFailure("malformed", "Malformed repository transaction signal"))
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def run(self):
        try:
            return super().run()
        finally:
            if self.connection is not None:
                if self.subscription:
                    self.connection.signal_unsubscribe(self.subscription)
                    self.subscription = 0
                if self.closed_handler:
                    self.connection.disconnect(self.closed_handler)
                    self.closed_handler = 0
                if self.failure and self.fetch_sent and not self.finished:
                    # Only this reader's exact transaction, never another owner's
                    # work. Best effort is not a claim that the daemon canceled it.
                    with contextlib.suppress(self.GLib.Error):
                        self.connection.call(self.owner, self.path, shared.TRANSACTION_INTERFACE, "Cancel",
                            None, None, self.Gio.DBusCallFlags.NONE, 1000, None, None, None)
                if self.match_rule:
                    # Also remove a rule whose AddMatch reply was lost. These
                    # asynchronous cleanup requests do not extend the deadline.
                    with contextlib.suppress(self.GLib.Error):
                        self.connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                            "org.freedesktop.DBus", "RemoveMatch", self.GLib.Variant("(s)", (self.match_rule,)),
                            None, self.Gio.DBusCallFlags.NONE, 1000, None, None, None)
                    self.match_rule = ""
            self.rows.clear()


@dataclass(frozen=True)
class UnitState:
    path: str
    load: str
    active: str
    sub: str


def decode_unit_state(reply: object) -> UnitState:
    """Decode the single fixed-name query before exposing any unit state."""
    if (reply.get_type_string() != UNIT_REPLY_TYPE or reply.get_size() > shared.UNIT_REPLY_BYTES
            or reply.get_child_value(0).n_children() != 1):
        raise shared.SnapshotFailure("malformed", "Invalid systemd unit reply")
    row = reply.get_child_value(0).get_child_value(0)
    # ListUnitsByNames can return a canonical alias name. The fixed request,
    # not a guessed object-path encoding or canonical name, identifies the unit.
    values = []
    for index in (2, 3, 4, 6):
        child = row.get_child_value(index)
        if child.get_size() > shared.MAX_TEXT_BYTES + 1:
            raise shared.SnapshotFailure("malformed", "Oversized systemd unit state")
        values.append(child.unpack())
    load, active, sub, path = values
    if (any(shared.UNIT_STATE_TOKEN.fullmatch(value) is None for value in (load, active, sub))
            or not path.startswith(shared.SYSTEMD_PATH + "/unit/")
            or shared.DBUS_OBJECT_PATH.fullmatch(path) is None):
        raise shared.SnapshotFailure("malformed", "Malformed systemd unit state")
    return UnitState(path, load, active, sub)


@dataclass(frozen=True)
class CupsState:
    status: str
    value: str
    units: tuple[tuple[str, UnitState], ...]
    errors: tuple[shared.SnapshotFailure, ...]


def classify_cups(units: Mapping[str, UnitState], errors=()) -> CupsState:
    """Keep a validated running scheduler independent of the socket probe."""
    service, socket = (units.get(name) for name in shared.CUPS_UNITS)
    status, value = "partial", "unknown"
    if service and service.load == "loaded" and service.active == "active":
        status, value = "available", "running"
    elif errors or len(units) != 2:
        status = "partial" if errors and all(error.code == "malformed" for error in errors) else "unavailable"
    else:
        service_absent = (service.load, service.active, service.sub) == ("not-found", "inactive", "dead")
        socket_absent = (socket.load, socket.active, socket.sub) == ("not-found", "inactive", "dead")
        if service_absent and socket_absent:
            status = "unsupported"
        elif service.load == "loaded" and service.active == "inactive":
            if socket.load == "loaded" and (socket.active, socket.sub) == ("active", "listening"):
                status, value = "available", "socket-ready"
            elif socket_absent or (socket.load == "loaded" and socket.active == "inactive"):
                status, value = "available", "stopped"
    return CupsState(status, value, tuple((name, units[name]) for name in shared.CUPS_UNITS if name in units),
                     tuple(errors))


class CupsRead(shared.ServiceRead):
    """Read two fixed CUPS units under one connection-to-decoding deadline."""

    label = "Printer"
    seconds = CUPS_READ_SECONDS

    def __init__(self, Gio=None, GLib=None) -> None:
        super().__init__(Gio, GLib)
        self.units = {}
        self.errors = []
        self.waiting = set(shared.CUPS_UNITS)

    def fail(self, failure: shared.SnapshotFailure) -> None:
        if not self.done:
            self.errors.append(failure)
            self.finish(value=classify_cups(self.units, self.errors))

    def connected(self, _source, result, _data) -> None:
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))
            return
        for unit in shared.CUPS_UNITS:
            if not self.pending():
                return
            try:
                self.connection.call(shared.SYSTEMD_NAME, shared.SYSTEMD_PATH, shared.SYSTEMD_MANAGER,
                    "ListUnitsByNames", self.GLib.Variant("(as)", ([unit],)),
                    self.GLib.VariantType.new(UNIT_REPLY_TYPE), self.Gio.DBusCallFlags.NO_AUTO_START,
                    max(1, int((self.deadline - time.monotonic()) * 1000)),
                    self.cancellable, self.replied, unit)
            except self.GLib.Error as error:
                self.unit_failed(unit, error)

    def unit_failed(self, unit: str, error: Exception) -> None:
        if not self.pending():
            return
        if self.Gio.dbus_error_get_remote_error(error) == "org.freedesktop.systemd1.NoSuchUnit":
            self.completed_unit(unit, state=UnitState("", "not-found", "inactive", "dead"))
        else:
            self.completed_unit(unit, failure=self.bus_failure(error))

    def completed_unit(self, unit: str, state=None, failure=None) -> None:
        if not self.pending() or unit not in self.waiting:
            return
        self.waiting.remove(unit)
        if failure is not None:
            self.errors.append(failure)
        else:
            self.units[unit] = state
        if not self.waiting:
            self.finish(value=classify_cups(self.units, self.errors))

    def replied(self, connection, result, unit) -> None:
        if not self.pending() or unit not in self.waiting:
            return
        try:
            self.completed_unit(unit, state=decode_unit_state(connection.call_finish(result)))
        except self.GLib.Error as error:
            self.unit_failed(unit, error)
        except shared.SnapshotFailure as error:
            self.completed_unit(unit, failure=error)


class FirewallUnitRead(shared.ServiceRead):
    """Read the ActiveState field of one fixed firewall unit without activating it."""

    def __init__(self, kind, Gio=None, GLib=None):
        if not isinstance(kind, str) or kind not in shared.FIREWALL_UNITS:
            raise shared.SnapshotFailure("malformed", "Unknown firewall unit read")
        self.kind = kind
        self.unit, self.name = shared.FIREWALL_UNITS[kind]
        self.label = f"{self.name} status"
        super().__init__(Gio, GLib)

    def connected(self, _source, result, _data):
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
            if self.pending():
                self.connection.call(shared.SYSTEMD_NAME, shared.SYSTEMD_PATH, shared.SYSTEMD_MANAGER, "ListUnitsByNames",
                    self.GLib.Variant("(as)", ([self.unit],)), self.GLib.VariantType.new(UNIT_REPLY_TYPE),
                    self.Gio.DBusCallFlags.NO_AUTO_START, max(1, int((self.deadline - time.monotonic()) * 1000)),
                    self.cancellable, self.replied, None)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def replied(self, connection, result, _data):
        if not self.pending():
            return
        try:
            unit = decode_unit_state(connection.call_finish(result))
            if unit.load == "not-found":
                if (unit.active, unit.sub) != ("inactive", "dead"):
                    raise shared.SnapshotFailure("malformed", f"{self.name} absence state is inconsistent")
                state = system_information.InformationState("unsupported", "unknown", f"{self.name} is not installed", "missing-provider")
            elif unit.active in ("active", "inactive"):
                state = system_information.InformationState("available", "enabled" if unit.active == "active" else "disabled",
                    f"{self.name} service only; rules content and other firewall managers are not assessed")
            else:
                state = system_information.InformationState("partial", "unknown", f"{self.name} service is failed or transitioning", "internal")
            if self.pending():
                self.finish(value=state)
        except self.GLib.Error as error:
            if self.pending():
                if self.Gio.dbus_error_get_remote_error(error) == "org.freedesktop.systemd1.NoSuchUnit":
                    self.fail(shared.SnapshotFailure("missing-provider", f"{self.name} is not installed", "unsupported"))
                else:
                    self.fail(self.bus_failure(error))
        except shared.SnapshotFailure as error:
            if self.pending():
                self.fail(error)


def read_firewall_status(kind: str) -> system_information.InformationState:
    """Keep fixed service-call failures scoped while preserving interruption."""
    try:
        return regional_settings.run_interruptible_read(FirewallUnitRead(kind))
    except shared.SnapshotFailure as error:
        state = system_information.information_unknown(error)
        return replace(state, status="unavailable") if state.status == "restricted" else state
