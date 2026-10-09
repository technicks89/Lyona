"""Read-only system information: OS, CPU, memory, security, filesystems, encryption, hardware, screen lock."""

from __future__ import annotations

import errno
import json
import os
import re
import selectors
import shlex
import signal
import stat
import subprocess
import threading
import time
from dataclasses import dataclass, replace
from typing import Callable, Mapping

from . import regional_settings, shared


INFORMATION_UINT_MAX = (1 << 64) - 1
INFORMATION_MEMORY_KEYS = {
    "MemTotal": "memory-total-bytes", "MemAvailable": "memory-available-bytes",
    "SwapTotal": "swap-total-bytes", "SwapFree": "swap-free-bytes",
}

FILESYSTEM_OUTPUT_BYTES = 2 * 1024 * 1024

ENCRYPTION_RECORDS = 1024
SECURITY_FILES = {
    "selinux-runtime": ("/sys/fs/selinux/enforce", 1),
    "selinux-config": ("/etc/selinux/config", 64 * 1024),
    "secure-boot": ("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c", 5),
}


@dataclass(frozen=True)
class InformationState:
    """One independently readable information value, not yet a protocol row."""

    status: str
    value: str
    detail: str
    error_code: str = ""


def information_unknown(error: Exception) -> InformationState:
    """Normalize source failures without exposing source contents or exception text."""
    if isinstance(error, shared.SnapshotFailure):
        return InformationState(error.status, "unknown", error.detail, error.code)
    if isinstance(error, OSError):
        if error.errno in (errno.EACCES, errno.EPERM):
            return InformationState("restricted", "unknown", "Information source access denied", "permission-denied")
        if error.errno in (errno.ENOENT, errno.ENOTDIR):
            return InformationState("unsupported", "unknown", "Information source is absent", "missing-provider")
        return InformationState("unavailable", "unknown", "Information source could not be read", "internal")
    return InformationState("partial", "unknown", "Information source is malformed", "malformed")


def information_text(value: object, detail: str) -> InformationState:
    """Validate bounded printable display text without truncating a malformed field."""
    if not isinstance(value, str) or not value.strip():
        raise shared.SnapshotFailure("malformed", "Information text is missing or invalid")
    if len(value) > shared.MAX_TEXT_BYTES or not value.isprintable() or len(value.encode("utf-8")) > shared.MAX_TEXT_BYTES:
        raise shared.SnapshotFailure("malformed", "Information text is oversized or undisplayable")
    return InformationState("available", value, detail)


def information_number(value: object, detail: str) -> InformationState:
    """Keep counters exact as canonical unsigned 64-bit decimal text."""
    if type(value) is not int or not 0 <= value <= INFORMATION_UINT_MAX:
        raise shared.SnapshotFailure("malformed", "Information counter is invalid or overflowing")
    return InformationState("available", str(value), detail)


def information_fields(data: bytes, keys: Mapping[str, str], separator: str,
                       decode: Callable[[str, str], InformationState]) -> dict[str, InformationState]:
    """Isolate duplicate, missing, and malformed allowlisted fields from their peers."""
    result = {}
    seen = set()
    encoded_keys = {key.encode("ascii"): key for key in keys}
    for line in data.splitlines():
        raw_key, found, value = line.partition(separator.encode("ascii"))
        key = encoded_keys.get(raw_key)
        if key is None:
            continue
        identifier = keys[key]
        try:
            if not found or key in seen:
                raise shared.SnapshotFailure("malformed", "Duplicate or malformed information field")
            result[identifier] = decode(key, value.decode("utf-8"))
        except (shared.SnapshotFailure, UnicodeError, ValueError) as error:
            result[identifier] = information_unknown(error)
        seen.add(key)
    for identifier in keys.values():
        if identifier not in result:
            result[identifier] = InformationState("partial", "unknown", "Information field was not reported", "missing-provider")
    return result


