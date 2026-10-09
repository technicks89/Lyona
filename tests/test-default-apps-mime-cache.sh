#!/usr/bin/env bash
set -euo pipefail

# #288: the Defaults snapshot reads the mimeapps.list files and the MIME caches
# once instead of running xdg-mime per type. It must still answer what the real
# xdg-mime answers in a lyona session, in every case: a default whose first app
# is installed, one whose first app is missing (left to xdg-mime), a
# desktop-prefixed list, a later file, the cache, and no default at all.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

if ! command -v xdg-mime >/dev/null 2>&1; then
	printf 'SKIP: xdg-mime is not installed\n'
	exit 0
fi

home=$work/home
data=$work/data
apps=$data/applications
mkdir -p "$home/.config" "$home/.local/share/applications" "$apps" "$work/etc-xdg" "$work/runtime"
desktop() { # ID EXEC MIMETYPES
	printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s %%U\nMimeType=%s\n' "$1" "$2" "$3" >"$apps/$1.desktop"
}
desktop alpha true 'text/plain;image/png;image/jpeg;image/gif;text/html;application/pdf;'
desktop beta /nonexistent/beta 'image/png;image/gif;'
desktop gamma true 'image/bmp;'
cat >"$home/.config/mimeapps.list" <<'EOF'
[Added Associations]
image/tiff=gamma.desktop;

[Default Applications]
text/plain=alpha.desktop
image/png=beta.desktop;alpha.desktop;
application/pdf=missing.desktop;
EOF
# The session's desktop-prefixed list comes first.
cat >"$home/.config/x-dwm-mimeapps.list" <<'EOF'
[Default Applications]
image/jpeg=alpha.desktop
EOF
# A later file: only for what the earlier ones leave out.
cat >"$apps/mimeapps.list" <<'EOF'
[Default Applications]
text/plain=gamma.desktop
image/bmp=gamma.desktop
EOF
cat >"$apps/mimeinfo.cache" <<'EOF'
[MIME Cache]
image/gif=beta.desktop;alpha.desktop;
text/html=alpha.desktop;
EOF

session() {
	env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CONFIG_DIRS="$work/etc-xdg" \
		XDG_DATA_HOME="$home/.local/share" XDG_DATA_DIRS="$data" XDG_RUNTIME_DIR="$work/runtime" \
		XDG_CURRENT_DESKTOP=X-DWM:dwm DESKTOP_SESSION=dwm "$@"
}

session "$repo/scripts/dwm-default-apps" snapshot >"$work/snapshot" || fail 'the snapshot failed'
checked=0
# awk, not read: an empty field is kept rather than collapsed.
while IFS='|' read -r mime current; do
	expected=$(session xdg-mime query default "$mime" 2>/dev/null || true)
	expected=${expected%%$'\n'*}
	# The snapshot shows only a default whose entry it can read.
	[[ -n $expected && ! -f $apps/$expected ]] && expected=
	[[ $current == "$expected" ]] ||
		fail "$mime: the snapshot says '$current', xdg-mime says '$expected'"
	checked=$((checked + 1))
done < <(awk -F '\t' '$1 == "mime" { print $2 "|" $4 }' "$work/snapshot")
((checked >= 15)) || fail "only $checked MIME rows were compared"
# The cases are really exercised, not all empty.
for want in 'text/plain alpha.desktop' 'image/png alpha.desktop' 'image/jpeg alpha.desktop' \
	'image/bmp gamma.desktop' 'image/gif beta.desktop' 'text/html alpha.desktop'; do
	awk -F '\t' -v mime="${want% *}" -v id="${want#* }" '$1 == "mime" && $2 == mime && $4 == id { found = 1 } END { exit !found }' \
		"$work/snapshot" || fail "expected $want in the snapshot"
done

printf 'Defaults snapshot MIME lookup matches xdg-mime (%s types): PASS\n' "$checked"
