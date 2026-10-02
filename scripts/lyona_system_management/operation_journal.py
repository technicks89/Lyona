"""The durable operation journal: frames, files, directory layout, locks and operations."""

from __future__ import annotations

import contextlib
import errno
import fcntl
import hashlib
import os
import re
import stat
import struct
import time
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Iterable, Iterator, Mapping

from . import shared


JOURNAL_MAGIC = b"DWMJNL1\0"
JOURNAL_FRAME_MAJOR = 1
JOURNAL_FRAME_MINOR = 0
JOURNAL_FRAME_SIZE = 8192
JOURNAL_PAYLOAD_OFFSET = 64
JOURNAL_PAYLOAD_MAX = JOURNAL_FRAME_SIZE - JOURNAL_PAYLOAD_OFFSET
JOURNAL_FILE_SIZE = JOURNAL_FRAME_SIZE * 2

JOURNAL_LOCK_DEADLINE_SECONDS = 5
JOURNAL_TERMINAL_COUNT = 32
JOURNAL_CURSOR_NAME = "cursor"
JOURNAL_PATH_MAX = 4095
JOURNAL_COMPONENT_MAX = 255
JOURNAL_DIRECTORY_SUFFIX = ("lyona", "system-management")
JOURNAL_BOOT_ID_TEMPLATE = "00000000-0000-0000-0000-000000000000"
JOURNAL_RESTART_ALL_CLEAR_TAIL = ("-", "none", "none", "0", "no", "0")
JOURNAL_RESTART_ALL_CLEAR_SUFFIX = (
    "\t" + "\t".join(JOURNAL_RESTART_ALL_CLEAR_TAIL)
).encode("ascii")

JOURNAL_SLOT_PATTERN = re.compile(r"(?:0[0-9]|[12][0-9]|3[01])")

JOURNAL_TIMESTAMP_PATTERN = re.compile(
    r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
)

JOURNAL_RESTART_SYSTEM_VALUES = frozenset(shared.JOURNAL_RESTART_SYSTEM_STRENGTH)

JOURNAL_RESTART_SESSION_VALUES = frozenset(shared.JOURNAL_RESTART_SESSION_STRENGTH)

JOURNAL_OPERATION_STATES = frozenset(
    (
        "pending",
        "authorizing",
        "running",
        "cancel-requested",
        "permission-denied",
        "canceled",
        "failed",
        "interrupted",
        "succeeded",
    )
)

JOURNAL_DATA_NAMES = (
    "active",
    "restart",
    "handoff",
    *(f"terminal-{index:02d}" for index in range(JOURNAL_TERMINAL_COUNT)),
)
JOURNAL_NAMES = (*JOURNAL_DATA_NAMES, JOURNAL_CURSOR_NAME)
JOURNAL_ACTIVE_ADMISSION_COMMITS = 12
JOURNAL_OPERATION_ID_ATTEMPTS = 4
JOURNAL_CONTROL_ADMISSION_COMMITS = {
    # pending, three later nonterminal states, six strictly stronger restart
    # contributions, the terminal result, and the final empty active payload.
    "active": JOURNAL_ACTIVE_ADMISSION_COMMITS,
    # Each existing session/application bucket can be pruned at most once by
    # snapshots OR terminalization (no-op pruning writes nothing). One further
    # commit applies the new terminal contribution: at most three in total.
    "restart": 3,
    "handoff": 2,
    JOURNAL_CURSOR_NAME: 1,
}


class JournalFrameError(ValueError):
    """A journal frame failed canonical validation."""


class JournalRecordError(ValueError):
    """A journal control record failed canonical validation."""


class JournalFileError(OSError):
    """A journal file descriptor failed bounded validation or I/O."""


class JournalCommitError(JournalFileError):
    """A frame commit may have reached storage and requires recovery."""


class JournalLockError(JournalFileError):
    """The bounded journal directory lock could not be acquired or released."""


class JournalLayoutError(JournalFileError):
    """The fixed journal path set could not be opened or initialized safely."""


class JournalAdmissionError(RuntimeError):
    """A valid journal state cannot admit another operation."""


class CancelTargetUnavailable(JournalAdmissionError):
    """An exact cancellation target was rejected without an accepted request."""


@dataclass(frozen=True)
class JournalFrame:
    sequence: int
    payload: str


@dataclass(frozen=True)
class JournalHandoff:
    operation_id: str
    slot: int


@dataclass(frozen=True)
class JournalRestart:
    boot_id: str
    last_applied_operation_id: str | None
    system: str
    session: str
    session_cutoff: int
    application: bool
    application_cutoff: int


@dataclass(frozen=True)
class JournalOperation:
    operation_id: str
    action_id: str
    started_at: str
    finished_at: str | None
    kind: str
    state: str
    error_code: str | None
    detail: str
    generation: str | None
    transaction_path: str | None
    system_restart: str | None
    session_restart: str | None
    application_restart: bool | None
    boot_id: str | None
    terminal_monotonic: int | None
    slot: int


@dataclass(frozen=True)
class JournalState:
    cursor: int
    restart: JournalRestart
    active: JournalOperation | None
    handoff: JournalHandoff | None
    terminals: tuple[JournalOperation | None, ...]


@dataclass(frozen=True)
class JournalAdmission:
    """Validated journal state and its next reusable terminal slot."""

    state: JournalState
    slot: int
    operation_id: str


@dataclass
class JournalDirectoryChain:
    """Held root-to-journal directory descriptors and their child names."""

    path: str
    names: tuple[str, ...]
    descriptors: tuple[int, ...]
    closed: bool = False

    @property
    def directory_descriptor(self) -> int:
        if self.closed:
            raise JournalLayoutError("journal directory chain is closed")
        return self.descriptors[-1]

    def validate(self) -> None:
        validate_journal_directory_chain(self)

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        first_error = _close_descriptors(reversed(self.descriptors))
        if first_error is not None:
            raise JournalLayoutError(
                "journal directory chain close failed"
            ) from first_error

    def __enter__(self) -> JournalDirectoryChain:
        if self.closed:
            raise JournalLayoutError("journal directory chain is closed")
        return self

    def __exit__(self, _type: object, _value: object, _traceback: object) -> None:
        self.close()


@dataclass
class JournalDescriptorSet:
    """Fixed journal file identities retained across bounded lock intervals."""

    chain: JournalDirectoryChain
    _descriptors: dict[str, int]
    writable: bool
    closed: bool = False
    _exclusive: bool = False

    def descriptor(self, name: str) -> int:
        if self.closed:
            raise JournalLayoutError("journal descriptor set is closed")
        if not isinstance(name, str) or name not in self._descriptors:
            raise JournalLayoutError("journal descriptor name is invalid")
        return self._descriptors[name]

    def validate(self) -> None:
        if self.closed:
            raise JournalLayoutError("journal descriptor set is closed")
        self.chain.validate()
        directory_descriptor = self.chain.directory_descriptor
        for name in JOURNAL_NAMES:
            _validate_journal_path_identity(
                directory_descriptor,
                name,
                self.descriptor(name),
                JOURNAL_FILE_SIZE,
                writable=self.writable,
            )
        self.chain.validate()


def _close_descriptors(descriptors: Iterable[int]) -> OSError | None:
    """Close every descriptor and return the first close error, if any."""
    first_error: OSError | None = None
    for descriptor in descriptors:
        try:
            os.close(descriptor)
        except OSError as error:
            if first_error is None:
                first_error = error
    return first_error


def _absolute_path_components(path: str) -> tuple[str, ...]:
    if not isinstance(path, str) or not path.startswith("/") or path.startswith("//"):
        raise JournalLayoutError("journal state path must be absolute")
    if "\0" in path:
        raise JournalLayoutError("journal state path contains a forbidden byte")
    if path != "/" and os.path.normpath(path) != path:
        raise JournalLayoutError("journal state path must be canonical")
    try:
        encoded = path.encode("utf-8")
    except UnicodeEncodeError as error:
        raise JournalLayoutError("journal state path must be UTF-8") from error
    if not encoded or len(encoded) > JOURNAL_PATH_MAX:
        raise JournalLayoutError("journal state path is too long")
    components = tuple(component for component in path.split("/") if component)
    if any(
        len(component.encode("utf-8")) > JOURNAL_COMPONENT_MAX
        for component in components
    ):
        raise JournalLayoutError("journal state path component is too long")
    return components


def journal_directory_path(environment: Mapping[str, str] | None = None) -> str:
    """Resolve the canonical absolute journal directory from XDG state inputs."""
    source = os.environ if environment is None else environment
    state_home = source.get("XDG_STATE_HOME", "")
    if (
        isinstance(state_home, str)
        and state_home not in {"", "/"}
        and not state_home.startswith("//")
    ):
        state_home = state_home.rstrip("/")
    if not isinstance(state_home, str) or not state_home.startswith("/"):
        state_home = ""
    if not state_home:
        home = source.get("HOME", "")
        if not isinstance(home, str) or not home:
            raise JournalLayoutError("HOME is required for journal state")
        if isinstance(home, str) and home != "/":
            home = home.rstrip("/")
        state_home = os.path.join(home, ".local", "state")
    _absolute_path_components(state_home)
    path = os.path.join(state_home, *JOURNAL_DIRECTORY_SUFFIX)
    _absolute_path_components(path)
    return path


def _validate_directory_component(
    parent_descriptor: int,
    name: str,
    descriptor: int,
    *,
    private: bool,
) -> None:
    try:
        held = os.fstat(descriptor)
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
        descriptor_flags = fcntl.fcntl(descriptor, fcntl.F_GETFD)
        reachable = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    except (OSError, OverflowError) as error:
        raise JournalLayoutError(
            f"journal directory component {name} is unavailable"
        ) from error
    if (
        not stat.S_ISDIR(held.st_mode)
        or not stat.S_ISDIR(reachable.st_mode)
        or (held.st_dev, held.st_ino) != (reachable.st_dev, reachable.st_ino)
        or (flags & os.O_ACCMODE) == os.O_WRONLY
        or not descriptor_flags & fcntl.FD_CLOEXEC
    ):
        raise JournalLayoutError(f"journal directory component {name} is unsafe")
    if private and (
        held.st_uid != os.geteuid()
        or stat.S_IMODE(held.st_mode) != 0o700
        or reachable.st_uid != held.st_uid
        or stat.S_IMODE(reachable.st_mode) != 0o700
    ):
        raise JournalLayoutError(f"journal directory component {name} is not private")


def _sync_directory_descriptor(
    descriptor: int, *, allow_unreadable: bool = False
) -> bool:
    try:
        held = os.fstat(descriptor)
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
    except (OSError, OverflowError) as error:
        raise JournalLayoutError(
            "journal directory sync handle is unavailable"
        ) from error
    if not flags & os.O_PATH:
        try:
            os.fsync(descriptor)
        except OSError as error:
            raise JournalLayoutError("journal directory sync failed") from error
        return True
    try:
        sync_descriptor = os.open(
            ".",
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=descriptor,
        )
    except OSError as error:
        if allow_unreadable and error.errno in {errno.EACCES, errno.EPERM}:
            return False
        raise JournalLayoutError(
            "journal directory sync handle is unavailable"
        ) from error
    try:
        current = os.fstat(sync_descriptor)
        if (current.st_dev, current.st_ino) != (held.st_dev, held.st_ino):
            raise JournalLayoutError("journal directory sync identity changed")
        os.fsync(sync_descriptor)
    except OSError as error:
        if isinstance(error, JournalLayoutError):
            raise
        raise JournalLayoutError("journal directory sync failed") from error
    finally:
        try:
            os.close(sync_descriptor)
        except OSError as error:
            raise JournalLayoutError(
                "journal directory sync handle close failed"
            ) from error
    return True