def parse_os_information(data: bytes) -> dict[str, InformationState]:
    """Read only the display keys; shell-like quoting never executes anything.

    Sync Sprint 2 S2-01 (#277): upstream maps only PRETTY_NAME -> os-name and
    VERSION_ID -> os-version, which renders "unknown" on Arch/CachyOS -- both
    are rolling releases with no VERSION_ID. Read BUILD_ID too (Arch's
    os-release sets it to "rolling") and fall back to it only when
    VERSION_ID itself was not reported, never overriding a real value.
    """
    def decode(key, value):
        fields = shlex.split(key + "=" + value, comments=False)
        if len(fields) != 1 or not fields[0].startswith(key + "="):
            raise shared.SnapshotFailure("malformed", "Malformed OS information field")
        return information_text(fields[0][len(key) + 1:], "Operating system identity")

    fields = information_fields(data, {"PRETTY_NAME": "os-name", "VERSION_ID": "os-version",
                                       "BUILD_ID": "os-build"}, "=", decode)
    if fields["os-version"].status != "available" and fields["os-build"].status == "available":
        fields["os-version"] = fields["os-build"]
    del fields["os-build"]
    return fields


def parse_memory_information(data: bytes) -> dict[str, InformationState]:
    """Accept only decimal kernel kB values and check the exact 1024-byte conversion."""
    def decode(_key, value):
        match = re.fullmatch(r"[ \t]*([0-9]{1,20})[ \t]+kB[ \t]*", value)
        if match is None:
            raise shared.SnapshotFailure("malformed", "Malformed memory information field")
        return information_number(int(match[1]) * 1024, "Memory bytes at this read")

    return information_fields(data, INFORMATION_MEMORY_KEYS, ":", decode)


def parse_cpu_information(data: bytes) -> dict[str, InformationState]:
    """Use the first x86_64 model-name field, never a later processor's fallback."""
    for line in data.splitlines():
        key, found, value = line.partition(b":")
        if key.strip() == b"model name":
            if not found:
                raise shared.SnapshotFailure("malformed", "Malformed processor model field")
            return {"cpu-model": information_text(value.decode("utf-8").strip(), "Processor model")}
    return {"cpu-model": InformationState("partial", "unknown", "Processor model was not reported", "missing-provider")}


def read_local_information() -> dict[str, InformationState]:
    """Read fixed local sources once; no service, subprocess, journal, or mutation."""
    result = {}
    sources = (
        ("/etc/os-release", 64 * 1024, parse_os_information, ("os-name", "os-version")),
        ("/proc/cpuinfo", 4 * 1024 * 1024, parse_cpu_information, ("cpu-model",)),
        ("/proc/meminfo", 1024 * 1024, parse_memory_information, tuple(INFORMATION_MEMORY_KEYS.values())),
    )
    for path, limit, parse, identifiers in sources:
        try:
            with open(path, "rb") as source:
                data = source.read(limit + 1)
            if len(data) > limit:
                raise shared.SnapshotFailure("malformed", "Information source exceeds its byte limit")
            result.update(parse(data))
        except (OSError, UnicodeError, shared.SnapshotFailure) as error:
            result.update((identifier, information_unknown(error)) for identifier in identifiers)
    try:
        identity = os.uname()
    except OSError as error:
        result.update((identifier, information_unknown(error)) for identifier in ("kernel-release", "architecture"))
    else:
        for attribute, identifier in (("release", "kernel-release"), ("machine", "architecture")):
            try:
                result[identifier] = information_text(getattr(identity, attribute, None), "Kernel identity")
            except (shared.SnapshotFailure, UnicodeError) as error:
                result[identifier] = information_unknown(error)
    try:
        count = os.cpu_count()
        if count is None:
            raise shared.SnapshotFailure("missing-provider", "Logical processor count was not reported")
        if type(count) is not int or count <= 0:
            raise shared.SnapshotFailure("malformed", "Logical processor count is invalid")
        result["logical-cpus"] = information_number(count, "Logical processors")
    except (OSError, shared.SnapshotFailure) as error:
        result["logical-cpus"] = information_unknown(error)
    try:
        clock = getattr(time, "CLOCK_BOOTTIME", None)
        if clock is None:
            raise shared.SnapshotFailure("unsupported", "Boot-time clock is unavailable", "unsupported")
        uptime = time.clock_gettime(clock)
        if type(uptime) not in (int, float) or not 0 <= uptime < (1 << 64):
            raise shared.SnapshotFailure("malformed", "Boot-time clock returned an invalid counter")
        result["uptime-seconds"] = information_number(int(uptime), "Whole seconds since boot, including suspend")
    except (OSError, shared.SnapshotFailure) as error:
        result["uptime-seconds"] = information_unknown(error)
    return result


