import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

/*
 * #286: one `dwm-system-management watch-domains` process for every Settings >
 * System domain, where each SystemProviderDiscovery used to start its own
 * watch-* process (about 30 MB of Python and GLib each, eight with the pane
 * open). Each discovery still owns a monitor object with the same lifecycle;
 * the object attaches here instead of running a process.
 *
 * The process runs while any monitor is attached, and stops when the last one
 * goes, so nothing runs while the pane is closed. A domain is subscribed with
 * "start DOMAIN" on stdin; its records come back as "DOMAIN<TAB>record", the
 * lines its watch-* command printed, and "DOMAIN<TAB>stopped<TAB>CODE" ends it
 * alone. A monitor attaching to a domain that is already subscribed and ready
 * is ready at once: that subscription has been live since before it attached,
 * so a read it starts now misses nothing. A domain that failed is retired with
 * "stop DOMAIN" once its last monitor goes, so a retry gets a fresh
 * subscription rather than the stale one; it is started again only after its
 * "stopped" reply, and the other domains carry on.
 */
Scope {
    id: root

    property var clients: []
    // Domains subscribed in the running process, and the ready record each
    // gave (empty until then); domains waiting for the process to start.
    property var subscribed: ({})
    property var readyRecord: ({})
    property var queued: []
    // Domains asked to stop, waiting for their "stopped" reply.
    property var retiring: ({})
    property bool started: false
    // Asked to stop: anything attaching now waits for a fresh process.
    property bool stopping: false

    function attach(client) {
        root.clients = root.clients.concat([client]);
        const domain = client.domain;
        // Started again once the old subscription has gone.
        if (root.started && !root.stopping && root.retiring[domain] === true) return;
        if (root.started && !root.stopping && root.subscribed[domain] === true) {
            const ready = root.readyRecord[domain] || "";
            if (ready.length > 0) Qt.callLater(function() { client.deliver(ready); });
            return;
        }
        if (root.started && !root.stopping) {
            root.subscribed[domain] = true;
            root.readyRecord[domain] = "";
            process.write("start " + domain + "\n");
            return;
        }
        if (root.queued.indexOf(domain) < 0) root.queued = root.queued.concat([domain]);
        if (!process.running) process.running = true;
    }

    // retire: the monitor failed, so its domain's subscription is not reused.
    function detach(client, retire) {
        root.clients = root.clients.filter(other => other !== client);
        if (root.clients.length === 0 && process.running && !root.stopping) {
            root.stopping = true;
            root.queued = [];
            process.signal(15);
            return;
        }
        const domain = client.domain;
        if (retire === true && root.started && !root.stopping && root.subscribed[domain] === true
                && !root.clients.some(other => other.domain === domain)) {
            root.subscribed[domain] = false;
            root.readyRecord[domain] = "";
            root.retiring[domain] = true;
            process.write("stop " + domain + "\n");
        }
    }

    function route(line) {
        const tab = line.indexOf("\t");
        if (tab <= 0 || root.stopping) return;
        const domain = line.slice(0, tab);
        const record = line.slice(tab + 1);
        const targets = root.clients.filter(client => client.domain === domain);
        if (record.indexOf("stopped\t") === 0 && root.retiring[domain] === true) {
            // The reply to "stop": start afresh for whoever attached since.
            delete root.retiring[domain];
            if (targets.length > 0) {
                root.subscribed[domain] = true;
                root.readyRecord[domain] = "";
                process.write("start " + domain + "\n");
            }
            return;
        }
        if (record.indexOf("stopped\t") === 0) {
            root.subscribed[domain] = false;
            root.readyRecord[domain] = "";
            root.clients = root.clients.filter(client => client.domain !== domain);
            for (const client of targets) client.ended();
            return;
        }
        if (record === "mount-monitor-ready" || /\tready$/.test(record)) root.readyRecord[domain] = record;
        for (const client of targets) client.deliver(record);
    }

    Process {
        id: process

        // Not checkedCommand: it would hold every line until the exit.
        command: Commands.watchCommand(Commands.systemManagementCommand("watch-domains", []))
        stdinEnabled: true
        running: false
        stdout: SplitParser { onRead: line => root.route(line) }
        onStarted: {
            root.started = true;
            root.stopping = false;
            root.retiring = ({});
            const domains = root.queued;
            root.queued = [];
            for (const domain of domains) {
                root.subscribed[domain] = true;
                root.readyRecord[domain] = "";
                process.write("start " + domain + "\n");
            }
        }
        onRunningChanged: if (!running) {
            const wasStopping = root.stopping;
            root.started = false;
            root.stopping = false;
            root.subscribed = ({});
            root.readyRecord = ({});
            root.retiring = ({});
            if (root.clients.length === 0) {
                root.queued = [];
                return;
            }
            if (wasStopping) {
                // Attached while the last process was stopping: start afresh.
                const domains = [];
                for (const client of root.clients) {
                    if (domains.indexOf(client.domain) < 0) domains.push(client.domain);
                }
                root.queued = domains;
                process.running = true;
                return;
            }
            // It ended on its own: every attached monitor has ended with it.
            const attached = root.clients;
            root.clients = [];
            root.queued = [];
            for (const client of attached) client.ended();
        }
    }
}