def _chmod_directory_descriptor(descriptor: int, mode: int) -> None:
    """Change a held directory's mode without reopening its mutable pathname."""
    try:
        os.chmod(f"/proc/self/fd/{descriptor}", mode)
    except (OSError, ValueError) as error:
        raise JournalLayoutError("journal directory mode update failed") from error


def _mkdir_private_directory(parent_descriptor: int, name: str) -> None:
    """Create a mode-0700 directory without an umask interruption window."""
    previous_umask = os.umask(0)
    try:
        os.mkdir(name, 0o700, dir_fd=parent_descriptor)
    finally:
        os.umask(previous_umask)


def _open_directory_component(
    parent_descriptor: int, name: str, *, private: bool
) -> int:
    created = False
    try:
        os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
        exists = True
    except FileNotFoundError:
        exists = False
    except OSError as error:
        raise JournalLayoutError(
            f"journal directory component {name} lookup failed"
        ) from error
    if not exists:
        _sync_directory_descriptor(parent_descriptor)
        try:
            _mkdir_private_directory(parent_descriptor, name)
            created = True
        except FileExistsError:
            pass
        except OSError as error:
            raise JournalLayoutError(
                f"journal directory component {name} creation failed"
            ) from error
    try:
        descriptor = os.open(
            name,
            os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=parent_descriptor,
        )
    except OSError as error:
        raise JournalLayoutError(
            f"journal directory component {name} open failed"
        ) from error
    try:
        _validate_directory_component(
            parent_descriptor, name, descriptor, private=False
        )
        if created:
            _chmod_directory_descriptor(descriptor, 0o700)
            _validate_directory_component(
                parent_descriptor, name, descriptor, private=True
            )
        if private or created:
            readable_descriptor = os.open(
                ".",
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=descriptor,
            )
            readable = os.fstat(readable_descriptor)
            held = os.fstat(descriptor)
            if (readable.st_dev, readable.st_ino) != (held.st_dev, held.st_ino):
                os.close(readable_descriptor)
                raise JournalLayoutError(
                    f"journal directory component {name} identity changed"
                )
            os.close(descriptor)
            descriptor = readable_descriptor
        if created:
            _sync_directory_descriptor(descriptor)
            _sync_directory_descriptor(parent_descriptor)
        else:
            _sync_directory_descriptor(descriptor, allow_unreadable=not private)
            _sync_directory_descriptor(parent_descriptor, allow_unreadable=True)
        _validate_directory_component(
            parent_descriptor, name, descriptor, private=private or created
        )
    except OSError as error:
        try:
            os.close(descriptor)
        except OSError:
            pass
        if isinstance(error, JournalLayoutError):
            raise
        raise JournalLayoutError(
            f"journal directory component {name} initialization failed"
        ) from error
    return descriptor


def validate_journal_directory_chain(chain: JournalDirectoryChain) -> None:
    """Prove every retained child is still reachable from its held parent."""
    if chain.closed or len(chain.descriptors) != len(chain.names) + 1:
        raise JournalLayoutError("journal directory chain is invalid")
    try:
        root = os.fstat(chain.descriptors[0])
        root_flags = fcntl.fcntl(chain.descriptors[0], fcntl.F_GETFL)
        root_descriptor_flags = fcntl.fcntl(chain.descriptors[0], fcntl.F_GETFD)
    except (OSError, OverflowError) as error:
        raise JournalLayoutError("journal root descriptor is unavailable") from error
    if (
        not stat.S_ISDIR(root.st_mode)
        or (root_flags & os.O_ACCMODE) == os.O_WRONLY
        or not root_descriptor_flags & fcntl.FD_CLOEXEC
    ):
        raise JournalLayoutError("journal root descriptor is unsafe")
    for index, name in enumerate(chain.names):
        _validate_directory_component(
            chain.descriptors[index],
            name,
            chain.descriptors[index + 1],
            private=index == len(chain.names) - 1,
        )


