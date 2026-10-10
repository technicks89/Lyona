#!/bin/sh
# Source guards for the floating and stacking code in dwm.c (#91). The X11
# behaviour is covered by make check-xvfb-runtime; these pin the structure that
# keeps the mechanism, the policy and the shared predicates from drifting apart.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

body() {
	wm_body "$1"
}

# ── Floating: the mechanism does not depend on an incidental Arg convention ─
setfloating=$(body 'setfloating(Client \*c, int shrink)')
[ -n "$setfloating" ] || fail 'setfloating(Client *c, int shrink) is missing.'
printf '%s\n' "$setfloating" | grep -q 'shrink &&' ||
	fail 'setfloating no longer gates the pop-out shrink on its shrink argument.'
toggle=$(body 'togglefloating(const Arg \*arg)')
printf '%s\n' "$toggle" | grep -q 'setfloating(' ||
	fail 'togglefloating no longer dispatches to setfloating.'
if printf '%s\n' "$toggle" | sed 1d | grep -qw 'arg'; then
	fail 'togglefloating reads its Arg again: NULL must not mean "mouse drag".'
fi
if wm_grep -q 'togglefloating(NULL)'; then
	fail 'A mouse drag calls togglefloating(NULL) again.'
fi
[ "$(wm_count 'setfloating(selmon->sel, 0)')" -eq 2 ] ||
	fail 'The two mouse-drag paths must call setfloating(selmon->sel, 0).'
wm_grep -q 'setfloating(selmon->sel, 1)' ||
	fail 'togglefloating must call setfloating(selmon->sel, 1).'

# ── Stacking: restack() and raiseselectedclient() share one predicate ───────
wm_grep -q '^restackraisesselected(Monitor \*m)' ||
	fail 'restackraisesselected(Monitor *m) is missing.'
body 'restack(Monitor \*m)' | grep -q 'restackraisesselected(m)' ||
	fail 'restack() does not use restackraisesselected().'
body 'raiseselectedclient(Monitor \*m)' | grep -q 'restackraisesselected(m)' ||
	fail 'raiseselectedclient() does not use restackraisesselected().'
[ "$(wm_count 'isfloating || !m->lt\[m->sellt\]->arrange')" -eq 1 ] ||
	fail 'The "floating or floating layout" predicate is spelled out more than once.'

# ── The pop-out percentage is a named tunable with the shipped default 85 ───
grep -Eq '^#define FLOATSHRINKPCT[[:space:]]+85([[:space:]]|$)' "$repo/config.def.h" ||
	fail 'config.def.h must define FLOATSHRINKPCT as 85.'
wm_grep -Eq '^#define FLOATSHRINKPCT[[:space:]]+85$' ||
	fail 'dwm.c must fall back to FLOATSHRINKPCT 85 for an older config.h.'
shrink=$(body 'shrinkfloating(Client \*c)')
printf '%s\n' "$shrink" | grep -q 'FLOATSHRINKPCT' ||
	fail 'shrinkfloating does not use FLOATSHRINKPCT.'
if printf '%s\n' "$shrink" | grep -Eq '(^|[^0-9])85([^0-9]|$)'; then
	fail 'shrinkfloating still has the literal 85.'
fi

# A config.h written before the tunable existed still builds (lyona-update
# builds with the user's own config.h), and one that sets it wins over the fallback.
wm_sources | while IFS= read -r file; do
	cp "$file" "$work/${file##*/}"
done
cp "$repo/config.mk" "$repo/Makefile" "$work/"
grep -v 'FLOATSHRINKPCT' "$repo/config.def.h" >"$work/config.h"
(cd "$work" && make dwm.o >build.log 2>&1) || {
	cat "$work/build.log" >&2
	fail 'dwm.c does not build with a config.h that lacks FLOATSHRINKPCT.'
}
rm -f "$work/dwm.o"
sed 's/^#define FLOATSHRINKPCT .*/#define FLOATSHRINKPCT 50/' "$repo/config.def.h" >"$work/config.h"
(cd "$work" && make dwm.o >build.log 2>&1) || {
	cat "$work/build.log" >&2
	fail 'dwm.c does not build with a config.h that sets FLOATSHRINKPCT.'
}
if grep -qi 'redefined' "$work/build.log"; then
	cat "$work/build.log" >&2
	fail 'FLOATSHRINKPCT is redefined when config.h sets it.'
fi

printf 'dwm floating and stacking structure: PASS\n'
