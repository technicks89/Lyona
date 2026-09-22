#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

mkdir -p "$work/data/applications"
mkdir -p "$work/home/.local/share/flatpak/exports/share/applications"
mkdir -p "$work/home/.local/share/snapd/applications"
mkdir -p "$work/bin"

assert_listed() {
	printf '%s\n' "$output" | grep -Fq "$1"
}

assert_file_line() {
	file=$1
	expected=$2
	attempts=0

	while [ "$attempts" -lt 5 ]; do
		if [ -f "$file" ] && grep -Fqx "$expected" "$file"; then
			return 0
		fi
		attempts=$((attempts + 1))
		sleep 1
	done

	printf 'expected line not found in %s: %s\n' "$file" "$expected" >&2
	return 1
}

visible_desktop="$work/data/applications/visible.desktop"
browser_desktop="$work/data/applications/browser-actions.desktop"
editor_desktop="$work/data/applications/editor-actions.desktop"
symlink_desktop="$work/data/applications/symlink.desktop"
flatpak_desktop="$work/home/.local/share/flatpak/exports/share/applications/flatpak.desktop"
snap_desktop="$work/home/.local/share/snapd/applications/snap.desktop"
localized_desktop="$work/data/applications/localized.desktop"
chatgpt_native_desktop="$work/data/applications/chatgpt.desktop"
chatgpt_web_desktop="$work/empty/applications/ChatGPT.desktop"

cat >"$work/data/applications/visible.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Visible App
GenericName=Utility
Comment=Shown in launcher
Exec=visible-app --flag %U
Icon=visible
Keywords=visible;sample;
Categories=Utility;System;
DESKTOP

cat >"$work/data/applications/browser-actions.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Brave Origin Browser
GenericName=Web Browser
Comment=Access the Internet
Exec=brave-origin-beta %U
Icon=brave-origin-beta
Categories=Network;WebBrowser;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=brave-origin-beta

[Desktop Action new-private-window]
Name=New Private Window
Exec=brave-origin-beta --incognito
DESKTOP

cat >"$work/data/applications/editor-actions.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Zed
GenericName=Text Editor
Comment=A high-performance code editor.
Exec=zeditor %U
Icon=zed
Categories=Utility;TextEditor;Development;IDE;
Keywords=zed;
Actions=NewWorkspace;

[Desktop Action NewWorkspace]
Name=Open a new workspace
Exec=zeditor --new %U
DESKTOP

cat >"$work/data/applications/symlink-target.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Symlinked App
Exec=symlinked-app
DESKTOP
ln -s "$work/data/applications/symlink-target.desktop" "$work/data/applications/symlink.desktop"

cat >"$work/home/.local/share/flatpak/exports/share/applications/flatpak.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Flatpak Export
GenericName=Exported App
Comment=Shown from Flatpak export path
Exec=flatpak-export
Icon=flatpak
Keywords=flatpak;exported;
Categories=Network;
DESKTOP

cat >"$work/home/.local/share/snapd/applications/snap.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Snap Export
GenericName=Packaged App
Comment=Shown from Snap export path
Exec=snap-export
Icon=snap
Keywords=snap;exported;
Categories=Utility;
StartupWMClass=snap-export
Actions=new-window;
DESKTOP

cat >"$work/data/applications/localized.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Base Name
Name[en_US]=Localized Name
GenericName=Base Generic
GenericName[en_US]=Localized Generic
Comment=Base comment
Comment[en_US]=Localized comment
Exec=localized-app
Icon=localized
Keywords=base;
Keywords[en_US]=localized;translated;
Categories=Office;
DESKTOP

cat >"$work/data/applications/hidden.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Hidden App
Exec=hidden-app
NoDisplay=true
DESKTOP

mkdir -p "$work/empty/applications"
cat >"$chatgpt_native_desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ChatGPT
GenericName=AI assistant
Exec=chatgpt %U
Categories=Utility;Development;
DESKTOP

cat >"$chatgpt_web_desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ChatGPT
Exec=webapp-launch https://chatgpt.com/
Categories=Network;WebApp;
DESKTOP

