#!/usr/bin/env bash
# Covers scripts/dwm-settings-toolkit, which lets the user override the
# cursor, icon, GTK and Qt choices independently of the active theme.
#
# The design decision the assertions here defend: theme-apply.sh is a function
# of (themes.toml, personalization.conf), so rolling a choice back is a re-run
# of the applier, not a restore of the eleven files it derives. The
# convergence case is what proves that.

set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

helper=$repo/scripts/dwm-settings-toolkit
assert_executable "$helper"

home=$work/home
config_home=$home/.config
state_home=$home/.local/state
data_home=$home/.local/share
runtime=$work/run
mkdir -p "$config_home/lyona" "$state_home" "$runtime" \
	"$data_home/themes/Lyona-nord/gtk-3.0" \
	"$data_home/themes/Lyona-nord/gtk-4.0" \
	"$data_home/icons/Paper/cursors" \
	"$data_home/icons/Papyrus"
printf '[Icon Theme]\nName=Papyrus\nDirectories=48x48/apps\n' \
	>"$data_home/icons/Papyrus/index.theme"
# A cursor theme is not an icon theme: no Directories, so icon must refuse it.
printf '[Icon Theme]\nName=Paper\n' >"$data_home/icons/Paper/index.theme"
cp "$repo/config/themes.toml" "$config_home/lyona/themes.toml"

config=$config_home/lyona/personalization.conf

toolkit() {
	HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
		XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		DWM_SETTINGS_TOOLKIT_NO_WATCHDOG=1 \
		timeout 120 "$helper" "$@"
}

refuses() {
	local label=$1
	shift
	if toolkit "$@" >/dev/null 2>&1; then
		fail "toolkit accepted $label"
	fi
}

# ── status with nothing configured ───────────────────────────────────────

status=$(toolkit status)
grep -Fqx $'toolkit-action-protocol\t1\t0' <<<"$status" ||
	fail 'status did not emit the action protocol header'
for capability in cursor icon gtk qt; do
	grep -Eq "^selection	$capability	available	follow-(theme|system)	[^	]*	" <<<"$status" ||
		fail "status has no default selection record for $capability"
	# Settings offers the sentinel as a choice like any other, so it has to be
	# among the candidates rather than a special case in the pane.
	grep -Eq "^candidate	$capability	follow-(theme|system)$" <<<"$status" ||
		fail "status does not offer the release sentinel for $capability"
done
grep -Fq $'preview\tnone' <<<"$status" || fail 'status did not report an idle preview'
toolkit mutation-ready || fail 'mutation-ready failed on a clean fixture'
assert_no_file "$config" 'no configuration is written until something is set'

# ── apply, and what it means for the derived files ───────────────────────

gtk3_ini=$config_home/gtk-3.0/settings.ini
toolkit apply gtk Lyona-nord >/dev/null || fail 'apply gtk failed'
assert_file "$config"
assert_line "$config" $'gtk\tLyona-nord'
assert_line "$config" $'cursor\tfollow-theme'
assert_contains "$gtk3_ini" 'gtk-theme-name=Lyona-nord'

status=$(toolkit status)
grep -Fq $'selection\tgtk\tavailable\tLyona-nord\tLyona-nord\tOverridden by the user' <<<"$status" ||
	fail 'status does not report the applied override'
# The saved option and what it currently resolves to are separate columns: a
# capability following the theme has no value of its own, and the pane still
# has to be able to say what following the theme means right now.
grep -Fq $'candidate\tgtk\tLyona-nord' <<<"$status" ||
	fail 'status does not offer the installed GTK theme as a candidate'
grep -Fq $'mutation\tready\t' <<<"$status" ||
	fail 'status does not report that mutations are possible'
grep -Fqx $'complete\t1' <<<"$status" ||
	fail 'status is not terminated, so a truncated read cannot be detected'

# ── convergence: reset restores the derived file exactly ─────────────────
#
# Not by restoring a backup of gtk-3.0/settings.ini, but by re-running the
# applier with the override withdrawn. If those two disagree, this fails.

baseline=$work/gtk3-before
cp -- "$gtk3_ini" "$baseline"
toolkit apply icon Papyrus >/dev/null || fail 'apply icon failed'
assert_contains "$gtk3_ini" 'gtk-icon-theme-name=Papyrus'
toolkit reset icon >/dev/null || fail 'reset icon failed'
if ! cmp -s "$baseline" "$gtk3_ini"; then
	printf 'resetting an override did not converge back to the previous file\n' >&2
	diff -u "$baseline" "$gtk3_ini" >&2 || true
	exit 1
fi

# The file only disappears once every capability follows the theme again.
assert_file "$config" 'a partial reset stays persisted'
toolkit reset gtk >/dev/null || fail 'reset gtk failed'
assert_no_file "$config" 'the configuration is removed once nothing is overridden'

# ── validation ───────────────────────────────────────────────────────────

