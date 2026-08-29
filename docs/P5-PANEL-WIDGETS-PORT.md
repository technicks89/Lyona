# Port Plan — Panel-Widget Persistence (dwm-titus PR #186, part 1 of 2)

Upstream: [ChrisTitusTech/dwm-titus#186](https://github.com/ChrisTitusTech/dwm-titus/pull/186)
`feat(settings): persist panel widgets and compact Settings` (closed, 27 files).

That PR bundles two independent changes. This document covers **panel-widget
persistence**. The Settings window enlargement and layout compaction is a
separate commit, planned in [`P5-SETTINGS-LAYOUT-PORT.md`](P5-SETTINGS-LAYOUT-PORT.md).

---

## Context

Panel widget visibility (workspaces, volume, Bluetooth, network, power) lives
today only in `ControlCenterModel.qml` as five in-memory `bool` properties. It
is lost on every shell restart, and Settings has no view of it at all. The
upstream change moves it onto one versioned, user-owned state file behind a new
`dwm-panel-settings` helper, read by a single root `PanelSettingsModel` that
every `DwmPanel`, the Control Center, and the Settings Appearance pane share.

`TASKS.md` already tracks this as an open APPEARANCE-001 checkbox, with
acceptance criteria written:

> - [ ] Move the existing in-memory panel-widget visibility controls onto
>   shared, versioned user state with Settings integration, safe defaults, and
>   migration that preserves the current Control Center behavior.

### What we already have

Nothing of PR #186 is in our tree, but every primitive the port needs is:

| Needed | Already in Lyona |
| --- | --- |
| Helper invocation pattern | `Commands.helperCommand(helper, action, args, preferManaged)` and `Commands.checkedCommand()` — `config/quickshell/core/Commands.qml` |
| Toggle control | `PanelToggleSwitch` with `checked`/`busy`/`enabled`/`onToggled` — `config/quickshell/core/PanelToggleSwitch.qml` |
| Provider status card | `StatusCard` with `label`/`statusState`/`value`/`detail` |
| Disable-able Control Center row | `MenuRow` — its `MouseArea` already gates on `root.enabled`, so the new `enabled:` binding works unchanged |
| Theme tokens | `menuMutedText`, `danger`, `controlNormalFill`, `controlNormalBorder`, `controlBorderWidth`, `controlRadius`, `spacingLg` — all present in `Theme.qml` |
| Locking convention | `flock -w 5 -x 9` on a runtime lock — `dwm-settings-font:738`, `dwm-settings-toolkit:814` |
| Runtime dir convention | `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` — `dwm-settings-input:11`, `dwm-settings-wallpaper:19` |

### Upstream hunks that do NOT apply to us

Drop these from the port:

- **`scripts/dwm-xsettings`** (+ `tests/test-dwm-xsettings.sh`). We have no such
  script — we fold the same job into `scripts/dwm-settings-display`, whose
  `write_xsettings_dpi()` writes `Xft/DPI <dpi * 1024>` to
  `$XDG_CONFIG_HOME/lyona/xsettingsd.conf` and `pkill -HUP`s the daemon. The
  upstream hunk is only test seams (`DWM_TEST_XSETTINGSD_UNAVAILABLE`,
  `DWM_TEST_DUMP_XSETTINGS_UNAVAILABLE`) for a file we don't have — and our
  `write_xsettings_dpi()` already degrades gracefully when `xsettingsd` is
  absent (`command -v xsettingsd >/dev/null 2>&1 || return 0`), which is the
  behaviour those seams exist to test.
- **`scripts/dev-sync-install.sh`** `source_update_dependencies_ready()` +
  `DWM_DEV_SYNC_SOURCE_UPDATE_READY` (+ the matching
  `tests/test-dev-sync-install.sh` changes). That function does not exist in
  our `dev-sync-install.sh`; it is Fedora `xsettingsd` bootstrapping.
- **`docs/P5-STATUS.md`**, **`docs/P5-PANEL-WIDGETS.md`** as written — upstream
  evidence records against Fedora 44 and their branch state. We record our own.

### Naming adaptations

| Upstream | Lyona |
| --- | --- |
| `scripts/dwm-panel-settings` | unchanged — parity with `dwm-settings-appearance`/`-font`/`-theme`, which we also kept verbatim, so future upstream diffs stay clean |
| `~/.config/dwm-titus/panel-widgets.conf` | `~/.config/lyona/panel-widgets.conf` — matches `AppearanceModel.qml:165-187` (`/lyona/themes.toml`, `/lyona/font.conf`, `/lyona/wallpaper.conf`) |
| `${XDG_RUNTIME_DIR:-/tmp/dwm-titus-$UID}` | `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` |

---

## 1. New file: `scripts/dwm-panel-settings`

Mode `0755`. Tab-indented (shfmt). Three fixed actions over
`~/.config/lyona/panel-widgets.conf`:

- `status` → 8 lines: header, one `state`, five `widget`, one `complete`.
- `set WIDGET enabled|disabled` / `reset` → 2 lines: header, one `result`.

Safety model, which is the substance of the change:

- **Absent file is the migration.** It is the former implicit all-on session
  state and is *not written* until the user sets or resets something.
- **Malformed / incomplete / unsupported-version files are preserved**, not
  repaired behind the user's back, and reported as `partial` with all-on
  values. An explicit `set`/`reset` replaces them atomically.
- **Unsafe entries are never replaced**: symlinks, hard-linked files, files
  over 4096 bytes, wrong-owner files, group/other-writable files, unsafe state
  directories, unsafe locks.
- **Writes preserve the existing file mode** and publish via
  `mv --no-clobber --no-target-directory` (absent baseline) or
  `mv --exchange --no-copy` (existing baseline), so a concurrent external edit
  is refused rather than clobbered — `restore_concurrent_config()` puts the
  intruder back. `--exchange` needs coreutils ≥ 9.5 (fine on Arch); the helper
  checks and fails cleanly otherwise.

> `tests/test-shell-contracts.sh` enforces `mv -fT` on every bare `mv -f` site.
> This helper uses the `--exchange` / `--no-clobber` forms and does not trip it.

```bash
#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

config_home=${XDG_CONFIG_HOME:-}
[[ $config_home == /* ]] || config_home=${HOME:?HOME is required for XDG_CONFIG_HOME fallback}/.config
config_dir=$config_home/lyona
config_file=$config_dir/panel-widgets.conf
runtime_base=${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}
[[ $runtime_base == /* ]] || {
	printf 'dwm-panel-settings: XDG_RUNTIME_DIR must be absolute\n' >&2
	exit 1
}
lock_file=$runtime_base/dwm-panel-settings.lock
readonly max_config_size=4096
readonly max_restore_attempts=8
readonly protocol_header=$'panel-settings-protocol\t1\t0'
readonly widget_ids='workspaces volume bluetooth network power'

declare -A widget_values=()
config_state=defaults
config_detail='Using safe all-on defaults; the first change creates persistent state'
mutation_baseline_kind=absent
mutation_baseline_hash=''
mutation_baseline_mode=600
mutation_baseline_fingerprint=''

usage() {
	printf 'usage: %s status | set WIDGET enabled|disabled | reset\n' "${0##*/}" >&2
}

die() {
	printf 'dwm-panel-settings: %s\n' "$*" >&2
	exit 1
}

set_defaults() {
	local widget
	for widget in $widget_ids; do
		widget_values[$widget]=enabled
	done
}

valid_widget() {
	case $1 in
	workspaces | volume | bluetooth | network | power) return 0 ;;
	*) return 1 ;;
	esac
}

state_file_safe() {
	local path=$1 mode
	mode=$(stat -c %a -- "$path" 2>/dev/null) || return 1
	[[ -f $path && ! -L $path && -r $path &&
		$(stat -c %u -- "$path") == "$UID" &&
		$(stat -c %h -- "$path") == 1 &&
		$(stat -c %s -- "$path") -le $max_config_size ]] &&
		(((8#$mode & 022) == 0))
}

config_file_safe() {
	state_file_safe "$config_file"
}

config_dir_safe() {
	local mode
	mode=$(stat -c %a -- "$config_dir" 2>/dev/null) || return 1
	[[ -d $config_dir && ! -L $config_dir && $(stat -c %u -- "$config_dir") == "$UID" ]] &&
		(((8#$mode & 022) == 0))
}

load_config() {
	local line first=true widget value count=0
	local -A seen=()
	set_defaults
	if [[ -e $config_dir || -L $config_dir ]] && ! config_dir_safe; then
		config_state=unavailable
		config_detail='Persistent panel state directory is unsafe; using all-on defaults'
		return 1
	fi
	if [[ ! -e $config_file && ! -L $config_file ]]; then
		return 0
	fi
	if ! config_file_safe; then
		config_state=unavailable
		config_detail='Persistent panel state is unsafe; using all-on defaults'
		return 1
	fi
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $first == true ]]; then
			if [[ $line != "$protocol_header" ]]; then
				config_state=partial
				if [[ $line == panel-settings-protocol$'\t'* ]]; then
					config_detail='Unsupported panel settings version was preserved; using all-on defaults'
				else
					config_detail='Malformed panel settings were preserved; using all-on defaults'
				fi
				return 1
			fi
			first=false
			continue
		fi
		if [[ $line != *$'\t'* || ${line#*$'\t'} == *$'\t'* ]]; then
			config_state=partial
			config_detail='Malformed panel settings were preserved; using all-on defaults'
			set_defaults
			return 1
		fi
		widget=${line%%$'\t'*}
		value=${line#*$'\t'}
		if ! valid_widget "$widget" || [[ $value != enabled && $value != disabled ]] ||
			[[ -n ${seen[$widget]+x} ]]; then
			config_state=partial
			config_detail='Malformed panel settings were preserved; using all-on defaults'
			set_defaults
			return 1
		fi
		seen[$widget]=1
		widget_values[$widget]=$value
		((count += 1))
	done <"$config_file"
	if [[ $first == true || $count -ne 5 ]]; then
		config_state=partial
		config_detail='Incomplete panel settings were preserved; using all-on defaults'
		set_defaults
		return 1
	fi
	config_state=available
	config_detail='Persistent panel visibility is active for every monitor'
}

emit_status() {
	local widget
	load_config || true
	printf '%s\n' "$protocol_header"
	printf 'state\t%s\t%s\n' "$config_state" "$config_detail"
	for widget in $widget_ids; do
		printf 'widget\t%s\t%s\n' "$widget" "${widget_values[$widget]}"
	done
	printf 'complete\tstatus\n'
}

ensure_mutation_paths() {
	if [[ ! -e $runtime_base ]]; then
		(umask 077 && mkdir -p -- "$runtime_base")
	fi
	[[ -d $runtime_base && ! -L $runtime_base &&
		$(stat -c %u -- "$runtime_base") == "$UID" ]] ||
		die "unsafe runtime directory: $runtime_base"
	chmod 700 -- "$runtime_base"
	if [[ -e $lock_file || -L $lock_file ]]; then
		[[ -f $lock_file && ! -L $lock_file && $(stat -c %u -- "$lock_file") == "$UID" &&
		$(stat -c %h -- "$lock_file") == 1 ]] || die "unsafe lock file: $lock_file"
	fi
	: >>"$lock_file"
	chmod 600 -- "$lock_file"
	exec 9>"$lock_file"
	flock -w 5 9 || die 'another panel settings operation is still running'
	if [[ ! -e $config_dir ]]; then
		(umask 077 && mkdir -p -- "$config_dir")
	fi
	config_dir_safe ||
		die "unsafe configuration directory: $config_dir"
}

file_hash() {
	sha256sum -- "$1" | awk '{ print $1 }'
}

entry_fingerprint() {
	local path=$1 metadata
	metadata=$(stat -c '%d:%i:%h:%f:%s' -- "$path") || return 1
	if [[ -L $path ]]; then
		printf '%s:link:%s\n' "$metadata" "$(readlink -- "$path")"
	elif [[ -f $path ]]; then
		printf '%s:file:%s\n' "$metadata" "$(file_hash "$path")"
	else
		printf '%s:other\n' "$metadata"
	fi
}

capture_mutation_baseline() {
	mutation_baseline_kind=absent
	mutation_baseline_hash=''
	mutation_baseline_mode=600
	mutation_baseline_fingerprint=''
	if [[ -e $config_file || -L $config_file ]]; then
		config_file_safe || die "unsafe persistent state: $config_file"
		mutation_baseline_kind='file'
		mutation_baseline_hash=$(file_hash "$config_file")
		mutation_baseline_mode=$(stat -c %a -- "$config_file")
		mutation_baseline_fingerprint=$(entry_fingerprint "$config_file")
	fi
}

mutation_baseline_unchanged() {
	if [[ $mutation_baseline_kind == file ]]; then
		config_file_safe && [[ $(file_hash "$config_file") == "$mutation_baseline_hash" &&
		$(stat -c %a -- "$config_file") == "$mutation_baseline_mode" ]]
	else
		[[ ! -e $config_file && ! -L $config_file ]]
	fi
}

die_mutation_baseline_changed() {
	if [[ $mutation_baseline_kind == file ]]; then
		die 'panel state changed during the transaction; refusing to overwrite it'
	else
		die 'panel state appeared during the transaction; refusing to overwrite it'
	fi
}

wait_for_baseline_test_release() {
	if [[ -n ${DWM_TEST_PANEL_BASELINE_READY:-} ]]; then
		: >"$DWM_TEST_PANEL_BASELINE_READY"
		while [[ ! -e ${DWM_TEST_PANEL_BASELINE_RELEASE:-} ]]; do
			sleep 0.01
		done
	fi
}

mv_exchange_options_supported() {
	local help
	help=$(LC_ALL=C mv --help 2>/dev/null) || return 1
	[[ $help == *'--exchange'* && $help == *'--no-copy'* ]]
}

wait_for_rollback_test_release() {
	if [[ -n ${DWM_TEST_PANEL_ROLLBACK_READY:-} ]]; then
		: >"$DWM_TEST_PANEL_ROLLBACK_READY"
		while [[ ! -e ${DWM_TEST_PANEL_ROLLBACK_RELEASE:-} ]]; do
			sleep 0.01
		done
		DWM_TEST_PANEL_ROLLBACK_READY=
		DWM_TEST_PANEL_ROLLBACK_RELEASE=
	fi
}

restore_concurrent_config() {
	local staged=$1 expected_fingerprint=$2 published_fingerprint=$3
	local candidate_fingerprint displaced_fingerprint current_fingerprint attempt=0
	while ((attempt < max_restore_attempts)); do
		attempt=$((attempt + 1))
		candidate_fingerprint=$(entry_fingerprint "$staged" 2>/dev/null || true)
		if [[ -z $candidate_fingerprint ]]; then
			printf 'dwm-panel-settings: concurrent panel state retained at %s\n' "$staged" >&2
			return 1
		fi
		current_fingerprint=$(entry_fingerprint "$config_file" 2>/dev/null || true)
		if [[ $current_fingerprint != "$expected_fingerprint" ]]; then
			printf 'dwm-panel-settings: concurrent panel state retained at %s\n' "$staged" >&2
			return 1
		fi
		wait_for_rollback_test_release
		if ! mv --exchange --no-copy -- "$staged" "$config_file"; then
			printf 'dwm-panel-settings: concurrent panel state retained at %s\n' "$staged" >&2
			return 1
		fi
		displaced_fingerprint=$(entry_fingerprint "$staged" 2>/dev/null || true)
		if [[ $displaced_fingerprint == "$expected_fingerprint" ]]; then
			if [[ $displaced_fingerprint == "$published_fingerprint" ]]; then
				unlink -- "$staged"
			else
				printf 'dwm-panel-settings: superseded panel state retained at %s\n' "$staged" >&2
			fi
			return 0
		fi
		# A newer edit landed after the check. It is now staged; make it the
		# next restoration candidate while treating the file just installed as
		# the only entry this transaction may exchange away.
		expected_fingerprint=$candidate_fingerprint
	done
	# The last failed comparison left the newest observed edit in staged and
	# the prior candidate at config_file. Give that edit one final guarded
	# exchange so exhaustion does not knowingly leave stale state published.
	candidate_fingerprint=$(entry_fingerprint "$staged" 2>/dev/null || true)
	current_fingerprint=$(entry_fingerprint "$config_file" 2>/dev/null || true)
	if [[ -n $candidate_fingerprint && $current_fingerprint == "$expected_fingerprint" ]] &&
		mv --exchange --no-copy -- "$staged" "$config_file"; then
		displaced_fingerprint=$(entry_fingerprint "$staged" 2>/dev/null || true)
		if [[ $displaced_fingerprint == "$expected_fingerprint" ]]; then
			if [[ $displaced_fingerprint == "$published_fingerprint" ]]; then
				unlink -- "$staged"
			else
				printf 'dwm-panel-settings: superseded panel state retained at %s\n' "$staged" >&2
			fi
			printf 'dwm-panel-settings: concurrent panel state restored at %s after retry exhaustion\n' \
				"$config_file" >&2
			return 1
		fi
	fi
	printf 'dwm-panel-settings: concurrent panel state retained at %s\n' "$staged" >&2
	return 1
}

publish_config() {
	local staged=$1 published_hash published_fingerprint captured_hash captured_mode captured_fingerprint
	published_hash=$(file_hash "$staged") || die 'cannot hash temporary panel state'
	published_fingerprint=$(entry_fingerprint "$staged") || die 'cannot identify temporary panel state'
	if [[ $mutation_baseline_kind == absent ]]; then
		mv --no-clobber --no-target-directory -- "$staged" "$config_file" ||
			die 'cannot publish panel state'
		if [[ -e $staged || -L $staged ]]; then
			unlink -- "$staged"
			die_mutation_baseline_changed
		fi
		[[ $(file_hash "$config_file" 2>/dev/null || true) == "$published_hash" ]] ||
			die 'published panel state could not be verified'
		return
	fi
	if ! mv_exchange_options_supported; then
		unlink -- "$staged"
		die 'GNU mv with --exchange and --no-copy is required (coreutils 9.5 or newer)'
	fi
	if ! mv --exchange --no-copy -- "$staged" "$config_file"; then
		unlink -- "$staged"
		die 'atomic panel state exchange is unavailable on the configuration filesystem'
	fi
	captured_hash=$(file_hash "$staged" 2>/dev/null || true)
	captured_mode=$(stat -c %a -- "$staged" 2>/dev/null || true)
	captured_fingerprint=$(entry_fingerprint "$staged" 2>/dev/null || true)
	if [[ $captured_hash == "$mutation_baseline_hash" &&
		$captured_mode == "$mutation_baseline_mode" &&
		$captured_fingerprint == "$mutation_baseline_fingerprint" ]]; then
		unlink -- "$staged"
		return
	fi
	restore_concurrent_config "$staged" "$published_fingerprint" "$published_fingerprint" || true
	die_mutation_baseline_changed
}

write_config() {
	local temporary widget
	temporary=$(umask 077 && mktemp "$config_dir/.panel-widgets.conf.XXXXXX") ||
		die 'cannot create temporary panel state'
	{
		printf '%s\n' "$protocol_header"
		for widget in $widget_ids; do
			printf '%s\t%s\n' "$widget" "${widget_values[$widget]}"
		done
	} >"$temporary"
	chmod "$mutation_baseline_mode" -- "$temporary"
	if [[ -n ${DWM_TEST_PANEL_PUBLISH_READY:-} ]]; then
		: >"$DWM_TEST_PANEL_PUBLISH_READY"
		while [[ ! -e ${DWM_TEST_PANEL_PUBLISH_RELEASE:-} ]]; do
			sleep 0.01
		done
	fi
	if ! mutation_baseline_unchanged; then
		unlink -- "$temporary"
		die_mutation_baseline_changed
	fi
	if [[ -n ${DWM_TEST_PANEL_EXCHANGE_READY:-} ]]; then
		: >"$DWM_TEST_PANEL_EXCHANGE_READY"
		while [[ ! -e ${DWM_TEST_PANEL_EXCHANGE_RELEASE:-} ]]; do
			sleep 0.01
		done
	fi
	publish_config "$temporary"
}

set_widget() {
	local widget=$1 value=$2
	valid_widget "$widget" || die "unsupported widget: $widget"
	[[ $value == enabled || $value == disabled ]] || die 'widget state must be enabled or disabled'
	ensure_mutation_paths
	capture_mutation_baseline
	wait_for_baseline_test_release
	load_config || {
		[[ $config_state == partial ]] || die 'persistent panel state is unsafe'
	}
	mutation_baseline_unchanged || die_mutation_baseline_changed
	widget_values[$widget]=$value
	write_config
	printf 'panel-settings-action-protocol\t1\t0\nresult\tset\t%s\t%s\n' "$widget" "$value"
}

reset_settings() {
	ensure_mutation_paths
	capture_mutation_baseline
	wait_for_baseline_test_release
	mutation_baseline_unchanged || die_mutation_baseline_changed
	set_defaults
	write_config
	printf 'panel-settings-action-protocol\t1\t0\nresult\treset\tall\tenabled\n'
}

case ${1:-} in
status)
	[[ $# -eq 1 ]] || {
		usage
		exit 2
	}
	emit_status
	;;
set)
	[[ $# -eq 3 ]] || {
		usage
		exit 2
	}
	set_widget "$2" "$3"
	;;
reset)
	[[ $# -eq 1 ]] || {
		usage
		exit 2
	}
	reset_settings
	;;
-h | --help | help)
	usage
	;;
*)
	usage
	exit 2
	;;
esac
```

---

## 2. New file: `config/quickshell/panel/PanelSettingsModel.qml`

One root instance, shared by every consumer. Event-driven through a single
`FileView` watch plus a 75 ms settle timer — no polling process, no
per-monitor watcher.

> **Reactivity note, do not "optimise" away:** `widgetEnabled()` reads
> `root.values[id]`, and `parseStatus()` **reassigns** `root.values` wholesale.
> That reassignment is what re-fires every binding in the panel, Control Center
> and Settings. Mutating the map in place would silently stop updating the UI.

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property string providerState: "idle"
    property string providerDetail: "Loading panel settings"
    property bool busy: false
    property string message: ""
    property string pendingWidget: ""
    property string pendingValue: ""
    property bool statusParsed: false
    property bool refreshPending: false
    property bool mutationRefreshPending: false
    property bool actionSucceeded: false
    property var values: ({
        "workspaces": true,
        "volume": true,
        "bluetooth": true,
        "network": true,
        "power": true
    })
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME")
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string configPath: root.configHome + "/lyona/panel-widgets.conf"
    readonly property bool mutationReady: root.providerState !== "unavailable"
    readonly property var widgets: [
        { "id": "workspaces", "label": "Workspaces" },
        { "id": "volume", "label": "Volume" },
        { "id": "bluetooth", "label": "Bluetooth" },
        { "id": "network", "label": "Network" },
        { "id": "power", "label": "Power" }
    ]

    function validWidget(id) {
        return id === "workspaces" || id === "volume" || id === "bluetooth"
            || id === "network" || id === "power";
    }

    function widgetEnabled(id) {
        return root.validWidget(id) ? root.values[id] !== false : true;
    }

    function useDefaults() {
        root.values = ({
            "workspaces": true,
            "volume": true,
            "bluetooth": true,
            "network": true,
            "power": true
        });
    }

    function refresh() {
        if (statusProcess.running) {
            root.refreshPending = true;
            return;
        }
        root.refreshPending = false;
        root.statusParsed = false;
        statusProcess.running = true;
    }

    function parseStatus(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 8 || lines[0] !== "panel-settings-protocol\t1\t0"
                || lines[7] !== "complete\tstatus") return;
        const state = lines[1].split("\t");
        if (state.length !== 3 || state[0] !== "state"
                || ["available", "defaults", "partial", "unavailable"].indexOf(state[1]) < 0)
            return;
        const parsed = {};
        for (let index = 2; index < 7; index++) {
            const fields = lines[index].split("\t");
            if (fields.length !== 3 || fields[0] !== "widget" || !root.validWidget(fields[1])
                    || (fields[2] !== "enabled" && fields[2] !== "disabled")
                    || parsed[fields[1]] !== undefined) return;
            parsed[fields[1]] = fields[2] === "enabled";
        }
        for (const widget of root.widgets) {
            if (parsed[widget.id] === undefined) return;
        }
        root.values = parsed;
        root.providerState = state[1];
        root.providerDetail = state[2];
        root.statusParsed = true;
    }

    function setWidget(id, enabled) {
        if (!root.validWidget(id) || root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingWidget = id;
        root.pendingValue = enabled ? "enabled" : "disabled";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(
            Commands.panelSettingsCommand("set", [id, root.pendingValue]));
        actionProcess.running = true;
    }

    function toggleWidget(id) {
        root.setWidget(id, !root.widgetEnabled(id));
    }

    function reset() {
        if (root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingWidget = "all";
        root.pendingValue = "enabled";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(Commands.panelSettingsCommand("reset", []));
        actionProcess.running = true;
    }

    function parseAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || lines[0] !== "panel-settings-action-protocol\t1\t0") return;
        const fields = lines[1].split("\t");
        if (fields.length !== 4 || fields[0] !== "result") return;
        if (fields[1] === "set")
            root.actionSucceeded = fields[2] === root.pendingWidget
                && fields[3] === root.pendingValue;
        else if (fields[1] === "reset")
            root.actionSucceeded = root.pendingWidget === "all"
                && fields[2] === "all" && fields[3] === "enabled";
    }

    Component.onCompleted: root.refresh()

    FileView {
        id: configWatch
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: settleTimer.restart()
        onLoadFailed: settleTimer.restart()
        onFileChanged: reload()
    }

    Timer {
        id: settleTimer
        interval: 75
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess
        command: Commands.panelSettingsCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: statusError }
        onRunningChanged: if (!running) {
            if (!root.statusParsed) {
                root.useDefaults();
                root.providerState = "unavailable";
                root.providerDetail = statusError.text.trim().length > 0
                    ? statusError.text.trim() : "Panel settings provider returned invalid data";
            }
            if (root.refreshPending) {
                Qt.callLater(root.refresh);
            } else if (root.mutationRefreshPending) {
                root.mutationRefreshPending = false;
                root.busy = false;
            }
        }
    }

    Process {
        id: actionProcess
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseAction(this.text) }
        stderr: StdioCollector { id: actionError }
        onRunningChanged: if (!running && root.busy) {
            root.message = root.actionSucceeded ? "Panel visibility updated"
                : actionError.text.trim().length > 0 ? actionError.text.trim()
                : "Panel settings helper did not confirm the change";
            root.mutationRefreshPending = true;
            Qt.callLater(root.refresh);
        }
    }
}
```

---

## 3. `config/quickshell/core/Commands.qml`

Append after `settingsToolkitCommand` (currently the last function, line ~111):

```diff
     function settingsToolkitCommand(action, args) {
         return helperCommand("dwm-settings-toolkit", action, args, true);
     }