def read_security_bytes(kind: str) -> bytes:
    """Read one allowlisted source once, including an overflow-detection byte."""
    if not isinstance(kind, str) or kind not in SECURITY_FILES:
        raise shared.SnapshotFailure("malformed", "Unknown security information source")
    path, limit = SECURITY_FILES[kind]
    with open(path, "rb") as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise shared.SnapshotFailure("malformed", "Security information source exceeds its byte limit")
    return data


def read_selinux_status() -> InformationState:
    """Use runtime enforcement; only an absent interface permits config fallback."""
    try:
        try:
            runtime = read_security_bytes("selinux-runtime")
        except OSError as error:
            if error.errno not in (errno.ENOENT, errno.ENOTDIR):
                raise
        else:
            if runtime not in (b"0", b"1"):
                raise shared.SnapshotFailure("malformed", "SELinux runtime state is malformed")
            return InformationState("available", "enforcing" if runtime == b"1" else "permissive",
                                    "SELinux kernel enforcement state")
        data = read_security_bytes("selinux-config")
        lines = []
        for line in data.splitlines():
            key, separator, value = line.partition(b"=")
            lines.append(key.strip() + separator + value)

        def decode(key, value):
            fields = shlex.split(key + "=" + value.lstrip(), comments=True)
            if len(fields) != 1 or not fields[0].startswith(key + "="):
                raise shared.SnapshotFailure("malformed", "SELinux configuration is malformed")
            mode = fields[0][len(key) + 1:]
            if mode != "disabled":
                raise shared.SnapshotFailure("malformed", "SELinux configuration does not establish disabled runtime state")
            return InformationState("available", "disabled", "SELinux is configured disabled and its runtime interface is absent")

        state = information_fields(b"\n".join(lines), {"SELINUX": "selinux"}, "=", decode)["selinux"]
        return replace(state, status="unsupported") if state.error_code == "missing-provider" else state
    except (OSError, shared.SnapshotFailure) as error:
        return information_unknown(error)


def read_secure_boot_status() -> InformationState:
    """Read only the fixed EFI variable; absence or denial never means disabled."""
    try:
        directory = os.stat("/sys/firmware/efi/efivars")
        if not stat.S_ISDIR(directory.st_mode):
            raise shared.SnapshotFailure("malformed", "EFI variables source is not a directory")
        try:
            data = read_security_bytes("secure-boot")
        except OSError as error:
            if error.errno in (errno.ENOENT, errno.ENOTDIR):
                raise shared.SnapshotFailure("missing-provider", "Secure Boot variable is absent on EFI", "partial") from error
            raise
        if len(data) != 5 or data[4] not in (0, 1):
            raise shared.SnapshotFailure("malformed", "Secure Boot variable is malformed")
        return InformationState("available", "enabled" if data[4] else "disabled", "EFI Secure Boot variable")
    except (OSError, shared.SnapshotFailure) as error:
        return information_unknown(error)


@dataclass(frozen=True)
class FilesystemRow:
    """A mount-ID-keyed observation; paths are display text, never action input."""

    mount_id: str
    status: str
    source: str
    target: str
    fstype: str
    size_bytes: str
    used_bytes: str
    available_bytes: str
    detail: str


@dataclass(frozen=True)
class FilesystemInformation:
    summary: InformationState
    rows: tuple[FilesystemRow, ...] = ()


def parse_storage_json(data: bytes, label: str) -> dict:
    """Decode capped storage JSON without ambiguous keys or non-JSON numbers."""
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result

    def invalid_constant(_value):
        raise ValueError("Invalid JSON number")

    if len(data) > FILESYSTEM_OUTPUT_BYTES:
        raise shared.SnapshotFailure("malformed", f"{label} output exceeds its byte limit")
    try:
        document = json.loads(data.decode("utf-8"), object_pairs_hook=pairs, parse_constant=invalid_constant)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise shared.SnapshotFailure("malformed", f"{label} output is not valid bounded JSON") from error
    if not isinstance(document, dict):
        raise shared.SnapshotFailure("malformed", f"{label} inventory is malformed")
    return document