def open_journal_directory_chain(path: str) -> JournalDirectoryChain:
    """Open or create a root-anchored journal directory descriptor chain."""
    names = _absolute_path_components(path)
    if not names:
        raise JournalLayoutError("journal directory path must not be root")
    descriptors: list[int] = []
    try:
        descriptors.append(
            os.open("/", os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        )
        for index, name in enumerate(names):
            descriptors.append(
                _open_directory_component(
                    descriptors[-1], name, private=index == len(names) - 1
                )
            )
        chain = JournalDirectoryChain(path, names, tuple(descriptors))
        chain.validate()
        return chain
    except (OSError, JournalLayoutError) as error:
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                pass
        if isinstance(error, JournalLayoutError):
            raise
        raise JournalLayoutError("journal directory chain open failed") from error


def open_journal_directory(
    environment: Mapping[str, str] | None = None,
) -> JournalDirectoryChain:
    """Resolve and open the fixed journal directory from XDG state inputs."""
    return open_journal_directory_chain(journal_directory_path(environment))


def _journal_payload_bytes(payload: str) -> bytes:
    if not isinstance(payload, str):
        raise JournalFrameError("journal payload must be text")
    if "\0" in payload or "\r" in payload or "\n" in payload:
        raise JournalFrameError("journal payload contains a forbidden byte")
    try:
        encoded = payload.encode("utf-8")
    except UnicodeEncodeError as error:
        raise JournalFrameError("journal payload is not UTF-8") from error
    if len(encoded) > JOURNAL_PAYLOAD_MAX:
        raise JournalFrameError("journal payload is too large")
    return encoded


def encode_journal_frame(sequence: int, payload: str) -> bytes:
    """Return one canonical fixed-size journal frame."""
    if not isinstance(sequence, int) or isinstance(sequence, bool):
        raise JournalFrameError("journal sequence must be an integer")
    if sequence < 1 or sequence > shared.JOURNAL_SEQUENCE_MAX:
        raise JournalFrameError("journal sequence is out of range")
    encoded = _journal_payload_bytes(payload)
    header = struct.pack(
        "<8sHHIQQ",
        JOURNAL_MAGIC,
        JOURNAL_FRAME_MAJOR,
        JOURNAL_FRAME_MINOR,
        len(encoded),
        sequence,
        0,
    )
    digest = hashlib.sha256(header + encoded).digest()
    return header + digest + encoded + bytes(JOURNAL_PAYLOAD_MAX - len(encoded))


def decode_journal_frame(image: bytes) -> JournalFrame:
    """Validate and decode one canonical fixed-size journal frame."""
    if not isinstance(image, bytes) or len(image) != JOURNAL_FRAME_SIZE:
        raise JournalFrameError("journal frame has an invalid size")
    magic, major, minor, length, sequence, reserved = struct.unpack(
        "<8sHHIQQ", image[:32]
    )
    if magic != JOURNAL_MAGIC:
        raise JournalFrameError("journal frame has invalid magic")
    if major != JOURNAL_FRAME_MAJOR or minor != JOURNAL_FRAME_MINOR:
        raise JournalFrameError("journal frame has an unsupported version")
    if reserved != 0:
        raise JournalFrameError("journal frame has nonzero reserved bytes")
    if length > JOURNAL_PAYLOAD_MAX:
        raise JournalFrameError("journal frame has an invalid payload length")
    if sequence < 1:
        raise JournalFrameError("journal frame has an invalid sequence")
    payload_end = JOURNAL_PAYLOAD_OFFSET + length
    encoded = image[JOURNAL_PAYLOAD_OFFSET:payload_end]
    if any(image[payload_end:]):
        raise JournalFrameError("journal frame has nonzero padding")
    expected = hashlib.sha256(image[:32] + encoded).digest()
    if image[32:JOURNAL_PAYLOAD_OFFSET] != expected:
        raise JournalFrameError("journal frame digest does not match")
    try:
        payload = encoded.decode("utf-8")
    except UnicodeDecodeError as error:
        raise JournalFrameError("journal payload is not UTF-8") from error
    _journal_payload_bytes(payload)
    return JournalFrame(sequence, payload)


def initial_journal_image(payload: str = "") -> bytes:
    """Return the canonical sequence-one image for a newly created path."""
    return encode_journal_frame(1, payload) + bytes(JOURNAL_FRAME_SIZE)


def select_journal_frame(image: bytes) -> tuple[int, JournalFrame]:
    """Select the authoritative valid frame from one dual-frame image."""
    if not isinstance(image, bytes) or len(image) != JOURNAL_FILE_SIZE:
        raise JournalFrameError("journal file has an invalid size")
    decoded: list[tuple[int, JournalFrame, bytes]] = []
    for index in range(2):
        raw = image[index * JOURNAL_FRAME_SIZE : (index + 1) * JOURNAL_FRAME_SIZE]
        try:
            decoded.append((index, decode_journal_frame(raw), raw))
        except JournalFrameError:
            continue
    if not decoded:
        raise JournalFrameError("journal file has no valid frame")
    if len(decoded) == 2 and decoded[0][1].sequence == decoded[1][1].sequence:
        if decoded[0][2] != decoded[1][2]:
            raise JournalFrameError("journal frames have conflicting sequences")
        selected = decoded[0]
    else:
        selected = max(decoded, key=lambda candidate: candidate[1].sequence)
    if selected[1].sequence == shared.JOURNAL_SEQUENCE_MAX:
        raise JournalFrameError("journal sequence is exhausted")
    return selected[0], selected[1]


def _validate_journal_record_payload(payload: str) -> None:
    try:
        _journal_payload_bytes(payload)
    except JournalFrameError as error:
        raise JournalRecordError("journal control record is not valid text") from error


def _decode_journal_uint64(value: str, field: str) -> int:
    if re.fullmatch(r"0|[1-9][0-9]*", value) is None:
        raise JournalRecordError(f"journal {field} is not canonical")
    maximum = str(shared.JOURNAL_SEQUENCE_MAX)
    if len(value) > len(maximum) or (len(value) == len(maximum) and value > maximum):
        raise JournalRecordError(f"journal {field} is out of range")
    return int(value)


def _encode_journal_uint64(value: int, field: str) -> str:
    if not isinstance(value, int) or isinstance(value, bool):
        raise JournalRecordError(f"journal {field} must be an integer")
    if value < 0 or value > shared.JOURNAL_SEQUENCE_MAX:
        raise JournalRecordError(f"journal {field} is out of range")
    return str(value)


def encode_journal_cursor(slot: int) -> str:
    """Encode one canonical two-digit terminal-ring cursor."""
    if not isinstance(slot, int) or isinstance(slot, bool):
        raise JournalRecordError("journal cursor must be an integer")
    if slot < 0 or slot >= JOURNAL_TERMINAL_COUNT:
        raise JournalRecordError("journal cursor is out of range")
    return f"{slot:02d}"


def decode_journal_cursor(payload: str) -> int:
    """Decode one canonical two-digit terminal-ring cursor."""
    _validate_journal_record_payload(payload)
    if JOURNAL_SLOT_PATTERN.fullmatch(payload) is None:
        raise JournalRecordError("journal cursor is not canonical")
    return int(payload)


def encode_journal_handoff(record: JournalHandoff | None) -> str:
    """Encode an empty or exact operation-to-terminal-slot handoff."""
    if record is None:
        return ""
    if not isinstance(record, JournalHandoff):
        raise JournalRecordError("journal handoff record is invalid")
    if (
        not isinstance(record.operation_id, str)
        or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(record.operation_id) is None
    ):
        raise JournalRecordError("journal handoff operation ID is invalid")
    return f"{record.operation_id}\t{encode_journal_cursor(record.slot)}"


def decode_journal_handoff(payload: str) -> JournalHandoff | None:
    """Decode an empty or exact operation-to-terminal-slot handoff."""
    _validate_journal_record_payload(payload)
    if payload == "":
        return None
    fields = payload.split("\t")
    if len(fields) != 2:
        raise JournalRecordError("journal handoff field count is invalid")
    if shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(fields[0]) is None:
        raise JournalRecordError("journal handoff operation ID is invalid")
    return JournalHandoff(fields[0], decode_journal_cursor(fields[1]))


def encode_journal_restart(record: JournalRestart) -> str:
    """Encode one canonical restart-guidance control record."""
    if not isinstance(record, JournalRestart):
        raise JournalRecordError("journal restart record is invalid")
    if (
        not isinstance(record.boot_id, str)
        or shared.BOOT_ID_PATTERN.fullmatch(record.boot_id) is None
    ):
        raise JournalRecordError("journal restart boot identity is invalid")
    operation_id = record.last_applied_operation_id
    if operation_id is None:
        operation_id = "-"
    elif (
        not isinstance(operation_id, str)
        or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(operation_id) is None
    ):
        raise JournalRecordError("journal restart operation ID is invalid")
    if (
        not isinstance(record.system, str)
        or record.system not in JOURNAL_RESTART_SYSTEM_VALUES
    ):
        raise JournalRecordError("journal system restart value is invalid")
    if (
        not isinstance(record.session, str)
        or record.session not in JOURNAL_RESTART_SESSION_VALUES
    ):
        raise JournalRecordError("journal session restart value is invalid")
    if not isinstance(record.application, bool):
        raise JournalRecordError("journal application restart value is invalid")
    fields = (
        record.boot_id,
        operation_id,
        record.system,
        record.session,
        _encode_journal_uint64(record.session_cutoff, "session cutoff"),
        "yes" if record.application else "no",
        _encode_journal_uint64(record.application_cutoff, "application cutoff"),
    )
    return "\t".join(fields)


def decode_journal_restart(payload: str) -> JournalRestart:
    """Decode one canonical restart-guidance control record."""
    _validate_journal_record_payload(payload)
    fields = payload.split("\t")
    if len(fields) != 7:
        raise JournalRecordError("journal restart field count is invalid")
    boot_id, operation_id, system, session, session_cutoff, application, app_cutoff = (
        fields
    )
    if shared.BOOT_ID_PATTERN.fullmatch(boot_id) is None:
        raise JournalRecordError("journal restart boot identity is invalid")
    if operation_id == "-":
        decoded_operation_id = None
    elif shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(operation_id) is not None:
        decoded_operation_id = operation_id
    else:
        raise JournalRecordError("journal restart operation ID is invalid")
    if system not in JOURNAL_RESTART_SYSTEM_VALUES:
        raise JournalRecordError("journal system restart value is invalid")
    if session not in JOURNAL_RESTART_SESSION_VALUES:
        raise JournalRecordError("journal session restart value is invalid")
    if application not in ("yes", "no"):
        raise JournalRecordError("journal application restart value is invalid")
    return JournalRestart(
        boot_id,
        decoded_operation_id,
        system,
        session,
        _decode_journal_uint64(session_cutoff, "session cutoff"),
        application == "yes",
        _decode_journal_uint64(app_cutoff, "application cutoff"),
    )


def _validate_journal_timestamp(value: str, field: str) -> None:
    if (
        not isinstance(value, str)
        or JOURNAL_TIMESTAMP_PATTERN.fullmatch(value) is None
    ):
        raise JournalRecordError(f"journal {field} timestamp is invalid")
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise JournalRecordError(f"journal {field} timestamp is invalid") from error


def _validate_journal_detail(value: str) -> None:
    if not isinstance(value, str):
        raise JournalRecordError("journal diagnostic is invalid")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise JournalRecordError("journal diagnostic is invalid") from error
    if (
        len(encoded) > shared.MAX_TEXT_BYTES
        or "\t" in value
        or "\r" in value
        or "\n" in value
        or "\0" in value
    ):
        raise JournalRecordError("journal diagnostic is not canonical")


def _journal_operation_fields(record: JournalOperation) -> tuple[str, ...]:
    if not isinstance(record, JournalOperation):
        raise JournalRecordError("journal operation record is invalid")
    if (
        not isinstance(record.operation_id, str)
        or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(record.operation_id) is None
    ):
        raise JournalRecordError("journal operation ID is invalid")
    if not isinstance(record.action_id, str):
        raise JournalRecordError("journal action ID is invalid")
    expected_kind = shared.JOURNAL_OPERATION_ACTION_KINDS.get(record.action_id)
    if not isinstance(record.kind, str) or expected_kind != record.kind:
        raise JournalRecordError("journal action and operation kind do not match")
    if not isinstance(record.state, str) or record.state not in JOURNAL_OPERATION_STATES:
        raise JournalRecordError("journal operation state is invalid")
    _validate_journal_timestamp(record.started_at, "started")
    terminal = record.state in shared.JOURNAL_OPERATION_TERMINAL_STATES
    if terminal:
        if record.finished_at is None:
            raise JournalRecordError("journal terminal operation has no finish timestamp")
        _validate_journal_timestamp(record.finished_at, "finished")
        finished = record.finished_at
    elif record.finished_at is None:
        finished = "pending"
    else:
        raise JournalRecordError("journal nonterminal operation has a finish timestamp")
    if record.error_code is not None and (
        not isinstance(record.error_code, str)
        or record.error_code not in shared.JOURNAL_ERROR_CODES
    ):
        raise JournalRecordError("journal operation error code is invalid")
    if not terminal or record.state == "succeeded":
        if record.error_code is not None:
            raise JournalRecordError("journal operation state cannot carry an error")
    elif record.state == "failed" and record.error_code is None:
        raise JournalRecordError("journal failed operation has no error code")
    _validate_journal_detail(record.detail)

    if record.kind == "update":
        if (
            not isinstance(record.generation, str)
            or shared.JOURNAL_GENERATION_PATTERN.fullmatch(record.generation) is None
        ):
            raise JournalRecordError("journal update generation is invalid")
        if (
            not isinstance(record.transaction_path, str)
            or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(record.transaction_path) is None
        ):
            raise JournalRecordError("journal PackageKit path is invalid")
        if (
            not isinstance(record.system_restart, str)
            or record.system_restart not in JOURNAL_RESTART_SYSTEM_VALUES
        ):
            raise JournalRecordError("journal system restart value is invalid")
        if (
            not isinstance(record.session_restart, str)
            or record.session_restart not in JOURNAL_RESTART_SESSION_VALUES
        ):
            raise JournalRecordError("journal session restart value is invalid")
        if not isinstance(record.application_restart, bool):
            raise JournalRecordError("journal application restart value is invalid")
        if (
            not isinstance(record.boot_id, str)
            or shared.BOOT_ID_PATTERN.fullmatch(record.boot_id) is None
        ):
            raise JournalRecordError("journal operation boot identity is invalid")
        typed = (
            record.generation,
            record.transaction_path,
            record.system_restart,
            record.session_restart,
            "yes" if record.application_restart else "no",
            record.boot_id,
        )
    elif record.kind == "refresh":
        if any(
            value is not None
            for value in (
                record.generation,
                record.system_restart,
                record.session_restart,
                record.application_restart,
                record.boot_id,
            )
        ):
            raise JournalRecordError("journal refresh typed fields are invalid")
        if (
            not isinstance(record.transaction_path, str)
            or shared.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(record.transaction_path) is None
        ):
            raise JournalRecordError("journal PackageKit path is invalid")
        typed = ("-", record.transaction_path, "-", "-", "-", "-")
    else:
        if any(
            value is not None
            for value in (
                record.generation,
                record.transaction_path,
                record.system_restart,
                record.session_restart,
                record.application_restart,
                record.boot_id,
                record.terminal_monotonic,
            )
        ):
            raise JournalRecordError("journal operation typed fields are invalid")
        typed = ("-", "-", "-", "-", "-", "-")

    if record.kind in ("update", "refresh"):
        if terminal:
            monotonic = _encode_journal_uint64(
                record.terminal_monotonic, "terminal monotonic timestamp"
            )
        elif record.terminal_monotonic is None:
            monotonic = "pending"
        else:
            raise JournalRecordError(
                "journal nonterminal operation has a terminal monotonic timestamp"
            )
    else:
        monotonic = "-"
    error_code = "-" if record.error_code is None else record.error_code
    return (
        record.operation_id,
        record.action_id,
        record.started_at,
        finished,
        record.kind,
        record.state,
        error_code,
        record.detail,
        *typed,
        monotonic,
        encode_journal_cursor(record.slot),
    )


def encode_journal_operation(record: JournalOperation) -> str:
    """Encode one canonical active or terminal operation record."""
    payload = "\t".join(_journal_operation_fields(record))
    _validate_journal_record_payload(payload)
    return payload


def decode_journal_operation(payload: str) -> JournalOperation:
    """Decode one canonical active or terminal operation record."""
    _validate_journal_record_payload(payload)
    fields = payload.split("\t")
    if len(fields) != 16:
        raise JournalRecordError("journal operation field count is invalid")
    (
        operation_id,
        action_id,
        started,
        finished,
        kind,
        state,
        error_code,
        detail,
        generation,
        transaction_path,
        system_restart,
        session_restart,
        application_restart,
        boot_id,
        terminal_monotonic,
        slot,
    ) = fields
    terminal = state in shared.JOURNAL_OPERATION_TERMINAL_STATES
    if kind in ("update", "refresh"):
        decoded_monotonic = (
            _decode_journal_uint64(
                terminal_monotonic, "terminal monotonic timestamp"
            )
            if terminal
            else None
        )
    else:
        decoded_monotonic = None
    record = JournalOperation(
        operation_id,
        action_id,
        started,
        None if finished == "pending" else finished,
        kind,
        state,
        None if error_code == "-" else error_code,
        detail,
        None if generation == "-" else generation,
        None if transaction_path == "-" else transaction_path,
        None if system_restart == "-" else system_restart,
        None if session_restart == "-" else session_restart,
        None if application_restart == "-" else application_restart == "yes",
        None if boot_id == "-" else boot_id,
        decoded_monotonic,
        decode_journal_cursor(slot),
    )
    if encode_journal_operation(record) != payload:
        raise JournalRecordError("journal operation record is not canonical")
    return record


def decode_journal_state(payloads: Mapping[str, str]) -> JournalState:
    """Validate the complete fixed journal payload set without changing it."""
    if not isinstance(payloads, Mapping) or set(payloads) != set(JOURNAL_NAMES):
        raise JournalRecordError("journal state path set is invalid")
    if any(not isinstance(value, str) for value in payloads.values()):
        raise JournalRecordError("journal state payload is invalid")

    cursor = decode_journal_cursor(payloads[JOURNAL_CURSOR_NAME])
    restart = decode_journal_restart(payloads["restart"])
    restart_is_all_clear = (
        restart.last_applied_operation_id is None
        and restart.system == "none"
        and restart.session == "none"
        and restart.session_cutoff == 0
        and not restart.application
        and restart.application_cutoff == 0
    )
    active_payload = payloads["active"]
    active = None if active_payload == "" else decode_journal_operation(active_payload)
    handoff = decode_journal_handoff(payloads["handoff"])
    terminals: list[JournalOperation | None] = []
    retained_ids: set[str] = set()
    for slot in range(JOURNAL_TERMINAL_COUNT):
        payload = payloads[f"terminal-{slot:02d}"]
        if payload == "":
            terminals.append(None)
            continue
        operation = decode_journal_operation(payload)
        if operation.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES:
            raise JournalRecordError("journal terminal slot is nonterminal")
        if operation.slot != slot:
            raise JournalRecordError("journal terminal slot identity does not match")
        if operation.operation_id in retained_ids:
            raise JournalRecordError("journal terminal operation ID is duplicated")
        retained_ids.add(operation.operation_id)
        terminals.append(operation)

    filled_slots = [
        slot for slot, operation in enumerate(terminals) if operation is not None
    ]
    if (
        active is None
        and handoff is None
        and len(filled_slots) == 1
        and cursor != (filled_slots[0] + 1) % JOURNAL_TERMINAL_COUNT
    ):
        raise JournalRecordError("journal cursor is stale")

    handoff_terminal = None
    if handoff is not None:
        handoff_terminal = terminals[handoff.slot]
        if (
            handoff_terminal is None
            or handoff_terminal.operation_id != handoff.operation_id
        ):
            raise JournalRecordError("journal handoff has no matching terminal")
        if cursor != (handoff.slot + 1) % JOURNAL_TERMINAL_COUNT:
            raise JournalRecordError("journal handoff cursor has not advanced")
        if (
            handoff_terminal.kind == "update"
            and handoff_terminal.boot_id == restart.boot_id
            and restart.last_applied_operation_id != handoff_terminal.operation_id
        ):
            raise JournalRecordError("journal update handoff has no restart commit")
        if (
            handoff_terminal.kind == "update"
            and handoff_terminal.boot_id != restart.boot_id
            and not restart_is_all_clear
        ):
            raise JournalRecordError("journal old-boot handoff is not all-clear")
        if active is not None and (
            active.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES
            or active != handoff_terminal
        ):
            raise JournalRecordError("journal active and handoff records conflict")

    if active is not None and active.state in shared.JOURNAL_OPERATION_TERMINAL_STATES:
        selected = terminals[active.slot]
        if (
            selected == active
            and active.kind == "update"
            and active.boot_id == restart.boot_id
            and restart.last_applied_operation_id != active.operation_id
        ):
            raise JournalRecordError("journal terminal update has no restart commit")
    if active is not None and active.operation_id in retained_ids:
        selected = terminals[active.slot]
        if active.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES or selected != active:
            raise JournalRecordError("journal active operation ID is duplicated")
    if (
        active is not None
        and active.kind == "update"
        and active.boot_id != restart.boot_id
        and not restart_is_all_clear
    ):
        raise JournalRecordError("journal old-boot active update is not all-clear")

    restart_operation_id = restart.last_applied_operation_id
    applied_updates = [
        operation
        for operation in terminals
        if operation is not None
        and operation.kind == "update"
        and operation.boot_id == restart.boot_id
    ]
    matching_updates: list[JournalOperation] = []
    ring_may_have_evicted = len(filled_slots) == JOURNAL_TERMINAL_COUNT
    if (
        active is not None
        and active.kind in ("update", "refresh")
        and (active.kind == "refresh" or active.boot_id == restart.boot_id)
        and active.state in shared.JOURNAL_OPERATION_TERMINAL_STATES
        and any(
            operation.terminal_monotonic > active.terminal_monotonic
            for operation in applied_updates
            if operation != active
        )
    ):
        raise JournalRecordError("journal active timestamp is stale")
    if (
        handoff_terminal is not None
        and handoff_terminal.kind in ("update", "refresh")
        and (
            handoff_terminal.kind == "refresh"
            or handoff_terminal.boot_id == restart.boot_id
        )
        and any(
            operation.operation_id != handoff_terminal.operation_id
            and operation.terminal_monotonic > handoff_terminal.terminal_monotonic
            for operation in applied_updates
        )
    ):
        raise JournalRecordError("journal handoff is superseded")
    if restart_operation_id is None:
        if (
            restart.system != "none"
            or restart.session != "none"
            or restart.session_cutoff != 0
            or restart.application
            or restart.application_cutoff != 0
        ):
            raise JournalRecordError("journal restart guidance has no identity")
        if applied_updates:
            raise JournalRecordError("journal update history has no restart identity")
    else:
        matching_operations = [
            operation
            for operation in (*terminals, active)
            if operation is not None and operation.operation_id == restart_operation_id
        ]
        if any(
            operation.kind != "update"
            or operation.boot_id != restart.boot_id
            or operation.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES
            for operation in matching_operations
        ):
            raise JournalRecordError("journal operation ID reuses restart identity")
        if (
            active is not None
            and active.operation_id == restart_operation_id
            and active.kind == "update"
            and active.boot_id == restart.boot_id
            and active not in applied_updates
        ):
            applied_updates.append(active)
        matching_updates = [
            operation
            for operation in applied_updates
            if operation.operation_id == restart_operation_id
        ]
        if not matching_updates and not ring_may_have_evicted:
            raise JournalRecordError("journal restart identity is not retained")
        if applied_updates and not matching_updates:
            raise JournalRecordError("journal restart identity is stale")
        if matching_updates and any(
            operation.terminal_monotonic > matching_updates[0].terminal_monotonic
            for operation in applied_updates
        ):
            raise JournalRecordError("journal restart identity is stale")
    if any(
        shared.JOURNAL_RESTART_SYSTEM_STRENGTH[restart.system]
        < shared.JOURNAL_RESTART_SYSTEM_STRENGTH[operation.system_restart]
        for operation in applied_updates
    ):
        raise JournalRecordError("journal restart contribution is incomplete")
    if not ring_may_have_evicted:
        expected_system = max(
            ("none", *(operation.system_restart for operation in applied_updates)),
            key=shared.JOURNAL_RESTART_SYSTEM_STRENGTH.__getitem__,
        )
        if restart.system != expected_system:
            raise JournalRecordError("journal system restart bucket is unsupported")
    if restart.session == "none" and restart.session_cutoff != 0:
        raise JournalRecordError("journal cleared session restart has a cutoff")
    session_contributors = [
        operation
        for operation in applied_updates
        if operation.session_restart != "none"
    ]
    if restart.session != "none" and (
        restart.session_cutoff == 0
        or (
            matching_updates
            and restart.session_cutoff > matching_updates[0].terminal_monotonic
        )
        or any(
            operation.session_restart != "none"
            and restart.session_cutoff < operation.terminal_monotonic
            for operation in applied_updates
        )
    ):
        raise JournalRecordError("journal session restart cutoff is stale")
    if (
        restart.session != "none"
        and any(
            shared.JOURNAL_RESTART_SESSION_STRENGTH[restart.session]
            < shared.JOURNAL_RESTART_SESSION_STRENGTH[operation.session_restart]
            for operation in matching_updates
        )
    ):
        raise JournalRecordError("journal session restart contribution is incomplete")
    if not ring_may_have_evicted and restart.session != "none":
        if (
            not session_contributors
            or restart.session
            not in {operation.session_restart for operation in session_contributors}
        ):
            raise JournalRecordError("journal session restart bucket is unsupported")
        latest_session_cutoff = max(
            operation.terminal_monotonic for operation in session_contributors
        )
        latest_session_strength = max(
            shared.JOURNAL_RESTART_SESSION_STRENGTH[operation.session_restart]
            for operation in session_contributors
            if operation.terminal_monotonic == latest_session_cutoff
        )
        if (
            restart.session_cutoff != latest_session_cutoff
            or shared.JOURNAL_RESTART_SESSION_STRENGTH[restart.session]
            < latest_session_strength
        ):
            raise JournalRecordError("journal session restart state is not derivable")
    if not restart.application and restart.application_cutoff != 0:
        raise JournalRecordError("journal cleared application restart has a cutoff")
    application_contributors = [
        operation for operation in applied_updates if operation.application_restart
    ]
    if restart.application and (
        restart.application_cutoff == 0
        or (
            matching_updates
            and restart.application_cutoff > matching_updates[0].terminal_monotonic
        )
        or any(
            operation.application_restart
            and restart.application_cutoff < operation.terminal_monotonic
            for operation in applied_updates
        )
    ):
        raise JournalRecordError("journal application restart cutoff is stale")
    if not ring_may_have_evicted and restart.application and (
        not application_contributors
        or restart.application_cutoff
        != max(
            operation.terminal_monotonic for operation in application_contributors
        )
    ):
        raise JournalRecordError("journal application restart state is not derivable")

    return JournalState(cursor, restart, active, handoff, tuple(terminals))


def _validate_journal_descriptor(
    descriptor: int, expected_size: int, *, writable: bool
) -> os.stat_result:
    if (
        not isinstance(descriptor, int)
        or isinstance(descriptor, bool)
        or descriptor < 0
    ):
        raise JournalFileError("journal file descriptor is invalid")
    try:
        metadata = os.fstat(descriptor)
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
    except (OSError, OverflowError) as error:
        raise JournalFileError("journal file descriptor is unavailable") from error
    access = flags & os.O_ACCMODE
    if (
        access == os.O_WRONLY
        or (writable and access != os.O_RDWR)
        or (writable and flags & os.O_APPEND)
    ):
        raise JournalFileError("journal file descriptor has unsafe access")
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or metadata.st_nlink != 1
        or metadata.st_size != expected_size
    ):
        raise JournalFileError("journal file metadata is unsafe")
    return metadata


