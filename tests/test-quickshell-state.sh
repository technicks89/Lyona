#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper="$repo/scripts/dwm-quickshell-state"
bin="$work/bin"
mkdir -p "$bin"

fail() {
	printf 'dwm-quickshell-state: %s\n' "$1" >&2
	[[ -n ${2:-} ]] && cat "$2" >&2
	exit 1
}

# A window's _NET_WM_PID does not decide whether it is listed (Sync Sprint 12
# S12-12): 0xdd claims pid 1 (root's) and is listed like the others.
root_pid=1
own_pid=$$

cat >"$bin/xprop" <<EOF
#!/bin/sh
# -root <props...>  |  -id <window> <props...>
printf '%s\n' "\$*" >>"$work/xprop.log"
if [ "\$1" = "-root" ] && [ "\$2" = "-spy" ]; then
	exec sleep 30
fi
if [ "\$1" = "-id" ] && [ "\$3" = "-spy" ]; then
	if [ "\$2" = "0xaa" ]; then
		while [ ! -f "$work/title-changed" ]; do sleep 0.05; done
		printf '_NET_WM_NAME(UTF8_STRING) = "Updated title"\n'
	elif [ "\$2" = "0xbb" ]; then
		while [ ! -f "$work/fallback-title-changed" ]; do sleep 0.05; done
		printf 'WM_NAME(STRING) = "Firefox Updated"\n'
	fi
	exec sleep 30
fi
if [ "\$1" = "-root" ] && [ "\$2" = "-f" ]; then
	printf '%s\n' "\$*" >>"$work/xprop-set.log"
	exit 0
fi
if [ "\$1" = "-root" ]; then
	if [ "\$2" = "_NET_CLIENT_LIST" ]; then
		printf '_NET_CLIENT_LIST(WINDOW): window id # 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff\n'
		exit 0
	fi
	# The active window, in the same root query (#283); 0xaa unless set.
	printf '_NET_ACTIVE_WINDOW(WINDOW): window id # %s\n' "\${TEST_ACTIVE:-0xaa}"
	cat <<'ROOT'
_NET_CURRENT_DESKTOP(CARDINAL) = 2
_NET_NUMBER_OF_DESKTOPS(CARDINAL) = 9
_NET_DESKTOP_NAMES(UTF8_STRING) = "one", "two", "three"
_NET_CLIENT_LIST(WINDOW): window id # 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff
_DWM_FULLSCREEN_MONITORS(STRING) = "1, 0, 1"
_DWM_MONITOR_DESKTOPS(STRING) = "0, 1, 2"
_DWM_SELECTED_MONITOR(CARDINAL) = 1
_DWM_LAYOUT(CARDINAL) = 2
WM_NAME(STRING) = "AC  |   VOL 15%"
ROOT
	exit 0
fi

window=\$2
shift 2
case "\$window:\$*" in
0xaa:*WM_CLASS*)
	printf '_NET_WM_DESKTOP(CARDINAL) = 3\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf 'WM_CLASS(STRING) = "alacritty", "Alacritty"\n'
	# Both present: _NET_WM_NAME must win over the stale WM_NAME, and its
	# "|" (the windows= field separator) must not survive into the field.
	# Once title-changed exists, this regular (non-spy) query must also
	# report the new title -- a real X server would too, once the property
	# actually changed -- matching what watch_state()'s own re-poll after a
	# -spy wakeup expects to see.
	if [ -f "$work/title-changed" ]; then
		printf '_NET_WM_NAME(UTF8_STRING) = "Updated title"\n'
	else
		printf '_NET_WM_NAME(UTF8_STRING) = "Term|one"\n'
	fi
	printf 'WM_NAME(STRING) = "stale wm name"\n'
	;;
