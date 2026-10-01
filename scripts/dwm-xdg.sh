# shellcheck shell=sh
# shellcheck disable=SC2034 # the four directories are set for the caller
#
# The XDG base directories, from the environment or their fallbacks under
# $HOME (Sync Sprint 12 S12-14). A set value is used only when it is absolute,
# as the XDG Base Directory spec requires; a relative one is ignored. POSIX, so
# both the Bash and the sh scripts source it:
#
#     . "$lyona_lib/dwm-xdg.sh"
#     lyona_xdg_dirs
#
# Sets config_home, data_home, state_home and cache_home. HOME is needed only
# for a fallback. Without it, the default fails through the ${HOME:?}
# expansion, which ends a non-interactive shell; `lyona_xdg_dirs lenient`
# leaves that directory empty instead, for a helper that reports a missing
# HOME through its own protocol.
lyona_xdg_dirs() {
	case ${XDG_CONFIG_HOME:-} in
	/*) config_home=$XDG_CONFIG_HOME ;;
	*) if [ "${1:-}" = lenient ]; then
		config_home=${HOME:+$HOME/.config}
	else
		config_home=${HOME:?HOME is required for XDG_CONFIG_HOME fallback}/.config
	fi ;;
	esac
	case ${XDG_DATA_HOME:-} in
	/*) data_home=$XDG_DATA_HOME ;;
	*) if [ "${1:-}" = lenient ]; then
		data_home=${HOME:+$HOME/.local/share}
	else
		data_home=${HOME:?HOME is required for XDG_DATA_HOME fallback}/.local/share
	fi ;;
	esac
	case ${XDG_STATE_HOME:-} in
	/*) state_home=$XDG_STATE_HOME ;;
	*) if [ "${1:-}" = lenient ]; then
		state_home=${HOME:+$HOME/.local/state}
	else
		state_home=${HOME:?HOME is required for XDG_STATE_HOME fallback}/.local/state
	fi ;;
	esac
	case ${XDG_CACHE_HOME:-} in
	/*) cache_home=$XDG_CACHE_HOME ;;
	*) if [ "${1:-}" = lenient ]; then
		cache_home=${HOME:+$HOME/.cache}
	else
		cache_home=${HOME:?HOME is required for XDG_CACHE_HOME fallback}/.cache
	fi ;;
	esac
}