+
+    function panelSettingsCommand(action, args) {
+        return helperCommand("dwm-panel-settings", action, args, true);
+    }
 }
```

Managed-first (`preferManaged = true`) like every other settings helper, so it
resolves `$XDG_DATA_HOME/lyona/scripts/dwm-panel-settings` before `$PATH`.

---

## 4. `config/quickshell/controlcenter/ControlCenterModel.qml`

Replace the five in-memory booleans with `readonly` delegations, and keep the
label-keyed public API — `ControlCenterWindow.qml` passes `"Volume"`,
`"Workspaces"`, … and its Repeater model is unchanged.

Lines 14-18:

```diff
     property var utilityScreen: null
-    property bool showVolumeWidget: true
-    property bool showBluetoothWidget: true
-    property bool showNetworkWidget: true
-    property bool showPowerWidget: true
-    property bool showWorkspaceWidget: true
+    property var panelSettingsModel: null
+    readonly property var widgetIds: ({
+        "Workspaces": "workspaces",
+        "Volume": "volume",
+        "Bluetooth": "bluetooth",
+        "Network": "network",
+        "Power": "power"
+    })
+    readonly property bool showVolumeWidget: root.panelSettingsModel
+        ? root.panelSettingsModel.widgetEnabled("volume") : true
+    readonly property bool showBluetoothWidget: root.panelSettingsModel
+        ? root.panelSettingsModel.widgetEnabled("bluetooth") : true
+    readonly property bool showNetworkWidget: root.panelSettingsModel
+        ? root.panelSettingsModel.widgetEnabled("network") : true
+    readonly property bool showPowerWidget: root.panelSettingsModel
+        ? root.panelSettingsModel.widgetEnabled("power") : true
+    readonly property bool showWorkspaceWidget: root.panelSettingsModel
+        ? root.panelSettingsModel.widgetEnabled("workspaces") : true
     property string message: ""
