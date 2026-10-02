"""Time zones, locales, NTP and the regional preview: validation, reads, and the regional mutation client."""

from __future__ import annotations

import contextlib
import hashlib
import os
import re
import selectors
import signal
import subprocess
import threading
import time
from dataclasses import dataclass, replace
from datetime import timezone
from typing import Callable, Sequence

from . import native_operations, shared


REGIONAL_TIMEZONE_MAX = 255
REGIONAL_TIMEZONE_COUNT = 2048
REGIONAL_TIMEZONE_BYTES = 256 * 1024
REGIONAL_LOCALE_MAX = 128
REGIONAL_LOCALE_COUNT = 4096
REGIONAL_LOCALE_OUTPUT_BYTES = 2 * 1024 * 1024
REGIONAL_LOCALE_ARRAY_BYTES = 8192
REGIONAL_CHOICE_STREAM_BYTES = {"timezone": 512 * 1024, "locale": 1024 * 1024}
REGIONAL_PREVIEW_STREAM_BYTES = 8192
# Sync Sprint 1 S1-07 (#271): bounded ntp-sample CLI output.
NTP_SAMPLE_STREAM_BYTES = 1024
# Sync Sprint 1 S1-07 (#273): bounded time-status CLI output.
TIME_STATUS_STREAM_BYTES = 1024
NTP_SAMPLE_ERROR_CODES = frozenset(("missing-provider", "permission-denied", "unsupported",
                                  "timeout", "malformed", "internal"))
REGIONAL_LOCALE_KEYS = (
    "LANG", "LANGUAGE", "LC_CTYPE", "LC_NUMERIC", "LC_TIME", "LC_COLLATE",
    "LC_MONETARY", "LC_MESSAGES", "LC_PAPER", "LC_NAME", "LC_ADDRESS",
    "LC_TELEPHONE", "LC_MEASUREMENT", "LC_IDENTIFICATION",
)

REGIONAL_MUTATION_SECONDS = 60
REGIONAL_CALLBACK_LIMIT = 64


# Sync Phase 8 (docs/SYNC-P8-REGIONAL-READERS.md): five bounded, read-only
# `Gio` service readers -- system timezone/NTP, locale, the local
# AccountsService account list, CUPS's running state, and the PackageKit
# repository list. No mutation, no D-Bus write of any kind. Each is its own
# fresh ServiceRead subclass call, never a cached result, and each source
# fails independently (a timedate1 outage must not blank the account list).
# Wiring these into build_snapshot()'s output is Sync Phase 9's
# NativeSnapshotSources/build_native_snapshot() -- that function also emits
# the timezone-set/ntp-set/locale-set/*-open mutation and delegate actions,
# and calls read_fedora_identity() (Fedora-specific, replaced elsewhere in
# this file by require_mutation_safe()'s direct D-Bus version check), so it
# is not read-only-only material and does not belong in this phase.
def validate_timezone_name(value: object) -> str:
    """Validate a timezone identity without normalizing or resolving its path."""
    if (not isinstance(value, str) or not value
            or len(value) > REGIONAL_TIMEZONE_MAX or not value.isascii()
            or any(ord(char) < 32 or ord(char) == 127 for char in value)
            or any(part in ("", ".", "..") for part in value.split("/"))):
        raise shared.SnapshotFailure("malformed", "Invalid regional timezone identity")
    return value


def validate_timezone_choices(values: object) -> tuple[str, ...]:
    """Validate one complete unpacked ListTimezones reply and its payload bounds."""
    if not isinstance(values, (list, tuple)) or len(values) > REGIONAL_TIMEZONE_COUNT:
        raise shared.SnapshotFailure("malformed", "Invalid regional timezone list")
    result = tuple(validate_timezone_name(value) for value in values)
    if (len(set(result)) != len(result)
            or sum(len(value) for value in result) > REGIONAL_TIMEZONE_BYTES):
        raise shared.SnapshotFailure("malformed", "Duplicate or oversized timezone list")
    return result


def prepare_timezone_change(value: object, choices: object) -> str:
    """Require exact membership in the caller's fresh ListTimezones reply."""
    timezone = validate_timezone_name(value)
    if timezone not in validate_timezone_choices(choices):
        raise shared.SnapshotFailure("conflict", "The selected timezone is no longer available")
    return timezone


def validate_locale_name(value: object) -> str:
    """Validate a locale identity; installed availability needs a fresh allowlist."""
    if (not isinstance(value, str) or not value
            or len(value) > REGIONAL_LOCALE_MAX or not value.isascii()
            or any(char.isspace() or ord(char) < 32 or ord(char) == 127
                   for char in value)):
        raise shared.SnapshotFailure("malformed", "Invalid regional locale identity")
    return value


def validate_locale_choices(output: object) -> tuple[str, ...]:
    """Validate complete bounded locale -a stdout without stripping identities."""
    if not isinstance(output, bytes) or len(output) > REGIONAL_LOCALE_OUTPUT_BYTES:
        raise shared.SnapshotFailure("malformed", "Invalid regional locale output")
    try:
        text = output.decode("ascii")
    except UnicodeDecodeError as error:
        raise shared.SnapshotFailure("malformed", "Non-ASCII regional locale output") from error
    if not text:
        return ()
    lines = text.removesuffix("\n").split("\n", REGIONAL_LOCALE_COUNT)
    if len(lines) > REGIONAL_LOCALE_COUNT:
        raise shared.SnapshotFailure("malformed", "Too many regional locale choices")
    return validate_locale_catalog(lines)


