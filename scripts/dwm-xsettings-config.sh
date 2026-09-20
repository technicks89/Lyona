#!/usr/bin/env bash
# Sourced, not executed. Shared by scripts/dwm-settings-display and
# scripts/theme-apply.sh (Sync Sprint 3 S3-06 #304,
# docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md) so both programs edit the
# same xsettingsd.conf through one writer: replacing one key's line while
# preserving every other line, including the other program's own key.

xsettingsd_write_line() {
	local config=$1 pattern=$2 line=$3 dir temporary
	command -v xsettingsd >/dev/null 2>&1 || return 0
	dir=${config%/*}
	if [[ -L $config ]]; then
		printf 'xsettingsd-config: refusing to write through a symlinked configuration\n' >&2
		return 0
	fi
	mkdir -p "$dir" || return 0
	temporary=$(mktemp "$dir/.xsettingsd.XXXXXX") || return 0
	trap 'rm -f "${temporary:-}"' RETURN
	if [[ -f $config ]]; then
		grep -v "$pattern" "$config" >"$temporary" || :
	fi
	if [[ -n $line ]]; then
		printf '%s\n' "$line" >>"$temporary"
	fi
	chmod 644 "$temporary"
	mv -fT "$temporary" "$config" || return 0
	temporary=
	# A missing or not-yet-started daemon is fine; it reads the file on start.
	pkill -HUP -u "$UID" -x xsettingsd >/dev/null 2>&1 || :
}