```

Lines 73-87:

```diff
     function widgetEnabled(name) {
-        if (name === "Volume") return root.showVolumeWidget;
-        if (name === "Bluetooth") return root.showBluetoothWidget;
-        if (name === "Network") return root.showNetworkWidget;
-        if (name === "Power") return root.showPowerWidget;
-        return root.showWorkspaceWidget;
+        const id = root.widgetIds[name];
+        if (!root.panelSettingsModel || id === undefined) return true;
+        return root.panelSettingsModel.widgetEnabled(id);
     }

     function toggleWidget(name) {
-        if (name === "Volume") root.showVolumeWidget = !root.showVolumeWidget;
-        else if (name === "Bluetooth") root.showBluetoothWidget = !root.showBluetoothWidget;
-        else if (name === "Network") root.showNetworkWidget = !root.showNetworkWidget;
-        else if (name === "Power") root.showPowerWidget = !root.showPowerWidget;
-        else if (name === "Workspaces") root.showWorkspaceWidget = !root.showWorkspaceWidget;
+        const id = root.widgetIds[name];
+        if (!root.panelSettingsModel || id === undefined) return;
+        root.panelSettingsModel.toggleWidget(id);
     }
```

---

## 5. `config/quickshell/panel/DwmPanel.qml`

Add the required property (after line 35), and repoint the five `visible`
bindings straight at the shared model rather than through the Control Center.

```diff
     required property var controlCenterModel
