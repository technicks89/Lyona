import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.core
import "../core/Protocol.js" as Protocol

Scope {
    id: root

    readonly property bool initialLoading: audioSnapshotProcess.running || volumeStatusProcess.running
        || micStatusProcess.running

    property bool visible: false
    property bool settingsVisible: false
    property bool busy: false
    property string volumeText: "VOL unavailable"
    property int volumePercent: 0
    property bool volumeMuted: false
    property string volumeDisplayText: volumeText + (outputDeviceDescription.length > 0 ? " - " + outputDeviceDescription : "")
    property var outputDevices: []
    property var inputDevices: []
    property var audioStreams: []
    property string outputDeviceName: ""
    property string outputDeviceDescription: ""
    property string micText: "MIC unavailable"
    // Media from Quickshell's MPRIS service, which follows the players over
    // D-Bus (#285): no resident playerctl --follow. The player shown is the
    // first one playing, else the first one, and the buttons act on it.
    readonly property var mediaSource: {
        const players = Mpris.players.values;
        for (const player of players) {
            if (player.isPlaying) return player;
        }
        return players.length > 0 ? players[0] : null;
    }
    readonly property string mediaPlayer: root.mediaSource ? root.playerName(root.mediaSource) : ""
    readonly property string mediaState: !root.mediaSource ? ""
        : root.mediaSource.playbackState === MprisPlaybackState.Playing ? "Playing"
        : root.mediaSource.playbackState === MprisPlaybackState.Paused ? "Paused" : "Stopped"
    readonly property string mediaArtist: root.mediaSource ? (root.mediaSource.trackArtist || "") : ""
    readonly property string mediaTitle: root.mediaSource ? (root.mediaSource.trackTitle || "") : ""
    readonly property string mediaText: {
        if (!root.mediaSource) return "MEDIA none";
        const label = [root.mediaPlayer, root.mediaState].filter(part => part.length > 0);
        const title = [root.mediaArtist, root.mediaTitle].filter(part => part.length > 0);
        return (label.length > 0 ? label.join(" ") : "MEDIA")
            + (title.length > 0 ? ": " + title.join(" - ") : "");
    }
    // From BluetoothModel, which already follows the adapter, rather than a
    // read of its own (#288).
    property var bluetoothModel: null
    readonly property string bluetoothText: root.bluetoothModel ? root.bluetoothModel.statusText : "BT unavailable"
    property string message: ""
    property string audioProviderState: "idle"
    property string audioProviderDetail: ""
    property string audioSourceKind: "none"
    property int audioSourceGeneration: 0
    property int fallbackProcessGeneration: 0
    // A refresh asked for while a snapshot was running (Sync Sprint 16 R16-38).
    property bool audioRefreshPending: false
    property int mutationGeneration: 0
    property int appliedMutationGeneration: 0
    property int actionProcessGeneration: 0
    property string mutationOrigin: ""
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource

    function nativeAudioReady() {
        return root.audioSink !== null && root.audioSink.ready && root.audioSink.audio !== null;
    }

    function selectAudioSource() {
        if (root.nativeAudioReady()) {
            nativeGraceTimer.stop();
            fallbackWatch.stop();
            if (root.audioSourceKind !== "native") {
                root.audioSourceGeneration++;
                root.audioSourceKind = "native";
            }
        } else if ((root.visible || root.settingsVisible) && root.audioSourceKind === "fallback") {
            // Reopened while on the fallback: closing stopped its watcher.
            fallbackWatch.start();
        } else if ((root.visible || root.settingsVisible) && !nativeGraceTimer.running) {
            nativeGraceTimer.restart();
        }
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refresh();
        root.selectAudioSource();
    }

    function closeSettings() {
        root.settingsVisible = false;
        if (!root.visible) fallbackWatch.stop();
        if (!root.visible) nativeGraceTimer.stop();
    }

    function refreshAudioStatus() {
        const sink = root.audioSink;

        if (sink !== null && sink.ready && sink.audio !== null) {
            root.volumePercent = root.clampPercent(sink.audio.volume * 100);
            root.volumeMuted = sink.audio.muted;
            root.volumeText = (root.volumeMuted ? "VOL muted " : "VOL ") + root.volumePercent.toString() + "%";
            root.outputDeviceName = sink.name;
            root.outputDeviceDescription = sink.description.length > 0 ? sink.description : sink.name;
        } else {
            root.volumeText = "VOL unavailable";
            root.volumeMuted = false;
            root.outputDeviceName = "";
            root.outputDeviceDescription = "";
            if (!volumeStatusProcess.running) {
                volumeStatusProcess.running = true;
            }
        }
        root.selectAudioSource();

        const source = root.audioSource;
        if (source !== null && source.ready && source.audio !== null) {
            root.micText = source.audio.muted ? "MIC muted" : "MIC on";
        } else {
            root.micText = "MIC unavailable";
            if (!micStatusProcess.running) {
                micStatusProcess.running = true;
            }
        }
    }

    function open() {
        root.visible = true;
        root.refresh();
        root.selectAudioSource();
    }

    function close() {
        root.visible = false;
        root.message = "";
        if (!root.settingsVisible) fallbackWatch.stop();
        if (!root.settingsVisible) nativeGraceTimer.stop();
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh() {
        root.refreshAudioStatus();
        root.refreshAudioInventory();
    }

    function refreshAudioInventory() {
        if (audioSnapshotProcess.running) {
            // Read again when this one ends: it may have missed the change.
            root.audioRefreshPending = true;
            return;
        }
        audioSnapshotProcess.running = true;
    }

    function parseAudioSnapshot(text) {
        const outputs = [];
        const inputs = [];
        const streams = [];
        let protocolValid = false;
        let providerSeen = false;
        let malformed = false;
        let defaultOutput = null;
        let defaultInput = null;
        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "audio-protocol") {
                protocolValid = Protocol.validHeader(fields, 1);
            } else if (fields[0] === "provider") {
                if (fields.length < 5 || fields[1] !== "audio") { malformed = true; continue; }
                providerSeen = true;
                root.audioProviderState = fields[2];
                root.audioProviderDetail = fields[4];
            } else if (fields[0] === "audio-output" && fields.length >= 6) {
                const percent = Number(fields[5]);
                if ((fields[3] !== "yes" && fields[3] !== "no")
                        || (fields[4] !== "yes" && fields[4] !== "no")
                        || !isFinite(percent) || percent < 0 || percent > 100) {
                    malformed = true;
                    continue;
                }
                const item = { "name": fields[1], "description": fields[2], "isDefault": fields[3] === "yes",
                    "muted": fields[4] === "yes", "volume": Math.round(percent) };
                outputs.push(item);
                if (item.isDefault) defaultOutput = item;
            } else if (fields[0] === "audio-input" && fields.length >= 6) {
                const percent = Number(fields[5]);
                if ((fields[3] !== "yes" && fields[3] !== "no")
                        || (fields[4] !== "yes" && fields[4] !== "no")
                        || !isFinite(percent) || percent < 0 || percent > 100) {
                    malformed = true;
                    continue;
                }
                const item = { "name": fields[1], "description": fields[2], "isDefault": fields[3] === "yes",
                    "muted": fields[4] === "yes", "volume": Math.round(percent) };
                inputs.push(item);
                if (item.isDefault) defaultInput = item;
            } else if (fields[0] === "audio-stream" && fields.length >= 6) {
                const percent = Number(fields[5]);
                if ((fields[4] !== "yes" && fields[4] !== "no")
                        || !isFinite(percent) || percent < 0 || percent > 100) {
                    malformed = true;
                    continue;
                }
                streams.push({ "index": fields[1], "application": fields[2], "description": fields[3],
                    "muted": fields[4] === "yes", "volume": Math.round(percent) });
            }
        }
        if (!protocolValid || !providerSeen || malformed) {
            root.outputDevices = [];
            root.inputDevices = [];
            root.audioStreams = [];
            root.audioProviderState = "failure";
            root.audioProviderDetail = !protocolValid ? "Unsupported audio protocol" : "Malformed audio provider record";
            return;
        }
        root.outputDevices = outputs;
        root.inputDevices = inputs;
        root.audioStreams = streams;
        if (defaultOutput !== null && root.audioSourceKind === "fallback") {
            root.volumePercent = defaultOutput.volume;
            root.volumeMuted = defaultOutput.muted;
            root.volumeText = (defaultOutput.muted ? "VOL muted " : "VOL ") + defaultOutput.volume + "%";
            root.outputDeviceName = defaultOutput.name;
            root.outputDeviceDescription = defaultOutput.description;
        }
        if (defaultInput !== null && root.audioSourceKind === "fallback") {
            root.micText = defaultInput.muted ? "MIC muted" : "MIC on";
        }
    }

    // The player's name as playerctl gave it: its bus name, without the
    // MPRIS prefix or a per-instance suffix ("firefox", not "firefox.instance_1").
    function playerName(player) {
        const name = String(player.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "");
        return name.replace(/\.instance[_0-9]*$/, "") || String(player.identity || "");
    }

    function parseVolume(text) {
        const trimmed = text.trim();

        if (trimmed.length > 0) {
            root.volumeText = trimmed;
        }

        const match = trimmed.match(/([0-9]+)%/);
        if (match !== null) {
            root.volumePercent = root.clampPercent(parseInt(match[1], 10));
        }
        root.volumeMuted = trimmed.indexOf("VOL muted") === 0;
    }

    function parseOutputDevices(text) {
        const devices = [];
        const lines = text.trim().split("\n");
        let defaultName = "";
        let defaultDescription = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();

            if (line.length === 0 || line === "OUTPUT unavailable") {
                continue;
            }

            const fields = line.split("\t");
            const name = fields.length > 0 ? fields[0] : "";

            if (name.length === 0) {
                continue;
            }

            const description = fields.length > 1 && fields[1].length > 0 ? fields[1] : name;
            const isDefault = fields.length > 2 && fields[2] === "1";

            devices.push({ "name": name, "description": description, "isDefault": isDefault });
            if (isDefault) {
                defaultName = name;
                defaultDescription = description;
            }
        }

        root.outputDevices = devices;
        root.outputDeviceName = defaultName;
        root.outputDeviceDescription = defaultDescription;
    }

    function clampPercent(value) {
        const number = Math.round(Number(value));

        if (isNaN(number)) {
            return root.volumePercent;
        }

        return Math.max(0, Math.min(100, number));
    }

    function runAction(action, args, origin) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.mutationGeneration++;
        root.actionProcessGeneration = root.mutationGeneration;
        root.mutationOrigin = origin || "panel";
        root.message = "";
        actionProcess.command = Commands.controlsHelperCommand(action, args || []);
        actionProcess.running = true;
    }

    function volumeUp() {
        root.runAction("volume-up", ["5%"]);
    }

    function volumeDown() {
        root.runAction("volume-down", ["5%"]);
    }

    function volumeToggleMute() {
        root.runAction("volume-toggle-mute");
    }

    function volumeSet(percent) {
        root.runAction("volume-set", [root.clampPercent(percent).toString() + "%"]);
    }

    function outputSetDefault(name, origin) {
        if (name.length === 0 || name === root.outputDeviceName) {
            return;
        }

        root.runAction("output-set-default", [name], origin);
    }

    function inputSetDefault(name, origin) { root.runAction("input-set-default", [name], origin); }
    function inputVolumeSet(name, percent, origin) {
        root.runAction("input-volume-set", [name, root.clampPercent(percent).toString() + "%"], origin);
    }
    function inputToggleMute(name, origin) { root.runAction("input-toggle-mute", [name], origin); }
    function streamVolumeSet(index, percent, origin) {
        root.runAction("stream-volume-set", [index, root.clampPercent(percent).toString() + "%"], origin);
    }
    function streamToggleMute(index, origin) { root.runAction("stream-toggle-mute", [index], origin); }

    function mediaPlayPause() {
        if (root.mediaSource && root.mediaSource.canTogglePlaying) root.mediaSource.togglePlaying();
    }

    function mediaNext() {
        if (root.mediaSource && root.mediaSource.canGoNext) root.mediaSource.next();
    }

    function mediaPrevious() {
        if (root.mediaSource && root.mediaSource.canGoPrevious) root.mediaSource.previous();
    }

    PwObjectTracker {
        objects: [root.audioSink, root.audioSource]
    }

    Connections {
        target: Pipewire

        function onDefaultAudioSinkChanged() {
            root.refreshAudioStatus();
            root.refreshAudioInventory();
        }

        function onDefaultAudioSourceChanged() {
            root.refreshAudioStatus();
        }

        function onReadyChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: Pipewire.nodes

        function onObjectInsertedPost(object, index) {
            if (root.visible || root.settingsVisible) {
                root.refreshAudioInventory();
            }
        }

        function onObjectRemovedPost(object, index) {
            if (root.visible || root.settingsVisible) {
                root.refreshAudioInventory();
            }
        }
    }

    Connections {
        target: root.audioSink

        function onReadyChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: root.audioSink !== null ? root.audioSink.audio : null

        function onMutedChanged() {
            root.refreshAudioStatus();
        }

        function onVolumesChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: root.audioSource

        function onReadyChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: root.audioSource !== null ? root.audioSource.audio : null

        function onMutedChanged() {
            root.refreshAudioStatus();
        }
    }

    Timer {
        id: nativeGraceTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.nativeAudioReady() && (root.visible || root.settingsVisible)) {
                root.audioSourceGeneration++;
                root.audioSourceKind = "fallback";
                root.fallbackProcessGeneration = root.audioSourceGeneration;
                root.refreshAudioInventory();
                fallbackWatch.start();
            }
        }
    }

    Process {
        id: audioSnapshotProcess
        command: Commands.controlsHelperCommand("audio-snapshot")
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseAudioSnapshot(this.text) }
        onRunningChanged: {
            if (!running && root.audioRefreshPending) {
                root.audioRefreshPending = false;
                // After this exit has finished, not from inside it.
                Qt.callLater(root.refreshAudioInventory);
            }
        }
    }

    // pactl's watcher, while the native PipeWire service is unavailable. It
    // prints several lines for one change: one snapshot once they settle (Sync
    // Sprint 16 R16-38). A restart backs off as every watcher's does (#279),
    // where this one used to retry every 3 s. Each start is tagged with the
    // audio source generation, which its snapshots are checked against.
    WatchedProcess {
        id: fallbackWatch
        command: Commands.watchCommand(Commands.controlsHelperCommand("audio-watch"))
        active: root.audioSourceKind === "fallback" && (root.visible || root.settingsVisible)
        onSettled: {
            if (root.audioSourceKind === "fallback"
                    && root.fallbackProcessGeneration === root.audioSourceGeneration)
                root.refreshAudioInventory();
        }
    }

    Process {
        id: volumeStatusProcess

        command: Commands.controlsHelperCommand("volume-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const sink = root.audioSink;
                if (sink === null || !sink.ready || sink.audio === null) {
                    root.parseVolume(this.text.length > 0 ? this.text : "VOL unavailable");
                }
            }
        }
    }

    Process {
        id: micStatusProcess

        command: Commands.controlsHelperCommand("mic-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const source = root.audioSource;
                if (source === null || !source.ready || source.audio === null) {
                    const text = this.text.trim();
                    root.micText = text.length > 0 ? text : "MIC unavailable";
                }
            }
        }
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running) {
                if (root.actionProcessGeneration !== root.mutationGeneration) return;
                root.busy = false;
                root.appliedMutationGeneration = root.mutationGeneration;
                root.refresh();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0 && root.actionProcessGeneration === root.mutationGeneration) {
                    root.message = error;
                }
            }
        }
    }

    Component.onCompleted: root.refreshAudioStatus()
}