0xbb:*WM_CLASS*)
	printf '_NET_WM_DESKTOP(CARDINAL) = 1\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf 'WM_CLASS(STRING) = "firefox", "firefox"\n'
	# No _NET_WM_NAME on this one: WM_NAME is the fallback, same as
	# window_title()'s own precedent, and its double space must collapse.
	# Once fallback-title-changed exists, this regular query must also
	# report the new WM_NAME, the same real-server reasoning as 0xaa above.
	printf '_NET_WM_NAME:  not found.\n'
	if [ -f "$work/fallback-title-changed" ]; then
		printf 'WM_NAME(STRING) = "Firefox Updated"\n'
	else
		printf 'WM_NAME(STRING) = "Firefox  page"\n'
	fi
	;;
0xcc:*WM_CLASS*)
	# duplicate class, a desktop that must sort before the others, and
	# neither title property set at all -- an empty title field, not a
	# crash and not the literal "not found." text.
	printf '_NET_WM_DESKTOP(CARDINAL) = 0\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf 'WM_CLASS(STRING) = "alacritty", "Alacritty"\n'
	printf '_NET_WM_NAME:  not found.\n'
	printf 'WM_NAME:  not found.\n'
	;;
0xdd:*WM_CLASS*)
	# Claims a root-owned pid: listed all the same, and its desktop counts.
	printf '_NET_WM_DESKTOP(CARDINAL) = 7\n'
	printf '_NET_WM_PID(CARDINAL) = %s\n' "$root_pid"
	printf 'WM_CLASS(STRING) = "rootapp", "RootApp"\n'
	printf '_NET_WM_NAME(UTF8_STRING) = "Root App"\n'
	;;
0xee:*WM_CLASS*)
	# A class containing this wire format's own separators (":", "|") and a
	# literal "%" must round-trip through sanitize_class()'s percent-encoding
	# and DwmStateWindows.js's decodeClass() without corruption. Passed via
	# printf's %s argument, not embedded in the format string, since a raw
	# "%7c" inside the format string itself would be a conversion, not text.
	printf '_NET_WM_DESKTOP(CARDINAL) = 2\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf '%s\n' 'WM_CLASS(STRING) = "edge-instance", "Edge:Case|With%7c"'
	printf '_NET_WM_NAME(UTF8_STRING) = "Edge title"\n'
	;;
0xff:*WM_CLASS*)
	# The panel, as Quickshell maps it: a dock with no WM_CLASS on every
	# desktop, which dwm lists with its clients. It is not a window (#280 VM).
	printf '_NET_WM_DESKTOP(CARDINAL) = 4294967295\n'
	printf '_NET_WM_WINDOW_TYPE(ATOM) = _NET_WM_WINDOW_TYPE_DOCK, _KDE_NET_WM_WINDOW_TYPE_OVERRIDE, _NET_WM_WINDOW_TYPE_NORMAL\n'
	printf 'WM_CLASS:  not found.\n'
	printf '_NET_WM_NAME(UTF8_STRING) = "quickshell"\n'
	;;
*_NET_WM_NAME*)
	printf '_NET_WM_NAME(UTF8_STRING) = "a  title\twith   spaces"\n'
	;;
*WM_CLASS*)
	printf 'WM_CLASS(STRING) = "alacritty", "Alacritty"\n'
	;;
esac
exit 0
EOF

# The active window comes from the root query now: any xdotool call is a
# process too many (#283).
cat >"$bin/xdotool" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/xdotool.log"
exit 1
EOF
chmod +x "$bin/xprop" "$bin/xdotool"

PATH="$bin:$PATH" "$helper" state >"$work/out" 2>"$work/err" ||
	fail 'state exited non-zero' "$work/err"

expect() {
	grep -Fqx "$1" "$work/out" ||
		fail "expected line: $1" "$work/out"
}

expect 'current=2'
expect 'count=9'
expect 'names=one|two|three'
expect 'focused_monitor=1'
expect 'layout=2'
expect 'monitor_desktops=0,1,2'
expect 'status=AC | VOL 15%'

# occupied is numerically sorted and de-duplicated
expect 'occupied=0|1|2|3|7'

