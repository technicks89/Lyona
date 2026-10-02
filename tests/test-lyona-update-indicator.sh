#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 15 S15-02: scripts/lyona-update-indicator against a stub
# checkupdates and a fake NetworkManager on a private bus. A count is reported
# for pending updates, current for none, and a failure or a timeout as an error,
# never as current; the settings take only the allowed values, default
# otherwise, and are private; watch-network reports a connection only when the
# state reaches full connectivity from below.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper=$repo/scripts/lyona-update-indicator
export XDG_CONFIG_HOME=$work/config
conf=$XDG_CONFIG_HOME/lyona/update-indicator.conf

cat >"$work/bin/checkupdates" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/log"
case ${STUB_MODE:-updates} in
updates) printf 'linux 6.17.1-1 -> 6.17.2-1\nmesa 1:25.2.4-1 -> 1:25.2.5-1\nvim 9.1-1 -> 9.1-2\n' ;;
none) exit 2 ;;
fail) exit 1 ;;
hang) sleep 30 ;;
esac
EOF
chmod +x "$work/bin/checkupdates"
export STUB_DIR=$work
: >"$work/log"

run() { PATH="$work/bin:$PATH" "$helper" "$@"; }
header=$'update-indicator-protocol\t1\t0'

out=$(run check)
[[ $out == "$header"$'\nprovider\tsystem\tavailable\t3\t3 package updates\ncomplete\tcheck' ]] ||
	fail "three updates: $out"
grep -Fqx -- '--nocolor' "$work/log" || fail "checkupdates was not run with --nocolor"
out=$(STUB_MODE=none run check)
[[ $out == *$'provider\tsystem\tcurrent\t0\tPackages are up to date'* ]] || fail "no updates: $out"
out=$(STUB_MODE=fail run check)
[[ $out == *$'provider\tsystem\terror\t0\t'* ]] || fail "a failed check was not an error: $out"
# A stalled check is ended and reported, not left open (the bound is shortened here).
stage_helpers checkout "$work/short" lyona-update-indicator
sed -i 's/^readonly check_seconds=180$/readonly check_seconds=1/' "$work/short/lyona-update-indicator"
grep -q '^readonly check_seconds=1$' "$work/short/lyona-update-indicator" || fail 'could not shorten the check bound'
SECONDS=0
out=$(STUB_MODE=hang PATH="$work/bin:$PATH" "$work/short/lyona-update-indicator" check)
((SECONDS < 15)) || fail "a stalled check ran for ${SECONDS}s"
[[ $out == *$'provider\tsystem\terror\t0\tThe package check timed out'* ]] || fail "a stalled check: $out"
# Without checkupdates the provider is unavailable, with the package to install.
mkdir -p "$work/nobin"
for cmd in bash awk timeout mktemp mkdir mv chmod rm dirname cat; do
	ln -sf "$(command -v "$cmd")" "$work/nobin/$cmd"
done
out=$(PATH="$work/nobin" "$helper" check)
[[ $out == *$'provider\tsystem\tunavailable\t0\tInstall pacman-contrib'* ]] || fail "no checkupdates: $out"

# Settings: defaults, the allowed values, and nothing else.
out=$(run status)
[[ $out == "$header"$'\nsetting\tinterval-hours\t6\nsetting\tshow-when-current\tno\ncomplete\tstatus' ]] ||
	fail "default settings: $out"
[[ ! -e $conf ]] || fail 'status wrote the settings file'
run set-interval 12 >/dev/null
run set-show-when-current yes >/dev/null
out=$(run status)
[[ $out == *$'interval-hours\t12'* && $out == *$'show-when-current\tyes'* ]] || fail "saved settings: $out"
[[ $(stat -c %a "$conf") == 600 ]] || fail "the settings file is $(stat -c %a "$conf"), not 600"
for bad in 0 2 25 -1 6h ''; do
	if run set-interval "$bad" >/dev/null 2>&1; then fail "set-interval accepted '$bad'"; fi
