"""Constants, the shared failure type, and the D-Bus read base class every reader builds on."""

from __future__ import annotations

import re
import time


PROTOCOL_MAJOR = 1
PROTOCOL_MINOR = 0

MAX_TEXT_BYTES = 512

HARDWARE_INFORMATION_FIELDS = {
    "HardwareVendor": "hardware-vendor", "HardwareModel": "hardware-model",
}

FILESYSTEM_RECORDS = 256

MAX_LIST_RECORDS = 4096

REPOSITORY_MAX_ROWS = 512
REPOSITORY_MAX_BYTES = 384 * 1024

DELEGATED_ACTIONS = frozenset(("accounts-open", "password-open", "printers-open", "sources-open"))

JOURNAL_SEQUENCE_MAX = (1 << 64) - 1

JOURNAL_OPERATION_ID_PATTERN = re.compile(r"op-[0-9a-f]{32}")

JOURNAL_GENERATION_PATTERN = re.compile(r"[0-9a-f]{64}")

JOURNAL_PACKAGEKIT_PATH_PATTERN = re.compile(
    # PackageKit CreateTransaction returns a root-level ID (e.g. /18_adcbcaed),
    # not a child of the manager's /org/freedesktop/PackageKit object.
    r"/[0-9]{1,20}_[A-Za-z0-9_]{1,64}"
)
JOURNAL_RESTART_SYSTEM_STRENGTH = {
    "none": 0,
    "unknown": 1,
    "system": 2,
    "security-system": 3,
}

JOURNAL_RESTART_SESSION_STRENGTH = {
    "none": 0,
    "session": 1,
    "security-session": 2,
}

JOURNAL_OPERATION_ACTION_KINDS = {
    "updates-refresh": "refresh",
    "updates-install-all": "update",
    "timezone-set": "timezone",
    "ntp-set": "ntp",
    "locale-set": "locale",
    "accounts-open": "delegate",
    "password-open": "delegate",
    "printers-open": "delegate",
    "sources-open": "delegate",
}

JOURNAL_OPERATION_TERMINAL_STATES = frozenset(
    ("permission-denied", "canceled", "failed", "interrupted", "succeeded")
)
JOURNAL_ERROR_CODES = frozenset(
    (
        "network",
        "repository",
        "conflict",
        "signature",
        "package",
        "unsupported",
        "malformed",
        "missing-provider",
        "permission-denied",
        "canceled",
        "timeout",
        "interrupted",
        "internal",
    )
)

BOOT_ID_PATTERN = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
)

PACKAGEKIT_NAME = "org.freedesktop.PackageKit"
PACKAGEKIT_PATH = "/org/freedesktop/PackageKit"
PACKAGEKIT_INTERFACE = "org.freedesktop.PackageKit"
TRANSACTION_INTERFACE = "org.freedesktop.PackageKit.Transaction"
PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"

REGIONAL_READ_SECONDS = 10

REGIONAL_TIME_PROPERTY_COUNT = 64
REGIONAL_READ_REQUESTS = {
    "time-state": ("org.freedesktop.timedate1", "/org/freedesktop/timedate1",
                   PROPERTIES_INTERFACE, "GetAll", "(s)",
                   ("org.freedesktop.timedate1",), "(a{sv})"),
    "locale-state": ("org.freedesktop.locale1", "/org/freedesktop/locale1",
                     PROPERTIES_INTERFACE, "Get", "(ss)",
                     ("org.freedesktop.locale1", "Locale"), "(v)"),
    "timezone-choices": ("org.freedesktop.timedate1", "/org/freedesktop/timedate1",
                         "org.freedesktop.timedate1", "ListTimezones", None,
                         None, "(as)"),
}

ACCOUNTS_NAME = "org.freedesktop.Accounts"
ACCOUNTS_PATH = "/org/freedesktop/Accounts"
ACCOUNT_INTERFACE = "org.freedesktop.Accounts.User"

ACCOUNT_LIMIT = 256
ACCOUNT_LIST_BYTES = 256 * 1024

DBUS_OBJECT_PATH = re.compile(r"/(?:[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)*)?")

SYSTEMD_NAME = "org.freedesktop.systemd1"
SYSTEMD_PATH = "/org/freedesktop/systemd1"
SYSTEMD_MANAGER = "org.freedesktop.systemd1.Manager"
CUPS_UNITS = ("cups.service", "cups.socket")
# Sync Phase 9 (docs/SYNC-P9-REGIONAL-MUTATION.md §4): both entries are
# dispatchable from main() below, matching upstream. "security" is left out
# of SystemProviderDiscovery.qml's domainDefinition table only -- no provider,
# state, or action for a "security" domain exists anywhere in this file's
# protocol-minor table (Sync Phase 1's decision, still Not implemented
# upstream / out of scope), so wiring the watch half into Settings alone
# would stream state Settings never displays. The CLI/backend surface is
# distro-neutral and not the place to encode that UI-scope decision.
WATCH_UNIT_SETS = {"printers": CUPS_UNITS, "security": ("firewalld.service",)}

UNIT_REPLY_BYTES = 64 * 1024
UNIT_STATE_TOKEN = re.compile(r"[a-z][a-z-]{0,63}")

EXIT_SUCCESS = 1
G_MAXUINT = (1 << 32) - 1


class SnapshotFailure(Exception):
    """A normalized provider failure safe to expose in the protocol."""

    def __init__(self, code: str, detail: str, status: str = "partial") -> None:
        super().__init__(detail)
        self.code = code
        self.detail = clean_text(detail)
        self.status = status


