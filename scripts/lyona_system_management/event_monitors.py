"""Event monitors: updates, authenticated changes, regional settings, time, accounts and units."""

from __future__ import annotations

import contextlib
import signal
import time
from typing import Callable

from . import regional_settings, shared, user_accounts


class UpdateEventMonitor:
    """Read-only manager signals, with bounded setup and no transaction calls."""

    record_prefix = "update-event"

    def __init__(self, Gio, GLib, GLibUnix, emit: Callable[[str], None]) -> None:
        """Initialize the monitor with injectable GLib bindings and output."""
        self.Gio, self.GLib, self.GLibUnix = Gio, GLib, GLibUnix
        self.emit = emit
        self.loop = GLib.MainLoop()
        self.cancellable = Gio.Cancellable()
        self.connection = None
        self.subscriptions: list[int] = []
        self.match_rules: list[str] = []
        self.installed_rules: list[str] = []
        self.sources: list[int] = []
        self.closed_handler = 0
        self.deadline_source = 0
        self.stopped = False
        self.ready = False
        self.dirty = False
        self.exit_code = 1
        self.deadline = 0.0
        self.owner = ""
        self.owner_epoch = 0

    def stop(self, code: int) -> None:
        """Stop the event loop once while preserving the first exit status."""
        if self.stopped:
            return
        self.stopped = True
        self.exit_code = code
        self.cancellable.cancel()
        self.loop.quit()

    def write(self, record: str) -> None:
        """Emit one protocol record or stop when the consumer is unavailable."""
        try:
            self.emit(record)
        except OSError:
            self.stop(1)

    def changed(self, *_args) -> None:
        """Coalesce setup-time changes or publish a change after readiness."""
        if self.stopped:
            return
        if not self.ready:
            self.dirty = True
        else:
            self.write(self.record_prefix + "\tchanged")

    def global_changed(self, _connection, sender, _path, _interface, _member, _parameters, _data) -> None:
        """Accept manager signals only from the current PackageKit owner."""
        # The bus-side match restricts the well-known sender. Avoid GDBus's
        # implicit name cache, whose lookup failures cannot be observed here.
        if not self.ready or sender == self.owner:
            self.changed()

    def owner_changed(self, _connection, _sender, _path, _interface, _member, parameters, _data) -> None:
        """Invalidate state when the PackageKit well-known name changes owner."""
        if self.stopped:
            return
        name, _old, new = parameters.unpack()
        if name == shared.PACKAGEKIT_NAME:
            self.owner_epoch += 1
            self.owner = new
            self.changed()

    def owner_resolved(self, connection, result, epoch) -> None:
        """Finish initial owner lookup and publish readiness for this epoch."""
        if self.stopped:
            return
        if time.monotonic() >= self.deadline:
            self.stop(1)
            return
        try:
            owner = connection.call_finish(result).unpack()[0]
        except self.GLib.Error as error:
            if self.Gio.dbus_error_get_remote_error(error) != "org.freedesktop.DBus.Error.NameHasNoOwner":
                self.stop(1)
                return
            owner = ""
        # A newer owner notification wins over an older in-flight lookup.
        if self.owner_epoch == epoch:
            self.owner = owner
        self.GLib.source_remove(self.deadline_source)
        self.deadline_source = 0
        self.ready = True
        self.write(self.record_prefix + "\tready")
        if self.dirty and not self.stopped:
            self.write(self.record_prefix + "\tchanged")
        self.dirty = False

    def match_finished(self, connection, result, rule) -> None:
        """Install the next fixed match after the bus confirms this rule."""
        if self.stopped:
            return
        if time.monotonic() >= self.deadline:
            self.stop(1)
            return
        try:
            connection.call_finish(result)
        except self.GLib.Error:
            self.stop(1)
            return
        self.installed_rules.append(rule)
        if len(self.installed_rules) < len(self.match_rules):
            self.add_match()
            return
        self.connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "GetNameOwner", self.GLib.Variant("(s)", (shared.PACKAGEKIT_NAME,)),
            self.GLib.VariantType.new("(s)"), self.Gio.DBusCallFlags.NONE,
            10000, self.cancellable, self.owner_resolved, self.owner_epoch)

    def add_match(self) -> None:
        """Request installation of the next fixed D-Bus signal match."""
        rule = self.match_rules[len(self.installed_rules)]
        # NO_MATCH_RULE local subscriptions plus explicit AddMatch replies make
        # denial observable; signal_subscribe alone cannot report bus rejection.
        self.connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "AddMatch", self.GLib.Variant("(s)", (rule,)),
            self.GLib.VariantType.new("()"), self.Gio.DBusCallFlags.NONE,
            10000, self.cancellable, self.match_finished, rule)

    def connected(self, _source, result, _data) -> None:
        """Finish connecting and register the fixed PackageKit subscriptions."""
        if self.stopped:
            return
        if time.monotonic() >= self.deadline:
            self.stop(1)
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
            self.closed_handler = self.connection.connect("closed", lambda *_args: self.stop(1))
            for member in ("UpdatesChanged", "InstalledChanged", "RepoListChanged"):
                self.subscriptions.append(self.connection.signal_subscribe(
                    None, shared.PACKAGEKIT_INTERFACE, member, shared.PACKAGEKIT_PATH,
                    None, self.Gio.DBusSignalFlags.NO_MATCH_RULE, self.global_changed, None))
                self.match_rules.append(f"type='signal',sender='{shared.PACKAGEKIT_NAME}',interface='{shared.PACKAGEKIT_INTERFACE}',member='{member}',path='{shared.PACKAGEKIT_PATH}'")
            # Daemon disappearance/replacement invalidates the old preview too.
            self.subscriptions.append(self.connection.signal_subscribe(
                "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                "/org/freedesktop/DBus", shared.PACKAGEKIT_NAME,
                self.Gio.DBusSignalFlags.NO_MATCH_RULE, self.owner_changed, None))
            self.match_rules.append(f"type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',path='/org/freedesktop/DBus',arg0='{shared.PACKAGEKIT_NAME}'")
            self.add_match()
        except self.GLib.Error:
            self.stop(1)

    def run(self) -> int:
        """Run until stopped, then remove subscriptions, sources, and matches."""
        def timeout():
            """Fail setup when the bounded readiness deadline expires."""
            self.deadline_source = 0
            self.stop(1)
            return self.GLib.SOURCE_REMOVE

        def terminate():
            """Translate a process termination signal into a clean stop."""
            self.stop(0)
            return self.GLib.SOURCE_CONTINUE

        try:
            self.deadline = time.monotonic() + 10
            self.deadline_source = self.GLib.timeout_add(10000, timeout)
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                self.sources.append(self.GLibUnix.signal_add(self.GLib.PRIORITY_DEFAULT, signum, terminate))
            self.Gio.bus_get(self.Gio.BusType.SYSTEM, self.cancellable, self.connected, None)
            self.loop.run()
        finally:
            self.stopped = True
            self.cancellable.cancel()
            if self.connection is not None:
                for subscription in self.subscriptions:
                    self.connection.signal_unsubscribe(subscription)
                if self.closed_handler:
                    self.connection.disconnect(self.closed_handler)
                for rule in self.installed_rules:
                    # Best-effort asynchronous cleanup cannot delay pane close.
                    # Process/bus disconnection also removes every match rule.
                    self.connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                        "org.freedesktop.DBus", "RemoveMatch", self.GLib.Variant("(s)", (rule,)),
                        None, self.Gio.DBusCallFlags.NONE, 1000, None, None, None)
            for source in self.sources + ([self.deadline_source] if self.deadline_source else []):
                self.GLib.source_remove(source)
        return self.exit_code


