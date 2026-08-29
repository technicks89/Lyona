#!/bin/sh
# Source guards for the X round-trip reductions in dwm.c. Each check pins the
# property that made the change worth doing, so a later edit that quietly
# reintroduces a synchronous round-trip into a hot path fails here.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
dwm_c="$repo/dwm.c"

body() {
	sed -n "/^$1/,/^}\$/p" "$dwm_c"
}

count() {
	printf '%s\n' "$2" | grep -c "$1" || true
}

order() {
	printf '%s\n' "$2" | grep -n "$1" | head -1 | cut -d: -f1
}

priority=$(body 'restackprioritywindows')
[ "$(order 'raisefloatingclients' "$priority")" \
	-lt "$(order 'raiseselectedclient' "$priority")" ] ||
	fail 'raiseselectedclient must run after the floating pass.'

# ── WM_CLASS is cached on the client ─────────────────────────────────────
grep -q '	char class\[256\];' "$dwm_c" ||
	fail 'Client no longer caches its WM_CLASS class.'
grep -q '	char instance\[256\];' "$dwm_c" ||
	fail 'Client no longer caches its WM_CLASS instance.'

update_class_body=$(body 'updateclass(Client \*c)')
printf '%s\n' "$update_class_body" | grep -q 'XGetClassHint' ||
	fail 'updateclass() does not read WM_CLASS.'

# attachbottom() walks every client on the monitor, and reconcilemonitortags()
# calls it from inside a monitor x client loop. One X round-trip in here is a
# monitors x clients^2 storm on hotplug.
attach_bottom_body=$(body 'attachbottom(Client \*c)')
if printf '%s\n' "$attach_bottom_body" | grep -qE '\bX[A-Z][A-Za-z]+\('; then
	fail 'attachbottom() issues an X round-trip inside its client walk.'
fi
printf '%s\n' "$attach_bottom_body" | grep -q '(\*tc)->class' ||
	fail 'attachbottom() no longer reads the cached class.'

for fn in 'applyrules(Client \*c)' 'applytitlerules(Client \*c)'; do
	fn_body=$(body "$fn")
	if printf '%s\n' "$fn_body" | grep -q 'XGetClassHint'; then
		fail "$fn refetches WM_CLASS instead of reading the cache."
	fi
	printf '%s\n' "$fn_body" | grep -q 'c->class' ||
		fail "$fn does not read the cached class."
done

# The cache is only correct if it is filled before anything reads it, and
# refreshed for the toolkits that set WM_CLASS after mapping.
manage_body=$(body 'manage(Window w, XWindowAttributes \*wa)')
update_line=$(printf '%s\n' "$manage_body" | grep -n 'updateclass(c);' | cut -d: -f1)
attach_line=$(printf '%s\n' "$manage_body" | grep -n 'attachbottom(c);' | cut -d: -f1)
rules_line=$(printf '%s\n' "$manage_body" | grep -n 'applyrules(c);' | cut -d: -f1)
[ -n "$update_line" ] || fail 'manage() does not fill the class cache.'
[ "$update_line" -lt "$attach_line" ] ||
	fail 'manage() attaches the client before caching its class.'
[ "$update_line" -lt "$rules_line" ] ||
	fail 'manage() applies rules before caching the class they match on.'

property_notify_body=$(body 'propertynotify(XEvent \*e)')
printf '%s\n' "$property_notify_body" | grep -q 'case XA_WM_CLASS:' ||
	fail 'propertynotify() does not refresh the class cache.'

# ── The tray rescan is gated ─────────────────────────────────────────────
# scantray() is a full root XQueryTree plus a WM_CLASS round-trip per
# top-level window. Without a gate, expose() ran it on every Expose for as
# long as no tray existed.
scantray_body=$(body 'scantray(void)')
printf '%s\n' "$scantray_body" | grep -q 'trayscanpending = 0;' ||
	fail 'scantray() does not consume the pending flag.'

expose_body=$(body 'expose(XEvent \*e)')
printf '%s\n' "$expose_body" | grep -q 'trayscanpending' ||
	fail 'expose() rescans the tray unconditionally.'

gates=$(grep -c 'traywin && trayscanpending' "$dwm_c")
[ "$gates" -eq 3 ] ||
	fail "expected 3 gated scantray() sites, found $gates."

# Something has to re-arm the gate, or a tray that appears late is never found.
mapnotify_body=$(body 'mapnotify(XEvent \*e)')
printf '%s\n' "$mapnotify_body" | grep -q 'trayscanpending = 1;' ||
	fail 'mapnotify() does not re-arm the tray scan.'
unmanagetray_body=$(body 'unmanagetray(Window w)')
printf '%s\n' "$unmanagetray_body" | grep -q 'trayscanpending = 1;' ||
	fail 'unmanagetray() does not re-arm the tray scan.'

# ── Per-monitor tag masks are cached ─────────────────────────────────────
# getmontagmask() walks mons and getmonlogicalindex() walks it twice more,
# from inside per-client loops.
grep -q '	unsigned int tagmask;' "$dwm_c" ||
	fail 'Monitor no longer caches its tag mask.'
get_mask_body=$(body 'getmontagmask(int monnum)')
printf '%s\n' "$get_mask_body" | grep -q 'm->tagmaskvalid' ||
	fail 'getmontagmask() does not consult the per-monitor cache.'
printf '%s\n' "$get_mask_body" | grep -q 'computemontagmask(monnum)' ||
	fail 'getmontagmask() does not delegate the cold path.'

# The cache is only safe while every layout change invalidates it.
updategeom_body=$(body 'updategeom(void)')
printf '%s\n' "$updategeom_body" | grep -q 'invalidatemontagmasks();' ||
	fail 'updategeom() does not invalidate the cached tag masks.'
updatemonitorcount_body=$(body 'updatemonitorcount(void)')
printf '%s\n' "$updatemonitorcount_body" | grep -q 'invalidatemontagmasks();' ||
	fail 'updatemonitorcount() does not invalidate the cached tag masks.'

# ── scan() probes each window once ───────────────────────────────────────
scan_body=$(body 'scan(void)')
attrs=$(count 'XGetWindowAttributes' "$scan_body")
trans=$(count 'XGetTransientForHint' "$scan_body")
[ "$attrs" -eq 1 ] ||
	fail "scan() issues $attrs XGetWindowAttributes passes, expected 1."
[ "$trans" -eq 1 ] ||
	fail "scan() issues $trans XGetTransientForHint passes, expected 1."
# Transients still have to be managed after their parents.
printf '%s\n' "$scan_body" | grep -q '!probe\[i\].transient' ||
	fail 'scan() no longer defers transients to a second pass.'
printf '%s\n' "$scan_body" | grep -q 'free(probe);' ||
	fail 'scan() leaks its probe table.'

printf '%s\n' "dwm X round-trip guards: PASS"