# apps keeps first-seen order and de-duplicates by class; a window claiming a
# root-owned pid (0xdd) is listed like any other
expect 'apps=0xaa:alacritty|0xbb:firefox|0xdd:rootapp|0xee:edge%3Acase%7Cwith%257c'

# windows= is per-window, never deduplicated by class (0xaa and 0xcc share
# one): _NET_WM_NAME wins over a stale WM_NAME and drops its "|" (0xaa),
# WM_NAME is the fallback when _NET_WM_NAME is absent (0xbb), neither present
# leaves an empty title rather than the literal "not found." text (0xcc), a
# window claiming a root-owned pid (0xdd) is listed, a class containing
# ":", "|" and a literal "%" round-trips through percent encoding intact (0xee),
# and the panel, a dock (0xff), is not a window: not in windows=, apps= or
# occupied=.
expect 'windows=0xaa:3:alacritty:Term one|0xbb:1:firefox:Firefox page|0xcc:0:alacritty:|0xdd:7:rootapp:Root App|0xee:2:edge%3Acase%7Cwith%257c:Edge title'

# fullscreen monitors are de-duplicated and sorted
expect 'fullscreen_monitors=0|1'

# The active window (0xaa) from the root query: its title keeps the "|" that
# windows= cannot carry, and its class comes from its windows= entry.
expect 'active_window=0xaa'
expect 'title=Term|one'
expect 'class=alacritty'

# One xprop for every root property, the active window included, then exactly
# one per client window: the active window's title and class cost nothing more
# (#283). Anything more is a regression.
root_calls=$(grep -c '^-root' "$work/xprop.log" || true)
[[ $root_calls -eq 1 ]] ||
	fail "expected exactly 1 batched root xprop call, got $root_calls" "$work/xprop.log"
per_window=$(grep -c '^-id .* _NET_WM_DESKTOP _NET_WM_WINDOW_TYPE WM_CLASS _NET_WM_NAME WM_NAME$' "$work/xprop.log" || true)
[[ $per_window -eq 6 ]] ||
	fail "expected 1 batched xprop per listed window (6, the dock too), got $per_window" "$work/xprop.log"
total=$(wc -l <"$work/xprop.log")
[[ $total -eq 7 ]] ||
	fail "expected 7 xprop calls for 6 listed windows, got $total" "$work/xprop.log"
[[ ! -e $work/xdotool.log ]] || fail 'state still ran xdotool' "$work/xdotool.log"

# state_for ACTIVE: the state with another active window.
state_for() {
	PATH="$bin:$PATH" TEST_ACTIVE=$1 "$helper" state >"$work/out" 2>"$work/err" ||
		fail "state with active window $1 exited non-zero" "$work/err"
}
# WM_NAME is the title when _NET_WM_NAME is absent, whitespace collapsed.
state_for 0xbb
expect 'title=Firefox page'
expect 'class=firefox'
# No active window: the defaults.
state_for 0x0
expect 'active_window='
expect 'title=Desktop'
expect 'class=application-x-executable'
# An active window outside the client list is read on its own.
state_for 0x99
expect 'active_window=0x99'
expect 'title=a title with spaces'
expect 'class=alacritty'

# Asking for a layout sets the _DWM_SET_LAYOUT root property; a malformed index
# is refused before anything is sent.
: >"$work/xprop-set.log"
PATH="$bin:$PATH" "$helper" layout 2 || fail 'layout 2 was refused'
grep -Fqx -- '-root -f _DWM_SET_LAYOUT 32c -set _DWM_SET_LAYOUT 2' "$work/xprop-set.log" ||
	fail 'layout did not set _DWM_SET_LAYOUT' "$work/xprop-set.log"
for bad in '' abc -1 100 '1 2'; do
	if PATH="$bin:$PATH" "$helper" layout "$bad" 2>/dev/null; then
		fail "layout accepted a malformed index: $bad"
	fi