def _validate_journal_lock_descriptor(descriptor: int) -> os.stat_result:
    if (
        not isinstance(descriptor, int)
        or isinstance(descriptor, bool)
        or descriptor < 0
    ):
        raise JournalLockError("journal lock descriptor is invalid")
    try:
        metadata = os.fstat(descriptor)
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
    except (OSError, OverflowError) as error:
        raise JournalLockError("journal lock descriptor is unavailable") from error
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) != 0o700
        or (flags & os.O_ACCMODE) == os.O_WRONLY
    ):
        raise JournalLockError("journal lock directory metadata is unsafe")
    return metadata


@contextlib.contextmanager
def _journal_lock(descriptor: int, *, exclusive: bool) -> Iterator[None]:
    held = _validate_journal_lock_descriptor(descriptor)
    try:
        lock_descriptor = os.open(
            ".",
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=descriptor,
        )
    except OSError as error:
        raise JournalLockError("journal lock handle is unavailable") from error
    try:
        lock_metadata = _validate_journal_lock_descriptor(lock_descriptor)
        if (lock_metadata.st_dev, lock_metadata.st_ino) != (
            held.st_dev,
            held.st_ino,
        ):
            raise JournalLockError("journal lock directory identity changed")
        deadline = time.monotonic() + JOURNAL_LOCK_DEADLINE_SECONDS
        operation = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        while True:
            try:
                fcntl.flock(lock_descriptor, operation | fcntl.LOCK_NB)
                break
            except OSError as error:
                if error.errno not in {errno.EACCES, errno.EAGAIN}:
                    raise JournalLockError("journal lock acquisition failed") from error
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise JournalLockError(
                        "journal lock acquisition timed out"
                    ) from error
                time.sleep(min(remaining, 0.01))

        try:
            current = _validate_journal_lock_descriptor(descriptor)
            if (current.st_dev, current.st_ino) != (
                lock_metadata.st_dev,
                lock_metadata.st_ino,
            ):
                raise JournalLockError("journal lock directory identity changed")
            yield
        finally:
            try:
                fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
            except OSError as error:
                raise JournalLockError("journal lock release failed") from error
    finally:
        try:
            os.close(lock_descriptor)
        except OSError as error:
            raise JournalLockError("journal lock handle close failed") from error