def validate_locale_catalog(values: object) -> tuple[str, ...]:
    """Validate already decoded identities without rebuilding unbounded stdout."""
    if not isinstance(values, (list, tuple)) or len(values) > REGIONAL_LOCALE_COUNT:
        raise shared.SnapshotFailure("malformed", "Invalid regional locale catalog")
    result = tuple(validate_locale_name(value) for value in values)
    if len(set(result)) != len(result):
        raise shared.SnapshotFailure("malformed", "Duplicate regional locale choices")
    return result


@dataclass(frozen=True)
class LocaleConfiguration:
    """Canonical, fully displayable locale1 assignments, not an authorization."""

    assignments: tuple[str, ...]
    lang: str
    detail: str


def parse_locale_configuration(values: object) -> LocaleConfiguration:
    """Preserve the complete allowlisted locale array or reject it without truncation."""
    if not isinstance(values, (list, tuple)) or len(values) > len(REGIONAL_LOCALE_KEYS):
        raise shared.SnapshotFailure("malformed", "Invalid regional locale assignment array")
    assignments: dict[str, str] = {}
    total_bytes = 0
    for assignment in values:
        if not isinstance(assignment, str) or len(assignment) > shared.MAX_TEXT_BYTES:
            raise shared.SnapshotFailure("malformed", "Invalid regional locale assignment")
        try:
            encoded = assignment.encode("utf-8")
        except UnicodeEncodeError as error:
            raise shared.SnapshotFailure("malformed", "Non-UTF-8 locale assignment") from error
        total_bytes += len(encoded) + 1
        key, separator, value = assignment.partition("=")
        if (not separator or key not in REGIONAL_LOCALE_KEYS or key in assignments
                or len(encoded) > shared.MAX_TEXT_BYTES
                or total_bytes > REGIONAL_LOCALE_ARRAY_BYTES
                or not assignment.isprintable()):
            raise shared.SnapshotFailure("malformed", "Unsafe or oversized locale assignment")
        assignments[key] = value
    ordered = tuple(f"{key}={assignments[key]}" for key in REGIONAL_LOCALE_KEYS
                    if key in assignments)
    detail = ", ".join(f"{key}={assignments[key]}" for key in REGIONAL_LOCALE_KEYS[1:]
                       if assignments.get(key)) or "none"
    if len(detail.encode("utf-8")) > shared.MAX_TEXT_BYTES:
        raise shared.SnapshotFailure("malformed", "Locale overrides are too large to confirm safely")
    return LocaleConfiguration(ordered, assignments.get("LANG", "unknown"), detail)


def prepare_locale_change(
    values: object, argument: object, choice_output: object
) -> LocaleConfiguration:
    """Prepare only LANG using caller-supplied fresh reads, preserving every override."""
    if not isinstance(argument, str) or not argument.startswith("LANG="):
        raise shared.SnapshotFailure("malformed", "Only LANG=LOCALE is accepted")
    locale = validate_locale_name(argument[5:])
    choices = validate_locale_choices(choice_output)
    if locale not in choices:
        raise shared.SnapshotFailure("conflict", "The selected locale is no longer available")
    current = parse_locale_configuration(values)
    preserved = [value for value in current.assignments if not value.startswith("LANG=")]
    return parse_locale_configuration([f"LANG={locale}", *preserved])


def locale_change_matches(expected_values: object, observed_values: object) -> bool:
    """Compare effective LC values, permitting omission of redundant overrides."""
    expected = dict(value.split("=", 1) for value in
                    parse_locale_configuration(expected_values).assignments)
    observed = dict(value.split("=", 1) for value in
                    parse_locale_configuration(observed_values).assignments)
    if expected.get("LANG", "") != observed.get("LANG", ""):
        return False
    # LANGUAGE is a preference list, not an LC category with LANG fallback.
    # Only a pre-existing explicit assignment has a preservation requirement.
    if ("LANGUAGE" in expected
            and ("LANGUAGE" not in observed or expected["LANGUAGE"] != observed["LANGUAGE"])):
        return False
    return all((expected.get(key) or expected.get("LANG", ""))
               == (observed.get(key) or observed.get("LANG", ""))
               for key in REGIONAL_LOCALE_KEYS[2:])


def require_locale_service_arguments(configuration: LocaleConfiguration) -> None:
    """Keep broader readable state, but never send known-invalid localed values.

    systemd 259 validates every SetLocale value, including LANGUAGE, as a locale
    name. Do not omit an unsupported override to make an otherwise valid LANG
    selection writable. Installed aliases remain the platform's responsibility.
    """
    for assignment in parse_locale_configuration(configuration.assignments).assignments:
        value = assignment.split("=", 1)[1]
        if (not 1 <= len(value) < 128 or value in {".", ".."}
                or re.fullmatch(r"[A-Za-z0-9_.@-]+", value) is None):
            raise shared.SnapshotFailure("unsupported", "The locale service cannot accept the complete preserved assignment set; review locale configuration without dropping overrides", "unsupported")


@dataclass(frozen=True)
class RegionalTimeState:
    """Typed timedate1 state, independent of locale and mutation availability."""

    timezone: str
    can_ntp: bool
    ntp_enabled: bool
    ntp_synchronized: bool


def regional_string_array(values: object, count: int, field_bytes: int,
                          total_bytes: int, *, separators: bool = False) -> tuple[str, ...]:
    """Bound serialized string sizes before allocating Python copies of a reply."""
    if values.get_type_string() != "as" or values.n_children() > count:
        raise shared.SnapshotFailure("malformed", "Invalid regional string array")
    result = []
    size = 0
    for index in range(values.n_children()):
        child = values.get_child_value(index)
        # A serialized GVariant string includes its one terminating NUL byte.
        payload_bytes = child.get_size() - 1
        size += payload_bytes + int(separators)
        if payload_bytes > field_bytes or size > total_bytes:
            raise shared.SnapshotFailure("malformed", "Oversized regional string array")
        result.append(child.unpack())
    return tuple(result)


