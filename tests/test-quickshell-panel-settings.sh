#!/usr/bin/env bash
# Covers scripts/dwm-panel-settings and its Quickshell consumer,
# config/quickshell/panel/PanelSettingsModel.qml: the shared, versioned state
# behind panel widget visibility (workspaces, volume, Bluetooth, network,
# power), which every monitor's DwmPanel, the Control Center, and Settings
# read from one place instead of five in-memory booleans.

set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

helper=$repo/scripts/dwm-panel-settings
assert_executable "$helper"

model=$repo/config/quickshell/panel/PanelSettingsModel.qml
shell=$repo/config/quickshell/shell.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
control_model=$repo/config/quickshell/controlcenter/ControlCenterModel.qml
control_window=$repo/config/quickshell/controlcenter/ControlCenterWindow.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
appearance_pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml
commands=$repo/config/quickshell/core/Commands.qml

home=$work/home
config=$work/config
runtime=$work/runtime
mkdir -p "$home" "$config" "$runtime"

state_file=$config/lyona/panel-widgets.conf

run_helper() {
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" "$helper" "$@"
}

# Poll for a readiness file rather than sleeping a fixed interval — the
# helper's test seams (DWM_TEST_PANEL_*_READY/_RELEASE) exist precisely so
# these races don't need a guessed sleep.
wait_for() {
	local path=$1 attempt=0
	while [ ! -e "$path" ]; do
		attempt=$((attempt + 1))
		if [ "$attempt" -ge 200 ]; then
			fail "timed out waiting for $path"
		fi
		sleep 0.01
	done
}

# ── status with nothing configured: the migration writes nothing ────────

status=$(run_helper status)
assert_string_contains "$status" $'panel-settings-protocol\t1\t0'
assert_string_contains "$status" \
	$'state\tdefaults\tUsing safe all-on defaults; the first change creates persistent state'
for widget in workspaces volume bluetooth network power; do
	assert_string_contains "$status" "widget	$widget	enabled"
done
assert_string_contains "$status" $'complete\tstatus'
assert_no_file "$state_file" 'status alone must not create persistent state'

# ── the runtime lock actually excludes a concurrent operation ───────────

lock_ready=$work/lock.ready
lock_release=$work/lock.release
(
	exec 8>"$runtime/dwm-panel-settings.lock"
	flock 8
	: >"$lock_ready"
	while [ ! -e "$lock_release" ]; do
		sleep 0.01
	done
) &
lock_holder_pid=$!
wait_for "$lock_ready"
set +e
HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	timeout 7 "$helper" reset >"$work/lock.out" 2>"$work/lock.err"
lock_status=$?
set -e
: >"$lock_release"
wait "$lock_holder_pid"
assert_equals 1 "$lock_status" 'reset under a held lock should time out, not silently proceed'
assert_line "$work/lock.err" 'dwm-panel-settings: another panel settings operation is still running'

# ── set persists, with the exact mode preserved ──────────────────────────

set_result=$(run_helper set volume disabled)
assert_string_contains "$set_result" $'result\tset\tvolume\tdisabled' 'set did not confirm the change'
assert_equals 600 "$(stat -c %a "$state_file")" 'a freshly created state file must be mode 600'
assert_line "$state_file" $'panel-settings-protocol\t1\t0'
assert_line "$state_file" $'volume\tdisabled'

persisted=$(run_helper status)
assert_string_contains "$persisted" $'widget\tvolume\tdisabled'
assert_string_contains "$persisted" \
	$'state\tavailable\tPersistent panel visibility is active for every monitor'

# ── writes preserve whatever mode the file already had ───────────────────

chmod 640 "$state_file"
run_helper set network disabled >/dev/null
assert_equals 640 "$(stat -c %a "$state_file")" 'set must preserve the existing file mode'
assert_line "$state_file" $'volume\tdisabled'
assert_line "$state_file" $'network\tdisabled'

# ── a group/other-writable state file is refused, not repaired ──────────

chmod 666 "$state_file"
unsafe_mode=$(run_helper status)
assert_string_contains "$unsafe_mode" \
	$'state\tunavailable\tPersistent panel state is unsafe; using all-on defaults'