cat >"$work/data/applications/link.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Link
Name=Link Entry
Exec=xdg-open https://example.invalid
DESKTOP

output=$(
	LANG=en_US.UTF-8 \
		HOME="$work/home" \
		XDG_DATA_HOME="$work/empty" \
		XDG_DATA_DIRS="$work/data" \
		"$repo/scripts/dwm-quickshell-launcher" list
)

assert_listed 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'
assert_listed 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'"$visible_desktop"'	visible;sample;	Utility;System;'
assert_listed 'Brave Origin Browser	Web Browser	Access the Internet	brave-origin-beta %U	brave-origin-beta	'"$browser_desktop"'		Network;WebBrowser;		new-window;new-private-window;'
assert_listed 'Zed	Text Editor	A high-performance code editor.	zeditor %U	zed	'"$editor_desktop"'	zed;	Utility;TextEditor;Development;IDE;		NewWorkspace;'
assert_listed 'Flatpak Export	Exported App	Shown from Flatpak export path	flatpak-export	flatpak	'"$flatpak_desktop"'	flatpak;exported;	Network;'
assert_listed 'Snap Export	Packaged App	Shown from Snap export path	snap-export	snap	'"$snap_desktop"'	snap;exported;	Utility;	snap-export	new-window;'
assert_listed 'Localized Name	Localized Generic	Localized comment	localized-app	localized	'"$localized_desktop"'	localized;translated;	Office;'
assert_listed 'Symlinked App			symlinked-app		'"$symlink_desktop"
if printf '%s\n' "$output" | grep -F 'Hidden App'; then
	exit 1
fi
if printf '%s\n' "$output" | grep -F 'Link Entry'; then
	exit 1
fi
assert_listed "$chatgpt_native_desktop"
if printf '%s\n' "$output" | grep -F "$chatgpt_web_desktop"; then
	exit 1
fi

# Entries scoped to other desktops are not listed (Desktop Entry spec: OnlyShowIn,
# NotShowIn against the XDG_CURRENT_DESKTOP tokens), so another environment's
# preference panels do not appear in the launcher.
mkdir -p "$work/desktops/applications"
make_scoped_entry() {
	# make_scoped_entry FILE NAME [KEY=VALUE]... (the extra lines go in the main group)
	scoped_file=$work/desktops/applications/$1.desktop
	scoped_name=$2
	shift 2
	{
		printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n' "$scoped_name" "$1-exec"
		printf '%s\n' "$@"
	} >"$scoped_file"
}
make_scoped_entry only-xfce 'XFCE Only App' 'OnlyShowIn=XFCE;'
make_scoped_entry only-dwm 'DWM Only App' 'OnlyShowIn=XFCE;dwm;'
make_scoped_entry only-xdwm 'X-DWM Only App' 'OnlyShowIn=X-DWM;'
make_scoped_entry not-dwm 'Not DWM App' 'NotShowIn=dwm;'
make_scoped_entry not-kde 'Not KDE App' 'NotShowIn=KDE;'
make_scoped_entry only-before-not 'Only Before Not App' 'OnlyShowIn=X-DWM;' 'NotShowIn=dwm;'
make_scoped_entry not-before-only 'Not Before Only App' 'OnlyShowIn=dwm;' 'NotShowIn=X-DWM;'
make_scoped_entry both-shown 'Both Keys Shown' 'OnlyShowIn=dwm;' 'NotShowIn=KDE;'
make_scoped_entry whitespace-only 'Whitespace Only App' 'OnlyShowIn =  dwm;'
make_scoped_entry whitespace-not 'Whitespace Not App' 'NotShowIn =  dwm;'
make_scoped_entry empty-only 'Empty Only App' 'OnlyShowIn='
make_scoped_entry empty-not 'Empty Not App' 'NotShowIn='
make_scoped_entry wrong-case 'Wrong Case App' 'OnlyShowIn=DWM;'
# A key inside an action group scopes the action, never the whole entry.
make_scoped_entry action-scope 'Action Scope App' 'Actions=new;'
printf '\n[Desktop Action new]\nName=New\nExec=action-scope-exec --new\nOnlyShowIn=XFCE;\n' >>"$work/desktops/applications/action-scope.desktop"