def _read_journal_image(descriptor: int) -> bytes:
    _validate_journal_descriptor(descriptor, JOURNAL_FILE_SIZE, writable=False)
    chunks: list[bytes] = []
    offset = 0
    while offset < JOURNAL_FILE_SIZE:
        try:
            chunk = os.pread(descriptor, JOURNAL_FILE_SIZE - offset, offset)
        except OSError as error:
            raise JournalFileError("journal file read failed") from error
        if not isinstance(chunk, bytes) or not chunk:
            raise JournalFileError("journal file read was incomplete")
        chunks.append(chunk)
        offset += len(chunk)
    image = b"".join(chunks)
    _validate_journal_descriptor(descriptor, JOURNAL_FILE_SIZE, writable=False)
    return image


def _read_journal_file_unlocked(descriptor: int) -> tuple[int, JournalFrame]:
    return select_journal_frame(_read_journal_image(descriptor))


def read_journal_file(
    lock_descriptor: int, descriptor: int
) -> tuple[int, JournalFrame]:
    """Load one journal file while holding the shared directory lock."""
    with _journal_lock(lock_descriptor, exclusive=False):
        return _read_journal_file_unlocked(descriptor)


def _initialize_journal_file_unlocked(
    descriptor: int, payload: str = ""
) -> JournalFrame:
    image = initial_journal_image(payload)
    _validate_journal_descriptor(descriptor, 0, writable=True)
    try:
        written = os.pwrite(descriptor, image, 0)
        if written != len(image):
            raise OSError("short journal initialization write")
        os.fsync(descriptor)
        _validate_journal_descriptor(descriptor, JOURNAL_FILE_SIZE, writable=True)
        if _read_journal_image(descriptor) != image:
            raise OSError("journal initialization readback mismatch")
    except OSError as error:
        raise JournalFileError("journal file initialization failed") from error
    return JournalFrame(1, payload)


def initialize_journal_file(
    lock_descriptor: int, descriptor: int, payload: str = ""
) -> JournalFrame:
    """Initialize one empty file while holding the exclusive directory lock."""
    with _journal_lock(lock_descriptor, exclusive=True):
        return _initialize_journal_file_unlocked(descriptor, payload)


def _commit_journal_file_unlocked(
    descriptor: int, payload: str
) -> tuple[int, JournalFrame]:
    active_index, active = _read_journal_file_unlocked(descriptor)
    next_frame = JournalFrame(active.sequence + 1, payload)
    encoded = encode_journal_frame(next_frame.sequence, next_frame.payload)
    inactive_index = 1 - active_index
    offset = inactive_index * JOURNAL_FRAME_SIZE
    _validate_journal_descriptor(descriptor, JOURNAL_FILE_SIZE, writable=True)
    try:
        written = os.pwrite(descriptor, encoded, offset)
        if written != len(encoded):
            raise OSError("short journal frame write")
        os.fsync(descriptor)
        image = _read_journal_image(descriptor)
        if image[offset : offset + JOURNAL_FRAME_SIZE] != encoded:
            raise OSError("journal frame readback mismatch")
        selected_index, selected = select_journal_frame(image)
        if selected_index != inactive_index or selected != next_frame:
            raise OSError("journal frame did not become authoritative")
    except (OSError, JournalFrameError) as error:
        raise JournalCommitError("journal frame commit is indeterminate") from error
    return inactive_index, next_frame


def commit_journal_file(
    lock_descriptor: int, descriptor: int, payload: str
) -> tuple[int, JournalFrame]:
    """Commit one frame while holding the exclusive directory lock."""
    with _journal_lock(lock_descriptor, exclusive=True):
        return _commit_journal_file_unlocked(descriptor, payload)


def _initial_journal_payloads(boot_id: str) -> dict[str, str]:
    if not isinstance(boot_id, str) or shared.BOOT_ID_PATTERN.fullmatch(boot_id) is None:
        raise JournalLayoutError("journal boot identity is invalid")
    payloads = {name: "" for name in JOURNAL_DATA_NAMES}
    payloads["restart"] = encode_journal_restart(
        JournalRestart(boot_id, None, "none", "none", 0, False, 0)
    )
    payloads[JOURNAL_CURSOR_NAME] = encode_journal_cursor(0)
    return payloads


def _validate_journal_path_identity(
    directory_descriptor: int,
    name: str,
    descriptor: int,
    expected_size: int,
    *,
    writable: bool = True,
) -> None:
    try:
        held = _validate_journal_descriptor(
            descriptor, expected_size, writable=writable
        )
    except JournalFileError as error:
        raise JournalLayoutError(
            f"journal path {name} identity is unsafe"
        ) from error
    try:
        reachable = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
    except OSError as error:
        raise JournalLayoutError(f"journal path {name} is unavailable") from error
    if (
        (reachable.st_dev, reachable.st_ino) != (held.st_dev, held.st_ino)
        or not stat.S_ISREG(reachable.st_mode)
        or reachable.st_uid != os.geteuid()
        or stat.S_IMODE(reachable.st_mode) != 0o600
        or reachable.st_nlink != 1
        or reachable.st_size != expected_size
    ):
        raise JournalLayoutError(f"journal path {name} identity is unsafe")


def _create_journal_path_unlocked(
    directory_descriptor: int, name: str, payload: str
) -> None:
    try:
        descriptor = os.open(
            name,
            os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
            0o600,
            dir_fd=directory_descriptor,
        )
    except OSError as error:
        raise JournalLayoutError(f"journal path {name} creation failed") from error
    try:
        try:
            os.fchmod(descriptor, 0o600)
            _validate_journal_path_identity(directory_descriptor, name, descriptor, 0)
            _initialize_journal_file_unlocked(descriptor, payload)
            _validate_journal_path_identity(
                directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
            )
        except (OSError, JournalFrameError) as error:
            raise JournalLayoutError(
                f"journal path {name} initialization failed"
            ) from error
    finally:
        try:
            os.close(descriptor)
        except OSError as error:
            raise JournalLayoutError(f"journal path {name} close failed") from error


def _inspect_partial_journal_path_unlocked(
    directory_descriptor: int, name: str, path_descriptor: int
) -> os.stat_result:
    try:
        held = os.fstat(path_descriptor)
        descriptor_flags = fcntl.fcntl(path_descriptor, fcntl.F_GETFD)
        reachable = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
    except (OSError, OverflowError) as error:
        raise JournalLayoutError(f"journal path {name} is unavailable") from error
    if (
        not stat.S_ISREG(held.st_mode)
        or not stat.S_ISREG(reachable.st_mode)
        or (held.st_dev, held.st_ino) != (reachable.st_dev, reachable.st_ino)
        or held.st_uid != os.geteuid()
        or reachable.st_uid != held.st_uid
        or stat.S_IMODE(reachable.st_mode) != stat.S_IMODE(held.st_mode)
        or held.st_nlink != 1
        or reachable.st_nlink != 1
        or held.st_size != reachable.st_size
        or held.st_size < 0
        or held.st_size > JOURNAL_FILE_SIZE
        or not descriptor_flags & fcntl.FD_CLOEXEC
    ):
        raise JournalLayoutError(f"journal path {name} partial metadata is unsafe")
    return held


def _open_partial_journal_path_unlocked(
    directory_descriptor: int,
    name: str,
    *,
    allow_empty_mode_repair: bool,
) -> tuple[int, bool] | None:
    try:
        path_descriptor = os.open(
            name,
            os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=directory_descriptor,
        )
    except FileNotFoundError:
        return None
    except OSError as error:
        raise JournalLayoutError(f"journal path {name} open failed") from error
    descriptor: int | None = None
    retained_path_descriptor = False
    try:
        held = _inspect_partial_journal_path_unlocked(
            directory_descriptor, name, path_descriptor
        )
        mode = stat.S_IMODE(held.st_mode)
        if (
            allow_empty_mode_repair
            and held.st_size == 0
            and mode != 0o600
            and mode & ~0o600 == 0
        ):
            retained_path_descriptor = True
            return path_descriptor, True
        if mode != 0o600:
            raise JournalLayoutError(f"journal path {name} partial metadata is unsafe")
        try:
            descriptor = os.open(
                name,
                os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
                dir_fd=directory_descriptor,
            )
        except OSError as error:
            raise JournalLayoutError(
                f"journal path {name} writable open failed"
            ) from error
        active = _validate_partial_journal_path_identity(
            directory_descriptor, name, descriptor
        )
        if (active.st_dev, active.st_ino) != (held.st_dev, held.st_ino):
            raise JournalLayoutError(f"journal path {name} identity changed")
        result = descriptor
        descriptor = None
        return result, False
    finally:
        first_error: OSError | None = None
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError as error:
                first_error = error
        if not retained_path_descriptor:
            try:
                os.close(path_descriptor)
            except OSError as error:
                if first_error is None:
                    first_error = error
        if first_error is not None:
            raise JournalLayoutError(
                f"journal path {name} open descriptor close failed"
            ) from first_error


def _repair_empty_journal_path_mode_unlocked(
    directory_descriptor: int, name: str, path_descriptor: int
) -> int:
    held = _inspect_partial_journal_path_unlocked(
        directory_descriptor, name, path_descriptor
    )
    mode = stat.S_IMODE(held.st_mode)
    if held.st_size != 0 or mode == 0o600 or mode & ~0o600:
        raise JournalLayoutError(f"journal path {name} mode recovery is unsafe")
    try:
        os.chmod(f"/proc/self/fd/{path_descriptor}", 0o600)
    except OSError as error:
        raise JournalLayoutError(f"journal path {name} mode recovery failed") from error
    held = _inspect_partial_journal_path_unlocked(
        directory_descriptor, name, path_descriptor
    )
    if held.st_size != 0 or stat.S_IMODE(held.st_mode) != 0o600:
        raise JournalLayoutError(f"journal path {name} mode recovery is unsafe")
    try:
        descriptor = os.open(
            name,
            os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
            dir_fd=directory_descriptor,
        )
    except OSError as error:
        raise JournalLayoutError(f"journal path {name} writable open failed") from error
    try:
        active = _validate_partial_journal_path_identity(
            directory_descriptor, name, descriptor
        )
        if (active.st_dev, active.st_ino) != (held.st_dev, held.st_ino):
            raise JournalLayoutError(f"journal path {name} identity changed")
    except OSError:
        try:
            os.close(descriptor)
        except OSError:
            pass
        raise
    return descriptor


def _validate_partial_journal_path_identity(
    directory_descriptor: int, name: str, descriptor: int
) -> os.stat_result:
    try:
        held = os.fstat(descriptor)
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
        descriptor_flags = fcntl.fcntl(descriptor, fcntl.F_GETFD)
        reachable = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
    except (OSError, OverflowError) as error:
        raise JournalLayoutError(f"journal path {name} is unavailable") from error
    if (
        not stat.S_ISREG(held.st_mode)
        or not stat.S_ISREG(reachable.st_mode)
        or (held.st_dev, held.st_ino) != (reachable.st_dev, reachable.st_ino)
        or held.st_uid != os.geteuid()
        or reachable.st_uid != held.st_uid
        or stat.S_IMODE(held.st_mode) != 0o600
        or stat.S_IMODE(reachable.st_mode) != 0o600
        or held.st_nlink != 1
        or reachable.st_nlink != 1
        or held.st_size != reachable.st_size
        or held.st_size < 0
        or held.st_size > JOURNAL_FILE_SIZE
        or (flags & os.O_ACCMODE) != os.O_RDWR
        or flags & os.O_APPEND
        or not descriptor_flags & fcntl.FD_CLOEXEC
    ):
        raise JournalLayoutError(f"journal path {name} partial metadata is unsafe")
    return held