# Sync Phase 9 (docs/SYNC-P9-REGIONAL-MUTATION.md §4): the generic
# authenticated-owner pattern watch-regional/watch-accounts/watch-units share,
# extending UpdateEventMonitor's bounded-setup/dirty-flag shape. Each fixed
# name owner is authenticated (GetNameOwner, matched) before enabling
# property/signal delivery -- a bus-side match filter alone cannot make bus
# rejection or a spoofed direct signal observable. `watch_update_events()`
# above is untouched: it is Sync Phase 4's own working, tested PackageKit
# monitor, not folded into this class family.
class AuthenticatedEventMonitor(UpdateEventMonitor):
    """Acknowledge fixed service matches and authenticate even setup-time signals."""

    def __init__(self, Gio, GLib, GLibUnix, emit):
        super().__init__(Gio, GLib, GLibUnix, emit)
        self.started = False
        self.name = ""
        self.path = ""

    def setting_up(self):
        if self.stopped:
            return False
        if time.monotonic() >= self.deadline:
            self.stop(1)
            return False
        return True

    def remove_match(self, connection, rule):
        with contextlib.suppress(self.GLib.Error):
            connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                "RemoveMatch", self.GLib.Variant("(s)", (rule,)), None,
                self.Gio.DBusCallFlags.NONE, 1000, None, None, None)

    def match_finished(self, connection, result, rule):
        try:
            reply = connection.call_finish(result)
            # Only acknowledged rules belong to this caller. A late reply can
            # release that rule, but can never resume an expired monitor.
            if self.stopped:
                self.remove_match(connection, rule)
                return
            self.installed_rules.append(rule)
            if not self.setting_up():
                return
            if reply.get_type_string() != "()":
                self.stop(1)
            elif 1 < len(self.installed_rules) < len(self.match_rules):
                self.add_match()
            else:
                # Authenticate the owner after the owner-change match, before
                # enabling property delivery. Bus-side matches do not filter
                # signals addressed directly to this connection.
                callback = self.owner_initialized if len(self.installed_rules) == 1 else self.owner_resolved
                connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                    "GetNameOwner", self.GLib.Variant("(s)", (self.name,)), self.GLib.VariantType.new("(s)"),
                    self.Gio.DBusCallFlags.NONE, max(1, int((self.deadline - time.monotonic()) * 1000)),
                    self.cancellable, callback, self.owner_epoch)
        except self.GLib.Error:
            self.stop(1)

    def resolve_owner(self, connection, result, epoch):
        if not self.setting_up():
            return
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(s)" or reply.get_size() > 256:
                self.stop(1)
                return
            owner = reply.unpack()[0]
            if not self.Gio.dbus_is_unique_name(owner):
                self.stop(1)
                return
        except self.GLib.Error as error:
            if self.Gio.dbus_error_get_remote_error(error) != "org.freedesktop.DBus.Error.NameHasNoOwner":
                self.stop(1)
                return
            owner = ""
        if not self.setting_up():
            return
        if epoch == self.owner_epoch:
            self.owner = owner
        return True

    def owner_initialized(self, connection, result, epoch):
        if self.resolve_owner(connection, result, epoch):
            self.add_match()

    def owner_resolved(self, connection, result, epoch):
        if not self.resolve_owner(connection, result, epoch):
            return
        self.GLib.source_remove(self.deadline_source)
        self.deadline_source = 0
        self.ready = True
        self.write(self.record_prefix + "\tready")
        if self.dirty and not self.stopped:
            self.write(self.record_prefix + "\tchanged")
        self.dirty = False

    def owner_changed(self, _connection, sender, path, interface, member, parameters, _data):
        if (self.stopped or sender != "org.freedesktop.DBus" or path != "/org/freedesktop/DBus"
                or interface != "org.freedesktop.DBus" or member != "NameOwnerChanged"):
            return
        if parameters.get_type_string() != "(sss)" or parameters.get_size() > 768:
            self.stop(1)
            return
        name, old, new = parameters.unpack()
        if name != self.name:
            return
        if any(len(value) > 255 or value and not self.Gio.dbus_is_unique_name(value) for value in (old, new)):
            self.stop(1)
            return
        self.owner_epoch += 1
        self.owner = new
        # timedated/localed normally exit after 30 idle seconds. Departure is
        # not a configuration change: rereading here would reactivate forever.
        # Arrival or replacement reconciles state; mutations still fresh-read.
        if new:
            self.owner_arrived()

    def owner_arrived(self):
        """Existing monitors conservatively invalidate on arrival or replacement."""
        self.changed()

    def service_specs(self):
        raise NotImplementedError

    def connected(self, _source, result, _data):
        if not self.setting_up():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            if not self.setting_up():
                return
            self.subscribe_connection()
        except self.GLib.Error:
            self.stop(1)

    def subscribe_connection(self):
        """Attach only local filters and acknowledged fixed bus matches."""
        try:
            self.connection.set_exit_on_close(False)
            self.closed_handler = self.connection.connect("closed", lambda *_args: self.stop(1))
            specs = [
                ("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus", self.name, self.owner_changed,
                 f"type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',path='/org/freedesktop/DBus',arg0='{self.name}'"),
            ] + self.service_specs()
            for sender, interface, member, path, arg0, callback, rule in specs:
                self.subscriptions.append(self.connection.signal_subscribe(sender, interface, member, path,
                    arg0, self.Gio.DBusSignalFlags.NO_MATCH_RULE, callback, None))
                self.match_rules.append(rule)
            self.add_match()
        except self.GLib.Error:
            self.stop(1)

    def run(self):
        if self.started:
            raise RuntimeError("Service monitors are single-use")
        self.started = True
        return super().run()