def decode_regional_reply(kind: str, reply: object) -> object:
    """Validate the exact reply signature and required regional property types."""
    if not isinstance(kind, str) or kind not in shared.REGIONAL_READ_REQUESTS:
        raise shared.SnapshotFailure("malformed", "Unknown regional read")
    if reply.get_type_string() != shared.REGIONAL_READ_REQUESTS[kind][-1]:
        raise shared.SnapshotFailure("malformed", "Unexpected regional reply signature")
    if kind == "timezone-choices":
        return validate_timezone_choices(regional_string_array(reply.get_child_value(0),
            REGIONAL_TIMEZONE_COUNT, REGIONAL_TIMEZONE_MAX, REGIONAL_TIMEZONE_BYTES))
    if kind == "locale-state":
        values = reply.get_child_value(0).get_variant()
        return parse_locale_configuration(regional_string_array(values,
            len(REGIONAL_LOCALE_KEYS), shared.MAX_TEXT_BYTES, REGIONAL_LOCALE_ARRAY_BYTES,
            separators=True))
    properties = reply.get_child_value(0)
    if properties.n_children() > shared.REGIONAL_TIME_PROPERTY_COUNT:
        raise shared.SnapshotFailure("malformed", "Too many timedate1 properties")
    keys = set()
    for index in range(properties.n_children()):
        key = properties.get_child_value(index).get_child_value(0)
        if key.get_size() > shared.MAX_TEXT_BYTES + 1 or key.unpack() in keys:
            raise shared.SnapshotFailure("malformed", "Duplicate or oversized timedate1 property name")
        keys.add(key.unpack())
    values = []
    for name, signature in (("Timezone", "s"), ("CanNTP", "b"),
                            ("NTP", "b"), ("NTPSynchronized", "b")):
        value = properties.lookup_value(name, None)
        if (value is None or value.get_type_string() != signature
                or (signature == "s" and value.get_size() > REGIONAL_TIMEZONE_MAX + 1)):
            raise shared.SnapshotFailure("malformed", "Missing or malformed timedate1 property")
        values.append(value.unpack())
    return RegionalTimeState(validate_timezone_name(values[0]), *values[1:])


@dataclass(frozen=True)
class RegionalPreview:
    action: str
    argument: str
    generation: str
    current: str
    target: str
    detail: str

    def fields(self) -> tuple[str, ...]:
        return ("preview", self.action, self.argument, self.generation,
                self.current, self.target, self.detail)


def validate_regional_argument(action: str, argument: object) -> str:
    """Validate one fixed action's selection before starting any preflight I/O."""
    if action == "timezone-set":
        return validate_timezone_name(argument)
    if action == "ntp-set" and isinstance(argument, str) and argument in ("enabled", "disabled"):
        return argument
    if action == "locale-set" and isinstance(argument, str) and argument.startswith("LANG="):
        return "LANG=" + validate_locale_name(argument[5:])
    raise shared.SnapshotFailure("malformed", "Invalid regional action or selected value")


def make_regional_preview(action: str, argument: object, state: object, choices=()) -> RegionalPreview:
    """Bind a selection to complete validated current state, without I/O."""
    argument = validate_regional_argument(action, argument)
    if action == "locale-set":
        if not isinstance(state, LocaleConfiguration):
            raise shared.SnapshotFailure("malformed", "Invalid regional locale state")
        current = parse_locale_configuration(state.assignments)
        catalog = validate_locale_catalog(choices)
        expected = prepare_locale_change(current.assignments, argument,
                                         ("\n".join(catalog) + ("\n" if catalog else "")).encode("ascii"))
        current_value, target, detail = current.lang, expected.lang, expected.detail
        source_fields = current.assignments
    else:
        if (not isinstance(state, RegionalTimeState)
                or any(type(value) is not bool for value in
                       (state.can_ntp, state.ntp_enabled, state.ntp_synchronized))):
            raise shared.SnapshotFailure("malformed", "Invalid regional time state")
        validate_timezone_name(state.timezone)
        if action == "timezone-set":
            target = prepare_timezone_change(argument, choices)
            current_value, detail = state.timezone, "System timezone"
            source_fields = (state.timezone,)
        else:
            if not state.can_ntp:
                raise shared.SnapshotFailure("unsupported", "No supported network time service is available", "unsupported")
            current_value = "enabled" if state.ntp_enabled else "disabled"
            target, detail = argument, "Network time synchronization setting"
            source_fields = ("yes", current_value)
    digest = hashlib.sha256(b"lyona-regional-preview-v1")
    for field in (action, argument, *source_fields):
        encoded = field.encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
    return RegionalPreview(action, argument, digest.hexdigest(), current_value, target, detail)


def require_regional_generation(preview: RegionalPreview, confirmed: object) -> None:
    """Future owners must call this with freshly collected preflight evidence."""
    if not isinstance(confirmed, str) or shared.JOURNAL_GENERATION_PATTERN.fullmatch(confirmed) is None:
        raise shared.SnapshotFailure("malformed", "Invalid regional confirmation generation")
    if confirmed != preview.generation:
        raise shared.SnapshotFailure("conflict", "Regional state changed; review a fresh confirmation")