refuses 'an unknown capability' apply nosuch Lyona-nord
refuses 'a traversal value' apply gtk ../evil
refuses 'a value with a slash' apply gtk sub/theme
refuses 'an uninstalled GTK theme' apply gtk NoSuchTheme
refuses 'an uninstalled cursor theme' apply cursor NoSuchCursor
refuses "another capability's sentinel" apply gtk follow-system
refuses 'an unknown Qt backend' apply qt notabackend
# A cursor theme has no Directories key, so it is not a usable icon theme.
refuses 'a cursor theme as an icon theme' apply icon Paper
refuses 'an unknown capability to reset' reset nosuch
assert_no_file "$config" 'a refused mutation writes nothing'

# The sentinels themselves are always accepted.
toolkit apply cursor follow-theme >/dev/null || fail 'the cursor sentinel was refused'
toolkit apply icon follow-system >/dev/null || fail 'the icon sentinel was refused'

# ── an icon theme the user set by hand survives a reset ──────────────────
#
# The icon theme is the only capability with no palette default, so releasing
# an override has nothing to fall back to and the key was simply deleted. That
# also deleted a gtk-icon-theme-name the user had set themselves long before
# Settings existed, which is not Settings' to remove.

baseline_icon_file=$state_home/lyona/appearance/toolkit/baseline-icon

rm -f -- "$config"
toolkit apply gtk Lyona-nord >/dev/null
sed -i '/^gtk-icon-theme-name=/d' "$gtk3_ini"
printf 'gtk-icon-theme-name=Hand-Set-Icons\n' >>"$gtk3_ini"

toolkit apply icon Papyrus >/dev/null || fail 'apply icon over a hand-set value failed'
assert_contains "$gtk3_ini" 'gtk-icon-theme-name=Papyrus'
assert_file "$baseline_icon_file" 'the hand-set icon theme was recorded before being overridden'
assert_line "$baseline_icon_file" 'Hand-Set-Icons'

toolkit reset icon >/dev/null || fail 'reset icon failed'
assert_contains "$gtk3_ini" 'gtk-icon-theme-name=Hand-Set-Icons'
assert_no_file "$baseline_icon_file" 'the baseline is consumed once it has been restored'

# Having been restored, it is no longer Settings' business: a later hand edit
# must not be reverted by a stale recording.
sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=Changed-Again/' "$gtk3_ini"
toolkit apply gtk Lyona-nord >/dev/null
assert_contains "$gtk3_ini" 'gtk-icon-theme-name=Changed-Again'

# With nothing set by hand the recording is empty rather than absent: it still
# has to say the key was not there, so releasing the override removes it again.
# An absent file means something different -- that no override was ever taken.
sed -i '/^gtk-icon-theme-name=/d' "$gtk3_ini"
toolkit apply icon Papyrus >/dev/null
assert_file "$baseline_icon_file" 'the absence of an icon theme is itself recorded'
[[ -z $(cat "$baseline_icon_file") ]] ||
	fail 'an icon theme was recorded where the user had none'
toolkit reset icon >/dev/null
if grep -q '^gtk-icon-theme-name=' "$gtk3_ini"; then
	fail 'reset invented an icon theme where the user had none'
fi

# And with no recording at all, a plain theme change leaves a hand-set icon
# theme untouched. This is the wider form of the same bug: gtk-icon-theme-name
# was deleted on every apply, so any theme switch destroyed it.
rm -f -- "$baseline_icon_file"
sed -i '/^gtk-icon-theme-name=/d' "$gtk3_ini"
printf 'gtk-icon-theme-name=Untouched-By-Settings\n' >>"$gtk3_ini"
toolkit apply gtk Lyona-nord >/dev/null
assert_contains "$gtk3_ini" 'gtk-icon-theme-name=Untouched-By-Settings'

rm -f -- "$config" "$baseline_icon_file"

# ── preview, keep and revert ─────────────────────────────────────────────

toolkit apply gtk Lyona-nord >/dev/null
before_preview=$(sha256sum <"$config")

toolkit preview tok-keep 30 gtk Adwaita-dark >/dev/null || fail 'preview failed'
assert_line "$config" $'gtk\tAdwaita-dark'
grep -Fq $'preview\tactive\ttok-keep\tgtk\tAdwaita-dark' <<<"$(toolkit status)" ||
	fail 'status does not describe the active preview'
toolkit keep tok-keep >/dev/null || fail 'keep failed'
assert_line "$config" $'gtk\tAdwaita-dark'

toolkit preview tok-revert 30 gtk Lyona-nord >/dev/null || fail 'second preview failed'
toolkit revert tok-revert >/dev/null || fail 'revert failed'
assert_line "$config" $'gtk\tAdwaita-dark'

# Reverting to exactly the pre-preview state, byte for byte.
toolkit apply gtk Lyona-nord >/dev/null
assert_equals "$before_preview" "$(sha256sum <"$config")" \
	'the configuration round-tripped through preview and back'

# ── the theme transaction gate ───────────────────────────────────────────
#
# dwm-settings-theme snapshots the files theme-apply.sh derives and refuses to
# revert if they changed underneath. A toolkit mutation during that window is
# exactly such a change, so it must wait rather than break the theme revert.