+    required property var panelSettingsModel
     required property var powerModel
```

Then, at lines 95, 224, 255, 287, 333 respectively:

```diff
-                        visible: root.controlCenterModel.showWorkspaceWidget
+                        visible: root.panelSettingsModel.widgetEnabled("workspaces")
```
```diff
-                        visible: root.controlCenterModel.showBluetoothWidget
+                        visible: root.panelSettingsModel.widgetEnabled("bluetooth")
```
```diff
-                        visible: root.controlCenterModel.showNetworkWidget
+                        visible: root.panelSettingsModel.widgetEnabled("network")
```
```diff
-                        visible: root.controlCenterModel.showVolumeWidget
+                        visible: root.panelSettingsModel.widgetEnabled("volume")
```
```diff
-                        visible: root.controlCenterModel.showPowerWidget
+                        visible: root.panelSettingsModel.widgetEnabled("power")
```

---

## 6. `config/quickshell/controlcenter/ControlCenterWindow.qml`

**6a.** Add `pageMessage()` after `pageTitle()` (line ~31), so the Bar Widgets
page can surface helper errors and provider state instead of a blank line:

```diff
     function pageTitle() {
         if (controlCenterModel.page === "widgets") return "Bar Widgets";
         if (controlCenterModel.page === "actions") return "Quick Actions";
         if (controlCenterModel.page === "appearance") return "Appearance";
         if (controlCenterModel.page === "power") return "Power Settings";
         return "Control Center";
     }