def _read_partial_journal_image_unlocked(
    directory_descriptor: int, name: str, descriptor: int
) -> bytes:
    before = _validate_partial_journal_path_identity(
        directory_descriptor, name, descriptor
    )
    chunks: list[bytes] = []
    offset = 0
    while offset < before.st_size:
        try:
            chunk = os.pread(descriptor, before.st_size - offset, offset)
        except OSError as error:
            raise JournalLayoutError(f"journal path {name} read failed") from error
        if not chunk:
            raise JournalLayoutError(f"journal path {name} read was incomplete")
        chunks.append(chunk)
        offset += len(chunk)
    after = _validate_partial_journal_path_identity(
        directory_descriptor, name, descriptor
    )
    if (before.st_dev, before.st_ino, before.st_size) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
    ):
        raise JournalLayoutError(f"journal path {name} changed while reading")
    return b"".join(chunks)


def _is_safe_initial_fragment(image: bytes, expected: bytes) -> bool:
    if len(image) > len(expected):
        return False
    if image == expected[: len(image)]:
        return True
    if len(image) != len(expected):
        return False
    common = 0
    while common < len(expected) and image[common] == expected[common]:
        common += 1
    return common > 0 and not any(image[common:])


def _is_all_clear_restart_payload(payload: str) -> bool:
    try:
        record = decode_journal_restart(payload)
    except JournalRecordError:
        return False
    return (
        record.last_applied_operation_id is None
        and record.system == "none"
        and record.session == "none"
        and record.session_cutoff == 0
        and not record.application
        and record.application_cutoff == 0
    )


def _restart_initial_header() -> bytes:
    payload_size = len(JOURNAL_BOOT_ID_TEMPLATE.encode("ascii")) + len(
        JOURNAL_RESTART_ALL_CLEAR_SUFFIX
    )
    return struct.pack(
        "<8sHHIQQ",
        JOURNAL_MAGIC,
        JOURNAL_FRAME_MAJOR,
        JOURNAL_FRAME_MINOR,
        payload_size,
        1,
        0,
    )


def _is_all_clear_restart_payload_prefix(encoded: bytes) -> bool:
    uuid_template = JOURNAL_BOOT_ID_TEMPLATE
    suffix = JOURNAL_RESTART_ALL_CLEAR_SUFFIX
    if len(encoded) > len(uuid_template) + len(suffix):
        return False
    for index, byte in enumerate(encoded):
        if index < len(uuid_template):
            marker = uuid_template[index]
            if marker == "-":
                if byte != ord("-"):
                    return False
            elif not (ord("0") <= byte <= ord("9") or ord("a") <= byte <= ord("f")):
                return False
        elif byte != suffix[index - len(uuid_template)]:
            return False
    return True


def _is_safe_restart_initial_fragment(image: bytes) -> bool:
    if len(image) > JOURNAL_FILE_SIZE:
        return False
    header = _restart_initial_header()
    if len(image) <= len(header):
        return image == header[: len(image)]
    if image[: len(header)] != header:
        return False
    if len(image) <= JOURNAL_PAYLOAD_OFFSET:
        return True
    payload_size = struct.unpack("<I", header[12:16])[0]
    payload_end = JOURNAL_PAYLOAD_OFFSET + payload_size
    payload_prefix = image[JOURNAL_PAYLOAD_OFFSET : min(len(image), payload_end)]
    if not _is_all_clear_restart_payload_prefix(payload_prefix):
        return False
    if len(image) < payload_end:
        return True
    try:
        frame = decode_journal_frame(
            image[:JOURNAL_FRAME_SIZE].ljust(JOURNAL_FRAME_SIZE, b"\0")
        )
    except JournalFrameError:
        return False
    return (
        frame.sequence == 1
        and _is_all_clear_restart_payload(frame.payload)
        and not any(image[JOURNAL_FRAME_SIZE:])
    )


def _is_safe_restart_rewrite_fragment(image: bytes, expected: bytes) -> bool:
    header = _restart_initial_header()
    payload_size = struct.unpack("<I", header[12:16])[0]
    payload_end = JOURNAL_PAYLOAD_OFFSET + payload_size
    if len(image) < payload_end or len(image) > JOURNAL_FILE_SIZE:
        return False
    try:
        payload = image[JOURNAL_PAYLOAD_OFFSET:payload_end].decode("ascii")
    except UnicodeDecodeError:
        return False
    if not _is_all_clear_restart_payload(payload):
        return False
    previous = initial_journal_image(payload)[: len(image)]
    current = expected[: len(image)]
    current_prefix = 0
    while (
        current_prefix < len(image) and image[current_prefix] == current[current_prefix]
    ):
        current_prefix += 1
    previous_suffix = len(image)
    while (
        previous_suffix > 0
        and image[previous_suffix - 1] == previous[previous_suffix - 1]
    ):
        previous_suffix -= 1
    return previous_suffix <= current_prefix


def _is_safe_initial_path_fragment(name: str, image: bytes, expected: bytes) -> bool:
    if _is_safe_initial_fragment(image, expected):
        return True
    if name != "restart":
        return False
    if len(image) == JOURNAL_FILE_SIZE and any(image[JOURNAL_FRAME_SIZE:]):
        return False
    if len(image) == JOURNAL_FILE_SIZE:
        nonzero = image.rstrip(b"\0")
        if not nonzero:
            return False
        payload_size = struct.unpack("<I", _restart_initial_header()[12:16])[0]
        if len(nonzero) < JOURNAL_PAYLOAD_OFFSET + payload_size:
            return _is_safe_restart_initial_fragment(nonzero)
    return _is_safe_restart_initial_fragment(
        image
    ) or _is_safe_restart_rewrite_fragment(image, expected)


def _rewrite_initial_journal_path_unlocked(
    directory_descriptor: int,
    name: str,
    descriptor: int,
    payload: str,
) -> None:
    expected = initial_journal_image(payload)
    observed = _read_partial_journal_image_unlocked(
        directory_descriptor, name, descriptor
    )
    if not _is_safe_initial_path_fragment(name, observed, expected):
        raise JournalLayoutError(f"journal path {name} is not recoverable")
    try:
        written = os.pwrite(descriptor, expected, 0)
        if written != len(expected):
            raise OSError("short journal recovery write")
        os.fsync(descriptor)
        _validate_journal_path_identity(
            directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
        )
        if _read_journal_image(descriptor) != expected:
            raise OSError("journal recovery readback mismatch")
        _validate_journal_path_identity(
            directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
        )
    except OSError as error:
        if isinstance(error, JournalLayoutError):
            raise
        raise JournalLayoutError(f"journal path {name} recovery failed") from error


def _validate_initialized_journal_path_unlocked(
    directory_descriptor: int, name: str, descriptor: int
) -> None:
    try:
        _validate_journal_path_identity(
            directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
        )
        select_journal_frame(_read_journal_image(descriptor))
        _validate_journal_path_identity(
            directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
        )
    except (JournalFileError, JournalFrameError) as error:
        raise JournalLayoutError(f"journal path {name} is malformed") from error


def _validate_initial_journal_path_unlocked(
    directory_descriptor: int, name: str, expected_payload: str
) -> None:
    try:
        descriptor = os.open(
            name,
            os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
            dir_fd=directory_descriptor,
        )
    except OSError as error:
        raise JournalLayoutError(f"journal path {name} open failed") from error
    try:
        _validate_journal_path_identity(
            directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
        )
        try:
            observed = _read_journal_file_unlocked(descriptor)
        except JournalFrameError as error:
            raise JournalLayoutError(f"journal path {name} is not initial") from error
        if observed != (0, JournalFrame(1, expected_payload)):
            raise JournalLayoutError(f"journal path {name} is not initial")
        _validate_journal_path_identity(
            directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE
        )
    finally:
        try:
            os.close(descriptor)
        except OSError as error:
            raise JournalLayoutError(f"journal path {name} close failed") from error


def initialize_journal_layout(directory_descriptor: int, boot_id: str) -> None:
    """Create or recover the fixed journal layout with cursor committed last."""
    payloads = _initial_journal_payloads(boot_id)
    with _journal_lock(directory_descriptor, exclusive=True):
        descriptors: dict[str, int] = {}
        mode_repair_descriptors: dict[str, int] = {}
        images: dict[str, bytes] = {}
        completed = False
        try:
            cursor_path = _open_partial_journal_path_unlocked(
                directory_descriptor,
                JOURNAL_CURSOR_NAME,
                allow_empty_mode_repair=True,
            )
            cursor = None
            if cursor_path is not None:
                cursor_descriptor, cursor_mode_repair = cursor_path
                if cursor_mode_repair:
                    mode_repair_descriptors[JOURNAL_CURSOR_NAME] = cursor_descriptor
                    cursor = b""
                else:
                    descriptors[JOURNAL_CURSOR_NAME] = cursor_descriptor
                    cursor = _read_partial_journal_image_unlocked(
                        directory_descriptor, JOURNAL_CURSOR_NAME, cursor_descriptor
                    )
                images[JOURNAL_CURSOR_NAME] = cursor
            cursor_expected = initial_journal_image(payloads[JOURNAL_CURSOR_NAME])
            cursor_present = cursor == cursor_expected
            if cursor is not None and not cursor_present:
                if _is_safe_initial_fragment(cursor, cursor_expected):
                    cursor_present = False
                elif len(cursor) == JOURNAL_FILE_SIZE:
                    try:
                        select_journal_frame(cursor)
                    except JournalFrameError as error:
                        raise JournalLayoutError(
                            "journal path cursor is not recoverable"
                        ) from error
                    cursor_present = True
                else:
                    raise JournalLayoutError("journal path cursor is not recoverable")

            for name in JOURNAL_DATA_NAMES:
                path = _open_partial_journal_path_unlocked(
                    directory_descriptor,
                    name,
                    allow_empty_mode_repair=not cursor_present,
                )
                if path is None:
                    continue
                descriptor, mode_repair = path
                if mode_repair:
                    mode_repair_descriptors[name] = descriptor
                    images[name] = b""
                else:
                    descriptors[name] = descriptor
                    images[name] = _read_partial_journal_image_unlocked(
                        directory_descriptor, name, descriptor
                    )

            if cursor_present:
                for name in JOURNAL_NAMES:
                    descriptor = descriptors.get(name)
                    if descriptor is None:
                        raise JournalLayoutError(
                            f"journal path {name} is missing after cursor"
                        )
                    _validate_initialized_journal_path_unlocked(
                        directory_descriptor, name, descriptor
                    )
                try:
                    os.fsync(directory_descriptor)
                except OSError as error:
                    raise JournalLayoutError("journal directory sync failed") from error
                completed = True
                return

            for name, image in images.items():
                expected = initial_journal_image(payloads[name])
                if not _is_safe_initial_path_fragment(name, image, expected):
                    raise JournalLayoutError(f"journal path {name} is not recoverable")

            for name, path_descriptor in mode_repair_descriptors.items():
                descriptors[name] = _repair_empty_journal_path_mode_unlocked(
                    directory_descriptor, name, path_descriptor
                )

            for name in JOURNAL_DATA_NAMES:
                descriptor = descriptors.get(name)
                if descriptor is None:
                    _create_journal_path_unlocked(
                        directory_descriptor, name, payloads[name]
                    )
                elif images[name] != initial_journal_image(payloads[name]):
                    _rewrite_initial_journal_path_unlocked(
                        directory_descriptor,
                        name,
                        descriptor,
                        payloads[name],
                    )
            try:
                os.fsync(directory_descriptor)
            except OSError as error:
                raise JournalLayoutError("journal directory sync failed") from error
            for name in JOURNAL_DATA_NAMES:
                _validate_initial_journal_path_unlocked(
                    directory_descriptor, name, payloads[name]
                )

            cursor_descriptor = descriptors.get(JOURNAL_CURSOR_NAME)
            if cursor_descriptor is None:
                _create_journal_path_unlocked(
                    directory_descriptor,
                    JOURNAL_CURSOR_NAME,
                    payloads[JOURNAL_CURSOR_NAME],
                )
            elif cursor != cursor_expected:
                _rewrite_initial_journal_path_unlocked(
                    directory_descriptor,
                    JOURNAL_CURSOR_NAME,
                    cursor_descriptor,
                    payloads[JOURNAL_CURSOR_NAME],
                )
            for name in JOURNAL_NAMES:
                _validate_initial_journal_path_unlocked(
                    directory_descriptor, name, payloads[name]
                )
            try:
                os.fsync(directory_descriptor)
            except OSError as error:
                # A readable cursor does not prove its directory entry reached
                # storage. A later initialization retries the directory sync.
                raise JournalLayoutError("journal directory sync failed") from error
            completed = True
        finally:
            first_error = _close_descriptors(
                reversed(tuple(descriptors.values()))
            )
            repair_error = _close_descriptors(
                reversed(tuple(mode_repair_descriptors.values()))
            )
            if first_error is None:
                first_error = repair_error
            if first_error is not None and completed:
                raise JournalLayoutError(
                    "journal partial descriptor close failed"
                ) from first_error


