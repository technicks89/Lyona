#!/bin/sh
set -eu

# #337: an update is installed by the root helper already on the system, which
# reads the new release's tree through its Makefile. What it reads is a contract
# (SPEC.md section 6, "The release-tree contract"): the previous release's
# helper, taken from the newest tag reachable from HEAD (or, when HEAD is a
# release itself, from the one before it: the release that updates to HEAD),
# must still find every variable and target it names in the current tree.
# Without a reachable tag (a clone without tags) the current helper stands in,
# so its reads are checked against the tree all the same.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace
helper_src=$work/previous-helper
head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
tag=$(git -C "$repo" describe --tags --abbrev=0 HEAD 2>/dev/null || true)
if [ -n "$tag" ] && [ "$(git -C "$repo" rev-parse "$tag^{commit}" 2>/dev/null)" = "$head" ]; then
	tag=$(git -C "$repo" describe --tags --abbrev=0 "$head^" 2>/dev/null || true)
fi
if [ -n "$tag" ] && git -C "$repo" show "$tag:scripts/lyona-update-root" >"$helper_src" 2>/dev/null; then
	printf 'previous release: %s\n' "$tag"
else
	cp "$repo/scripts/lyona-update-root" "$helper_src"
	printf 'no previous release tag reachable; checking the current helper against the tree\n'
fi

make_values() { # EXPR: the words the tree's Makefile expands EXPR to, as the helper reads them
	make -s -C "$repo" --no-print-directory \
		--eval="lyona-root-print: ; @printf '%s\\n' $1" lyona-root-print
}

# Every Makefile expression the helper reads expands to something.
grep -o "tree_make_values \"\$[a-z_]*\" '[^']*'" "$helper_src" | sed "s/^[^']*'//; s/'\$//" |
	sort -u >"$work/exprs"
[ -s "$work/exprs" ] || fail 'the helper reads no Makefile values (the extraction found none)'
while IFS= read -r expr; do
	values=$(make_values "$expr" 2>"$work/make.err") ||
		fail "the tree's Makefile cannot expand $expr: $(cat "$work/make.err")"
	[ -n "$(printf '%s' "$values" | tr -d '[:space:]')" ] ||
		fail "the tree's Makefile expands $expr to nothing, which the installed helper relies on"
done <"$work/exprs"

# The targets the helper asks make for exist in the tree.
for target in all-root dwm clean install-system; do
	make -n -C "$repo" "$target" >/dev/null 2>"$work/make.err" ||
		fail "the tree has no $target target: $(head -3 "$work/make.err")"
done
# all-root never includes config.h: its prerequisites, as make's database
# records them for this tree, hold every object but dwm.o, the three helper
# programs, and neither dwm nor dwm.o; and only dwm.c includes config.h.
prereqs=$(make -pqn -C "$repo" all-root 2>/dev/null | sed -n 's/^all-root: //p')
[ -n "$prereqs" ] || fail 'make lists no prerequisites for all-root'
case " $prereqs " in
*" dwm.o "* | *" dwm "*) fail "all-root would build dwm or dwm.o as root: $prereqs" ;;
esac
for want in $(make_values '$(filter-out dwm.o,$(OBJ)) $(THUMB) $(TOML_TOOL) $(XWATCH)'); do
	case " $prereqs " in
	*" $want "*) ;;
	*) fail "all-root does not build $want, which the root helper needs built: $prereqs" ;;
	esac
done
[ "$(grep -l '#include "config.h"' "$repo"/*.c)" = "$repo/dwm.c" ] ||
	fail 'a source other than dwm.c includes config.h, so all-root would compile it as root'

# The record fields the helper reads are the ones stamp-system writes.
for key in LYONA_PREFIX LYONA_MANPREFIX LYONA_DATADIR LYONA_XSESSIONSDIR; do
	grep -Fq "$key" "$helper_src" || continue
	grep -Fq "'$key=%s" "$repo/Makefile" || fail "stamp-system no longer writes $key, which the helper reads"
done

printf 'Update root helper contract: PASS\n'