done
if run set-show-when-current maybe >/dev/null 2>&1; then fail 'set-show-when-current accepted maybe'; fi
[[ $(run status) == *$'interval-hours\t12'* ]] || fail 'a rejected value changed the settings'
# A hand-edited bad value reads as the default.
printf 'interval-hours=7\nshow-when-current=sure\n' >"$conf"
out=$(run status)
[[ $out == *$'interval-hours\t6'* && $out == *$'show-when-current\tno'* ]] || fail "bad stored values: $out"
# A symlinked settings file is never written through.
rm -f "$conf"
ln -s "$work/elsewhere" "$conf"
if run set-interval 3 >/dev/null 2>&1; then fail 'wrote through a symlinked settings file'; fi
[[ ! -e $work/elsewhere ]] || fail 'the symlink target was created'
rm -f "$conf"
if run frobnicate >/dev/null 2>&1; then fail 'an unknown action succeeded'; fi

# watch-network against a fake NetworkManager, on a private bus standing in for
# the system bus.
if ! command -v dbus-run-session >/dev/null 2>&1 || ! python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null; then
	printf 'lyona-update-indicator: PASS (watch-network skipped: dbus-run-session or python-gobject missing)\n'
	exit 0
fi
cat >"$work/fake-nm.py" <<'EOF'
import sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

NAME = "org.freedesktop.NetworkManager"
PATH = "/org/freedesktop/NetworkManager"
XML = """<node><interface name="org.freedesktop.NetworkManager">
<property name="State" type="u" access="read"/>
<signal name="StateChanged"><arg type="u"/></signal></interface></node>"""
state = [int(sys.argv[1])]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
info = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]

def get_property(_c, _s, _p, _i, name):
    return GLib.Variant("u", state[0]) if name == "State" else None

bus.register_object(PATH, info, None, get_property, None)

def command(channel, _condition):
    line = channel.readline()
    if not line:
        loop.quit()
        return False
    state[0] = int(line)
    bus.emit_signal(None, PATH, NAME, "StateChanged", GLib.Variant("(u)", (state[0],)))
    bus.flush_sync(None)
    return True

def acquired(_connection, _name):
    print("owned", flush=True)

Gio.bus_own_name_on_connection(bus, NAME, Gio.BusNameOwnerFlags.NONE, acquired, None)
loop = GLib.MainLoop()
GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.IO_IN | GLib.IO_HUP, command)
loop.run()
EOF
cat >"$work/watch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
work=$1 helper=$2
export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
mkfifo "$work/nm.in"
# Already connected: the first full-connectivity reading is not a reconnect.
python3 -W ignore::DeprecationWarning "$work/fake-nm.py" 70 <"$work/nm.in" >"$work/nm.out" &
exec 3>"$work/nm.in"
for _ in $(seq 100); do grep -q owned "$work/nm.out" 2>/dev/null && break; sleep 0.05; done
grep -q owned "$work/nm.out"
"$helper" watch-network >"$work/events" &
watcher=$!
for _ in $(seq 100); do grep -q ready "$work/events" 2>/dev/null && break; sleep 0.05; done
# Connected again (no change), then a drop, then back: one event.
printf '70\n20\n50\n70\n' >&3
for _ in $(seq 100); do grep -q connected "$work/events" 2>/dev/null && break; sleep 0.05; done
sleep 0.3
kill "$watcher"
exec 3>&-
wait
EOF
chmod +x "$work/watch.sh"
timeout 30 dbus-run-session -- "$work/watch.sh" "$work" "$helper" || fail 'the watch-network run failed'
expected=$'network-event\tready\nnetwork-event\tconnected'
[[ $(cat "$work/events") == "$expected" ]] || fail "network events: $(cat "$work/events")"
# No bus at all: unavailable, and the helper exits.
out=$(DBUS_SYSTEM_BUS_ADDRESS=unix:path=$work/no-such-socket timeout 10 "$helper" watch-network) ||
	fail 'watch-network did not exit without a bus'
[[ $out == $'network-event\tunavailable' ]] || fail "no bus: $out"

printf 'lyona-update-indicator: PASS\n'