def load_journal_state(chain: JournalDirectoryChain) -> JournalState:
    """Load the complete validated journal through retained descriptors."""
    chain.validate()
    directory_descriptor = chain.directory_descriptor
    with _journal_lock(directory_descriptor, exclusive=False):
        descriptors: dict[str, int] = {}
        completed = False
        try:
            chain.validate()
            for name in JOURNAL_NAMES:
                try:
                    descriptor = os.open(
                        name,
                        os.O_RDONLY
                        | os.O_NONBLOCK
                        | os.O_NOFOLLOW
                        | os.O_CLOEXEC,
                        dir_fd=directory_descriptor,
                    )
                except OSError as error:
                    raise JournalLayoutError(
                        f"journal path {name} open failed"
                    ) from error
                descriptors[name] = descriptor
                _validate_journal_path_identity(
                    directory_descriptor,
                    name,
                    descriptor,
                    JOURNAL_FILE_SIZE,
                    writable=False,
                )

            payloads: dict[str, str] = {}
            for name in JOURNAL_NAMES:
                descriptor = descriptors[name]
                _validate_journal_path_identity(
                    directory_descriptor,
                    name,
                    descriptor,
                    JOURNAL_FILE_SIZE,
                    writable=False,
                )
                try:
                    _index, frame = _read_journal_file_unlocked(descriptor)
                except (JournalFileError, JournalFrameError) as error:
                    raise JournalLayoutError(
                        f"journal path {name} is malformed"
                    ) from error
                _validate_journal_path_identity(
                    directory_descriptor,
                    name,
                    descriptor,
                    JOURNAL_FILE_SIZE,
                    writable=False,
                )
                payloads[name] = frame.payload

            state = decode_journal_state(payloads)
            for name in JOURNAL_NAMES:
                _validate_journal_path_identity(
                    directory_descriptor,
                    name,
                    descriptors[name],
                    JOURNAL_FILE_SIZE,
                    writable=False,
                )
            chain.validate()
            completed = True
            return state
        finally:
            first_error = _close_descriptors(
                reversed(tuple(descriptors.values()))
            )
            if first_error is not None and completed:
                raise JournalLayoutError(
                    "journal state descriptor close failed"
                ) from first_error


@contextlib.contextmanager
def _retain_journal_files_unlocked(
    chain: JournalDirectoryChain,
) -> Iterator[JournalDescriptorSet]:
    """Open under the caller's lock; retain every file until context exit."""
    chain.validate()
    directory_descriptor = chain.directory_descriptor
    journal = JournalDescriptorSet(chain, {}, writable=True)
    completed = False
    try:
        for name in JOURNAL_NAMES:
            try:
                descriptor = os.open(
                    name,
                    os.O_RDWR | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC,
                    dir_fd=directory_descriptor,
                )
            except OSError as error:
                raise JournalLayoutError(
                    f"journal path {name} writable open failed"
                ) from error
            journal._descriptors[name] = descriptor
            _validate_journal_path_identity(
                directory_descriptor, name, descriptor, JOURNAL_FILE_SIZE,
            )

        journal.validate()
        try:
            yield journal
        except BaseException as body_error:
            try:
                journal.validate()
            except JournalLayoutError as validation_error:
                raise body_error from validation_error
            raise
        journal.validate()
        completed = True
    finally:
        journal.closed = True
        first_error = _close_descriptors(
            reversed(tuple(journal._descriptors.values()))
        )
        if first_error is not None and completed:
            raise JournalLayoutError(
                "writable journal descriptor close failed"
            ) from first_error


@contextlib.contextmanager
def retain_writable_journal(
    chain: JournalDirectoryChain,
) -> Iterator[JournalDescriptorSet]:
    """Retain exact files without holding a lock during external service work.

    Callers use lock_writable_journal for every state read and checkpoint,
    and validate the retained identities immediately before external mutations.
    """
    with contextlib.ExitStack() as retained:
        with _journal_lock(chain.directory_descriptor, exclusive=True):
            journal = retained.enter_context(_retain_journal_files_unlocked(chain))
        yield journal


@contextlib.contextmanager
def lock_writable_journal(
    journal: JournalDescriptorSet,
) -> Iterator[JournalDescriptorSet]:
    """Revalidate retained identities around one bounded exclusive interval."""
    if not isinstance(journal, JournalDescriptorSet) or not journal.writable:
        raise JournalLayoutError("writable journal descriptor set is invalid")
    if journal._exclusive:
        raise JournalLockError("journal exclusive interval is already active")
    journal.validate()
    with _journal_lock(journal.chain.directory_descriptor, exclusive=True):
        journal.validate()
        journal._exclusive = True
        try:
            try:
                yield journal
            except BaseException as body_error:
                try:
                    journal.validate()
                except JournalLayoutError as validation_error:
                    raise body_error from validation_error
                raise
            journal.validate()
        finally:
            journal._exclusive = False


@contextlib.contextmanager
def open_writable_journal(
    chain: JournalDirectoryChain,
) -> Iterator[JournalDescriptorSet]:
    """Retain the complete writable journal under one exclusive lock."""
    chain.validate()
    with _journal_lock(chain.directory_descriptor, exclusive=True):
        with _retain_journal_files_unlocked(chain) as journal:
            journal._exclusive = True
            try:
                yield journal
            finally:
                journal._exclusive = False


def _require_exclusive_journal(journal: JournalDescriptorSet) -> None:
    if not isinstance(journal, JournalDescriptorSet) or not journal.writable:
        raise JournalLayoutError("writable journal descriptor set is invalid")
    if not journal._exclusive:
        raise JournalLockError("journal state access requires an exclusive interval")


def _load_writable_journal_state(
    journal: JournalDescriptorSet,
) -> tuple[JournalState, dict[str, JournalFrame]]:
    _require_exclusive_journal(journal)
    journal.validate()
    payloads: dict[str, str] = {}
    frames: dict[str, JournalFrame] = {}
    for name in JOURNAL_NAMES:
        descriptor = journal.descriptor(name)
        try:
            _index, frame = _read_journal_file_unlocked(descriptor)
        except (JournalFileError, JournalFrameError) as error:
            raise JournalLayoutError(f"journal path {name} is malformed") from error
        payloads[name] = frame.payload
        frames[name] = frame
    state = decode_journal_state(payloads)
    journal.validate()
    return state, frames


def load_writable_journal_state(journal: JournalDescriptorSet) -> JournalState:
    """Decode the complete state through an exclusively locked descriptor set."""
    state, _frames = _load_writable_journal_state(journal)
    return state


def _native_owner_descriptor(journal: JournalDescriptorSet, operation: JournalOperation) -> int:
    _require_exclusive_journal(journal)
    if (not isinstance(operation, JournalOperation)
            or operation.kind not in {"timezone", "ntp", "locale", "delegate"}
            or operation.state in shared.JOURNAL_OPERATION_TERMINAL_STATES
            or load_writable_journal_state(journal).active != operation):
        raise JournalAdmissionError("native lease target is not the exact active operation")
    return journal.descriptor("active")


def _try_native_owner_lock(descriptor: int) -> bool:
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError as error:
        if error.errno in {errno.EACCES, errno.EAGAIN}:
            return False
        raise JournalLockError("native owner lease acquisition failed") from error


def _unlock_native_owner(descriptor: int) -> None:
    try:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
    except OSError as error:
        raise JournalLockError("native owner lease release failed") from error


@contextlib.contextmanager
def retain_native_journal_owner(
    journal: JournalDescriptorSet, operation: JournalOperation,
) -> Iterator[None]:
    """Enter beside admission under the directory lock; retain only a file lease.

    Use an ExitStack to retain this context after the short directory interval
    ends, and close it before closing the retained journal. This lease is local
    operation liveness, not authorization or proof of a platform result.
    """
    _native_owner_descriptor(journal, operation)
    try:
        # A separate open file description is essential: flock on dup(active)
        # would let a probe through active release the owner's own lock.
        lease_descriptor = os.open("active",
            os.O_RDWR | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=journal.chain.directory_descriptor)
    except OSError as error:
        raise JournalLockError("native owner lease descriptor open failed") from error
    try:
        _validate_journal_path_identity(journal.chain.directory_descriptor, "active",
                                       lease_descriptor, JOURNAL_FILE_SIZE)
        journal.validate()
        if not _try_native_owner_lock(lease_descriptor):
            journal.validate()
            raise JournalAdmissionError("another live native owner holds the lease")
        try:
            journal.validate()
            yield
        finally:
            _unlock_native_owner(lease_descriptor)
    finally:
        error = _close_descriptors((lease_descriptor,))
        if error is not None:
            raise JournalLockError("native owner lease descriptor close failed") from error


def native_journal_owner_busy(journal: JournalDescriptorSet, operation: JournalOperation) -> bool:
    """Probe nonblocking under the directory lock without releasing our own lease."""
    descriptor = _native_owner_descriptor(journal, operation)
    if not _try_native_owner_lock(descriptor):
        journal.validate()
        return True
    try:
        journal.validate()
        return False
    finally:
        _unlock_native_owner(descriptor)


def commit_writable_journal_path(
    journal: JournalDescriptorSet, name: str, payload: str
) -> tuple[int, JournalFrame]:
    """Commit one retained path between complete journal identity checks."""
    _require_exclusive_journal(journal)
    journal.validate()
    descriptor = journal.descriptor(name)
    try:
        result = _commit_journal_file_unlocked(descriptor, payload)
    except JournalCommitError as commit_error:
        try:
            journal.validate()
        except JournalLayoutError as validation_error:
            raise commit_error from validation_error
        raise
    journal.validate()
    return result