def parse_filesystem_information(data: bytes) -> FilesystemInformation:
    """Validate the fixed findmnt JSON inventory and retain only unambiguous rows."""
    document = parse_storage_json(data, "Filesystem")
    if not isinstance(document, dict) or not isinstance(document.get("filesystems"), list):
        raise shared.SnapshotFailure("malformed", "Filesystem inventory is missing")
    pending = list(reversed(document["filesystems"]))
    seen, rows = set(), {}
    partial = False
    while pending:
        item = pending.pop()
        if not isinstance(item, dict):
            partial = True
            continue
        children = item.get("children", [])
        if isinstance(children, list):
            pending.extend(reversed(children))
        else:
            partial = True
        try:
            identifier = information_number(item.get("id"), "Mount identity").value
        except shared.SnapshotFailure:
            partial = True
            continue
        if identifier in seen:
            rows.pop(identifier, None)
            partial = True
            continue
        if len(seen) >= shared.FILESYSTEM_RECORDS:
            raise shared.SnapshotFailure("malformed", "Filesystem inventory exceeds its record limit")
        seen.add(identifier)
        display = []
        try:
            for key in ("source", "target", "fstype"):
                value = item.get(key)
                if not isinstance(value, str) or not value:
                    raise ValueError("Missing display field")
                value.encode("utf-8")  # Reject escaped surrogates before sanitization.
                display.append(shared.clean_text("".join(char if char.isprintable() else " " for char in value)))
        except (ValueError, UnicodeError):
            partial = True
            continue
        counters = []
        for key in ("size", "used", "avail"):
            try:
                counters.append(information_number(item.get(key), "Filesystem bytes").value)
            except shared.SnapshotFailure:
                counters.append("unknown")
        complete = "unknown" not in counters
        partial = partial or not complete
        rows[identifier] = FilesystemRow(identifier, "available" if complete else "partial", *display, *counters,
            "Filesystem bytes at this read" if complete else "Some filesystem byte counts could not be read")
    ordered = tuple(rows[key] for key in sorted(rows, key=int))
    summary = (InformationState("partial", "unknown", "Filesystem inventory is incomplete", "malformed") if partial
        else information_number(len(ordered), "Mounted real filesystems"))
    return FilesystemInformation(summary, ordered)