list_for_desktop() {
	# list_for_desktop TOKENS ("-" leaves XDG_CURRENT_DESKTOP unset)
	if [ "$1" = - ]; then
		env -u XDG_CURRENT_DESKTOP LANG=en_US.UTF-8 HOME="$work/home" \
			XDG_DATA_HOME="$work/empty" XDG_DATA_DIRS="$work/desktops" \
			"$repo/scripts/dwm-quickshell-launcher" list
	else
		XDG_CURRENT_DESKTOP=$1 LANG=en_US.UTF-8 HOME="$work/home" \
			XDG_DATA_HOME="$work/empty" XDG_DATA_DIRS="$work/desktops" \
			"$repo/scripts/dwm-quickshell-launcher" list
	fi
}
listed_name() {
	# The name is the whole first column, so "DWM Only App" does not match "X-DWM Only App".
	printf '%s\n' "$1" | awk -F'\t' -v n="$2" '$1 == n { found = 1 } END { exit !found }'
}
expect_listed() {
	# expect_listed OUTPUT DESKTOP NAME...
	scoped_output=$1
	scoped_desktop=$2
	shift 2
	for scoped_name in "$@"; do
		listed_name "$scoped_output" "$scoped_name" ||
			fail "'$scoped_name' should be listed for XDG_CURRENT_DESKTOP=$scoped_desktop"
	done
}
expect_hidden() {
	scoped_output=$1
	scoped_desktop=$2
	shift 2
	for scoped_name in "$@"; do
		if listed_name "$scoped_output" "$scoped_name"; then
			fail "'$scoped_name' should not be listed for XDG_CURRENT_DESKTOP=$scoped_desktop"
		fi
	done
}

# In a Lyona session the tokens are X-DWM and dwm; unset means the same.
for desktop in 'X-DWM:dwm' -; do
	scoped_output=$(list_for_desktop "$desktop")
	expect_listed "$scoped_output" "$desktop" 'DWM Only App' 'X-DWM Only App' 'Not KDE App' \
		'Only Before Not App' 'Both Keys Shown' 'Whitespace Only App' 'Empty Not App' 'Action Scope App'
	expect_hidden "$scoped_output" "$desktop" 'XFCE Only App' 'Not DWM App' 'Not Before Only App' \
		'Whitespace Not App' 'Empty Only App' 'Wrong Case App'
done
# Another desktop sees its own entries and not this one's.
scoped_output=$(list_for_desktop XFCE)
expect_listed "$scoped_output" XFCE 'XFCE Only App' 'DWM Only App' 'Not DWM App' 'Not KDE App' \
	'Whitespace Not App' 'Empty Not App' 'Action Scope App'
expect_hidden "$scoped_output" XFCE 'X-DWM Only App' 'Only Before Not App' 'Not Before Only App' \
	'Both Keys Shown' 'Whitespace Only App' 'Empty Only App'
# Any one of several tokens is enough.
scoped_output=$(list_for_desktop 'GNOME:dwm')
expect_listed "$scoped_output" 'GNOME:dwm' 'DWM Only App' 'Not Before Only App' 'Whitespace Only App'
expect_hidden "$scoped_output" 'GNOME:dwm' 'XFCE Only App' 'Only Before Not App' 'Whitespace Not App'

cat >"$work/bin/dex" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >"$DWM_TEST_DEX_LOG"
SH
chmod +x "$work/bin/dex"

DWM_TEST_DEX_LOG="$work/dex.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/visible.desktop"
assert_file_line "$work/dex.log" "$work/data/applications/visible.desktop"

if "$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/missing.desktop" 2>"$work/missing.err"; then
	exit 1
fi
grep -Fqx "desktop entry not found: $work/data/applications/missing.desktop" "$work/missing.err"

printf 'Quickshell launcher helper: PASS\n'
