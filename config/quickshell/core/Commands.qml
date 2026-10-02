pragma Singleton

import Quickshell

Singleton {
    // One runtime source (Sync Sprint 12 S12-13): the developer override
    // LYONA_DEV_SCRIPTS (a checkout's scripts/, never set by an install) when it
    // holds the helper, else the installed command on PATH. The helper's name is
    // the script's $0, so nothing is spliced into the shell text.
    function helperCommand(helper, action, args) {
        const argv = args || [];
        const script = '[ -n "${LYONA_DEV_SCRIPTS:-}" ] && [ -x "$LYONA_DEV_SCRIPTS/$0" ] '
            + '&& exec "$LYONA_DEV_SCRIPTS/$0" "$@"; exec "$0" "$@"';

        const command = ["sh", "-c", script, helper];
        if (action !== undefined && action !== null) {
            command.push(action);
        }

        return command.concat(argv);
    }

    // A resident watcher ends with Quickshell, however Quickshell ends: a crash
    // or SIGKILL runs none of its own cleanup (Sync Sprint 12 S12-09). setpriv
    // arms a parent-death signal (SIGTERM, which each watcher traps to stop its
    // children) and execs the guard dwm-watchdog.sh's run_parent_bound uses: the
    // parent may have died before the signal was armed, so the guard checks it is
    // still the Quickshell that started it, then execs the watcher. Without
    // setpriv (util-linux) the watcher runs as before.
    function watchCommand(command) {
        const guard = '[ "$PPID" = "$1" ] || exit 0; shift; exec "$@"';
        const script = 'command -v setpriv >/dev/null 2>&1 || exec "$@"; '
            + 'exec setpriv --pdeathsig TERM -- sh -c \'' + guard + '\' sh "$PPID" "$@"';
        return ["sh", "-c", script, "dwm-parent-bound"].concat(command);
    }

    function checkedCommand(command) {

        const script = 'output=$("$@"); status=$?; [ "$status" -eq 0 ] || exit "$status"; printf "%s\\n" "$output"';
        return ["sh", "-c", script, "dwm-checked-command"].concat(command);
    }

    function booleanStatusCommand(command) {
        const script = 'if "$@" >/dev/null 2>&1; then printf "available\\n"; else printf "restricted\\n"; fi';
        return ["sh", "-c", script, "dwm-boolean-status"].concat(command);
    }

    function terminatingCheckedCommand(command) {
        // Preserve checkedCommand's success gate while forwarding surface-close
        // signals to a long-running helper instead of orphaning it.
        const script = [
            'runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}',
            'output_file=',
            'error_file=',
            'child=',
            'terminate_requested=0',
            'cleanup() { status=$?; trap - EXIT; rm -f -- "$output_file" "$error_file"; exit "$status"; }',
            'terminate() { terminate_requested=1; if [ -n "$child" ]; then trap - HUP INT TERM; kill -TERM "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; exit 143; fi; }',
            'trap cleanup EXIT',
            'trap terminate HUP INT TERM',
            'output_file=$(mktemp "$runtime_dir/dwm-checked-command.XXXXXX") || exit 1',
            '[ "$terminate_requested" -eq 0 ] || exit 143',
            'error_file=$(mktemp "$runtime_dir/dwm-checked-command-error.XXXXXX") || exit 1',
            '[ "$terminate_requested" -eq 0 ] || exit 143',
            'file_limit=$(ulimit -f)',
            // ulimit -f counts 512-byte blocks, not bytes: 32 blocks is the
            // actual 16 KiB cap (32 * 512 = 16384 bytes), not 16384 blocks
            // (which would be 8 MiB).
            'if [ "$file_limit" = unlimited ] || [ "$file_limit" -gt 32 ]; then ulimit -f 32 || exit 1; fi',
            '[ "$terminate_requested" -eq 0 ] || exit 143',
            '"$@" >"$output_file" 2>"$error_file" &',
            'child=$!',
            '[ "$terminate_requested" -eq 0 ] || terminate',
            'wait "$child"',
            'status=$?',
            'child=',
            'head -c 512 "$error_file" >&2 || :',
            '[ "$status" -eq 0 ] || exit "$status"',
            'cat "$output_file"'
        ].join("\n");
        return ["sh", "-c", script, "dwm-terminating-checked-command"].concat(command);
    }

    function launcherHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-launcher", action, args);
    }

    function networkHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-network", action, args);
    }

    function pointerHelperCommand(action) {
        return helperCommand("dwm-quickshell-pointer", action, []);
    }

    function controlsHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controls", action, args);
    }

    function controlCenterHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controlcenter", action, args);
    }

    function powerHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controlcenter", action, args);
    }

    function sessionActionCommand(action) {
        return powerHelperCommand("session-action", [action]);
    }

    function defaultsHelperCommand(action, args) {
        return helperCommand("dwm-default-apps", action, args);
    }

    function autostartHelperCommand(action, args) {
        return helperCommand("dwm-xdg-autostart", action, args);
    }

    function lockHelperCommand() {
        return helperCommand("dwm-lock", undefined, []);
    }

    function screenshotHelperCommand(action) {
        return helperCommand("dwm-screenshot", action, []);
    }

    function systemHealthHelperCommand(action, args) {
        return helperCommand("dwm-system-health", action, args);
    }

    function systemManagementCommand(action, args) {
        return helperCommand("dwm-system-management", action, args);
    }

    function settingsProviderCommand(action, args) {
        return helperCommand("dwm-settings-provider", action, args);
    }

    function settingsDisplayCommand(action, args) {
        return helperCommand("dwm-settings-display", action, args);
    }

    function settingsDisplayProfilesCommand(action, args) {
        return helperCommand("dwm-settings-display-profiles", action, args);
    }

    function settingsInputCommand(action, args) {
        return helperCommand("dwm-settings-input", action, args);
    }

    function settingsAppearanceCommand(action, args) {
        return helperCommand("dwm-settings-appearance", action, args);
    }

    function settingsWallpaperCommand(action, args) {
        return helperCommand("dwm-settings-wallpaper", action, args);
    }

    function settingsFontCommand(action, args) {
        return helperCommand("dwm-settings-font", action, args);
    }

    function settingsThemeCommand(action, args) {
        return helperCommand("dwm-settings-theme", action, args);
    }

    function settingsToolkitCommand(action, args) {
        return helperCommand("dwm-settings-toolkit", action, args);
    }

    function panelSettingsCommand(action, args) {
        return helperCommand("dwm-panel-settings", action, args);
    }

    // The panel weather (Sync Sprint 12 S12-20).
    function weatherCommand(action, args) {
        return helperCommand("lyona-weather", action, args);
    }

    function accessibilitySettingsCommand(action, args) {
        return helperCommand("dwm-accessibility-settings", action, args);
    }

    function updateCommand(action, args) {
        return helperCommand("lyona-update", action, args);
    }

    // The panel's updates-available indicator (Sync Sprint 15 S15-02).
    function updateIndicatorCommand(action, args) {
        return helperCommand("lyona-update-indicator", action, args);
    }

    // Updates in a terminal, from Settings > System (Sync Sprint 15 S15-04).
    function updateTerminalCommand(action, args) {
        return helperCommand("lyona-update-terminal", action, args);
    }

    function versionCommand(action, args) {
        return helperCommand("lyona-version", action, args);
    }
}