done
[[ $(wc -l <"$work/xprop-set.log") -eq 1 ]] || fail 'a refused layout still reached xprop' "$work/xprop-set.log"

watch_pid=
# shellcheck disable=SC2016 # deferred by design: cleanup_add's argument is
# eval'd later by lyona_run_cleanup, once $watch_pid actually holds a value.
cleanup_add 'if [[ -n $watch_pid ]]; then kill "$watch_pid" 2>/dev/null || true; wait "$watch_pid" 2>/dev/null || true; fi'

# The watch runs from a checkout, where dwm-xwatch is the built binary beside
# scripts/ (#282). Its stand-in prints what the real one does: "ready", then
# "window 0xID" for each window whose properties changed. Unless it is told to
# fail, when the watch falls back to an xprop -spy per window.
checkout=$work/checkout
stage_helpers checkout "$checkout/scripts" dwm-quickshell-state
cat >"$checkout/dwm-xwatch" <<EOF
#!/bin/sh
printf 'xwatch\n' >>"$work/xwatch.log"
[ ! -f "$work/xwatch-broken" ] || exit 1
printf 'ready\n'
while [ ! -f "$work/title-changed" ]; do sleep 0.05; done
printf 'window 0xaa\n'
while [ ! -f "$work/fallback-title-changed" ]; do sleep 0.05; done
printf 'window 0xbb\n'
exec sleep 30
EOF
chmod +x "$checkout/dwm-xwatch"

initial='windows=0xaa:3:alacritty:Term one|0xbb:1:firefox:Firefox page|0xcc:0:alacritty:|0xdd:7:rootapp:Root App|0xee:2:edge%3Acase%7Cwith%257c:Edge title'
updated='windows=0xaa:3:alacritty:Updated title|0xbb:1:firefox:Firefox page|0xcc:0:alacritty:|0xdd:7:rootapp:Root App|0xee:2:edge%3Acase%7Cwith%257c:Edge title'
fallback_updated='windows=0xaa:3:alacritty:Updated title|0xbb:1:firefox:Firefox Updated|0xcc:0:alacritty:|0xdd:7:rootapp:Root App|0xee:2:edge%3Acase%7Cwith%257c:Edge title'

wait_for_line() { # LINE MESSAGE
	local i=0
	while [ "$i" -lt 100 ]; do
		grep -Fqx "$1" "$work/watch-out" && return 0
		sleep 0.05
		i=$((i + 1))
	done
	fail "$2" "$work/watch-out"
}

# run_watch: start the watch, see the initial titles, then a _NET_WM_NAME and a
# WM_NAME change each reach the output.
run_watch() {
	rm -f "$work/title-changed" "$work/fallback-title-changed" "$work/watch-out" "$work/xwatch.log"
	: >"$work/xprop.log"
	PATH="$bin:$PATH" "$checkout/scripts/dwm-quickshell-state" watch >"$work/watch-out" 2>"$work/watch-err" &
	watch_pid=$!
	wait_for_line "$initial" 'watch did not emit initial titles'
	touch "$work/title-changed"
	wait_for_line "$updated" 'watch ignored a title-only change'
	grep -Fqx 'title=Updated title' "$work/watch-out" || fail 'the active title did not follow the change' "$work/watch-out"
	touch "$work/fallback-title-changed"
	wait_for_line "$fallback_updated" 'watch ignored a WM_NAME-only change'
	kill "$watch_pid"
	wait "$watch_pid" 2>/dev/null || true
	watch_pid=
}

# dwm-xwatch: one watcher for every window, and no xprop -spy at all.
run_watch
[[ -s $work/xwatch.log ]] || fail 'the watch did not use dwm-xwatch'
# The dock is read once and remembered as left out, not read again on every
# rebuild because no windows= entry cached it.
dock_reads=$(grep -c '^-id 0xff ' "$work/xprop.log" || true)
[[ $dock_reads -eq 1 ]] ||
	fail "the watch read the dock $dock_reads times; once is enough" "$work/xprop.log"