def regional_choices(kind: str) -> tuple[str, ...]:
    if kind == "timezone":
        return validate_timezone_choices(RegionalRead("timezone-choices").run())
    if kind == "locale":
        return validate_locale_catalog(read_locale_choices())
    raise shared.SnapshotFailure("malformed", "Unknown regional choice catalog")


def read_regional_preview(action: str, argument: object) -> RegionalPreview:
    argument = validate_regional_argument(action, argument)
    state = RegionalRead("locale-state" if action == "locale-set" else "time-state").run()
    choices = regional_choices("locale" if action == "locale-set" else "timezone") if action != "ntp-set" else ()
    return make_regional_preview(action, argument, state, choices)


def regional_preflight_output(command: str, arguments: Sequence[str]) -> tuple[str, int]:
    """Fully buffer a bounded read-only stream; failures never leak partial rows."""
    choices = command == "regional-choices"
    if (choices and (len(arguments) != 1 or arguments[0] not in REGIONAL_CHOICE_STREAM_BYTES)
            or not choices and (command != "regional-preview" or len(arguments) != 2
                or arguments[0] not in {"timezone-set", "ntp-set", "locale-set"})):
        raise ValueError("invalid regional preflight command")
    header = f"{command}-protocol\t1\t0" + ("\t" + arguments[0] if choices else "")
    completion = "complete\t" + command
    limit = REGIONAL_CHOICE_STREAM_BYTES[arguments[0]] if choices else REGIONAL_PREVIEW_STREAM_BYTES
    try:
        if choices:
            records = [("choice", value) for value in sorted(regional_choices(arguments[0]))]
        else:
            records = [read_regional_preview(*arguments).fields()]
        for record in records:
            if any(not isinstance(field, str) or len(field.encode("utf-8")) > shared.MAX_TEXT_BYTES
                   or field and not field.isprintable() for field in record):
                raise shared.SnapshotFailure("malformed", "Undisplayable regional preflight field")
        output = "\n".join((header, *("\t".join(record) for record in records), completion)) + "\n"
        if len(output.encode("utf-8")) > limit:
            raise shared.SnapshotFailure("malformed", "Regional preflight stream is too large")
        return output, 0
    except (shared.SnapshotFailure, UnicodeError) as error:
        failure = error if isinstance(error, shared.SnapshotFailure) else shared.SnapshotFailure("malformed", "Non-UTF-8 regional preflight field")
        code = failure.code if failure.code in shared.JOURNAL_ERROR_CODES else "internal"
        detail = "".join(char if char.isprintable() else " " for char in failure.detail)
        return "\n".join((header, f"error\tregional\t{code}\t{detail}", completion)) + "\n", 1


class RegionalRead(shared.ServiceRead):
    """One fixed read with an aggregate connection, reply, and decoding deadline."""

    label = "Regional"

    def __init__(self, kind: str, Gio=None, GLib=None) -> None:
        if not isinstance(kind, str) or kind not in shared.REGIONAL_READ_REQUESTS:
            raise shared.SnapshotFailure("malformed", "Unknown regional read")
        self.kind = kind
        super().__init__(Gio, GLib)

    def connected(self, _source, result, _data) -> None:
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
            name, path, interface, method, signature, args, reply_type = shared.REGIONAL_READ_REQUESTS[self.kind]
            parameters = None if signature is None else self.GLib.Variant(signature, args)
            if not self.pending():
                return
            self.connection.call(name, path, interface, method, parameters,
                self.GLib.VariantType.new(reply_type), self.Gio.DBusCallFlags.NONE,
                max(1, int((self.deadline - time.monotonic()) * 1000)),
                self.cancellable, self.replied, None)
        except self.GLib.Error as error:
            self.finish(failure=self.bus_failure(error))

    def replied(self, connection, result, _data) -> None:
        if not self.pending():
            return
        try:
            value = decode_regional_reply(self.kind, connection.call_finish(result))
            if self.pending():
                self.finish(value=value)
        except self.GLib.Error as error:
            self.finish(failure=self.bus_failure(error))
        except shared.SnapshotFailure as error:
            if self.pending():
                self.finish(failure=error)


@dataclass(frozen=True)
class NtpSample:
    """The two explicitly sampled, non-emitting network time properties."""

    can_ntp: bool
    synchronized: bool


class NtpRead(shared.ServiceRead):
    """Read only the two non-emitting timedate1 properties under one deadline."""

    label = "Network time status"

    def __init__(self, Gio=None, GLib=None):
        super().__init__(Gio, GLib)
        self.values = {}
        self.waiting = {"CanNTP", "NTPSynchronized"}

    def connected(self, _source, result, _data):
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
            name, path = shared.REGIONAL_READ_REQUESTS["time-state"][:2]
            for field in ("CanNTP", "NTPSynchronized"):
                if not self.pending():
                    return
                self.connection.call(name, path, shared.PROPERTIES_INTERFACE, "Get",
                    self.GLib.Variant("(ss)", (name, field)), self.GLib.VariantType.new("(v)"),
                    self.Gio.DBusCallFlags.NONE, max(1, int((self.deadline - time.monotonic()) * 1000)),
                    self.cancellable, self.replied, field)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def replied(self, connection, result, field):
        if not self.pending() or field not in self.waiting:
            return
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(v)" or reply.get_size() > 32:
                raise shared.SnapshotFailure("malformed", "Invalid network time status reply")
            value = reply.get_child_value(0).get_variant()
            if value.get_type_string() != "b":
                raise shared.SnapshotFailure("malformed", "Invalid network time status property")
            self.values[field] = value.unpack()
            self.waiting.remove(field)
            if not self.waiting and self.pending():
                self.finish(NtpSample(self.values["CanNTP"], self.values["NTPSynchronized"]))
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))
        except shared.SnapshotFailure as error:
            if self.pending():
                self.fail(error)


