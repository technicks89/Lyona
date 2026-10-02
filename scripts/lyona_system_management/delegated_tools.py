"""Trusted delegated administration tools and the terminal they open in."""

from __future__ import annotations

import os
import selectors
import shutil
import signal
import stat
import subprocess
import threading
import time
from typing import Mapping

from . import regional_settings, shared


# D-3 (docs/UPSTREAM-SYNC.md#open-decisions), decided 2026-09-15: neither
# upstream's lxqt-admin-user (accounts-open) nor dnfdragora (sources-open)
# exists in Arch's official repositories. Both ship permanent `unavailable`
# (see delegated_command()) rather than an unverified AUR dependency or a
# new privileged repo-editing surface. Only printers-open has a real fixed
# executable; system-config-printer is confirmed in Arch `extra`.
DELEGATED_TOOLS = {
    "printers-open": ("/usr/bin/system-config-printer", "Printers"),
}
PASSWORD_TERMINALS = {"alacritty": ("-e",), "kitty": (), "st": ("-e",), "xterm": ("-e",)}


# Sync Phase 9 (docs/SYNC-P9-REGIONAL-MUTATION.md §3): delegated
# administration for accounts/password/printers/software-sources.
# `password-open` has no fixed executable -- it resolves the user's already
# -configured terminal via Lyona's own `dwm-terminal --print-command`
# (the same contract upstream's read_terminal_selection() calls), matches it
# against PASSWORD_TERMINALS, and launches `<terminal> [-e] passwd`.
def trusted_delegated_executable(path: str, basename: str) -> str:
    """Resolve an unprivileged launch target into a root-controlled executable path."""
    try:
        resolved = os.path.realpath(path, strict=True)
        if os.path.basename(resolved) != basename:
            raise shared.SnapshotFailure("unsupported", "The configured administration command has an unsupported identity")
        current = resolved
        while True:
            value = os.stat(current, follow_symlinks=False)
            expected_type = stat.S_ISREG if current == resolved else stat.S_ISDIR
            if not expected_type(value.st_mode) or value.st_uid != 0 or value.st_mode & 0o022:
                raise shared.SnapshotFailure("unsupported", "The administration command is not in a root-controlled executable path")
            if current == "/":
                break
            current = os.path.dirname(current)
        if not os.access(resolved, os.X_OK):
            raise shared.SnapshotFailure("permission-denied", "The administration command is not executable")
        return resolved
    except FileNotFoundError as error:
        raise shared.SnapshotFailure("missing-provider", "The required administration command is not installed") from error
    except OSError as error:
        raise shared.SnapshotFailure("internal", "The administration command could not be inspected") from error


def terminal_selection_environment() -> dict[str, str]:
    """Preserve only terminal-selection inputs, never shell startup or loader overrides."""
    result = {"PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"), "LANG": "C", "LC_ALL": "C"}
    for name in ("HOME", "XDG_CONFIG_HOME", "DWM_TERMINAL"):
        if name in os.environ:
            result[name] = os.environ[name]
    try:
        invalid = any(len(value.encode("utf-8")) > 4096 or "\0" in value for value in result.values())
    except UnicodeError:
        invalid = True
    if not result.get("HOME", "").startswith("/") or invalid:
        raise shared.SnapshotFailure("malformed", "Terminal selection environment is unavailable or oversized")
    return result


def read_terminal_selection(helper: str, environment: Mapping[str, str]) -> str:
    """Bound the managed helper's read-only terminal selection without capturing passwords."""
    if (threading.current_thread() is not threading.main_thread()
            or signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL):
        raise shared.SnapshotFailure("internal", "Terminal selection process ownership is unavailable")
    process, handlers, interrupted = None, {}, 0

    def terminate(number, _frame):
        nonlocal interrupted
        interrupted = interrupted or number

    def check_deadline():
        if interrupted:
            raise SystemExit(128 + interrupted)
        if time.monotonic() >= deadline:
            raise shared.SnapshotFailure("timeout", "Terminal selection timed out")

    try:
        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            handlers[number] = signal.signal(number, terminate)
        deadline = time.monotonic() + 3
        # A fixed interpreter avoids resolving the helper's env shebang through
        # the user's PATH. The helper only prints its selected command identity.
        check_deadline()
        process = subprocess.Popen(["/usr/bin/timeout", "--signal=TERM", "--kill-after=1", "3",
            "/usr/bin/bash", helper, "--print-command"], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, env=dict(environment))
        output, received = bytearray(), 0
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
                        chunk = os.read(key.fd, min(4096, 4096 - received + 1))
                    except BlockingIOError:
                        continue
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    received += len(chunk)
                    if received > 4096:
                        raise shared.SnapshotFailure("malformed", "Terminal selection output is oversized")
                    if key.fileobj is process.stdout:
                        output.extend(chunk)
        check_deadline()
        code = status.si_status if status.si_code == os.CLD_EXITED else -status.si_status
        if code in (124, 137, -signal.SIGKILL):
            raise shared.SnapshotFailure("timeout", "Terminal selection timed out")
        if code != 0:
            raise shared.SnapshotFailure("missing-provider" if code == 127 else "internal", "Terminal selection failed")
        try:
            value = bytes(output).decode("utf-8")
        except UnicodeDecodeError as error:
            check_deadline()
            raise shared.SnapshotFailure("malformed", "Terminal selection is not UTF-8") from error
        valid = value.endswith("\n") and bool(value[:-1]) and value[:-1].isprintable()
        check_deadline()
        if not valid:
            raise shared.SnapshotFailure("malformed", "Terminal selection is not one command identity")
        return value[:-1]
    except FileNotFoundError as error:
        raise shared.SnapshotFailure("missing-provider", "Terminal selection helper is unavailable") from error
    except OSError as error:
        raise shared.SnapshotFailure("internal", "Terminal selection failed") from error
    finally:
        try:
            if process is not None:
                try:
                    regional_settings.close_locale_process(process)
                except shared.SnapshotFailure as error:
                    raise shared.SnapshotFailure("timeout", "Terminal selection cleanup could not be confirmed") from error
        finally:
            for number, handler in handlers.items():
                signal.signal(number, handler)
            if interrupted:
                raise SystemExit(128 + interrupted)


