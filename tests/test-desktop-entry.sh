#!/usr/bin/env bash
set -euo pipefail

# #275: scripts/dwm-desktop-entry.sh, the one desktop-entry reader and Exec=
# writer. The reader refuses a file with control characters, a NUL, a repeated
# group or a duplicate key; the writer quotes and escapes one Exec argument.
# And a contract: no script grows a hand-written reader of its own.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
# shellcheck source=scripts/dwm-desktop-entry.sh
. "$repo/scripts/dwm-desktop-entry.sh"

entry=$work/entry.desktop
get() { # KEY [GROUP]: prints the value, then the status
	local status=0 value
	value=$(desktop_entry_get "$entry" "$@") || status=$?
	printf '%s|%s\n' "$value" "$status"
}

# ── the reader ──────────────────────────────────────────────────────────────
printf '%s\n' '# a comment' '[Desktop Entry]' 'Type=Application' 'Name = Spaced Name' \
	'Name[de]=Deutsch' 'Exec="/opt/my app/run" %U' '' '[Desktop Action new]' 'Name=Action name' >"$entry"
[[ $(get Type) == 'Application|0' ]] || fail "a plain key: $(get Type)"
[[ $(get Name) == 'Spaced Name|0' ]] || fail "spaces around = are not part of the key or value: $(get Name)"
[[ $(get 'Name[de]') == 'Deutsch|0' ]] || fail "a localized key: $(get 'Name[de]')"
[[ $(get Exec) == '"/opt/my app/run" %U|0' ]] || fail "a value is not given as written: $(get Exec)"
[[ $(get Missing) == '|1' ]] || fail "a missing key is not status 1: $(get Missing)"
[[ $(get Name 'Desktop Action new') == 'Action name|0' ]] || fail 'another group is not read when asked for'
[[ $(desktop_entry_get "$work/none.desktop" Name || echo "status $?") == 'status 1' ]] || fail 'a missing file is not status 1'

printf '[Desktop Entry]\r\nName=Windows lines\r\n' >"$entry"
[[ $(get Name) == 'Windows lines|0' ]] || fail "CRLF line ends: $(get Name)"

refused() { # DESCRIPTION: the entry in $entry is refused whole
	[[ $(get Name) == '|2' ]] || fail "$1 was not refused: $(get Name)"
}
printf '[Desktop Entry]\nName=Tab\there\n' >"$entry"
refused 'a control character'
printf '[Desktop Entry]\nName=Escape\033[31m\n' >"$entry"
refused 'an escape sequence'
printf '[Desktop Entry]\nName=Nul\000hidden\nExec=evil\n' >"$entry"
refused 'a NUL byte'
printf '[Desktop Entry]\nName=First\nName=Second\n' >"$entry"
refused 'a duplicate key'
printf '[Desktop Entry]\nName=First\n[Desktop Entry]\nExec=evil\n' >"$entry"
refused 'a repeated group'
{
	printf '[Desktop Entry]\nName=Big\n'
	head -c 70000 /dev/zero | tr '\0' x
	printf '\n'
} >"$entry"
refused 'a file over the size limit'

# ── the batch reader (#308) ─────────────────────────────────────────────────
mkdir -p "$work/batch"
printf '%s\n' '[Desktop Entry]' 'Name=One' 'Exec=one' '[Desktop Action a]' 'Name=Action' >"$work/batch/one.desktop"
printf '[Desktop Entry]\nName=Nul\000x\n' >"$work/batch/nul.desktop"
printf '%s\n' '[Desktop Entry]' 'Name=First' 'Name=Second' >"$work/batch/dup.desktop"
printf '%s\n' '[Other]' 'Name=Elsewhere' >"$work/batch/nogroup.desktop"
printf '%s\n' '[Desktop Entry]' 'Name=Two' >"$work/batch/two.desktop"
batch=$(desktop_entries_read 'Desktop Entry' "$work/batch/one.desktop" "$work/batch/nul.desktop" \
	"$work/batch/dup.desktop" "$work/batch/nogroup.desktop" "$work/batch/missing.desktop" "$work/batch/two.desktop")