def parse_root_encryption(data: bytes) -> InformationState:
    """Require a complete root-device ancestry; ambiguous evidence stays unknown."""
    def malformed():
        return shared.SnapshotFailure("malformed", "Root block-device topology is incomplete or inconsistent")

    def token(value):
        if (not isinstance(value, str) or not value or len(value) > shared.MAX_TEXT_BYTES
                or not value.isprintable()):
            raise malformed()
        try:
            if len(value.encode("utf-8")) > shared.MAX_TEXT_BYTES:
                raise malformed()
        except UnicodeError as error:
            raise malformed() from error
        return value

    document = parse_storage_json(data, "Root encryption")
    if not isinstance(document.get("blockdevices"), list):
        raise malformed()
    pending = [(item, None) for item in document["blockdevices"]]
    nodes, parents, aliases, alias_owners = {}, {}, {}, {}
    roots, top_level = set(), set()
    while pending:
        item, parent = pending.pop()
        if not isinstance(item, dict) or not all(key in item for key in ("name", "type", "fstype", "mountpoints", "pkname")):
            raise malformed()
        name, device_type = token(item["name"]), token(item["type"])
        fstype = None if item["fstype"] is None else token(item["fstype"])
        mounts = item["mountpoints"]
        children = item.get("children", [])
        if not isinstance(mounts, list) or not isinstance(children, list):
            raise malformed()
        mounts = frozenset(token(mount) for mount in mounts if mount is not None)
        metadata = (device_type, fstype, mounts)
        if name in nodes:
            if nodes[name] != metadata:
                raise malformed()
        else:
            if len(nodes) >= ENCRYPTION_RECORDS:
                raise malformed()
            nodes[name] = metadata
            parents[name] = set()
        if "/" in mounts:
            roots.add(name)
        # lsblk NAME uses a mapper alias, but PKNAME uses the parent's kernel
        # name. The nested tree supplies the edge; each observed kernel alias
        # must identify exactly one consistent parent, including repeated rows.
        if parent is None:
            if item["pkname"] is not None:
                raise malformed()
            top_level.add(name)
        else:
            kernel_parent = token(item["pkname"])
            if (parent in aliases and aliases[parent] != kernel_parent
                    or kernel_parent in alias_owners and alias_owners[kernel_parent] != parent):
                raise malformed()
            aliases[parent] = kernel_parent
            alias_owners[kernel_parent] = parent
            parents[name].add(parent)
        pending.extend((child, name) for child in children)
    if not roots:
        raise malformed()
    for name, (device_type, _fstype, _mounts) in nodes.items():
        if name in top_level and parents[name]:
            raise malformed()
        if name in aliases and aliases[name] != name:
            # Only device-mapper nodes have a distinct NAME and dm-N KNAME.
            if (re.fullmatch(r"dm-[0-9]+", aliases[name]) is None
                    or device_type in ("disk", "rom", "loop")
                    or aliases[name] in nodes):
                raise malformed()
    # Resolve the entire graph iteratively. Each node is visited once, so
    # repeated multi-parent devices do not cause exponential path enumeration.
    visiting, resolved = set(), {}
    for start in nodes:
        stack = [(start, False)]
        while stack:
            name, finishing = stack.pop()
            if name in resolved:
                continue
            if not finishing:
                if name in visiting:
                    raise malformed()
                visiting.add(name)
                stack.append((name, True))
                stack.extend((parent, False) for parent in parents[name])
                continue
            visiting.remove(name)
            device_type, fstype, _mounts = nodes[name]
            if not parents[name]:
                # lsblk cannot establish a loop device's backing-file ancestry
                # or the missing dependencies of a top-level mapper/partition.
                paths = 1 if device_type in ("disk", "rom") else 0
            else:
                paths = 0
                for parent in parents[name]:
                    if resolved[parent] == 0:
                        paths = 0
                        break
                    paths |= resolved[parent]
            if paths and (device_type == "crypt" or fstype == "crypto_LUKS"):
                # Every resolved backing path crosses this encryption layer.
                paths = 2
            resolved[name] = paths
    evidence = 0
    for name in roots:
        if resolved[name] == 0 or nodes[name][1] in (None, "crypto_LUKS"):
            raise malformed()
        evidence |= resolved[name]
    if evidence not in (1, 2):
        raise malformed()
    return InformationState("available", "encrypted" if evidence == 2 else "unencrypted",
        "Resolved root block-device ancestry only; file-level and hardware encryption are not assessed")


class HardwareRead(shared.ServiceRead):
    """Read two fixed hostname1 properties while preserving a validated peer."""

    label = "Hardware information"

    def __init__(self, Gio=None, GLib=None):
        super().__init__(Gio, GLib)
        self.values = {}
        self.waiting = set(shared.HARDWARE_INFORMATION_FIELDS)

    def fail(self, failure):
        if self.done:
            return
        for field in self.waiting:
            self.values[shared.HARDWARE_INFORMATION_FIELDS[field]] = information_unknown(failure)
        self.waiting.clear()
        self.finish(value=dict(self.values))

    def record(self, field, state):
        if not self.pending() or field not in self.waiting:
            return
        self.values[shared.HARDWARE_INFORMATION_FIELDS[field]] = state
        self.waiting.remove(field)
        if not self.waiting:
            self.finish(value=dict(self.values))

    def property_failure(self, error):
        if self.Gio.dbus_error_get_remote_error(error) == "org.freedesktop.DBus.Error.UnknownProperty":
            return shared.SnapshotFailure("unsupported", "Hardware information property is absent", "unsupported")
        return self.bus_failure(error)

    def connected(self, _source, result, _data):
        if not self.pending():
            return
        try:
            self.connection = self.Gio.bus_get_finish(result)
            self.connection.set_exit_on_close(False)
        except self.GLib.Error as error:
            self.fail(self.bus_failure(error))
            return
        for field in shared.HARDWARE_INFORMATION_FIELDS:
            if not self.pending():
                return
            try:
                self.connection.call("org.freedesktop.hostname1", "/org/freedesktop/hostname1",
                    shared.PROPERTIES_INTERFACE, "Get", self.GLib.Variant("(ss)", ("org.freedesktop.hostname1", field)),
                    self.GLib.VariantType.new("(v)"), self.Gio.DBusCallFlags.NONE,
                    max(1, int((self.deadline - time.monotonic()) * 1000)), self.cancellable, self.replied, field)
            except self.GLib.Error as error:
                self.record(field, information_unknown(self.property_failure(error)))

    def replied(self, connection, result, field):
        if not self.pending() or field not in self.waiting:
            return
        try:
            reply = connection.call_finish(result)
            if reply.get_type_string() != "(v)" or reply.get_size() > shared.MAX_TEXT_BYTES + 32:
                raise shared.SnapshotFailure("malformed", "Invalid hardware information reply")
            value = reply.get_child_value(0).get_variant()
            if value.get_type_string() != "s" or value.get_size() > shared.MAX_TEXT_BYTES + 1:
                raise shared.SnapshotFailure("malformed", "Invalid hardware information property")
            state = information_text(value.unpack(), "Hardware identity reported by hostname1")
        except self.GLib.Error as error:
            state = information_unknown(self.property_failure(error))
        except (shared.SnapshotFailure, UnicodeError) as error:
            state = information_unknown(error)
        self.record(field, state)


