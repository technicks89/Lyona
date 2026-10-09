#!/usr/bin/python3
"""watch-domains (#286) against fixed services on a private bus: two domains'
real monitors in one process, each line tagged with its domain, and a change
in one never reported as the other's."""

import os
import selectors
import subprocess
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

PACKAGEKIT = "org.freedesktop.PackageKit"
TIMEDATE = "org.freedesktop.timedate1"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
address = os.environ["DBUS_SESSION_BUS_ADDRESS"]


def own(name):
    reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
        "RequestName", GLib.Variant("(su)", (name, 0)), GLib.VariantType.new("(u)"),
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
    assert reply == 1, name


def lines(process, count, timeout=5):
    """Collect COUNT lines, or what arrived before the deadline."""
    output = b""
    deadline = time.monotonic() + timeout
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while output.count(b"\n") < count and time.monotonic() < deadline:
            if selector.select(max(0, deadline - time.monotonic())):
                chunk = os.read(process.stdout.fileno(), 1)
                if not chunk:
                    break
                output += chunk
    return output.decode().splitlines()


own(PACKAGEKIT)
own(TIMEDATE)
process = subprocess.Popen([sys.argv[1], "watch-domains"], env=dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=address),
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
try:
    process.stdin.write(b"start updates\nstart time\n")
    ready = sorted(lines(process, 2))
    assert ready == ["time\ttime-event\tready", "updates\tupdate-event\tready"], ready
    # Starting a domain already running adds nothing.
    process.stdin.write(b"start updates\n")
    assert lines(process, 1, 0.3) == [], "a second start re-subscribed"

    bus.emit_signal(None, "/org/freedesktop/PackageKit", PACKAGEKIT, "UpdatesChanged", None)
    bus.flush_sync(None)
    assert lines(process, 1) == ["updates\tupdate-event\tchanged"]
    bus.emit_signal(None, "/org/freedesktop/timedate1", "org.freedesktop.DBus.Properties", "PropertiesChanged",
        GLib.Variant("(sa{sv}as)", (TIMEDATE, {}, ["Timezone"])))
    bus.flush_sync(None)
    assert lines(process, 1) == ["time\ttime-event\tchanged"]
    assert lines(process, 1, 0.3) == [], "an idle watcher printed"

    # The consumer going away ends it, cleanly.
    process.stdin.close()
    assert process.wait(timeout=5) == 0
    assert process.stderr.read() == b""
finally:
    if process.poll() is None:
        process.kill()
        process.wait(timeout=3)
print("watch-domains private-bus monitors: PASS")