def read_ntp_sample() -> NtpSample:
    """Return the NTP pair through the shared cooperative read boundary."""
    return run_interruptible_read(NtpRead())


def run_interruptible_read(read: shared.ServiceRead):
    """Cancel the asynchronous read instead of raising inside a GLib callback."""
    handlers = {}
    interrupted = False
    cancel_source = 0

    def cancel_read():
        nonlocal cancel_source
        cancel_source = 0
        read.fail(shared.SnapshotFailure("internal", f"{read.label} read was interrupted"))
        return read.GLib.SOURCE_REMOVE

    def cancel(_signum, _frame):
        nonlocal interrupted, cancel_source
        if interrupted:
            return
        interrupted = True
        # A quit before MainLoop.run() is lost. Dispatch on the context so a
        # signal in the startup gap cannot mark the reader done prematurely.
        cancel_source = read.GLib.idle_add(cancel_read, priority=read.GLib.PRIORITY_HIGH)

    try:
        for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            handlers[signum] = signal.signal(signum, cancel)
        return read.run()
    finally:
        for signum, handler in handlers.items():
            signal.signal(signum, handler)
        if cancel_source:
            read.GLib.source_remove(cancel_source)
        if interrupted:
            raise InterruptedError(f"{read.label} read was interrupted")


def ntp_sample_output() -> tuple[str, int]:
    """Publish one complete pair or one scoped error, never a partial sample."""
    try:
        sample = read_ntp_sample()
        if (not isinstance(sample, NtpSample) or type(sample.can_ntp) is not bool
                or type(sample.synchronized) is not bool):
            raise shared.SnapshotFailure("malformed", "Invalid network time sample")
        record = "sample\t" + ("yes" if sample.can_ntp else "no") + "\t" + ("yes" if sample.synchronized else "no")
        code = 0
    except shared.SnapshotFailure as failure:
        error_code = failure.code if failure.code in NTP_SAMPLE_ERROR_CODES else "internal"
        detail = "".join(char if char.isprintable() else " " for char in failure.detail)
        detail = shared.clean_text(detail.encode("utf-8", "replace").decode("utf-8"))
        record = f"error\tntp-sample\t{error_code}\t{detail or 'Network time read failed'}"
        code = 1
    output = "ntp-sample-protocol\t1\t0\n" + record + "\ncomplete\tntp-sample\n"
    if len(output.encode("utf-8")) > NTP_SAMPLE_STREAM_BYTES:
        raise OSError("Network time sample exceeds its output limit")
    return output, code


def time_status_output() -> tuple[str, int]:
    """Read one complete time configuration for event-driven reconciliation."""
    try:
        state = run_interruptible_read(RegionalRead("time-state"))
        if (not isinstance(state, RegionalTimeState)
                or any(type(value) is not bool for value in
                       (state.can_ntp, state.ntp_enabled, state.ntp_synchronized))):
            raise shared.SnapshotFailure("malformed", "Invalid time status")
        zone = validate_timezone_name(state.timezone)
        record = "time\t" + zone + "\t" + "\t".join("yes" if value else "no" for value in
            (state.can_ntp, state.ntp_enabled, state.ntp_synchronized))
        code = 0
    except shared.SnapshotFailure as failure:
        error_code = failure.code if failure.code in NTP_SAMPLE_ERROR_CODES else "internal"
        detail = "".join(char if char.isprintable() else " " for char in failure.detail)
        detail = shared.clean_text(detail.encode("utf-8", "replace").decode("utf-8"))
        record = f"error\ttime-status\t{error_code}\t{detail or 'Time status read failed'}"
        code = 1
    output = "time-status-protocol\t1\t0\n" + record + "\ncomplete\ttime-status\n"
    if len(output.encode("utf-8")) > TIME_STATUS_STREAM_BYTES:
        raise OSError("Time status exceeds its output limit")
    return output, code


