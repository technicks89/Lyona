#!/usr/bin/python3
"""watch-domains for the test stubs of dwm-system-management (#286).

The real watch-domains runs every domain's monitor on one GLib loop. The stubs
only implement the separate watch-* commands, so this adapter gives them the
same protocol: "start DOMAIN" on stdin runs STUB's watch-* command for it,
each line it prints comes out as "DOMAIN<TAB>line", and its exit as
"DOMAIN<TAB>stopped<TAB>CODE". "stop DOMAIN" ends that child, whose exit is
the reply; stdin closing or SIGTERM stops every child.
"""
import os
import selectors
import signal
import subprocess
import sys

COMMANDS = {
    "updates": ["watch-updates"],
    "time": ["watch-time"],
    "locale": ["watch-regional", "locale"],
    "accounts": ["watch-accounts"],
    "printers": ["watch-units", "printers"],
    "security": ["watch-units", "security"],
    "storage": ["watch-mounts"],
}


def main(stub):
    selector = selectors.DefaultSelector()
    children = {}
    buffers = {}
    stopping = []

    def terminate(_number, _frame):
        stopping.append(True)

    signal.signal(signal.SIGTERM, terminate)
    selector.register(sys.stdin.fileno(), selectors.EVENT_READ, "stdin")
    pending = b""

    def emit(line):
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    while not stopping:
        try:
            events = selector.select(0.2)
        except InterruptedError:
            continue
        for key, _mask in events:
            if key.data == "stdin":
                chunk = os.read(key.fd, 4096)
                if not chunk:
                    stopping.append(True)
                    break
                pending += chunk
                while b"\n" in pending:
                    line, _, pending = pending.partition(b"\n")
                    words = line.decode().split(" ")
                    if len(words) != 2 or words[0] not in ("start", "stop") or words[1] not in COMMANDS:
                        return 1
                    domain = words[1]
                    if words[0] == "stop":
                        if domain in children:
                            children[domain].terminate()
                        continue
                    if domain in children:
                        continue
                    child = subprocess.Popen([stub] + COMMANDS[domain], stdin=subprocess.DEVNULL,
                                             stdout=subprocess.PIPE)
                    children[domain] = child
                    buffers[domain] = b""
                    selector.register(child.stdout.fileno(), selectors.EVENT_READ, domain)
            else:
                domain = key.data
                chunk = os.read(key.fd, 4096)
                if chunk:
                    buffers[domain] += chunk
                    while b"\n" in buffers[domain]:
                        line, _, buffers[domain] = buffers[domain].partition(b"\n")
                        emit(domain + "\t" + line.decode())
                    continue
                selector.unregister(key.fd)
                child = children.pop(domain)
                emit(f"{domain}\tstopped\t{child.wait()}")
    for child in children.values():
        child.terminate()
    for child in children.values():
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