class ServiceRead:
    """Shared single-use lifetime for bounded, asynchronous service readers."""

    label = "Service"
    seconds = REGIONAL_READ_SECONDS

    def __init__(self, Gio=None, GLib=None) -> None:
        if Gio is None or GLib is None:
            try:
                import gi
                gi.require_version("Gio", "2.0")
                from gi.repository import Gio, GLib
            except (ImportError, ValueError) as error:
                raise SnapshotFailure("missing-provider", "System Python GObject bindings are unavailable",
                                      "unavailable") from error
        self.Gio, self.GLib = Gio, GLib
        self.loop = GLib.MainLoop()
        self.cancellable = Gio.Cancellable()
        self.connection = None
        self.deadline = 0.0
        self.deadline_source = 0
        self.started = False
        self.done = False
        self.value = None
        self.failure = None

    def finish(self, value=None, failure=None) -> None:
        if self.done:
            return
        self.done = True
        self.value, self.failure = value, failure
        self.cancellable.cancel()
        self.loop.quit()

    def fail(self, failure: SnapshotFailure) -> None:
        self.finish(failure=failure)

    def timeout_failure(self) -> SnapshotFailure:
        return SnapshotFailure("timeout", f"{self.label} read timed out", "unavailable")

    def expire(self) -> bool:
        self.deadline_source = 0
        self.fail(self.timeout_failure())
        return self.GLib.SOURCE_REMOVE

    def pending(self) -> bool:
        if self.done:
            return False
        if time.monotonic() >= self.deadline:
            self.fail(self.timeout_failure())
            return False
        return True

    def bus_failure(self, error: Exception) -> SnapshotFailure:
        if time.monotonic() >= self.deadline:
            return self.timeout_failure()
        name = self.Gio.dbus_error_get_remote_error(error)
        code, status = {
            "org.freedesktop.DBus.Error.ServiceUnknown": ("missing-provider", "unavailable"),
            "org.freedesktop.DBus.Error.NameHasNoOwner": ("missing-provider", "unavailable"),
            "org.freedesktop.DBus.Error.UnknownObject": ("missing-provider", "unavailable"),
            "org.freedesktop.DBus.Error.AccessDenied": ("permission-denied", "restricted"),
            "org.freedesktop.DBus.Error.AuthFailed": ("permission-denied", "restricted"),
            "org.freedesktop.DBus.Error.InvalidArgs": ("malformed", "partial"),
            "org.freedesktop.DBus.Error.InvalidSignature": ("malformed", "partial"),
            "org.freedesktop.DBus.Error.UnknownMethod": ("unsupported", "unsupported"),
            "org.freedesktop.DBus.Error.UnknownInterface": ("unsupported", "unsupported"),
            "org.freedesktop.DBus.Error.Timeout": ("timeout", "unavailable"),
            "org.freedesktop.DBus.Error.TimedOut": ("timeout", "unavailable"),
            "org.freedesktop.DBus.Error.NoReply": ("timeout", "unavailable"),
        }.get(name, ("internal", "unavailable"))
        if (name is None and error.matches(self.Gio.io_error_quark(),
                                          self.Gio.IOErrorEnum.TIMED_OUT)):
            code, status = "timeout", "unavailable"
        return SnapshotFailure(code, f"{self.label} service read failed", status)

    def connected(self, _source, result, _data) -> None:
        raise NotImplementedError

    def run(self) -> object:
        if self.started:
            raise RuntimeError(f"{self.label} reads are single-use")
        self.started = True
        self.deadline = time.monotonic() + self.seconds
        try:
            self.deadline_source = self.GLib.timeout_add(self.seconds * 1000, self.expire)
            self.Gio.bus_get(self.Gio.BusType.SYSTEM, self.cancellable, self.connected, None)
            if not self.done:
                self.loop.run()
            if not self.done:
                self.fail(SnapshotFailure("internal", f"{self.label} read ended without a reply", "unavailable"))
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))
        finally:
            self.done = True
            self.cancellable.cancel()
            self.loop.quit()
            if self.deadline_source:
                self.GLib.source_remove(self.deadline_source)
                self.deadline_source = 0
            # bus_get returns a shared connection; never close another reader's bus.
        if self.failure:
            raise self.failure
        return self.value


# Sync Sprint 2 S2-02 (D-5, decided 2026-09-16): upstream's FirewalldRead
# only ever asks about firewalld.service. A default Arch/CachyOS install
# runs no firewall at all -- users pick ufw, firewalld, or raw nftables --
# so this is generalized to one parametrized reader over all three real,
# distinct systemd units rather than only ever reporting on firewalld.
FIREWALL_UNITS = {
    "firewalld": ("firewalld.service", "Firewalld"),
    "ufw": ("ufw.service", "ufw"),
    "nftables": ("nftables.service", "nftables"),
}

JOURNAL_TRANSITIONS = {
    "pending": frozenset(
        ("authorizing", "running", "canceled", "failed", "interrupted")
    ),
    "authorizing": frozenset(
        ("running", "permission-denied", "canceled", "failed", "interrupted")
    ),
    "running": frozenset(
        ("running", "cancel-requested", "succeeded", "failed", "interrupted")
    ),
    "cancel-requested": frozenset(
        ("cancel-requested", "canceled", "succeeded", "failed", "interrupted")
    ),
}


def clean_text(value: object, *, truncate: bool = True) -> str:
    text = str(value).replace("\t", " ").replace("\r", " ").replace("\n", " ")
    encoded = text.encode("utf-8", "replace")
    if len(encoded) <= MAX_TEXT_BYTES:
        return text
    if not truncate:
        raise SnapshotFailure("malformed", "PackageKit returned an oversized identity")
    encoded = encoded[:MAX_TEXT_BYTES]
    while True:
        try:
            return encoded.decode("utf-8")
        except UnicodeDecodeError:
            encoded = encoded[:-1]