if run_helper set network enabled >"$work/unsafe-mode.out" 2>"$work/unsafe-mode.err"; then
	fail 'set accepted a writable-by-others state file'
fi
assert_equals 666 "$(stat -c %a "$state_file")" 'refusing the file must not touch it'
chmod 640 "$state_file"

# ── an unsupported protocol version is preserved, not silently upgraded ─

printf 'panel-settings-protocol\t2\t0\nvolume\tdisabled\n' >"$state_file"
future=$(run_helper status)
assert_string_contains "$future" \
	$'state\tpartial\tUnsupported panel settings version was preserved; using all-on defaults'
for widget in workspaces volume bluetooth network power; do
	assert_string_contains "$future" "widget	$widget	enabled"
done
assert_line "$state_file" $'panel-settings-protocol\t2\t0'

# ── a malformed file is preserved verbatim, not rewritten ───────────────

printf 'broken\n' >"$state_file"
malformed=$(run_helper status)
assert_string_contains "$malformed" \
	$'state\tpartial\tMalformed panel settings were preserved; using all-on defaults'
assert_line "$state_file" 'broken'

for malformed_record in "volume		disabled" "	volume	disabled" "volume	disabled	"; do
	{
		printf 'panel-settings-protocol\t1\t0\n'
		printf 'workspaces\tenabled\n%s\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\n' \
			"$malformed_record"
	} >"$state_file"
	malformed=$(run_helper status)
	assert_string_contains "$malformed" \
		$'state\tpartial\tMalformed panel settings were preserved; using all-on defaults'
	for widget in workspaces volume bluetooth network power; do
		assert_string_contains "$malformed" "widget	$widget	enabled"
	done
done

# ── an explicit set atomically repairs a malformed file ──────────────────

run_helper set power disabled >/dev/null
assert_line "$state_file" $'power\tdisabled'
for widget in workspaces volume bluetooth network; do
	assert_line "$state_file" "$widget	enabled"
done

# ── a single concurrent edit between staging and publish is refused ─────

publish_ready=$work/publish.ready
publish_release=$work/publish.release
DWM_TEST_PANEL_PUBLISH_READY=$publish_ready DWM_TEST_PANEL_PUBLISH_RELEASE=$publish_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set bluetooth disabled >"$work/race.out" 2>"$work/race.err" &
race_pid=$!
wait_for "$publish_ready"
printf 'external edit\n' >"$state_file"
: >"$publish_release"
if wait "$race_pid"; then
	fail 'a transaction overwrote a concurrent edit made before publish'
fi
assert_contains "$work/race.err" 'panel state changed during the transaction'
assert_line "$state_file" 'external edit'

# ── the same race, but the edit lands at the exchange itself ────────────

run_helper reset >/dev/null

exchange_ready=$work/exchange.ready
exchange_release=$work/exchange.release
DWM_TEST_PANEL_EXCHANGE_READY=$exchange_ready DWM_TEST_PANEL_EXCHANGE_RELEASE=$exchange_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set bluetooth disabled >"$work/exchange-race.out" 2>"$work/exchange-race.err" &
exchange_race_pid=$!
wait_for "$exchange_ready"
printf 'last-moment external edit\n' >"$state_file"
: >"$exchange_release"
if wait "$exchange_race_pid"; then
	fail 'an exchange overwrote a last-moment concurrent edit'
fi
assert_contains "$work/exchange-race.err" 'panel state changed during the transaction'
assert_line "$state_file" 'last-moment external edit'

# ── two edits in a row exhaust the retry budget without ever clobbering ─

run_helper reset >/dev/null

exchange_ready=$work/two-edit-exchange.ready
exchange_release=$work/two-edit-exchange.release
rollback_ready=$work/two-edit-rollback.ready
rollback_release=$work/two-edit-rollback.release
DWM_TEST_PANEL_EXCHANGE_READY=$exchange_ready DWM_TEST_PANEL_EXCHANGE_RELEASE=$exchange_release \
	DWM_TEST_PANEL_ROLLBACK_READY=$rollback_ready DWM_TEST_PANEL_ROLLBACK_RELEASE=$rollback_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set bluetooth disabled >"$work/two-edit-race.out" 2>"$work/two-edit-race.err" &