def read_hardware_information() -> dict[str, InformationState]:
    """Keep missing service bindings scoped without swallowing interruption."""
    try:
        return regional_settings.run_interruptible_read(HardwareRead())
    except shared.SnapshotFailure as error:
        return {identifier: information_unknown(error) for identifier in shared.HARDWARE_INFORMATION_FIELDS.values()}


def parse_screen_lock(data: bytes) -> InformationState:
    """Map only the versioned power helper's automatic-lock evidence."""
    failure = shared.SnapshotFailure("malformed", "Automatic lock evidence is malformed")
    if not isinstance(data, bytes) or len(data) > 8192 or not data.endswith(b"\n"):
        raise failure
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeError as error:
        raise failure from error
    if not lines:
        raise failure
    header = lines[0].split("\t")
    if (len(header) < 3 or header[:2] != ["power-protocol", "1"]
            or not re.fullmatch(r"[0-9]{1,10}", header[2]) or int(header[2]) > 2147483647):
        raise failure
    lock = None
    for line in lines[1:]:
        fields = line.split("\t")
        if fields[0] == "power-protocol":
            raise failure
        if fields[0] != "power-lock":
            continue
        if (lock is not None or len(fields) < 7
                or fields[1] not in ("available", "partial", "restricted", "unavailable")
                or fields[2] not in ("yes", "no") or fields[4] not in ("yes", "no")
                or not re.fullmatch(r"[0-9]{1,5}", fields[3]) or int(fields[3]) > 86400
                or fields[5] != "user-session"):
            raise failure
        information_text(fields[6], "Automatic lock evidence")
        lock = fields
    if lock is None:
        raise failure
    status, enabled, running = lock[1], lock[2], lock[4]
    detail = "Automatic screen locking from the shared power helper; not the current locked state"
    if status != "available":
        return InformationState(status, "unknown", detail)
    if enabled == "yes" and running == "no":
        return InformationState("partial", "unknown", "Automatic locking is configured but the locker is not running")
    return InformationState("available", "enabled" if enabled == "yes" else "disabled", detail)


def sibling_command(name: str) -> str:
    """A lyona command beside this package: scripts/ in a checkout, PREFIX/bin when installed."""
    parent = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    beside = os.path.join(parent, name)
    if os.path.exists(beside):
        return beside
    # PREFIX/lib/lyona/python -> PREFIX/bin
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(parent))), "bin", name)