def generate_journal_operation_id(state: JournalState) -> str:
    """Generate a unique journal operation ID from the kernel CSPRNG."""
    if (
        not isinstance(state, JournalState)
        or not isinstance(state.restart, JournalRestart)
        or not isinstance(state.terminals, tuple)
        or len(state.terminals) != JOURNAL_TERMINAL_COUNT
        or any(
            operation is not None and not isinstance(operation, JournalOperation)
            for operation in state.terminals
        )
        or (state.active is not None and not isinstance(state.active, JournalOperation))
    ):
        raise JournalAdmissionError("journal operation ID state is invalid")
    operations = tuple(
        operation for operation in state.terminals if operation is not None
    ) + ((state.active,) if state.active is not None else ())
    operation_ids = tuple(operation.operation_id for operation in operations)
    restart_operation_id = state.restart.last_applied_operation_id
    if any(
        not isinstance(operation_id, str)
        or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(operation_id) is None
        for operation_id in operation_ids
    ) or (
        restart_operation_id is not None
        and (
            not isinstance(restart_operation_id, str)
            or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(restart_operation_id) is None
        )
    ):
        raise JournalAdmissionError("journal operation ID state is invalid")
    retained_ids = set(operation_ids)
    if restart_operation_id is not None:
        retained_ids.add(restart_operation_id)
    for _attempt in range(JOURNAL_OPERATION_ID_ATTEMPTS):
        try:
            random_bytes = os.urandom(16)
        except OSError as error:
            raise JournalAdmissionError(
                "journal operation ID generation failed"
            ) from error
        if not isinstance(random_bytes, bytes) or len(random_bytes) != 16:
            raise JournalAdmissionError("journal operation ID generation failed")
        operation_id = f"op-{random_bytes.hex()}"
        if operation_id not in retained_ids:
            return operation_id
    raise JournalAdmissionError("journal operation ID collision limit reached")


def prepare_journal_admission(journal: JournalDescriptorSet) -> JournalAdmission:
    """Select a reusable ring slot when no operation or handoff blocks admission."""
    state, frames = _load_writable_journal_state(journal)
    if state.active is not None or state.handoff is not None:
        raise JournalAdmissionError("journal operation admission is blocked")
    for name, required_commits in JOURNAL_CONTROL_ADMISSION_COMMITS.items():
        if frames[name].sequence >= shared.JOURNAL_SEQUENCE_MAX - required_commits:
            raise JournalAdmissionError("journal control path has no commit headroom")
    for offset in range(JOURNAL_TERMINAL_COUNT):
        slot = (state.cursor + offset) % JOURNAL_TERMINAL_COUNT
        if frames[f"terminal-{slot:02d}"].sequence < shared.JOURNAL_SEQUENCE_MAX - 1:
            return JournalAdmission(state, slot, generate_journal_operation_id(state))
    raise JournalAdmissionError("journal has no reusable terminal slot")


def begin_journal_operation(
    journal: JournalDescriptorSet,
    action_id: str,
    started_at: str,
    detail: str,
    *,
    transaction_path: str | None = None,
    generation: str | None = None,
    boot_id: str | None = None,
) -> JournalOperation:
    """Reserve and durably publish pending before the caller can mutate anything.

    The caller holds open_writable_journal only for this local critical section,
    never while creating a service transaction or waiting for its result.
    """
    admission = prepare_journal_admission(journal)
    kind = shared.JOURNAL_OPERATION_ACTION_KINDS.get(action_id)
    operation = JournalOperation(
        admission.operation_id,
        action_id,
        started_at,
        None,
        kind,
        "pending",
        None,
        detail,
        generation,
        transaction_path,
        "none" if kind == "update" else None,
        "none" if kind == "update" else None,
        False if kind == "update" else None,
        boot_id if kind != "refresh" else None,
        None,
        admission.slot,
    )
    payload = encode_journal_operation(operation)
    # Refresh terminal timestamps also use this boot's monotonic clock. Reject
    # stale boot evidence for both PackageKit kinds before comparing history.
    if kind in ("refresh", "update") and boot_id != admission.state.restart.boot_id:
        raise JournalAdmissionError("journal boot boundary needs recovery")
    commit_writable_journal_path(journal, "active", payload)
    return operation


def advance_journal_operation(
    journal: JournalDescriptorSet,
    expected: JournalOperation,
    following: JournalOperation,
    *,
    recovery_boot_id: str | None = None,
) -> JournalOperation:
    """Commit one legal state/contribution change, rejecting stale observations."""
    encode_journal_operation(expected)
    payload = encode_journal_operation(following)
    state = load_writable_journal_state(journal)
    current = state.active
    if current != expected:
        raise JournalAdmissionError("journal active operation changed")
    if following == expected:
        return current
    immutable = (
        "operation_id",
        "action_id",
        "started_at",
        "kind",
        "generation",
        "transaction_path",
        "boot_id",
        "slot",
    )
    if any(
        getattr(expected, field) != getattr(following, field) for field in immutable
    ):
        raise JournalAdmissionError("journal operation identity changed")
    # RequireRestart can strengthen a tuple before running or during authorization.
    same_state = following.state == expected.state
    if expected.state in shared.JOURNAL_OPERATION_TERMINAL_STATES or (
        not same_state and following.state not in shared.JOURNAL_TRANSITIONS[expected.state]
    ):
        raise JournalAdmissionError("journal operation transition is invalid")
    recovery_replacement = False
    if recovery_boot_id is not None:
        if (not isinstance(recovery_boot_id, str) or shared.BOOT_ID_PATTERN.fullmatch(recovery_boot_id) is None
                or expected.kind != "update" or following.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES):
            raise JournalAdmissionError("journal recovery boundary is invalid")
        recovery_replacement = (
            recovery_boot_id != expected.boot_id
            and (following.system_restart, following.session_restart, following.application_restart) == ("none", "none", False)
        ) or (
            recovery_boot_id == expected.boot_id and following.system_restart == "unknown"
            and following.session_restart == expected.session_restart
            and following.application_restart == expected.application_restart
        )
    if expected.kind == "update" and not recovery_replacement and (
        shared.JOURNAL_RESTART_SYSTEM_STRENGTH[following.system_restart]
        < shared.JOURNAL_RESTART_SYSTEM_STRENGTH[expected.system_restart]
        or shared.JOURNAL_RESTART_SESSION_STRENGTH[following.session_restart]
        < shared.JOURNAL_RESTART_SESSION_STRENGTH[expected.session_restart]
        or (expected.application_restart and not following.application_restart)
    ):
        raise JournalAdmissionError("journal restart contribution weakened")
    # Progress/detail-only changes are in-memory; reserve frame headroom for
    # actual lifecycle and strictly stronger restart contributions only.
    if same_state and (
        expected.system_restart,
        expected.session_restart,
        expected.application_restart,
    ) == (
        following.system_restart,
        following.session_restart,
        following.application_restart,
    ):
        raise JournalAdmissionError("journal operation has no durable change")
    # A valid individual record can still contradict retained history (for
    # example, a stale monotonic cutoff). Reject it before poisoning active.
    prospective = {
        "active": payload,
        "restart": encode_journal_restart(state.restart),
        "cursor": encode_journal_cursor(state.cursor),
        "handoff": encode_journal_handoff(state.handoff),
        **{
            f"terminal-{slot:02d}": (
                "" if operation is None else encode_journal_operation(operation)
            )
            for slot, operation in enumerate(state.terminals)
        },
    }
    decode_journal_state(prospective)
    commit_writable_journal_path(journal, "active", payload)
    return following


def prune_journal_restart(
    journal: JournalDescriptorSet,
    boot_id: str,
    session_started: int | None,
) -> JournalRestart:
    """Apply already-obtained boot/logind evidence; no service calls under lock."""
    if not isinstance(boot_id, str) or shared.BOOT_ID_PATTERN.fullmatch(boot_id) is None:
        raise JournalRecordError("journal restart boot identity is invalid")
    if session_started is not None:
        _encode_journal_uint64(session_started, "session start")
    restart = load_writable_journal_state(journal).restart
    if restart.boot_id != boot_id:
        pruned = JournalRestart(boot_id, None, "none", "none", 0, False, 0)
    else:
        pruned = restart
        if session_started is not None:
            if session_started > restart.session_cutoff:
                pruned = replace(pruned, session="none", session_cutoff=0)
            if session_started > restart.application_cutoff:
                pruned = replace(pruned, application=False, application_cutoff=0)
    if pruned != restart:
        commit_writable_journal_path(journal, "restart", encode_journal_restart(pruned))
    return pruned


def complete_journal_terminal(
    journal: JournalDescriptorSet,
    *,
    boot_id: str | None = None,
    session_started: int | None = None,
) -> JournalOperation | None:
    """Idempotently finish a durable terminal checkpoint through its handoff.

    Callers checkpoint the final result with advance_journal_operation first.
    Every return implies all required commits were synced and identity-checked;
    any failure leaves the last durable checkpoint for bounded recovery.
    """
    state = load_writable_journal_state(journal)
    operation = state.active
    if operation is None:
        return None
    if operation.state not in shared.JOURNAL_OPERATION_TERMINAL_STATES:
        raise JournalAdmissionError("journal operation is not terminal")
    if operation.kind == "update":
        restart = prune_journal_restart(journal, boot_id, session_started)
        if (
            operation.boot_id == boot_id
            and restart.last_applied_operation_id != operation.operation_id
        ):
            restart = replace(
                restart,
                last_applied_operation_id=operation.operation_id,
                system=max(
                    restart.system,
                    operation.system_restart,
                    key=shared.JOURNAL_RESTART_SYSTEM_STRENGTH.__getitem__,
                ),
                session=max(
                    restart.session,
                    operation.session_restart,
                    key=shared.JOURNAL_RESTART_SESSION_STRENGTH.__getitem__,
                ),
                session_cutoff=(
                    operation.terminal_monotonic
                    if operation.session_restart != "none"
                    else restart.session_cutoff
                ),
                application=restart.application or operation.application_restart,
                application_cutoff=(
                    operation.terminal_monotonic
                    if operation.application_restart
                    else restart.application_cutoff
                ),
            )
            # A recovered checkpoint can predate the current login. Its original
            # cutoff is authoritative; never reintroduce already satisfied work.
            if session_started is not None:
                if session_started > restart.session_cutoff:
                    restart = replace(restart, session="none", session_cutoff=0)
                if session_started > restart.application_cutoff:
                    restart = replace(restart, application=False, application_cutoff=0)
            commit_writable_journal_path(
                journal, "restart", encode_journal_restart(restart)
            )
    payload = encode_journal_operation(operation)
    name = f"terminal-{operation.slot:02d}"
    if state.terminals[operation.slot] != operation:
        commit_writable_journal_path(journal, name, payload)
    cursor = (operation.slot + 1) % JOURNAL_TERMINAL_COUNT
    if state.cursor != cursor:
        commit_writable_journal_path(journal, "cursor", encode_journal_cursor(cursor))
    handoff = JournalHandoff(operation.operation_id, operation.slot)
    if state.handoff != handoff:
        commit_writable_journal_path(
            journal, "handoff", encode_journal_handoff(handoff)
        )
    commit_writable_journal_path(journal, "active", "")
    load_writable_journal_state(journal)
    return operation


def retained_journal_operation(
    journal: JournalDescriptorSet, operation_id: str
) -> JournalOperation:
    """Find exactly the requested retained terminal, independent of ring age."""
    if (
        not isinstance(operation_id, str)
        or shared.JOURNAL_OPERATION_ID_PATTERN.fullmatch(operation_id) is None
    ):
        raise JournalRecordError("journal operation ID is invalid")
    state = load_writable_journal_state(journal)
    if state.active is not None:
        raise JournalAdmissionError("journal active operation needs recovery")
    for operation in state.terminals:
        if operation is not None and operation.operation_id == operation_id:
            return operation
    raise JournalAdmissionError("journal terminal operation is unavailable")


def acknowledge_journal_handoff(
    journal: JournalDescriptorSet, operation_id: str
) -> None:
    """Clear only an exact validated handoff, retaining its audit evidence."""
    operation = retained_journal_operation(journal, operation_id)
    state = load_writable_journal_state(journal)
    if state.handoff != JournalHandoff(operation_id, operation.slot):
        raise JournalAdmissionError("journal handoff is unavailable")
    commit_writable_journal_path(journal, "handoff", "")