class RegionalEventMonitor(AuthenticatedEventMonitor):
    """Observe fixed regional properties, without activating idle platform services."""

    record_prefix = "regional-event"

    def __init__(self, kind, Gio, GLib, GLibUnix, emit):
        if not isinstance(kind, str) or kind not in ("time", "locale"):
            raise ValueError("Unknown regional monitor")
        super().__init__(Gio, GLib, GLibUnix, emit)
        self.name, self.path = shared.REGIONAL_READ_REQUESTS[kind + "-state"][:2]
        self.relevant = {"Locale"} if kind == "locale" else {"Timezone", "CanNTP", "NTP", "NTPSynchronized"}

    def service_specs(self):
        return [(None, shared.PROPERTIES_INTERFACE, "PropertiesChanged", self.path, self.name, self.properties_changed,
            f"type='signal',sender='{self.name}',interface='{shared.PROPERTIES_INTERFACE}',member='PropertiesChanged',path='{self.path}',arg0='{self.name}'")]

    def properties_changed(self, _connection, sender, path, interface, member, parameters, _data):
        if (self.stopped or path != self.path or interface != shared.PROPERTIES_INTERFACE
                or member != "PropertiesChanged" or not self.owner or sender != self.owner):
            return
        try:
            if parameters.get_type_string() != "(sa{sv}as)" or parameters.get_size() > 16384:
                raise shared.SnapshotFailure("malformed", "Invalid regional notification")
            if parameters.get_child_value(0).unpack() != self.name:
                return
            changed = parameters.get_child_value(1)
            invalidated = regional_settings.regional_string_array(parameters.get_child_value(2),
                shared.REGIONAL_TIME_PROPERTY_COUNT, shared.MAX_TEXT_BYTES, 8192)
            if changed.n_children() > shared.REGIONAL_TIME_PROPERTY_COUNT:
                raise shared.SnapshotFailure("malformed", "Oversized regional notification")
            keys = set()
            for index in range(changed.n_children()):
                key = changed.get_child_value(index).get_child_value(0)
                if key.get_size() > shared.MAX_TEXT_BYTES + 1 or key.unpack() in keys:
                    raise shared.SnapshotFailure("malformed", "Invalid regional notification key")
                keys.add(key.unpack())
            if self.relevant.intersection(keys.union(invalidated)):
                self.changed()
        except shared.SnapshotFailure:
            self.stop(1)