expected=$(printf '%s\n' \
	"$work/batch/one.desktop	Name	One" "$work/batch/one.desktop	Exec	one" "$work/batch/one.desktop		ok" \
	"$work/batch/nul.desktop		invalid" "$work/batch/dup.desktop		invalid" \
	"$work/batch/nogroup.desktop		ok" \
	"$work/batch/two.desktop	Name	Two" "$work/batch/two.desktop		ok")
[[ $batch == "$expected" ]] || fail "the batch reader:
$batch
wanted:
$expected"
# A refused file's earlier keys never leak out; another group is read when asked.
[[ $(desktop_entries_read 'Desktop Action a' "$work/batch/one.desktop") == "$work/batch/one.desktop	Name	Action
$work/batch/one.desktop		ok" ]] || fail 'the batch reader does not read another group'
[[ -z $(desktop_entries_read 'Desktop Entry') ]] || fail 'the batch reader printed something for no files'

# ── the key writer (#308) ───────────────────────────────────────────────────
printf '%s\r\n' '[Desktop Entry]' 'Name=App' 'NotShowIn=GNOME;' '' '[Desktop Action a]' 'Name=A' >"$work/set.desktop"
desktop_entry_set "$work/set.desktop" "$work/set.out" 'Desktop Entry' NotShowIn 'GNOME;X-DWM;' OnlyShowIn 'X-DWM;' ||
	fail 'desktop_entry_set failed'
[[ $(cat "$work/set.out") == $'[Desktop Entry]\nName=App\nNotShowIn=GNOME;X-DWM;\n\nOnlyShowIn=X-DWM;\n[Desktop Action a]\nName=A' ]] ||
	fail "desktop_entry_set wrote: $(cat -A "$work/set.out")"
[[ $(desktop_entry_get "$work/set.out" NotShowIn) == 'GNOME;X-DWM;' ]] || fail 'a set key does not read back'
if desktop_entry_set "$work/set.desktop" "$work/bad.out" 'Desktop Entry' Name $'evil\nExec=x'; then
	fail 'desktop_entry_set wrote a value with a line break'
fi

# ── the Exec= writer ────────────────────────────────────────────────────────
exec_case() { # VALUE EXPECTED
	local actual
	actual=$(desktop_exec_arg "$1")
	[[ $actual == "$2" ]] || fail "desktop_exec_arg '$1' gave '$actual', want '$2'"
}
exec_case /usr/bin/app /usr/bin/app
exec_case '/opt/my app' '"/opt/my app"'
exec_case '100%' '100%%'
exec_case 'say "hi"' '"say \\"hi\\""'
exec_case 'a\b' '"a\\\\b"'
# shellcheck disable=SC2016 # a literal $ and backticks, which the writer escapes
exec_case 'cost $5' '"cost \\$5"'
# shellcheck disable=SC2016
exec_case 'run `x`' '"run \\`x\\`"'

# ── the contract ────────────────────────────────────────────────────────────
# Desktop entries are read through dwm-desktop-entry.sh, with no exceptions
# since #308: anything else that compares a line with its group header, reads
# an Exec= line itself, or looks for a desktop key at the start of a line is a
# new hand-written parser. (Name= and Type= are left out: autostop.sh reads
# them from loginctl, not from a desktop entry.)
while IFS= read -r file; do
	name=${file##*/}
	[[ $name == dwm-desktop-entry.sh ]] ||
		fail "$name reads desktop entries by hand; use scripts/dwm-desktop-entry.sh"
done < <(grep -lE "== *[\"']\[Desktop Entry\][\"']|== Exec=\*|\^(Exec|TryExec|Categories|OnlyShowIn|NotShowIn|MimeType|NoDisplay|Hidden)=" \
	"$repo"/scripts/* 2>/dev/null || true)

printf 'Desktop entry reader and Exec writer: PASS\n'