+    function pageMessage() {
+        if (root.controlCenterModel.page === "power")
+            return root.powerModel.messageFor("controlcenter");
+        if (root.controlCenterModel.page === "widgets"
+                && root.controlCenterModel.panelSettingsModel) {
+            const panelModel = root.controlCenterModel.panelSettingsModel;
+            if (panelModel.message.length > 0 && !panelModel.actionSucceeded)
+                return panelModel.message;
+            if (panelModel.providerState !== "available" && panelModel.providerState !== "defaults")
+                return panelModel.providerDetail;
+            if (panelModel.message.length > 0) return panelModel.message;
+        }
+        return root.controlCenterModel.message;
+    }
+
```

**6b.** Use it for the status line (lines 198-206). This also collapses the
duplicated ternary that was evaluated twice:

```diff
                 UiText {
                     Layout.fillWidth: true
-                    visible: (root.controlCenterModel.page === "power"
-                        ? root.powerModel.messageFor("controlcenter") : root.controlCenterModel.message).length > 0
-                    text: root.controlCenterModel.page === "power"
-                        ? root.powerModel.messageFor("controlcenter") : root.controlCenterModel.message
+                    visible: root.pageMessage().length > 0
+                    text: root.pageMessage()
                     color: Theme.textMuted
                     elide: Text.ElideRight
                 }
