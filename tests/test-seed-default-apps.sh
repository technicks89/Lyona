#!/usr/bin/env bash
# scripts/seed-default-apps.sh gives a fresh account Celluloid, sxiv and Thunar
# as its media, image and folder handlers, and must never replace a choice the
# user already made.
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

seed=$repo/scripts/seed-default-apps.sh
assert_executable "$seed"

if [[ $(id -u) == 0 ]]; then
	# The script refuses root by design; prove that instead of the rest.
	if "$seed" >"$work/root.out" 2>"$work/root.err"; then
		fail 'seed-default-apps.sh ran as root'
	fi
	grep -Fq 'refusing to run as root' "$work/root.err" ||
		fail 'the root refusal does not say why'
	printf 'Seed default apps: PASS (root guard only; run as a normal user for the rest)\n'
	exit 0
fi

export HOME=$work/home
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share
export XDG_DATA_DIRS=$work/system-data
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/applications" \
	"$XDG_DATA_DIRS/applications" "$work/bin"
export PATH="$work/bin:$PATH"
mimeapps=$XDG_CONFIG_HOME/mimeapps.list

install_handlers() {
	for app in celluloid sxiv thunar; do
		printf '#!/bin/sh\nexit 0\n' >"$work/bin/$app"
		chmod +x "$work/bin/$app"
	done
	cat >"$XDG_DATA_DIRS/applications/io.github.celluloid_player.Celluloid.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=Celluloid
Exec=celluloid %U
MimeType=audio/mpeg;audio/flac;video/mp4;application/ogg;application/x-matroska;
APP
	# Arch's sxiv hides itself from menus; it must still get the image types.
	cat >"$XDG_DATA_DIRS/applications/sxiv.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=sxiv
Exec=sxiv %F
NoDisplay=true
MimeType=image/png;image/jpeg;image/gif;image/bmp;image/tiff;
APP
	cat >"$XDG_DATA_DIRS/applications/thunar.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=Thunar
Exec=thunar %U
MimeType=inode/directory;
APP
}

no_partial_files() {
	[[ -z $(find "$XDG_CONFIG_HOME" -name '.lyona-mimeapps.*' -print -quit) ]] ||
		fail 'a temporary MIME file was left behind'
}

# ── it takes no arguments ────────────────────────────────────────────────

install_handlers
if "$seed" surprise >/dev/null 2>&1; then
	fail 'seed-default-apps.sh accepted an argument'
fi
assert_no_file "$mimeapps" 'a refused invocation wrote a MIME file'

# ── existing preferences are preserved, whichever file holds them ────────

printf '[Default Applications]\nimage/png=custom.desktop;\n' >"$mimeapps"
cp "$mimeapps" "$work/original"
"$seed" >"$work/out" || fail 'seeding failed next to an existing mimeapps.list'
cmp "$work/original" "$mimeapps" || fail 'an existing mimeapps.list was changed'
grep -Fq 'Preserving existing application defaults' "$work/out" ||
	fail 'preserving an existing file was not reported'
rm -f "$mimeapps"

# A desktop-specific file counts too, and must not gain a generic sibling.
printf '[Default Applications]\nimage/png=custom.desktop;\n' >"$XDG_CONFIG_HOME/dwm-mimeapps.list"
"$seed" >/dev/null || fail 'seeding failed next to a desktop-specific file'
assert_no_file "$mimeapps" 'a desktop-specific preference did not stop seeding'
rm -f "$XDG_CONFIG_HOME/dwm-mimeapps.list"

# So do the legacy locations under the data directory.
printf '[Default Applications]\nimage/png=custom.desktop;\n' >"$XDG_DATA_HOME/applications/defaults.list"
"$seed" >/dev/null || fail 'seeding failed next to defaults.list'
assert_no_file "$mimeapps" 'defaults.list did not stop seeding'
rm -f "$XDG_DATA_HOME/applications/defaults.list"

# ── a fresh account gets the defaults, through the real xdg-mime ─────────

"$seed" >/dev/null || fail 'seeding a fresh account failed'
assert_file "$mimeapps"
no_partial_files
for mime in audio/mpeg audio/flac video/mp4 application/ogg application/x-matroska; do
	[[ $(xdg-mime query default "$mime") == io.github.celluloid_player.Celluloid.desktop ]] ||
		fail "$mime is not opened by Celluloid"
done
for mime in image/png image/jpeg image/gif image/bmp image/tiff; do
	[[ $(xdg-mime query default "$mime") == sxiv.desktop ]] ||
		fail "$mime is not opened by sxiv"
done
[[ $(xdg-mime query default inode/directory) == thunar.desktop ]] ||
	fail 'folders are not opened by Thunar'
if grep -q 'image/webp=' "$mimeapps"; then
	fail 'a format no handler advertises was claimed'
fi

# Running it again is a no-op, not a rewrite.
cp "$mimeapps" "$work/seeded"
"$seed" >/dev/null
cmp "$work/seeded" "$mimeapps" || fail 'a second run changed the seeded file'

# ── a missing required handler fails without writing anything ────────────

