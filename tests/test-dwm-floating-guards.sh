#!/bin/sh
# Source guards for the floating and stacking code in dwm.c (#91). The X11
# behaviour is covered by make check-xvfb-runtime; these pin the structure that
# keeps the mechanism, the policy and the shared predicates from drifting apart.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
dwm_c="$repo/dwm.c"

body() {
	sed -n "/^$1/,/^}\$/p" "$dwm_c"
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
if grep -q 'togglefloating(NULL)' "$dwm_c"; then
	fail 'A mouse drag calls togglefloating(NULL) again.'
fi
[ "$(grep -c 'setfloating(selmon->sel, 0)' "$dwm_c")" -eq 2 ] ||
	fail 'The two mouse-drag paths must call setfloating(selmon->sel, 0).'
grep -q 'setfloating(selmon->sel, 1)' "$dwm_c" ||
	fail 'togglefloating must call setfloating(selmon->sel, 1).'

# ── Stacking: restack() and raiseselectedclient() share one predicate ───────
grep -q '^restackraisesselected(Monitor \*m)' "$dwm_c" ||
	fail 'restackraisesselected(Monitor *m) is missing.'
body 'restack(Monitor \*m)' | grep -q 'restackraisesselected(m)' ||
	fail 'restack() does not use restackraisesselected().'
body 'raiseselectedclient(Monitor \*m)' | grep -q 'restackraisesselected(m)' ||
	fail 'raiseselectedclient() does not use restackraisesselected().'
[ "$(grep -c 'isfloating || !m->lt\[m->sellt\]->arrange' "$dwm_c")" -eq 1 ] ||
	fail 'The "floating or floating layout" predicate is spelled out more than once.'

# ── The pop-out percentage is a named tunable with the shipped default 85 ───
grep -Eq '^#define FLOATSHRINKPCT[[:space:]]+85([[:space:]]|$)' "$repo/config.def.h" ||
	fail 'config.def.h must define FLOATSHRINKPCT as 85.'
grep -Eq '^#define FLOATSHRINKPCT[[:space:]]+85$' "$dwm_c" ||
	fail 'dwm.c must fall back to FLOATSHRINKPCT 85 for an older config.h.'
shrink=$(body 'shrinkfloating(Client \*c)')
printf '%s\n' "$shrink" | grep -q 'FLOATSHRINKPCT' ||
	fail 'shrinkfloating does not use FLOATSHRINKPCT.'
if printf '%s\n' "$shrink" | grep -Eq '(^|[^0-9])85([^0-9]|$)'; then
	fail 'shrinkfloating still has the literal 85.'
fi

# A config.h written before the tunable existed still builds (lyona-update
# builds with the user's own config.h), and one that sets it wins over the fallback.
for file in dwm.c drw.c drw.h util.c util.h tomlparser.c tomlparser.h config.mk Makefile; do
	cp "$repo/$file" "$work/$file"
done
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