```

**6c.** Make the widget rows inert while the helper is busy or the state file is
unsafe (line ~299). `MenuRow`'s `MouseArea` already reads `root.enabled`, so
this needs no component change:

```diff
                         delegate: MenuRow {
                             required property string modelData

                             Layout.fillWidth: true
                             label: modelData
                             detail: root.controlCenterModel.widgetEnabled(modelData) ? "On" : "Off"
                             active: root.controlCenterModel.widgetEnabled(modelData)
+                            enabled: !root.controlCenterModel.panelSettingsModel
+                                || (root.controlCenterModel.panelSettingsModel.mutationReady
+                                    && !root.controlCenterModel.panelSettingsModel.busy)
                             onActivated: root.controlCenterModel.toggleWidget(modelData)
                         }
```

---

## 7. `config/quickshell/settings/SettingsModel.qml`

Line ~26:

```diff
     property var appearanceModel: null
+    property var panelSettingsModel: null
     property var capabilities: []
```

In `activateSection(id)`, after the appearance block (line ~180):

```diff
             else if (!wantAppearance && root.appearanceModel.settingsVisible) root.appearanceModel.closeSettings();
         }
+        if (id === "appearance" && root.panelSettingsModel) root.panelSettingsModel.refresh();
         if (id === "displays") root.refreshDisplays();
