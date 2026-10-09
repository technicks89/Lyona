#!/usr/bin/env bash
set -euo pipefail

# #282: the shell reads the XDG base directories in one place, core/Xdg.qml,
# with dwm-xdg.sh's rule: a set value only when it is absolute, else the
# fallback under HOME, and empty without a HOME. Two models used to accept a
# relative XDG_CACHE_HOME or XDG_DATA_HOME, and six worked it out themselves.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

qs=$repo/config/quickshell
# Either quote style, and any spacing around the argument.
inline=$(grep -rnE "Quickshell[.]env[[:space:]]*[(][[:space:]]*[\"'](XDG_[A-Z_]*|HOME)[\"'][[:space:]]*[)]" \
	"$qs" --include='*.qml' --include='*.js' |
	grep -v '^[^:]*/core/Xdg.qml:' || true)
[[ -z $inline ]] || fail "XDG directories read outside core/Xdg.qml:"$'\n'"$inline"
# Xdg is the qs.core module's: a file that uses it without the import gets
# "Xdg is not defined" at run time, which qmllint does not report.
while IFS= read -r user; do
	[[ $user == "$qs"/core/* ]] && continue
	grep -q '^import qs.core$' "$user" || fail "${user#"$qs"/} uses Xdg without importing qs.core"
done < <(grep -rl 'Xdg\.' "$qs" --include='*.qml')

if ! command -v quickshell >/dev/null 2>&1; then
	printf 'SKIP: quickshell is not installed; the static check passed\n'
	exit 0
fi

mkdir -p "$work/qml"
cp -a "$qs/core" "$work/qml/"
cat >"$work/qml/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.core

Scope {
    // Quit from the event loop: Quickshell is not listening for it yet while
    // the config completes.
    Timer {
        interval: 0
        running: true
        onTriggered: {
            console.info("XDG " + JSON.stringify([Xdg.home, Xdg.configHome, Xdg.dataHome,
                Xdg.stateHome, Xdg.cacheHome, Xdg.runtimeDir]));
            Qt.quit();
        }
    }
}
QML

mkdir -p "$work/runtime" "$work/h"
chmod 700 "$work/runtime"
h=$work/h
# xdg ENV...: the six values Xdg.qml gives in that environment, as JSON.
xdg() {
	env -i PATH="$PATH" QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/runtime" "$@" \
		timeout 20 quickshell --path "$work/qml/shell.qml" 2>&1 |
		sed -n 's/.*XDG \(\[.*\]\)$/\1/p' | tail -n 1
}

got=$(xdg HOME="$h")
[[ $got == "[\"$h\",\"$h/.config\",\"$h/.local/share\",\"$h/.local/state\",\"$h/.cache\",\"$work/runtime\"]" ]] ||
	fail "the defaults under HOME gave $got"
got=$(xdg HOME="$h" XDG_CONFIG_HOME=/c XDG_DATA_HOME=/d XDG_STATE_HOME=/s XDG_CACHE_HOME=/k)
[[ $got == "[\"$h\",\"/c\",\"/d\",\"/s\",\"/k\",\"$work/runtime\"]" ]] ||
	fail "absolute values were not used: $got"
# Relative values are ignored, as the specification requires.
got=$(xdg HOME="$h" XDG_CONFIG_HOME=c XDG_DATA_HOME=d XDG_STATE_HOME=s XDG_CACHE_HOME=k)
[[ $got == "[\"$h\",\"$h/.config\",\"$h/.local/share\",\"$h/.local/state\",\"$h/.cache\",\"$work/runtime\"]" ]] ||
	fail "relative values were not ignored: $got"
# No HOME: empty, as lyona_xdg_dirs lenient gives.
got=$(xdg XDG_CONFIG_HOME=/c)
[[ $got == "[\"\",\"/c\",\"\",\"\",\"\",\"$work/runtime\"]" ]] ||
	fail "without HOME the fallbacks were not empty: $got"

# The same answers as dwm-xdg.sh.
# shellcheck disable=SC2016 # expanded by the inner shell
shell=$(env -i HOME="$h" XDG_CONFIG_HOME=c XDG_DATA_HOME=/d /bin/sh -c \
	'. "$1"; lyona_xdg_dirs lenient; printf "%s %s %s %s" "$config_home" "$data_home" "$state_home" "$cache_home"' \
	sh "$repo/scripts/dwm-xdg.sh")
got=$(xdg HOME="$h" XDG_CONFIG_HOME=c XDG_DATA_HOME=/d)
[[ $shell == "$h/.config /d $h/.local/state $h/.cache" &&
	$got == "[\"$h\",\"$h/.config\",\"/d\",\"$h/.local/state\",\"$h/.cache\",\"$work/runtime\"]" ]] ||
	fail "Xdg.qml ($got) and dwm-xdg.sh ($shell) disagree"

printf 'Quickshell XDG directories from core/Xdg.qml: PASS\n'