class TimeEventMonitor(RegionalEventMonitor):
    """Separate authenticated owner arrival from actual time property changes."""

    record_prefix = "time-event"

    def __init__(self, Gio, GLib, GLibUnix, emit):
        super().__init__("time", Gio, GLib, GLibUnix, emit)

    def owner_arrived(self):
        # Setup races still require the initial bounded reconciliation cycle.
        # After readiness, arrival is uncertainty, not proof of changed state.
        if self.ready:
            self.write(self.record_prefix + "\towner-arrived")
        else:
            self.changed()


class AccountEventMonitor(AuthenticatedEventMonitor):
    """Cover candidate changes before enumeration without retaining an unbounded list."""

    record_prefix = "accounts-event"

    def __init__(self, Gio, GLib, GLibUnix, emit):
        super().__init__(Gio, GLib, GLibUnix, emit)
        self.name, self.path = shared.ACCOUNTS_NAME, shared.ACCOUNTS_PATH

    def service_specs(self):
        specs = [(None, self.name, member, self.path, None, self.users_changed,
            f"type='signal',sender='{self.name}',interface='{self.name}',member='{member}',path='{self.path}'")
            for member in ("UserAdded", "UserDeleted")]
        # This single authenticated interface subscription already covers all
        # selected candidates, including excluded/new objects, before any read.
        # Extra objects can only invalidate; no identities or values are kept.
        specs.append((None, shared.ACCOUNT_INTERFACE, "Changed", None, None, self.user_changed,
            f"type='signal',sender='{self.name}',interface='{shared.ACCOUNT_INTERFACE}',member='Changed'"))
        return specs

    def users_changed(self, _connection, sender, path, interface, member, parameters, _data):
        if (self.stopped or not self.owner or sender != self.owner or path != self.path
                or interface != self.name or member not in ("UserAdded", "UserDeleted")):
            return
        try:
            if parameters.get_type_string() != "(o)" or parameters.get_size() > shared.MAX_TEXT_BYTES + 8:
                raise shared.SnapshotFailure("malformed", "Invalid account notification")
            user_accounts.account_object_path(parameters.get_child_value(0))
            self.changed()
        except shared.SnapshotFailure:
            self.stop(1)

    def user_changed(self, _connection, sender, path, interface, member, parameters, _data):
        if (self.stopped or not self.owner or sender != self.owner
                or interface != shared.ACCOUNT_INTERFACE or member != "Changed"):
            return
        if (not isinstance(path, str) or len(path) > shared.MAX_TEXT_BYTES
                or shared.DBUS_OBJECT_PATH.fullmatch(path) is None
                or parameters.get_type_string() != "()" or parameters.get_size() > 8):
            self.stop(1)
            return
        self.changed()