```

In `refresh()` (line 540) — note this goes **before** the early return, so the
panel state refreshes even when the capability discovery process is mid-flight:

```diff
     function refresh() {
+        if (root.visible && root.selectedSectionId === "appearance" && root.panelSettingsModel)
+            root.panelSettingsModel.refresh();
         if (!root.visible || providerProcess.running) return;
```

---

## 8. `config/quickshell/settings/AppearanceSettingsPane.qml`

Line 10:

```diff
     required property var appearanceModel
+    required property var panelSettingsModel
     required property var capabilities
```

New section inserted immediately **before** `SectionLabel { label: "Application
status" }` (line 874):

```qml
        SectionLabel { label: "Panel widgets" }

        StatusCard {
            visible: root.panelSettingsModel.providerState !== "available"
                && root.panelSettingsModel.providerState !== "defaults"
            label: "Panel visibility"
            statusState: root.panelSettingsModel.providerState
            value: "Using safe defaults"
            detail: root.panelSettingsModel.providerDetail
        }

        UiText {
            Layout.fillWidth: true
            text: "These choices apply to every monitor and persist for future shell sessions."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.panelSettingsModel.widgets

            delegate: Rectangle {
                id: panelWidgetRow
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 48
                color: Theme.controlNormalFill
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingLg
                    anchors.rightMargin: Theme.spacingLg

                    UiText {
                        Layout.fillWidth: true
                        text: panelWidgetRow.modelData.label
                        color: Theme.menuText
                    }

                    PanelToggleSwitch {
                        checked: root.panelSettingsModel.widgetEnabled(panelWidgetRow.modelData.id)
                        busy: root.panelSettingsModel.busy
                        enabled: root.panelSettingsModel.mutationReady
                        onToggled: root.panelSettingsModel.toggleWidget(panelWidgetRow.modelData.id)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            UiText {
                Layout.fillWidth: true
                text: root.panelSettingsModel.message.length > 0
                        && !root.panelSettingsModel.actionSucceeded
                    ? root.panelSettingsModel.message
                    : root.panelSettingsModel.providerState !== "available"
                        && root.panelSettingsModel.providerState !== "defaults"
                        ? root.panelSettingsModel.providerDetail
                        : root.panelSettingsModel.message.length > 0
                            ? root.panelSettingsModel.message : root.panelSettingsModel.providerDetail
                color: root.panelSettingsModel.providerState === "unavailable"
                    ? Theme.danger : Theme.menuMutedText
                wrapMode: Text.WordWrap
            }

            ShellButton {
                label: "Show all widgets"
                enabled: root.panelSettingsModel.mutationReady && !root.panelSettingsModel.busy
                onActivated: root.panelSettingsModel.reset()
            }
        }

```

---

## 9. `config/quickshell/settings/SettingsWindow.qml`

Line ~18:

```diff
     required property var appearanceModel
+    required property var panelSettingsModel
```

Line ~375, on the `AppearanceSettingsPane` instantiation:

```diff
                                 appearanceModel: root.appearanceModel
+                                panelSettingsModel: root.panelSettingsModel
                                 capabilities: root.settingsModel.capabilitiesForSection("appearance")
```

---

## 10. `config/quickshell/shell.qml` — one instance, five consumers

**10a.** Instantiate beside `AppearanceModel` (line ~174):

```diff
     AppearanceModel {
         id: appearanceModel
     }

+    PanelSettingsModel {
+        id: panelSettingsModel
+    }
+
     readonly property string dpiStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "")
```

**10b.** Control Center (line ~217):

```diff
     ControlCenterModel {
         id: controlCenterModel
         powerModel: powerModel
+        panelSettingsModel: panelSettingsModel
     }
```

**10c.** Settings model (line ~235):

```diff
         autostartModel: autostartModel
         appearanceModel: appearanceModel
+        panelSettingsModel: panelSettingsModel
     }
```

**10d.** Every panel, inside the `Variants` over `Quickshell.screens` (line ~896):

```diff
             controlCenterModel: controlCenterModel
+            panelSettingsModel: panelSettingsModel
             powerModel: powerModel
```

**10e.** Settings window (line ~960):

```diff
         autostartModel: autostartModel
         appearanceModel: appearanceModel
+        panelSettingsModel: panelSettingsModel
     }
 }
```

**10f.** Four new IPC functions in the `settings` `IpcHandler`, alongside the
existing `appearance*` ones. These are what `test-quickshell-settings-xvfb.sh`
drives:

```diff
         function appearanceRecoveryState(): string {
             return appearanceModel.recoveryState;
         }

+        function panelSettingsState(): string {
+            return panelSettingsModel.providerState;
+        }
+
+        function panelWidgetEnabled(widget: string): bool {
+            return panelSettingsModel.widgetEnabled(widget);
+        }
+
+        function panelWidgetSet(widget: string, enabled: bool): void {
+            panelSettingsModel.setWidget(widget, enabled);
+        }
+
+        function panelWidgetsReset(): void {
+            panelSettingsModel.reset();
+        }
+
```

---

## 11. `Makefile`

**11a.** `INSTALL_COMMANDS` — so the helper lands in
`$XDG_DATA_HOME/lyona/scripts/`, where `Commands.helperCommand` looks first:

```diff
 	scripts/dwm-lock-watch \
+	scripts/dwm-panel-settings \
 	scripts/dwm-quickshell-launcher \
```

**11b.** `check-shell` and `check-format` — add `scripts/dwm-panel-settings` to
both explicit script lists (it has no `.sh` suffix, so the `scripts/*.sh` glob
does not cover it). Insert after `scripts/dwm-keybinds` in each:

```diff
-... scripts/dwm-keybinds scripts/dwm-quickshell-launcher ...
+... scripts/dwm-keybinds scripts/dwm-panel-settings scripts/dwm-quickshell-launcher ...
```

**11c.** New target, after `check-quickshell-panel-menus` (line ~493):

```diff
 check-quickshell-panel-menus:
 	tests/test-quickshell-panel-menus.sh

+check-quickshell-panel-settings:
+	tests/test-quickshell-panel-settings.sh
+
 check-quickshell-command-menu:
```

**11d.** `check:` recipe (line ~668):

```diff
 	$(MAKE) check-quickshell-panel-menus
+	$(MAKE) check-quickshell-panel-settings
 	$(MAKE) check-quickshell-command-menu
```

**11e.** `.PHONY` (line ~702) — add `check-quickshell-panel-settings` after
`check-quickshell-panel-menus`.

---

## 12. Tests

### 12a. New: `tests/test-quickshell-panel-settings.sh`

Port upstream's 333-line test, rewritten to our `tests/lib.sh` conventions
(`make_workspace`, `assert_line`, `assert_contains`, `assert_equals`, `fail`,
`cleanup_add`) rather than bare `grep` with a hand-rolled `mktemp -d` + `trap`.

Cases to preserve, all against a scoped
`HOME`/`XDG_CONFIG_HOME`/`XDG_RUNTIME_DIR`:

| Case | Assertion |
| --- | --- |
| Absent state | `status` reports `state defaults`, five `enabled`, and **writes nothing** |
| Set persists | `set volume disabled` then `status` reports `available` + `volume disabled`; survives a second process |
| Malformed file | garbage first line → `state partial`, all-on values, file byte-identical afterwards |
| Unsupported version | `panel-settings-protocol\t2\t0` → `partial` with the version-specific detail |
| Incomplete file | four widget lines → `partial` "Incomplete…" |
| Explicit repair | `reset` over a malformed file publishes a valid all-on file |
| Mode preservation | `chmod 640`, `set`, mode is still `640` |
| Symlink refusal | state file symlinked → `status` reports `unavailable`; `set` dies and the link target is untouched |
| World-writable refusal | `chmod 666` → `unavailable`, no write |
| Single concurrent edit | `DWM_TEST_PANEL_PUBLISH_READY`/`_RELEASE` seam: external edit between staging and publish → helper exits non-zero, the external edit survives |
| Repeated concurrent edits | `DWM_TEST_PANEL_ROLLBACK_READY`/`_RELEASE` seam driving `restore_concurrent_config` retries |

Plus the static QML assertions upstream carries — cheap regression guards:

- `shell.qml` instantiates `PanelSettingsModel` exactly once and passes it to
  `ControlCenterModel`, `SettingsModel`, `DwmPanel`, `SettingsWindow`.
- `DwmPanel.qml` has no remaining `controlCenterModel.show*Widget` reference.
- `ControlCenterModel.qml` declares no writable `show*Widget` property.
- `Commands.qml` defines `panelSettingsCommand`.

### 12b. `tests/test-quickshell-settings-xvfb.sh`

Copy the helper into the managed script dir (line ~269):

```diff
 	"$repo/scripts/dwm-settings-theme" \
+	"$repo/scripts/dwm-panel-settings" \
 	"$repo/scripts/theme-apply.sh" \
```

Then append a stage after the appearance-recovery block (line ~1321):

```sh
test_stage='validating shared panel widget persistence'
panel_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelSettingsState)
case $panel_state in defaults | available) ;; *) exit 1 ;; esac

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetSet volume false >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	panel_volume=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetEnabled volume 2>/dev/null || true)
	[ "$panel_volume" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$panel_volume" = false ]
expected=$(printf 'volume\tdisabled')
grep -Fqx "$expected" "$config_home/lyona/panel-widgets.conf"

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetsReset >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	panel_volume=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetEnabled volume 2>/dev/null || true)
	[ "$panel_volume" = true ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$panel_volume" = true ]
```

Upstream also wraps the managed helper in a slow-`status` shim to prove the
model coalesces overlapping refreshes. Port that too — it is the only coverage
for the `refreshPending` / `mutationRefreshPending` paths in the model.

---

## 13. Documentation

**`docs/src/control-center.md`** — the "Panel Widgets" section:

```diff
 The Bar Widgets page can show or hide the workspace, volume, Bluetooth,
-network, and power widgets for the current Quickshell session. The redesigned
-panel retains the active-window title, status segments, and system tray, and
-shows all nine dwm tags (workspaces). Hovering icon-only panel controls displays
-a text tooltip.
+network, and power widgets. Those choices are stored in the project-owned
+`~/.config/lyona/panel-widgets.conf` state and apply to every monitor and
+future Quickshell session. Settings Appearance exposes the same shared controls
+and can restore the safe all-on default. The redesigned panel retains the
+active-window title, status segments, and system tray, and shows all nine dwm
+tags (workspaces). Hovering icon-only panel controls displays a text tooltip.
```

**`docs/SETTINGS-CAPABILITIES.md`** — line 56:

```diff
-| Open/close pages, show/hide panel widgets | `ControlCenterModel.qml` in-memory state | User-session | Reuse interaction patterns; persistence is not currently provided for widget visibility. |
+| Open/close pages, show/hide panel widgets | One root `PanelSettingsModel.qml` over versioned `dwm-panel-settings` state; Control Center delegates to it | User-session | Workspace, volume, Bluetooth, network, and power visibility is shared by every monitor and Settings. Absent or invalid state safely reads as all-on; atomic set/reset refuses unsafe or concurrent replacement. |
```

…and a new row in the appearance operations table:

```
| Panel widget visibility | One root `PanelSettingsModel.qml` and fixed `dwm-panel-settings` status/set/reset protocols over `panel-widgets.conf` | User-session | The former implicit all-on session state migrates without a write. All monitors, Control Center, and Settings consume the same values. Malformed or unsupported state is preserved and presented as safe all-on defaults until an explicit set/reset atomically repairs it; unsafe files are never replaced. |
```

**`CHANGELOG.md`** — under `## [Unreleased]` → `### Added`:

```markdown
- Persist workspace, volume, Bluetooth, network, and power panel visibility in
  one versioned user-owned state file shared by every monitor, Control Center,
  and Settings. An absent file migrates from the prior implicit all-on state;
  malformed, incomplete, unsafe, or unsupported state falls back all-on
  without preventing shell startup. Atomic set/reset actions preserve the file
  mode and refuse concurrent or unsafe replacements.
```

**`TASKS.md`** — tick the APPEARANCE-001 checkbox:

```diff
-- [ ] Move the existing in-memory panel-widget visibility controls onto shared,
+- [x] Move the existing in-memory panel-widget visibility controls onto shared,
   versioned user state with Settings integration, safe defaults, and migration
   that preserves the current Control Center behavior.
```

**`ROADMAP.md`** — refresh the Phase 5 status line (301).

---

## Verification

Run everything through `scripts/run-tests` (it enforces the safe temp root).

```bash
scripts/run-tests make check-quickshell-panel-settings
scripts/run-tests make check-quickshell-controlcenter check-quickshell-panel-menus
scripts/run-tests make check-quickshell-qml check-shell check-format
scripts/run-tests tests/test-shell-contracts.sh
scripts/run-tests env DWM_SETTINGS_POWER_CPU_SECONDS=0 tests/test-quickshell-settings-xvfb.sh
scripts/run-tests make check          # full suite before the commit lands
```

Helper contract by hand — no live session needed:

```bash
export XDG_CONFIG_HOME=$(mktemp -d) XDG_RUNTIME_DIR=$(mktemp -d)
scripts/dwm-panel-settings status                 # state defaults, five enabled
test ! -e "$XDG_CONFIG_HOME/lyona/panel-widgets.conf"   # migration writes nothing
scripts/dwm-panel-settings set volume disabled
scripts/dwm-panel-settings status                 # state available, volume disabled
printf 'garbage\n' > "$XDG_CONFIG_HOME/lyona/panel-widgets.conf"
scripts/dwm-panel-settings status                 # state partial, all-on, file preserved
scripts/dwm-panel-settings reset                  # repairs atomically
```

Live desktop — this is what `TASKS.md` actually asks for (persistence across a
fresh session, consistent on every monitor):

1. `scripts/dev-sync-install.sh` to install the exact tree, then a full LightDM
   logout/login.
2. Control Center → Bar Widgets → toggle Volume off. It disappears from the
   panel on **every** monitor at once, and `~/.config/lyona/panel-widgets.conf`
   gains `volume<TAB>disabled`.
3. Settings → Appearance → Panel widgets: the toggle reads back off. Flip it on
   there; the Control Center row follows.
4. Log out and back in — the choice survives.
5. "Show all widgets" restores all five.
6. `chmod 666` the state file and reopen Settings: expect the `unavailable`
   StatusCard, all-on defaults, inert toggles, and an unmodified file.
7. One `quickshell` process, no new watcher or poller (`pgrep -a quickshell`;
   idle CPU ≈ 0 over a 5 s sample).

Multi-monitor is the one item needing real hardware. Record it explicitly as
tested-or-not in the commit message, the way the `docs/P5-*` evidence files do.
