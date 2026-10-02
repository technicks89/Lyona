"""AccountsService reads."""

from __future__ import annotations

import bisect
import os
import time
from dataclasses import dataclass

from . import shared, update_plans


ACCOUNT_PROPERTIES = {"UserName": "s", "RealName": "s", "SystemAccount": "b", "LocalAccount": "b"}

ACCOUNT_PROPERTY_CONCURRENCY = 8


@dataclass(frozen=True)
class AccountRecord:
    path: str
    scope: str
    display_name: str
    login_name: str
    local_account: bool

    def fields(self) -> tuple[str, ...]:
        return "account", self.path, self.scope, self.display_name, self.login_name


@dataclass(frozen=True)
class AccountInventory:
    records: tuple[AccountRecord, ...]
    candidates: tuple[str, ...]
    current_path: str | None
    status: str
    errors: tuple[shared.SnapshotFailure, ...]


def account_object_path(value: object) -> str:
    if value.get_type_string() != "o" or value.get_size() > shared.MAX_TEXT_BYTES + 1:
        raise shared.SnapshotFailure("malformed", "Invalid AccountsService object path")
    path = value.unpack()
    if not isinstance(path, str) or shared.DBUS_OBJECT_PATH.fullmatch(path) is None:
        raise shared.SnapshotFailure("malformed", "Invalid AccountsService object path")
    return path