two_edit_race_pid=$!
wait_for "$exchange_ready"
printf 'first last-moment edit\n' >"$state_file"
: >"$exchange_release"
wait_for "$rollback_ready"
printf 'second last-moment edit\n' >"$state_file"
: >"$rollback_release"
if wait "$two_edit_race_pid"; then
	fail 'exchange retries overwrote a two-edit race'
fi
assert_contains "$work/two-edit-race.err" 'panel state changed during the transaction'
assert_line "$state_file" 'second last-moment edit'

# ── a symlink dropped in mid-transaction is never exchanged away ────────

run_helper reset >/dev/null

unsafe_target=$work/exchange-symlink-target
printf 'unsafe replacement target\n' >"$unsafe_target"
exchange_ready=$work/symlink-exchange.ready
exchange_release=$work/symlink-exchange.release
DWM_TEST_PANEL_EXCHANGE_READY=$exchange_ready DWM_TEST_PANEL_EXCHANGE_RELEASE=$exchange_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set bluetooth disabled >"$work/symlink-race.out" 2>"$work/symlink-race.err" &
symlink_race_pid=$!
wait_for "$exchange_ready"
mv "$state_file" "$work/pre-symlink-state"
ln -s "$unsafe_target" "$state_file"
: >"$exchange_release"
if wait "$symlink_race_pid"; then
	fail 'an exchange replaced a concurrent symlink'
fi
assert_contains "$work/symlink-race.err" 'panel state changed during the transaction'
[ -L "$state_file" ] || fail 'the concurrently planted symlink should still be in place'
assert_equals "$unsafe_target" "$(readlink "$state_file")" \
	'the symlink must still point at the attacker-controlled target'

unlink "$state_file"
mv "$work/pre-symlink-state" "$state_file"
run_helper reset >/dev/null

# ── an edit made before the baseline is even read is still caught ───────

baseline_ready=$work/baseline.ready
baseline_release=$work/baseline.release
DWM_TEST_PANEL_BASELINE_READY=$baseline_ready DWM_TEST_PANEL_BASELINE_RELEASE=$baseline_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set network disabled >"$work/baseline-race.out" 2>"$work/baseline-race.err" &
baseline_race_pid=$!
wait_for "$baseline_ready"
sed -i 's/^power	enabled$/power	disabled/' "$state_file"
: >"$baseline_release"
if wait "$baseline_race_pid"; then
	fail 'a transaction overwrote an edit made before the baseline was captured'
fi
assert_contains "$work/baseline-race.err" 'panel state changed during the transaction'
assert_line "$state_file" $'network\tenabled'
assert_line "$state_file" $'power\tdisabled'

# ── a symlinked state file is refused outright, not followed ────────────

mv "$state_file" "$work/real-state"
ln -s "$work/real-state" "$state_file"
unsafe=$(run_helper status)
assert_string_contains "$unsafe" \
	$'state\tunavailable\tPersistent panel state is unsafe; using all-on defaults'
if run_helper set volume disabled >"$work/unsafe.out" 2>"$work/unsafe.err"; then
	fail 'set accepted a symlinked state file'
fi
[ -L "$state_file" ] || fail 'the symlink must be left exactly as found'

# ── an unsafe config directory is refused (symlink and world-writable) ──

unsafe_config=$work/unsafe-config
unsafe_dir_target=$work/unsafe-dir-target
mkdir -p "$unsafe_config" "$unsafe_dir_target"
ln -s "$unsafe_dir_target" "$unsafe_config/lyona"
unsafe_dir_status=$(HOME="$home" XDG_CONFIG_HOME="$unsafe_config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" status)
assert_string_contains "$unsafe_dir_status" \
	$'state\tunavailable\tPersistent panel state directory is unsafe; using all-on defaults'

writable_config=$work/writable-config
mkdir -p "$writable_config/lyona"
chmod 777 "$writable_config/lyona"
writable_dir_status=$(HOME="$home" XDG_CONFIG_HOME="$writable_config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" status)
assert_string_contains "$writable_dir_status" \
	$'state\tunavailable\tPersistent panel state directory is unsafe; using all-on defaults'
if HOME="$home" XDG_CONFIG_HOME="$writable_config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set volume disabled >"$work/writable-dir.out" 2>"$work/writable-dir.err"; then
	fail 'set accepted a world-writable state directory'