class RegionalMutation(shared.ServiceRead):
    """Internal fixed service client; durable admission is a required caller hook.

    The fixed CLI owner uses this client; Settings origins remain gated. The
    caller must retain its native journal lease, checkpoint authorizing in
    before_send, checkpoint running in after_reply, and commit the result before
    releasing ownership.
    A sent timeout is ambiguous, not proof of failure or service cancellation.
    """

    label = "Regional operation"

    def __init__(self, action: str, argument: str, generation: str,
                 before_send: Callable[[RegionalPreview], None],
                 after_reply: Callable[[], None], Gio=None, GLib=None) -> None:
        self.action = action
        self.argument = validate_regional_argument(action, argument)
        if not isinstance(generation, str) or shared.JOURNAL_GENERATION_PATTERN.fullmatch(generation) is None:
            raise shared.SnapshotFailure("malformed", "Invalid regional confirmation generation")
        if not callable(before_send) or not callable(after_reply):
            raise ValueError("Regional operation requires durable lifecycle hooks")
        self.generation = generation
        self.before_send, self.after_reply = before_send, after_reply
        self.kind = "locale-state" if action == "locale-set" else "time-state"
        self.name, self.path = shared.REGIONAL_READ_REQUESTS[self.kind][:2]
        self.owner = ""
        self.sent = self.acknowledged = False
        self.local_interrupted = False
        self.dirty = False
        self.observed = self.expected = self.preview = None
        self.choices = ()
        self.hook_error = None
        self.subscriptions = []
        self.rules = []
        self.installed_rules = []
        self.closed_handler = 0
        super().__init__(Gio, GLib)

    def pending(self) -> bool:
        if not super().pending():
            return False
        if self.local_interrupted:
            self.fail(native_operations.regional_interruption_failure(self))
            return False
        return True

    def timeout_failure(self) -> shared.SnapshotFailure:
        detail = ("Regional operation timed out after dispatch; the outcome is unknown. Refresh state before a new confirmation"
                  if self.sent else "Regional operation preflight timed out; no change was sent")
        return shared.SnapshotFailure("timeout", detail, "unavailable")

    def request(self, name, path, interface, method, parameters, reply_type, handler,
                *, interactive=False, match_rule=None) -> None:
        if not self.pending():
            return

        def replied(connection, result, _data):
            if match_rule is None and not self.pending():
                return
            try:
                reply = connection.call_finish(result)
                if match_rule is not None:
                    # Pair only a successful AddMatch with RemoveMatch. An
                    # unrequested or rejected rule can belong to another user
                    # of this shared connection. Late acknowledgments perform
                    # cleanup only, never resume the operation.
                    if self.done:
                        self.remove_match(match_rule)
                        return
                    self.installed_rules.append(match_rule)
                if not self.pending():
                    return
                if reply.get_type_string() != reply_type:
                    raise shared.SnapshotFailure("malformed", "Unexpected regional operation reply")
                if self.pending():
                    handler(reply)
            except self.GLib.Error as error:
                if self.pending():
                    self.fail(self.bus_failure(error))
            except shared.SnapshotFailure as error:
                if self.pending():
                    self.fail(error)

        flags = (self.Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION
                 if interactive else self.Gio.DBusCallFlags.NONE)
        try:
            expected_type = self.GLib.VariantType.new(reply_type)
            remaining = max(1, int((self.deadline - time.monotonic()) * 1000))
            if not self.pending():
                return
            self.connection.call(name, path, interface, method, parameters,
                expected_type, flags, remaining,
                self.cancellable, replied, None)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def bus_request(self, method, value, reply_type, handler):
        self.request("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", method, self.GLib.Variant("(s)", (value,)),
            reply_type, handler)

    def bus_failure(self, error):
        name = self.Gio.dbus_error_get_remote_error(error)
        if (time.monotonic() < self.deadline
                and name == "org.freedesktop.DBus.Error.InteractiveAuthorizationRequired"):
            return shared.SnapshotFailure("permission-denied", "Regional authorization was not granted", "restricted")
        failure = super().bus_failure(error)
        if failure.code == "timeout":
            return self.timeout_failure()
        if self.sent and name is None:
            return shared.SnapshotFailure("interrupted", "Regional transport failed after dispatch; the outcome is unknown. Refresh state before retrying")
        return failure

    def remove_match(self, rule):
        with contextlib.suppress(self.GLib.Error):
            self.connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "RemoveMatch", self.GLib.Variant("(s)", (rule,)),
                None, self.Gio.DBusCallFlags.NONE, 1000, None, None, None)

    def read_state(self, handler, *, activate=False):
        _name, path, interface, method, signature, arguments, reply_type = shared.REGIONAL_READ_REQUESTS[self.kind]
        self.request(self.name if activate else self.owner, path, interface, method,
            self.GLib.Variant(signature, arguments), reply_type, handler)

    def connected(self, _source, result, _data) -> None:
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
            self.closed_handler = self.connection.connect("closed", lambda *_args: self.fail(
                shared.SnapshotFailure("interrupted", "Regional service connection was lost; refresh state before retrying")))
            # A fixed read may activate an idle platform service. Its result is
            # not confirmation evidence; the pinned, subscribed read below is.
            self.read_state(lambda _reply: self.resolve_owner(self.pinned), activate=True)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))

    def resolve_owner(self, handler):
        self.bus_request("GetNameOwner", self.name, "(s)", handler)

    def pinned(self, reply):
        value = reply.get_child_value(0)
        if value.get_size() > 256:
            raise shared.SnapshotFailure("malformed", "Invalid regional service owner")
        owner = value.unpack()
        if not self.Gio.dbus_is_unique_name(owner):
            raise shared.SnapshotFailure("malformed", "Invalid regional service owner")
        self.owner = owner
        specs = [
            (None, shared.PROPERTIES_INTERFACE, "PropertiesChanged", self.path, self.name,
             self.properties_changed,
             f"type='signal',sender='{owner}',interface='{shared.PROPERTIES_INTERFACE}',member='PropertiesChanged',path='{self.path}',arg0='{self.name}'"),
            ("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
             "/org/freedesktop/DBus", self.name, self.owner_changed,
             f"type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',path='/org/freedesktop/DBus',arg0='{self.name}'"),
        ]
        for sender, interface, member, path, arg0, callback, rule in specs:
            self.subscriptions.append(self.connection.signal_subscribe(sender, interface,
                member, path, arg0, self.Gio.DBusSignalFlags.NO_MATCH_RULE, callback, None))
            self.rules.append(rule)
        self.add_match(0)

    def add_match(self, index):
        if index < len(self.rules):
            rule = self.rules[index]
            self.request("org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "AddMatch", self.GLib.Variant("(s)", (rule,)),
                "()", lambda _reply: self.add_match(index + 1), match_rule=rule)
        else:
            self.resolve_owner(self.ready)

    def require_owner(self, reply):
        if reply.get_child_value(0).get_size() > 256 or reply.unpack()[0] != self.owner:
            raise shared.SnapshotFailure("conflict", "Regional service owner changed; refresh state before retrying")

    def ready(self, reply):
        self.require_owner(reply)
        if self.action == "timezone-set":
            self.request(self.owner, self.path, self.name, "ListTimezones", None,
                "(as)", self.catalog_read)
        else:
            self.read_state(self.preflight_read)

    def catalog_read(self, reply):
        self.choices = decode_regional_reply("timezone-choices", reply)
        self.read_state(self.preflight_read)

    def drain(self) -> bool:
        # Flush already queued notifications after synchronous journal work.
        # Never turn a signal flood into an unbounded nested event loop.
        context = self.loop.get_context()
        for _ in range(REGIONAL_CALLBACK_LIMIT):
            if not self.pending():
                return False
            if not context.pending():
                return True
            context.iteration(False)
        if self.pending() and context.pending():
            self.fail(shared.SnapshotFailure("conflict", "Regional state notifications did not settle; refresh before retrying"))
        return self.pending()

    def hook(self, callback, *args) -> bool:
        try:
            callback(*args)
        except Exception as error:
            # A failed durable checkpoint must never escape a GLib callback
            # and leave the loop able to send or publish a later success.
            self.hook_error = error
            self.fail(shared.SnapshotFailure("interrupted", "Regional operation checkpoint failed; inspect recovery before retrying"))
        return self.pending()

    def preflight_read(self, reply):
        state = decode_regional_reply(self.kind, reply)
        self.preview = make_regional_preview(self.action, self.argument, state, self.choices)
        require_regional_generation(self.preview, self.generation)
        self.expected = (parse_locale_configuration((self.argument, *(value for value in state.assignments
            if not value.startswith("LANG=")))) if self.action == "locale-set" else
            replace(state, timezone=self.argument) if self.action == "timezone-set" else
            replace(state, ntp_enabled=self.argument == "enabled"))
        if self.action == "locale-set":
            require_locale_service_arguments(self.expected)
        if not self.drain():
            return
        if self.dirty:
            raise shared.SnapshotFailure("conflict", "Regional state changed before dispatch; review a fresh confirmation")
        if not self.hook(self.before_send, self.preview) or not self.drain():
            return
        require_regional_generation(self.preview, self.generation)
        if self.dirty:
            raise shared.SnapshotFailure("conflict", "Regional state changed before dispatch; review a fresh confirmation")
        method, parameters = {
            "timezone-set": ("SetTimezone", lambda: self.GLib.Variant("(sb)", (self.argument, True))),
            "ntp-set": ("SetNTP", lambda: self.GLib.Variant("(bb)", (self.argument == "enabled", True))),
            "locale-set": ("SetLocale", lambda: self.GLib.Variant("(asb)", (self.expected.assignments, True))),
        }[self.action]
        arguments = parameters()
        self.GLib.source_remove(self.deadline_source)
        self.deadline = time.monotonic() + REGIONAL_MUTATION_SECONDS
        self.deadline_source = self.GLib.timeout_add(REGIONAL_MUTATION_SECONDS * 1000, self.expire)
        if not self.pending():
            return
        self.sent = True
        self.request(self.owner, self.path, self.name, method, arguments, "()",
            self.method_replied, interactive=True)

    def method_replied(self, _reply):
        self.acknowledged = True
        if self.hook(self.after_reply):
            self.read_state(self.verified)

    def matches(self, state):
        if self.action == "locale-set":
            return locale_change_matches(self.expected.assignments, state.assignments)
        if self.action == "timezone-set":
            return state.timezone == self.expected.timezone
        return state.can_ntp and state.ntp_enabled == self.expected.ntp_enabled

    def verified(self, reply):
        self.observed = decode_regional_reply(self.kind, reply)
        if not self.matches(self.observed):
            self.dirty = True
        self.resolve_owner(self.completed)

    def completed(self, reply):
        self.require_owner(reply)
        if not self.drain():
            return
        if self.dirty:
            raise shared.SnapshotFailure("conflict", "Regional state differs from the confirmed result; a concurrent writer may have changed or been overwritten. Refresh state before retrying")
        self.finish(value=self.observed)

    def owner_changed(self, _connection, _sender, _path, _interface, _member, parameters, _data):
        if self.pending():
            self.fail(shared.SnapshotFailure("interrupted" if self.sent else "conflict",
                "Regional service owner changed; the result cannot be confirmed. Refresh state before retrying"))

    def properties_changed(self, _connection, sender, _path, _interface, _member, parameters, _data):
        if not self.pending() or sender != self.owner:
            return
        try:
            if parameters.get_type_string() != "(sa{sv}as)" or parameters.get_size() > 16384:
                raise shared.SnapshotFailure("malformed", "Invalid regional notification")
            if parameters.get_child_value(0).unpack() != self.name:
                return
            changed = parameters.get_child_value(1)
            invalidated = regional_string_array(parameters.get_child_value(2),
                shared.REGIONAL_TIME_PROPERTY_COUNT, shared.MAX_TEXT_BYTES, 8192)
            if changed.n_children() > shared.REGIONAL_TIME_PROPERTY_COUNT:
                raise shared.SnapshotFailure("malformed", "Oversized regional notification")
            keys = set()
            for index in range(changed.n_children()):
                key = changed.get_child_value(index).get_child_value(0)
                if key.get_size() > shared.MAX_TEXT_BYTES + 1 or key.unpack() in keys:
                    raise shared.SnapshotFailure("malformed", "Invalid regional notification key")
                keys.add(key.unpack())
            relevant = ({"Locale"} if self.action == "locale-set" else
                        {"Timezone"} if self.action == "timezone-set" else {"NTP", "CanNTP"})
            if not relevant.intersection(keys.union(invalidated)):
                return
            if not self.sent or relevant.intersection(invalidated):
                self.dirty = True
                return
            for key in relevant.intersection(keys):
                value = changed.lookup_value(key, None)
                if key == "Locale":
                    state = parse_locale_configuration(regional_string_array(value,
                        len(REGIONAL_LOCALE_KEYS), shared.MAX_TEXT_BYTES, REGIONAL_LOCALE_ARRAY_BYTES, separators=True))
                    equivalent = self.matches(state)
                elif key == "Timezone":
                    equivalent = (value.get_type_string() == "s" and value.get_size() <= REGIONAL_TIMEZONE_MAX + 1
                                  and value.unpack() == self.expected.timezone)
                else:
                    equivalent = (value.get_type_string() == "b" and value.unpack()
                                  == (True if key == "CanNTP" else self.expected.ntp_enabled))
                if not equivalent:
                    self.dirty = True
        except shared.SnapshotFailure:
            self.dirty = True

    def run(self):
        if self.started:
            raise RuntimeError("Regional operations are single-use")
        if self.action == "locale-set":
            self.choices = validate_locale_catalog(read_locale_choices())
        try:
            return super().run()
        finally:
            if self.connection is not None:
                for subscription in self.subscriptions:
                    self.connection.signal_unsubscribe(subscription)
                if self.closed_handler:
                    self.connection.disconnect(self.closed_handler)
                for rule in self.installed_rules:
                    self.remove_match(rule)