mkdir -p "$state_home/lyona/appearance"
printf 'ready\n' >"$state_home/lyona/appearance/integration-transaction"
refuses 'a mutation during an armed theme transaction' apply gtk Adwaita-dark
refuses 'a reset during an armed theme transaction' reset gtk
refuses 'a preview during an armed theme transaction' preview tok-gate 30 gtk Adwaita-dark
grep -Fq $'provider\ttoolkit\trestricted' <<<"$(toolkit status)" ||
	fail 'status does not report the provider as restricted during a theme transaction'
grep -Fq $'mutation\tblocked\t' <<<"$(toolkit status)" ||
	fail 'status does not report mutations as blocked during a theme transaction'
rm -f -- "$state_home/lyona/appearance/integration-transaction"
toolkit apply gtk Adwaita-dark >/dev/null ||
	fail 'mutation stayed blocked after the theme transaction ended'

# ── an override the applier silently declines ─────────────────
#
# theme-apply.sh falls back to Adwaita when a GTK theme is missing and still
# exits 0, so exit status alone cannot tell an applied override from a
# declined one. Reporting a declined override as applied is the bug this
# guards; the stub applier reproduces it without depending on which themes
# happen to be installed on the machine running the tests.

stub_dir=$work/stub
mkdir -p "$stub_dir"
cp -- "$helper" "$repo/scripts/dwm-paths.sh" "$stub_dir/"

write_stub_applier() {
	cat >"$stub_dir/theme-apply.sh" <<STUB
#!/bin/sh
[ -z "\$DWM_APPEARANCE_TOOLKIT_REPORT" ] ||
	printf 'toolkit-selection\t%s\t%s\t%s\t%s\n' '$1' '$2' '$3' '$4' \
		>"\$DWM_APPEARANCE_TOOLKIT_REPORT"
exit 0
STUB
	chmod +x "$stub_dir/theme-apply.sh"
}

stub_toolkit() {
	HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
		XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		DWM_SETTINGS_TOOLKIT_NO_WATCHDOG=1 \
		timeout 120 "$stub_dir/dwm-settings-toolkit" "$@"
}

rm -f -- "$config"

# The applier claims a different GTK theme than the one that was requested.
write_stub_applier follow-theme '' Adwaita-dark qt6ct
if stub_toolkit apply gtk Lyona-nord >/dev/null 2>&1; then
	fail 'a GTK override the applier declined was reported as applied'
fi

# An empty icon field must not shift the later columns: tab is an IFS
# whitespace character, so splitting this record with read collapses the empty
# field and silently compares gtk against the Qt value.
write_stub_applier Capitaine-Cursors '' Lyona-nord qt6ct
stub_toolkit apply gtk Lyona-nord >/dev/null 2>&1 ||
	fail 'a converged apply was rejected because an empty report field shifted the columns'

# A capability that follows the theme is the theme's to choose, so whatever
# the applier reports for it is correct by definition.
write_stub_applier Whatever-The-Theme-Picked Some-Icon-Set Lyona-nord gtk3
stub_toolkit apply gtk Lyona-nord >/dev/null 2>&1 ||
	fail 'convergence was checked against a capability that follows the theme'

# An applier too old to write a report at all still has to work.
printf '#!/bin/sh\nexit 0\n' >"$stub_dir/theme-apply.sh"
chmod +x "$stub_dir/theme-apply.sh"
stub_toolkit apply gtk Lyona-nord >/dev/null 2>&1 ||
	fail 'an applier that writes no report was treated as a failure'

# A non-zero applier is still a failure regardless of any report.
printf '#!/bin/sh\nexit 3\n' >"$stub_dir/theme-apply.sh"
chmod +x "$stub_dir/theme-apply.sh"
if stub_toolkit apply gtk Lyona-nord >/dev/null 2>&1; then
	fail 'a failing applier was reported as success'
fi

rm -f -- "$config"

# ── a damaged configuration degrades rather than dying ───────────────────

printf 'not-a-header\tx\n' >"$config"
status=$(toolkit status) || fail 'status died on a malformed configuration'
grep -Fq $'selection\tgtk\tpartial' <<<"$status" ||
	fail 'a malformed configuration should report partial, not available'

printf 'toolkit-protocol\t1\t0\ncursor\tfollow-theme\n' >"$config"
status=$(toolkit status) || fail 'status died on a truncated configuration'
grep -Fq $'selection\tgtk\tpartial' <<<"$status" ||
	fail 'a truncated configuration should report partial'

rm -f -- "$config"

# ── an override whose theme is uninstalled afterwards ────────────────────

toolkit apply gtk Lyona-nord >/dev/null
rm -rf -- "$data_home/themes/Lyona-nord"
grep -Fq $'selection\tgtk\tunavailable\tLyona-nord' <<<"$(toolkit status)" ||
	fail 'a vanished override theme should report unavailable'
# ...and stops offering it, so the pane cannot re-apply what just vanished.
if grep -Fq $'candidate\tgtk\tLyona-nord' <<<"$(toolkit status)"; then
	fail 'an uninstalled theme is still offered as a candidate'
fi

printf '%s\n' 'Toolkit settings helper: PASS'