def read_information_process(kind: str) -> FilesystemInformation | InformationState:
    """Collect one fixed information source with bounded owned-group cleanup."""
    duration = 3
    output_limit = FILESYSTEM_OUTPUT_BYTES
    environment = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"}
    if kind == "filesystem":
        label = "Filesystem"
        command = ["/usr/bin/findmnt", "--json", "--bytes", "--real", "--uniq", "--output",
                   "ID,SOURCE,TARGET,FSTYPE,SIZE,USED,AVAIL"]
        parse = parse_filesystem_information
    elif kind == "root-encryption":
        label = "Root encryption"
        command = ["/usr/bin/lsblk", "--json", "--output", "NAME,TYPE,FSTYPE,MOUNTPOINTS,PKNAME"]
        parse = parse_root_encryption
    elif kind == "screen-lock":
        label = "Automatic screen lock"
        command = [sibling_command("dwm-settings-power"), "power-lock-snapshot"]
        parse = parse_screen_lock
        duration = 10
        output_limit = 8192
        environment = dict(os.environ, PATH="/usr/bin:/bin", LANG="C", LC_ALL="C")
    else:
        raise shared.SnapshotFailure("malformed", "Unknown storage information source")

    def unknown(error):
        state = information_unknown(error)
        return FilesystemInformation(state) if kind == "filesystem" else state

    if (threading.current_thread() is not threading.main_thread()
            or signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL):
        return unknown(shared.SnapshotFailure("internal", f"{label} process ownership is unavailable", "unavailable"))
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
            raise shared.SnapshotFailure("timeout", f"{label} enumeration timed out", "unavailable")

    try:
        try:
            for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                handlers[number] = signal.signal(number, terminate)
            deadline = time.monotonic() + duration
            check_deadline()
            try:
                process = subprocess.Popen(["/usr/bin/timeout", "--signal=TERM", "--kill-after=1", str(duration)] + command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
                    env=environment)
            except FileNotFoundError as error:
                raise shared.SnapshotFailure("missing-provider", f"{label} command is unavailable", "unavailable") from error
            output = bytearray()
            received = 0
            with selectors.DefaultSelector() as selector:
                for stream in (process.stdout, process.stderr):
                    os.set_blocking(stream.fileno(), False)
                    selector.register(stream, selectors.EVENT_READ)
                while True:
                    check_deadline()
                    status = regional_settings.locale_process_status(process)
                    if status is not None and not selector.get_map():
                        break
                    for key, _events in selector.select(min(0.05, max(0, deadline - time.monotonic()))):
                        check_deadline()
                        try:
                            chunk = os.read(key.fd, min(65536, output_limit - received + 1))
                        except BlockingIOError:
                            continue
                        if not chunk:
                            selector.unregister(key.fileobj)
                            continue
                        received += len(chunk)
                        if received > output_limit:
                            raise shared.SnapshotFailure("malformed", f"{label} output exceeds its byte limit")
                        if key.fileobj is process.stdout:
                            output.extend(chunk)
            exit_code = status.si_status if status.si_code == os.CLD_EXITED else -status.si_status
            if exit_code in (124, 137, -signal.SIGKILL):
                raise shared.SnapshotFailure("timeout", f"{label} enumeration timed out", "unavailable")
            if exit_code == 127:
                raise shared.SnapshotFailure("missing-provider", f"{label} command is unavailable", "unavailable")
            if exit_code != 0:
                raise shared.SnapshotFailure("internal", f"{label} enumeration failed", "unavailable")
            try:
                result = parse(bytes(output))
            finally:
                check_deadline()
        finally:
            try:
                if process is not None:
                    try:
                        regional_settings.close_locale_process(process)
                    except shared.SnapshotFailure as error:
                        raise shared.SnapshotFailure(error.code, f"{label} process cleanup could not be confirmed",
                                              error.status) from error
            finally:
                for number, handler in handlers.items():
                    signal.signal(number, handler)
                if interrupted:
                    raise SystemExit(128 + interrupted)
    except shared.SnapshotFailure as error:
        return unknown(error)
    except OSError as error:
        return unknown(error)
    return result


def read_storage_information(kind: str) -> FilesystemInformation | InformationState:
    if kind not in ("filesystem", "root-encryption"):
        raise shared.SnapshotFailure("malformed", "Unknown storage information source")
    return read_information_process(kind)


def read_screen_lock() -> InformationState:
    """Reuse the power helper without querying another locker or GSettings source."""
    return read_information_process("screen-lock")


def read_filesystem_information() -> FilesystemInformation:
    """Read the fixed filesystem inventory, never a caller-selected command."""
    return read_storage_information("filesystem")


def read_root_encryption() -> InformationState:
    """Read root block-encryption evidence without requesting writes or elevation."""
    return read_storage_information("root-encryption")