class UnitEventMonitor(AuthenticatedEventMonitor):
    """Observe fixed loaded units on a private, sender-owned systemd subscription.

    A private Gio.DBusConnection.new_for_address() connection, not the shared
    Gio.bus_get() one every other monitor here uses: systemd's own
    Manager.Subscribe() is scoped to the calling connection, so sharing the
    process-wide bus connection could collide with another reader's Subscribe
    state within the same process.
    """

    record_prefix = "units-event"

    def __init__(self, kind, Gio, GLib, GLibUnix, emit):
        if not isinstance(kind, str) or kind not in shared.WATCH_UNIT_SETS:
            raise ValueError("Unknown unit monitor")
        super().__init__(Gio, GLib, GLibUnix, emit)
        self.name, self.path = shared.SYSTEMD_NAME, shared.SYSTEMD_PATH
        self.units = shared.WATCH_UNIT_SETS[kind]
        self.paths = dict.fromkeys(self.units, "")
        self.subscribed_owner = ""
        self.subscription_ready = False
        self.resolving = False
        self.resolve_again = False
        self.resolve_round = 0
        self.resolution_epoch = 0
        self.resolve_source = 0
        self.resolve_cancel = None
        self.connecting = False
        self.closing = False
        self.cleanup_done = False
        self.cleanup_loop = None

    def service_specs(self):
        specs = [(None, shared.SYSTEMD_MANAGER, member, self.path, None, self.manager_event,
            f"type='signal',sender='{self.name}',interface='{shared.SYSTEMD_MANAGER}',member='{member}',path='{self.path}'")
            for member in ("UnitNew", "UnitRemoved", "UnitFilesChanged", "Reloading")]
        specs.append((None, shared.PROPERTIES_INTERFACE, "PropertiesChanged", None, shared.SYSTEMD_NAME + ".Unit", self.properties_changed,
            f"type='signal',sender='{self.name}',interface='{shared.PROPERTIES_INTERFACE}',member='PropertiesChanged',arg0='{shared.SYSTEMD_NAME}.Unit'"))
        return specs

    def connected(self, _source, result, _data):
        self.connecting = False
        try:
            self.connection = self.Gio.DBusConnection.new_for_address_finish(result)
            self.connection.set_exit_on_close(False)
            if not self.setting_up():
                self.close_connection()
                return
            self.subscribe_connection()
        except self.GLib.Error:
            self.stop(1)
            if self.cleanup_loop is not None:
                self.cleanup_done = True
                self.cleanup_loop.quit()

    def owner_resolved(self, connection, result, epoch):
        """Subscribe only after all matches and an authenticated owner barrier."""
        if not self.resolve_owner(connection, result, epoch):
            return
        if not self.owner:
            self.stop(1)
            return
        self.subscribed_owner = self.owner
        try:
            connection.call(self.owner, self.path, shared.SYSTEMD_MANAGER, "Subscribe", None,
                self.GLib.VariantType.new("()"), self.Gio.DBusCallFlags.NO_AUTO_START,
                max(1, int((self.deadline - time.monotonic()) * 1000)), self.cancellable,
                self.subscribed, None)
        except self.GLib.Error:
            self.stop(1)

    def subscribed(self, connection, result, _data):
        try:
            reply = connection.call_finish(result)
            if not self.setting_up():
                return
            if reply.get_type_string() != "()" or reply.get_size() > 8:
                self.stop(1)
                return
            self.subscription_ready = True
            self.reconcile()
        except self.GLib.Error:
            self.stop(1)

    def owner_changed(self, *args):
        super().owner_changed(*args)
        if self.subscribed_owner and self.owner != self.subscribed_owner:
            # A new daemon does not inherit the old sender's Subscribe state.
            # Fail explicitly instead of silently reconnecting or reauthorizing.
            self.stop(1)

    @staticmethod
    def valid_path(path):
        return (isinstance(path, str) and len(path) <= shared.MAX_TEXT_BYTES
                and path.startswith(shared.SYSTEMD_PATH + "/unit/")
                and shared.DBUS_OBJECT_PATH.fullmatch(path) is not None)

    def manager_event(self, _connection, sender, path, interface, member, parameters, _data):
        if (self.stopped or not self.owner or sender != self.owner
                or path != self.path or interface != shared.SYSTEMD_MANAGER):
            return
        relevant = True
        if member in ("UnitNew", "UnitRemoved"):
            if parameters.get_type_string() != "(so)" or parameters.get_size() > 2 * shared.MAX_TEXT_BYTES + 16:
                self.stop(1)
                return
            name, unit_path = parameters.unpack()
            if (not name or len(name.encode("utf-8")) > shared.MAX_TEXT_BYTES
                    or any(ord(char) < 32 or ord(char) == 127 for char in name)
                    or not self.valid_path(unit_path)):
                self.stop(1)
                return
            relevant = name in self.units or unit_path in self.paths.values()
            if member == "UnitRemoved" and not relevant:
                return
        elif member == "UnitFilesChanged":
            if parameters.get_type_string() != "()" or parameters.get_size() > 8:
                self.stop(1)
                return
        elif member == "Reloading":
            if parameters.get_type_string() != "(b)" or parameters.get_size() > 8:
                self.stop(1)
                return
            if parameters.unpack()[0]:
                return
        else:
            return
        if relevant:
            self.changed()
        # An arrival may use a previously unknown canonical alias. Resolve
        # only our fixed names; never enumerate or load the announced unit.
        self.reconcile()

    def properties_changed(self, _connection, sender, path, interface, member, parameters, _data):
        if (self.stopped or not self.owner or sender != self.owner
                or interface != shared.PROPERTIES_INTERFACE or member != "PropertiesChanged"
                or not self.valid_path(path)):
            return
        if path not in self.paths.values() and self.ready and not self.resolving:
            return
        try:
            if parameters.get_type_string() != "(sa{sv}as)" or parameters.get_size() > shared.UNIT_REPLY_BYTES:
                raise shared.SnapshotFailure("malformed", "Invalid unit notification")
            fields = parameters.get_child_value(1)
            invalidated = parameters.get_child_value(2)
            if (parameters.get_child_value(0).unpack() != shared.SYSTEMD_NAME + ".Unit"):
                return
            if fields.n_children() > 256 or invalidated.n_children() > 256:
                raise shared.SnapshotFailure("malformed", "Oversized unit notification")
            relevant = {"LoadState", "ActiveState", "SubState"}
            changed = False
            for index in range(fields.n_children()):
                item = fields.get_child_value(index)
                key = item.get_child_value(0)
                if key.get_size() > shared.MAX_TEXT_BYTES + 1:
                    raise shared.SnapshotFailure("malformed", "Oversized unit property")
                if key.unpack() in relevant:
                    value = item.get_child_value(1).get_variant()
                    if value.get_type_string() != "s" or value.get_size() > 65 or shared.UNIT_STATE_TOKEN.fullmatch(value.unpack()) is None:
                        raise shared.SnapshotFailure("malformed", "Invalid unit property")
                    changed = True
            for index in range(invalidated.n_children()):
                key = invalidated.get_child_value(index)
                if key.get_size() > shared.MAX_TEXT_BYTES + 1:
                    raise shared.SnapshotFailure("malformed", "Oversized invalidated unit property")
                changed = changed or key.unpack() in relevant
            if changed:
                self.changed()
        except shared.SnapshotFailure:
            self.stop(1)

    def reconcile(self):
        """Resolve at most two fixed-name passes for one in-flight event burst."""
        if self.stopped or not self.subscription_ready:
            return
        if self.resolving:
            self.resolve_again = True
            return
        self.resolving = True
        self.resolution_epoch += 1
        self.resolve_again = False
        self.resolve_round = 0
        self.resolve_deadline = min(self.deadline, time.monotonic() + 10) if not self.ready else time.monotonic() + 10
        self.resolve_cancel = self.Gio.Cancellable()
        self.resolve_source = self.GLib.timeout_add(max(1, int((self.resolve_deadline - time.monotonic()) * 1000)), self.resolve_timeout)
        self.resolve_pass()

    def resolve_timeout(self):
        self.resolve_source = 0
        self.stop(1)
        return self.GLib.SOURCE_REMOVE

    def resolve_pass(self):
        self.waiting = set(self.units)
        self.next_paths = {}
        for name in self.units:
            if self.stopped or time.monotonic() >= self.resolve_deadline:
                self.stop(1)
                return
            try:
                self.connection.call(self.subscribed_owner, self.path, shared.SYSTEMD_MANAGER, "GetUnit",
                    self.GLib.Variant("(s)", (name,)), self.GLib.VariantType.new("(o)"),
                    self.Gio.DBusCallFlags.NO_AUTO_START,
                    max(1, int((self.resolve_deadline - time.monotonic()) * 1000)),
                    self.resolve_cancel, self.unit_resolved, (self.resolution_epoch, self.resolve_round, name))
            except self.GLib.Error:
                self.stop(1)
                return

    def unit_resolved(self, connection, result, identity):
        epoch, round_id, name = identity
        if (self.stopped or not self.resolving or epoch != self.resolution_epoch
                or round_id != self.resolve_round or name not in self.waiting):
            return
        if time.monotonic() >= self.resolve_deadline:
            self.stop(1)
            return
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(o)" or reply.get_size() > shared.MAX_TEXT_BYTES + 8:
                self.stop(1)
                return
            path = reply.unpack()[0]
            if not self.valid_path(path):
                self.stop(1)
                return
        except self.GLib.Error as error:
            if self.Gio.dbus_error_get_remote_error(error) != "org.freedesktop.systemd1.NoSuchUnit":
                self.stop(1)
                return
            path = ""
        if time.monotonic() >= self.resolve_deadline:
            self.stop(1)
            return
        self.next_paths[name] = path
        self.waiting.remove(name)
        if self.waiting:
            return
        changed = self.paths != self.next_paths
        self.paths = self.next_paths
        if changed and self.ready:
            self.changed()
        if self.resolve_again:
            if self.resolve_round:
                self.stop(1)
                return
            self.resolve_again = False
            self.resolve_round = 1
            self.resolve_pass()
            return
        self.resolving = False
        self.GLib.source_remove(self.resolve_source)
        self.resolve_source = 0
        if not self.ready:
            try:
                self.connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                    "GetNameOwner", self.GLib.Variant("(s)", (self.name,)), self.GLib.VariantType.new("(s)"),
                    self.Gio.DBusCallFlags.NONE, max(1, int((self.deadline - time.monotonic()) * 1000)),
                    self.cancellable, self.final_owner, (self.owner_epoch, self.resolution_epoch))
            except self.GLib.Error:
                self.stop(1)

    def final_owner(self, connection, result, identity):
        owner_epoch, resolution_epoch = identity
        if (self.stopped or self.ready or self.resolving
                or resolution_epoch != self.resolution_epoch):
            return
        if not self.resolve_owner(connection, result, owner_epoch):
            return
        if self.owner != self.subscribed_owner:
            self.stop(1)
            return
        self.GLib.source_remove(self.deadline_source)
        self.deadline_source = 0
        self.ready = True
        self.write(self.record_prefix + "\tready")
        if self.dirty and not self.stopped:
            self.write(self.record_prefix + "\tchanged")
        self.dirty = False

    def close_connection(self):
        """Close only this sender's connection; never unsubscribe another client."""
        if self.connection is None or self.closing:
            return
        self.closing = True
        if self.connection.is_closed():
            self.cleanup_done = True
            if self.cleanup_loop is not None:
                self.cleanup_loop.quit()
            return

        def closed(connection, result, _data):
            try:
                connection.close_finish(result)
            except self.GLib.Error:
                if not connection.is_closed():
                    self.exit_code = 1
            self.cleanup_done = True
            if self.cleanup_loop is not None:
                self.cleanup_loop.quit()

        self.connection.close(None, closed, None)

    def run(self):
        if self.started:
            raise RuntimeError("Service monitors are single-use")
        self.started = True

        def expired():
            self.deadline_source = 0
            self.stop(1)
            return self.GLib.SOURCE_REMOVE

        def terminate():
            self.stop(0)
            return self.GLib.SOURCE_CONTINUE

        try:
            self.deadline = time.monotonic() + 10
            self.deadline_source = self.GLib.timeout_add(10000, expired)
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                self.sources.append(self.GLibUnix.signal_add(self.GLib.PRIORITY_DEFAULT, signum, terminate))
            address = self.Gio.dbus_address_get_for_bus_sync(self.Gio.BusType.SYSTEM, self.cancellable)
            if self.setting_up():
                self.connecting = True
                flags = self.Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | self.Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
                self.Gio.DBusConnection.new_for_address(address, flags, None, self.cancellable, self.connected, None)
                self.loop.run()
        except self.GLib.Error:
            self.stop(1)
        finally:
            self.stopped = True
            self.cancellable.cancel()
            if self.resolve_cancel is not None:
                self.resolve_cancel.cancel()
            if self.connection is not None:
                for subscription in self.subscriptions:
                    self.connection.signal_unsubscribe(subscription)
                if self.closed_handler:
                    self.connection.disconnect(self.closed_handler)
            for source in self.sources + [self.deadline_source, self.resolve_source]:
                if source:
                    self.GLib.source_remove(source)
            self.cleanup_loop = self.GLib.MainLoop()
            cleanup_expired = False

            def cleanup_timeout():
                nonlocal cleanup_expired
                cleanup_expired = True
                self.exit_code = 1
                self.cleanup_loop.quit()
                return self.GLib.SOURCE_REMOVE

            cleanup_source = self.GLib.timeout_add(1000, cleanup_timeout)
            self.close_connection()
            if not self.cleanup_done and (self.connection is not None or self.connecting):
                self.cleanup_loop.run()
            if not cleanup_expired:
                self.GLib.source_remove(cleanup_source)
        return self.exit_code