fi
assert_no_file "$writable_config/lyona/panel-widgets.conf"

# ── static QML/shell wiring guards ───────────────────────────────────────
#
# Cheap regression guards for the wiring itself, not the helper's behaviour:
# a single shared model instance, no leftover per-widget booleans, and every
# consumer reading from the one model rather than its own copy.

assert_contains "$commands" 'function panelSettingsCommand(action, args)'
assert_contains "$helper" 'readonly max_restore_attempts=8'
assert_contains "$helper" 'while ((attempt < max_restore_attempts)); do'
assert_contains "$helper" 'Give that edit one final guarded'
assert_contains "$helper" "current_fingerprint == \"\$expected_fingerprint\""

assert_contains "$model" 'panel-settings-protocol\t1\t0'
assert_contains "$model" 'Component.onCompleted: root.refresh()'
assert_contains "$model" 'watchChanges: true'
assert_contains "$model" 'property bool refreshPending: false'
assert_contains "$model" 'property bool mutationRefreshPending: false'
assert_contains "$model" 'root.mutationRefreshPending = true;'
assert_contains "$model" '} else if (root.mutationRefreshPending) {'
assert_contains "$model" 'function useDefaults()'
assert_contains "$model" 'root.useDefaults();'
assert_contains "$model" 'configuredConfigHome.startsWith("/")'
assert_contains "$model" 'readonly property bool mutationReady:'

assert_contains "$shell" 'PanelSettingsModel {'
assert_equals 1 "$(grep -Fc 'PanelSettingsModel {' "$shell")" \
	'PanelSettingsModel must be instantiated exactly once'
assert_contains "$shell" 'panelSettingsModel: panelSettingsModel'
assert_contains "$shell" 'function panelWidgetEnabled(widget: string): bool'
assert_contains "$shell" 'function panelWidgetSet(widget: string, enabled: bool): void'

assert_contains "$panel" 'required property var panelSettingsModel'
for widget in workspaces volume bluetooth network power; do
	assert_contains "$panel" "root.panelSettingsModel.widgetEnabled(\"$widget\")"
done

assert_contains "$control_model" 'property var panelSettingsModel: null'
assert_contains "$control_model" 'readonly property var widgetIds:'
assert_contains "$control_model" '"Volume": "volume"'
assert_equals 2 "$(grep -Fc 'const id = root.widgetIds[name];' "$control_model")" \
	'widgetEnabled and toggleWidget should each resolve the id the same way'
assert_contains "$control_model" 'root.panelSettingsModel.widgetEnabled(id)'
assert_contains "$control_model" 'root.panelSettingsModel.toggleWidget(id)'

assert_contains "$control_window" 'enabled: !root.controlCenterModel.panelSettingsModel'
assert_contains "$control_window" 'function pageMessage()'
assert_contains "$control_window" 'return panelModel.providerDetail;'
assert_contains "$control_window" 'if (panelModel.message.length > 0 && !panelModel.actionSucceeded)'
provider_detail_line=$(grep -nF 'return panelModel.providerDetail;' "$control_window" |
	cut -d: -f1 | head -1)
action_message_line=$(grep -nF 'if (panelModel.message.length > 0) return panelModel.message;' \
	"$control_window" | cut -d: -f1 | head -1)
[ "$provider_detail_line" -lt "$action_message_line" ] ||
	fail 'the unhealthy-provider detail must be checked before the leftover action message'

assert_contains "$settings_window" 'required property var panelSettingsModel'
assert_equals 2 "$(grep -Fc 'root.panelSettingsModel.refresh();' "$settings_model")" \
	'the appearance section must refresh the panel model on both activation and periodic refresh'
assert_contains "$appearance_pane" 'required property var panelSettingsModel'
assert_contains "$appearance_pane" 'SectionLabel { label: "Panel widgets" }'
assert_contains "$appearance_pane" 'root.panelSettingsModel.providerState !== "available"'
assert_contains "$appearance_pane" '&& !root.panelSettingsModel.actionSucceeded'
assert_contains "$appearance_pane" \
	'onToggled: root.panelSettingsModel.toggleWidget(panelWidgetRow.modelData.id)'

printf 'Quickshell panel settings persistence: PASS\n'