if grep -Fq -- '-spy' "$work/xprop.log"; then
	fail 'the watch started xprop -spy although dwm-xwatch was ready' "$work/xprop.log"
fi

# dwm-xwatch cannot watch the display: the per-window xprop -spy fallback.
touch "$work/xwatch-broken"
run_watch
grep -Fq -- '-id 0xaa -spy _NET_WM_NAME WM_NAME WM_CLASS _NET_WM_DESKTOP' "$work/xprop.log" ||
	fail 'the fallback did not subscribe to client title properties' "$work/xprop.log"
rm -f "$work/xwatch-broken"

PATH="$bin:$PATH" "$helper" state >"$work/reopened-out" 2>"$work/reopened-err" ||
	fail 'fresh state after title change exited non-zero' "$work/reopened-err"
grep -Fqx "$fallback_updated" "$work/reopened-out" || fail 'fresh snapshot kept the old title' "$work/reopened-out"

# #320: when dwm-xwatch dies (an OOM kill, a crash), the watch ends, so that
# WatchedProcess starts it again; it used to block on its own fifo for ever.
cat >"$checkout/dwm-xwatch" <<EOF
#!/bin/sh
printf 'ready\n'
while [ ! -f "$work/xwatch-die" ]; do sleep 0.05; done
exit 0
EOF
chmod +x "$checkout/dwm-xwatch"
rm -f "$work/xwatch-die" "$work/title-changed" "$work/fallback-title-changed"
PATH="$bin:$PATH" "$checkout/scripts/dwm-quickshell-state" watch >"$work/watch-out" 2>"$work/watch-err" &
watch_pid=$!
wait_for_line "$initial" 'watch did not emit initial titles (dying watcher)'
touch "$work/xwatch-die"
i=0
while kill -0 "$watch_pid" 2>/dev/null; do
	i=$((i + 1))
	[ "$i" -lt 60 ] || fail 'the watch kept running after dwm-xwatch died' "$work/watch-err"
	sleep 0.05
done
wait "$watch_pid" 2>/dev/null || true
watch_pid=
grep -Fq 'dwm-xwatch stopped' "$work/watch-err" || fail 'the watch did not say why it ended' "$work/watch-err"

# A window that retitles without pause (here about 100 times a second for 2 s)
# rebuilds the state at most every 200 ms, about 10 times, not once per 50 ms
# burst; a single change still shows at once.
cat >"$checkout/dwm-xwatch" <<EOF
#!/bin/sh
printf 'ready\n'
while [ ! -f "$work/churn-start" ]; do sleep 0.05; done
n=0
while [ "\$n" -lt 200 ]; do printf 'window 0xaa\n'; sleep 0.01; n=\$((n + 1)); done
exec sleep 30
EOF
chmod +x "$checkout/dwm-xwatch"
rm -f "$work/churn-start"
PATH="$bin:$PATH" "$checkout/scripts/dwm-quickshell-state" watch >"$work/watch-out" 2>"$work/watch-err" &
watch_pid=$!
wait_for_line "$initial" 'watch did not emit initial titles (churn)'
blocks_before=$(grep -c '^current=' "$work/watch-out")
start_ms=$(($(date +%s%N) / 1000000))
touch "$work/churn-start"
sleep 3
blocks=$(($(grep -c '^current=' "$work/watch-out") - blocks_before))
elapsed_ms=$(($(date +%s%N) / 1000000 - start_ms))
kill "$watch_pid"
wait "$watch_pid" 2>/dev/null || true
watch_pid=
printf 'retitling for 2 s: %d rebuilds\n' "$blocks"
# 2 s of churn at one rebuild per 200 ms is about 10; allow for a slow host.
[[ $blocks -ge 2 && $blocks -le 16 ]] ||
	fail "a retitling window caused $blocks rebuilds in ${elapsed_ms} ms; want at most about 10" "$work/watch-out"

printf 'Quickshell state bridge: PASS\n'