class AccountRead(shared.ServiceRead):
    """Bounded account discovery; neither publishes a protocol nor changes users."""

    label = "Account"
    seconds = 3

    def __init__(self, Gio=None, GLib=None) -> None:
        super().__init__(Gio, GLib)
        self.enumerated = False
        self.selected: list[str] = []
        self.seen: set[str] = set()
        self.current_path = None
        self.candidates: tuple[str, ...] = ()
        self.errors: dict[str, shared.SnapshotFailure] = {}
        self.values: dict[str, dict[str, object]] = {}
        self.records: dict[str, AccountRecord] = {}
        self.invalid: set[str] = set()
        self.queue: tuple[tuple[str, str], ...] = ()
        self.offset = 0
        self.outstanding = 0
        self.draining = False

    def note(self, error: shared.SnapshotFailure) -> None:
        # One diagnostic per closed error code, not one per failed property.
        self.errors.setdefault(error.code, error)

    def inventory(self) -> AccountInventory:
        records = tuple(self.records[path] for path in self.candidates if path in self.records)
        errors = dict(self.errors)
        if (len(records) > shared.ACCOUNT_LIMIT
                or sum(update_plans.encoded_record_size(row.fields()) for row in records) > shared.ACCOUNT_LIST_BYTES):
            records = ()
            errors["malformed"] = shared.SnapshotFailure("malformed", "Account rows exceeded the protocol budget")
        status = "available"
        if errors:
            status = "partial" if self.enumerated or records or "timeout" in errors else next(iter(errors.values())).status
        return AccountInventory(records, self.candidates, self.current_path, status, tuple(errors.values()))

    def fail(self, failure: shared.SnapshotFailure) -> None:
        if not self.done:
            self.note(failure)
            self.finish(value=self.inventory())

    def request(self, path, interface, method, parameters, reply_type, callback, data=None):
        if self.pending():
            self.connection.call(shared.ACCOUNTS_NAME, path, interface, method, parameters,
                self.GLib.VariantType.new(reply_type), self.Gio.DBusCallFlags.NONE,
                max(1, int((self.deadline - time.monotonic()) * 1000)),
                self.cancellable, callback, data)

    def connected(self, _source, result, _data) -> None:
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
            self.request(shared.ACCOUNTS_PATH, shared.ACCOUNTS_NAME, "ListCachedUsers", None, "(ao)", self.cached)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def cached(self, connection, result, _data) -> None:
        if not self.pending():
            return
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(ao)":
                raise shared.SnapshotFailure("malformed", "Invalid cached account list")
            self.enumerated = True
            paths = reply.get_child_value(0)
            # Never unpack or sort an unbounded reply. Retain at most 257
            # unique identities for overflow evidence and the lowest 256 paths.
            for index in range(paths.n_children()):
                if not self.pending():
                    return
                try:
                    path = account_object_path(paths.get_child_value(index))
                except shared.SnapshotFailure as error:
                    if not self.pending():
                        return
                    self.note(error)
                    continue
                if not self.pending():
                    return
                if len(self.seen) <= shared.ACCOUNT_LIMIT:
                    self.seen.add(path)
                if len(self.seen) > shared.ACCOUNT_LIMIT:
                    self.note(shared.SnapshotFailure("malformed", "Too many AccountsService candidates"))
                if path not in self.selected and (len(self.selected) < shared.ACCOUNT_LIMIT or path < self.selected[-1]):
                    bisect.insort(self.selected, path)
                    if len(self.selected) > shared.ACCOUNT_LIMIT:
                        self.selected.pop()
        except self.GLib.Error as error:
            if not self.pending():
                return
            self.note(self.bus_failure(error))
        except shared.SnapshotFailure as error:
            if not self.pending():
                return
            self.note(error)
        if self.pending():
            try:
                self.request(shared.ACCOUNTS_PATH, shared.ACCOUNTS_NAME, "FindUserById",
                    self.GLib.Variant("(x)", (os.getuid(),)), "(o)", self.current)
            except self.GLib.Error as error:
                self.note(self.bus_failure(error))
                self.start_properties()

    def current(self, connection, result, _data) -> None:
        if not self.pending():
            return
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(o)":
                raise shared.SnapshotFailure("malformed", "Invalid current account reply")
            current = account_object_path(reply.get_child_value(0))
            if not self.pending():
                return
            if len(self.seen) >= shared.ACCOUNT_LIMIT and current not in self.seen:
                self.note(shared.SnapshotFailure("malformed", "Too many AccountsService candidates"))
            if self.pending():
                self.current_path = current
        except self.GLib.Error as error:
            if not self.pending():
                return
            self.note(self.bus_failure(error))
        except shared.SnapshotFailure as error:
            if not self.pending():
                return
            self.note(error)
        self.start_properties()

    def start_properties(self) -> None:
        if not self.pending():
            return
        others = [path for path in self.selected if path != self.current_path][:shared.ACCOUNT_LIMIT - 1]
        self.candidates = ((self.current_path,) if self.current_path is not None else ()) + tuple(others)
        self.values = {path: {} for path in self.candidates}
        self.queue = tuple((path, name) for path in self.candidates for name in ACCOUNT_PROPERTIES)
        self.pump()

    def pump(self) -> None:
        if self.draining or not self.pending():
            return
        self.draining = True
        try:
            while self.pending() and self.outstanding < ACCOUNT_PROPERTY_CONCURRENCY and self.offset < len(self.queue):
                path, name = self.queue[self.offset]
                self.offset += 1
                if path in self.invalid:
                    continue
                self.outstanding += 1
                try:
                    self.request(path, shared.PROPERTIES_INTERFACE, "Get",
                        self.GLib.Variant("(ss)", (shared.ACCOUNT_INTERFACE, name)), "(v)", self.property_reply, (path, name))
                except self.GLib.Error as error:
                    self.outstanding -= 1
                    self.invalid.add(path)
                    self.note(self.bus_failure(error))
            if not self.outstanding and self.offset == len(self.queue):
                value = self.inventory()
                if self.pending():
                    self.finish(value=value)
        finally:
            self.draining = False

    def property_reply(self, connection, result, data) -> None:
        if not self.pending():
            return
        path, name = data
        self.outstanding -= 1
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(v)":
                raise shared.SnapshotFailure("malformed", "Invalid account property reply")
            value = reply.get_child_value(0).get_variant()
            signature = ACCOUNT_PROPERTIES[name]
            if (value.get_type_string() != signature
                    or (signature == "s" and value.get_size() > shared.MAX_TEXT_BYTES + 1)):
                raise shared.SnapshotFailure("malformed", "Invalid account property type or size")
            decoded = value.unpack()
            if name == "UserName" and not decoded:
                raise shared.SnapshotFailure("malformed", "Account has no login name")
            if not self.pending():
                return
            if path not in self.invalid:
                self.values[path][name] = decoded
                fields = self.values[path]
                if len(fields) == len(ACCOUNT_PROPERTIES):
                    scope = "current" if path == self.current_path else "other"
                    if scope == "current" or not fields["SystemAccount"]:
                        record = AccountRecord(path, scope,
                            shared.clean_text(fields["RealName"] or fields["UserName"]),
                            shared.clean_text(fields["UserName"]), fields["LocalAccount"])
                        if not self.pending():
                            return
                        self.records[path] = record
        except self.GLib.Error as error:
            if not self.pending():
                return
            self.invalid.add(path)
            if self.Gio.dbus_error_get_remote_error(error) == "org.freedesktop.DBus.Error.UnknownProperty":
                self.note(shared.SnapshotFailure("malformed", "Missing account property"))
            else:
                self.note(self.bus_failure(error))
        except shared.SnapshotFailure as error:
            if not self.pending():
                return
            self.invalid.add(path)
            self.note(error)
        self.pump()