def locale_process_status(process: subprocess.Popen):
    # Leave the child waitable so its PID/process-group ID cannot be reused
    # between observing exit and signaling any remaining group members.
    return os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)


def close_locale_process(process: subprocess.Popen) -> None:
    """Stop only our still-owned group, reap its leader, and close both pipes."""
    try:
        status = locale_process_status(process)
        if status is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            deadline = time.monotonic() + 1
            # Do not reap an early-exiting supervisor: a descendant may still
            # resist TERM, and the retained PID protects the final group signal.
            while time.monotonic() < deadline:
                time.sleep(min(0.02, max(0, deadline - time.monotonic())))
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
        # A separately bounded reap tolerates scheduler delay after KILL. A
        # kernel-stuck process is a cleanup failure, never a successful catalog.
        process.wait(timeout=1)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise shared.SnapshotFailure("timeout", "Locale process cleanup could not be confirmed",
                              "unavailable") from error
    finally:
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()


def read_locale_choices() -> tuple[str, ...]:
    """Collect one fresh system locale catalog, never a caller-selected command."""
    if (threading.current_thread() is not threading.main_thread()
            or signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL):
        raise shared.SnapshotFailure("internal", "Locale process ownership is unavailable", "unavailable")
    process = None
    handlers = {}
    interrupted = 0

    def terminate(number, _frame):
        nonlocal interrupted
        interrupted = interrupted or number

    def check_deadline():
        if interrupted:
            raise SystemExit(128 + interrupted)
        if time.monotonic() >= deadline:
            raise shared.SnapshotFailure("timeout", "Locale enumeration timed out", "unavailable")

    try:
        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            handlers[number] = signal.signal(number, terminate)
        deadline = time.monotonic() + 3
        check_deadline()
        try:
            # The independent timeout also bounds the fixed command if this
            # collector is killed before its finally block can execute. Avoid
            # Python preexec_fn callbacks in a process that can also use GIO.
            process = subprocess.Popen(["/usr/bin/timeout", "--signal=TERM",
                "--kill-after=1", "3", "/usr/bin/locale", "-a"],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                start_new_session=True, env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"})
        except FileNotFoundError as error:
            raise shared.SnapshotFailure("missing-provider", "Locale enumeration command is unavailable",
                                  "unavailable") from error
        output = bytearray()
        received = 0
        with selectors.DefaultSelector() as selector:
            for stream in (process.stdout, process.stderr):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ)
            while True:
                check_deadline()
                status = locale_process_status(process)
                if status is not None and not selector.get_map():
                    break
                for key, _events in selector.select(min(0.05, max(0, deadline - time.monotonic()))):
                    check_deadline()
                    try:
                        chunk = os.read(key.fd, min(65536, REGIONAL_LOCALE_OUTPUT_BYTES - received + 1))
                    except BlockingIOError:
                        continue
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    received += len(chunk)
                    if received > REGIONAL_LOCALE_OUTPUT_BYTES:
                        raise shared.SnapshotFailure("malformed", "Oversized locale enumeration output")
                    if key.fileobj is process.stdout:
                        output.extend(chunk)
        exit_code = status.si_status if status.si_code == os.CLD_EXITED else -status.si_status
        if exit_code in (124, 137, -signal.SIGKILL):
            raise shared.SnapshotFailure("timeout", "Locale enumeration timed out", "unavailable")
        if exit_code == 127:
            raise shared.SnapshotFailure("missing-provider", "Locale enumeration command is unavailable", "unavailable")
        if exit_code != 0:
            raise shared.SnapshotFailure("internal", "Locale enumeration failed", "unavailable")
        try:
            choices = validate_locale_choices(bytes(output))
        except shared.SnapshotFailure:
            check_deadline()
            raise
        check_deadline()
        return choices
    except OSError as error:
        raise shared.SnapshotFailure("internal", "Locale enumeration failed", "unavailable") from error
    finally:
        try:
            if process is not None:
                close_locale_process(process)
        finally:
            for number, handler in handlers.items():
                signal.signal(number, handler)
            # Termination must remain terminal even if group cleanup failed;
            # otherwise callers could catch a read failure and keep running.
            if interrupted:
                raise SystemExit(128 + interrupted)