def delegated_command(action: str) -> tuple[tuple[str, ...], str]:
    """Resolve only fixed administration entries; unavailable tools are capability-local."""
    if not isinstance(action, str) or action not in shared.DELEGATED_ACTIONS:
        raise shared.SnapshotFailure("malformed", "Unknown delegated administration action")
    if action == "accounts-open":
        raise shared.SnapshotFailure("unsupported",
            "No account-management tool is packaged for Arch; see docs/src/settings.md", "unsupported")
    if action == "sources-open":
        raise shared.SnapshotFailure("unsupported",
            "No interactive repository editor is packaged for Arch; edit /etc/pacman.conf directly, "
            "see docs/src/settings.md", "unsupported")
    if action in DELEGATED_TOOLS:
        path, label = DELEGATED_TOOLS[action]
        return (trusted_delegated_executable(path, os.path.basename(path)),), label
    # action == "password-open"
    passwd = trusted_delegated_executable("/usr/bin/passwd", "passwd")
    environment = terminal_selection_environment()
    helper = shutil.which("dwm-terminal", path=environment["PATH"])
    if helper is None:
        raise shared.SnapshotFailure("missing-provider", "The managed terminal selector is not installed")
    helper = trusted_delegated_executable(helper, "dwm-terminal")
    selected = read_terminal_selection(helper, environment)
    name = os.path.basename(selected)
    if name not in PASSWORD_TERMINALS:
        raise shared.SnapshotFailure("unsupported", "The configured terminal has no supported password-launch form; run passwd in your terminal")
    terminal = shutil.which(selected, path=environment["PATH"])
    if terminal is None:
        raise shared.SnapshotFailure("missing-provider", "The selected terminal is no longer installed")
    terminal = trusted_delegated_executable(terminal, name)
    return (terminal, *PASSWORD_TERMINALS[name], passwd), "Password change"


def launch_delegated_tool(command: tuple[str, ...]) -> None:
    """Accept a resolved fixed exec without waiting for the tool's internal administration."""
    if not hasattr(os, "POSIX_SPAWN_CLOSEFROM"):
        raise shared.SnapshotFailure("unsupported", "Isolated administration launches are unavailable")
    accepted = False
    try:
        null = os.open("/dev/null", os.O_RDWR | os.O_CLOEXEC)
        try:
            actions = [(os.POSIX_SPAWN_DUP2, null, descriptor) for descriptor in (0, 1, 2)]
            actions.append((os.POSIX_SPAWN_CLOSEFROM, 3))
            os.posix_spawn(command[0], command, dict(os.environ), file_actions=actions,
                setsid=True, setsigmask=(),
                setsigdef=(signal.SIGPIPE, signal.SIGINT, signal.SIGTERM, signal.SIGHUP))
            accepted = True
        finally:
            os.close(null)
    except FileNotFoundError as error:
        raise shared.SnapshotFailure("missing-provider", "The administration tool is no longer installed") from error
    except PermissionError as error:
        raise shared.SnapshotFailure("permission-denied", "The administration tool could not be launched") from error
    except NotImplementedError as error:
        raise shared.SnapshotFailure("unsupported", "Isolated administration launches are unavailable") from error
    except OSError as error:
        if accepted or isinstance(error, InterruptedError):
            raise shared.SnapshotFailure("interrupted", "Administration launch observation was interrupted; the tool may already be open") from error
        raise shared.SnapshotFailure("internal", "The administration tool could not be launched") from error
