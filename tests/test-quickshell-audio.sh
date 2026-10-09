#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
model=$repo/config/quickshell/controls/ControlsModel.qml
pane=$repo/config/quickshell/settings/AudioSettingsPane.qml
settings=$repo/config/quickshell/settings/SettingsModel.qml
shell=$repo/config/quickshell/shell.qml

grep -Fq 'property int audioSourceGeneration: 0' "$model"
grep -Fq 'property int mutationGeneration: 0' "$model"
grep -Fq 'property int appliedMutationGeneration: 0' "$model"
grep -Fq 'root.actionProcessGeneration !== root.mutationGeneration' "$model"
grep -Fq 'property string mutationOrigin: ""' "$model"
grep -Fq 'interval: 3000' "$model"
grep -Fq 'repeat: false' "$model"
grep -Fq 'root.fallbackProcessGeneration === root.audioSourceGeneration' "$model"
# #279: the pactl watcher is a WatchedProcess (restarts back off), stopped when
# the native service takes over.
grep -Fq 'WatchedProcess {' "$model"
grep -Fq 'active: root.audioSourceKind === "fallback" && (root.visible || root.settingsVisible)' "$model"
grep -Fq 'fallbackWatch.stop();' "$model"
# Sync Sprint 16 R16-38: a burst of pactl lines is one snapshot once it settles,
# and a change during a snapshot is read again after it.
sed -n '/id: fallbackWatch$/,/^    }/p' "$model" | grep -Fq 'onSettled: {' ||
	fail 'the pactl watcher does not wait for a burst to settle'
sed -n '/stdout: SplitParser {/,/^        }/p' "$model" | grep -Fq 'root.refreshAudioInventory();' &&
	fail 'a pactl line still refreshes at once'
grep -Fq 'root.audioRefreshPending = true;' "$model"
[ "$(grep -Fc 'Commands.controlsHelperCommand("audio-watch")' "$model")" -eq 1 ]
if grep -Fq 'repeat: true' "$model"; then
	exit 1
fi
grep -Fq 'function parseAudioSnapshot(text)' "$model"
grep -Fq 'fields[3] !== "yes" && fields[3] !== "no"' "$model"
grep -Fq 'fields[4] !== "yes" && fields[4] !== "no"' "$model"
grep -Fq 'function inputSetDefault(name, origin)' "$model"
grep -Fq 'function streamVolumeSet(index, percent, origin)' "$model"
grep -Fq 'property var controlsModel: null' "$settings"
grep -Fq 'root.controlsModel.openSettings()' "$settings"
grep -Fq 'root.controlsModel.closeSettings()' "$settings"
grep -Fq 'controlsModel: controlsModel' "$shell"
grep -Fq 'root.controlsModel.inputSetDefault' "$pane"
grep -Fq 'root.controlsModel.inputToggleMute' "$pane"
grep -Fq 'root.controlsModel.streamVolumeSet' "$pane"
grep -Fq 'root.controlsModel.streamToggleMute' "$pane"

printf 'Quickshell audio provider and Settings contract: PASS\n'