rm -f "$mimeapps"
mv "$XDG_DATA_DIRS/applications/sxiv.desktop" "$work/sxiv.desktop"
if "$seed" >/dev/null 2>"$work/missing.err"; then
	fail 'a missing image handler was accepted'
fi
grep -Fq 'Missing default application: sxiv.desktop' "$work/missing.err" ||
	fail 'the missing handler was not named'
assert_no_file "$mimeapps" 'a failed seed left a partial MIME file'
no_partial_files
mv "$work/sxiv.desktop" "$XDG_DATA_DIRS/applications/sxiv.desktop"

# A desktop entry without its program is just as missing. That is judged
# against PATH, so run it with a PATH holding only the tools the script needs
# and stub programs: a real Celluloid installed on the host (CI installs the
# whole profile) must not be able to satisfy it.
hermetic=$work/hermetic
mkdir -p "$hermetic/tools" "$hermetic/programs"
for tool in id python3 mkdir mktemp rm ln; do
	ln -s "$(command -v "$tool")" "$hermetic/tools/$tool"
done
for app in celluloid sxiv thunar; do
	cp "$work/bin/$app" "$hermetic/programs/$app"
done
run_hermetic() { PATH=$hermetic/tools:$hermetic/programs "$seed"; }
rm -f "$mimeapps"
# Control: with every program present, the hermetic PATH is enough to seed.
run_hermetic >/dev/null 2>"$work/hermetic.err" ||
	fail "seeding failed with the hermetic PATH: $(cat "$work/hermetic.err")"
assert_file "$mimeapps"
rm -f "$mimeapps"
rm "$hermetic/programs/celluloid"
if run_hermetic >/dev/null 2>"$work/noprogram.err"; then
	fail 'a handler whose program is not installed was accepted'
fi
grep -Fq 'Missing default application: io.github.celluloid_player.Celluloid.desktop (celluloid)' \
	"$work/noprogram.err" || fail 'the missing program was not named'
assert_no_file "$mimeapps" 'a missing program left a partial MIME file'
no_partial_files

# A handler that advertises none of the wanted types is refused, not guessed at.
cp "$XDG_DATA_DIRS/applications/sxiv.desktop" "$work/sxiv.saved"
sed -i 's/^MimeType=.*/MimeType=text\/plain;/' "$XDG_DATA_DIRS/applications/sxiv.desktop"
if "$seed" >/dev/null 2>"$work/nomime.err"; then
	fail 'a handler advertising no image types was accepted'
fi
grep -Fq 'No supported MIME types advertised by sxiv.desktop' "$work/nomime.err" ||
	fail 'the handler with no image types was not named'
assert_no_file "$mimeapps"
cp "$work/sxiv.saved" "$XDG_DATA_DIRS/applications/sxiv.desktop"

# ── Thunar is optional ───────────────────────────────────────────────────

rm -f "$XDG_DATA_DIRS/applications/thunar.desktop"
"$seed" >/dev/null || fail 'seeding failed without a file manager entry'
if grep -q 'inode/directory' "$mimeapps"; then
	fail 'a folder handler was claimed without a file manager'
fi
rm -f "$mimeapps"
install_handlers

# ── a choice made between the check and the publication wins ─────────────
#
# The script links the finished file into place rather than renaming it, so a
# preference the user wrote in that window is kept, not silently replaced.

real_ln=$(command -v ln)
export DWM_TEST_REAL_LN=$real_ln
cat >"$work/bin/ln" <<'SH'
#!/bin/sh
printf '[Default Applications]\ntext/plain=user-editor.desktop;\n' >"$XDG_CONFIG_HOME/mimeapps.list"
exec "$DWM_TEST_REAL_LN" "$@"
SH
chmod +x "$work/bin/ln"
"$seed" >"$work/race.out" || fail 'seeding failed when a preference appeared mid-run'
printf '[Default Applications]\ntext/plain=user-editor.desktop;\n' >"$work/concurrent"
cmp "$work/concurrent" "$mimeapps" || fail 'a preference written mid-run was replaced'
grep -Fq 'Preserving existing application defaults' "$work/race.out" ||
	fail 'keeping the concurrent preference was not reported'
no_partial_files

# ── install.sh installs the handlers, then seeds, then sets up Gear Lever ─
#
# Gear Lever writes its own AppImage MIME preference file. Were it to run
# first, the seed would see that file and leave every media default unset.

media_line=$(grep -n '^	dwm_install_package_profile media$' "$repo/install.sh" | head -n 1 | cut -d: -f1)
seed_line=$(grep -n 'scripts/seed-default-apps.sh' "$repo/install.sh" | head -n 1 | cut -d: -f1)
# shellcheck disable=SC2016 # matching install.sh's literal text, not expanding it
gearlever_line=$(grep -n 'if "$REPO_DIR/scripts/install-gearlever"; then' "$repo/install.sh" | head -n 1 | cut -d: -f1)
[[ -n $media_line && -n $seed_line && -n $gearlever_line ]] ||
	fail 'install.sh no longer installs media, seeds defaults and sets up Gear Lever'
((media_line < seed_line && seed_line < gearlever_line)) ||
	fail "install.sh order must be media packages ($media_line), seed ($seed_line), Gear Lever ($gearlever_line)"

printf 'Seed default apps: PASS\n'
