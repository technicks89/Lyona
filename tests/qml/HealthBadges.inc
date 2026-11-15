    // Runs inside an isolated copy of the production ShellRoot (#500): the
    // System Health tabs' warning and error count badges, against the real
    // model and window, with every helper replaced by `true`.
    property int badgeStage: 0
    property double badgeStageStarted: Date.now()

    function badgeCheck(ok, detail) {
        if (!ok) {
            console.error("Health badges FAILED at stage " + root.badgeStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function badgeFind(name) {
        const pending = [systemHealthWindow.contentItem];
        while (pending.length > 0) {
            const item = pending.shift();
            if (item.objectName === name) return item;
            for (const child of item.children || []) pending.push(child);
        }
        return null;
    }
    // A badge's count, or 0 when it is hidden.
    function badge(category, kind) {
        const item = root.badgeFind("healthBadge-" + category + "-" + kind);
        root.badgeCheck(item !== null, "no " + kind + " badge on " + category);
        return item.visible ? item.count : 0;
    }
    function check(category, status, id) {
        systemHealthModel.ingestLine(["check", category, status, id, id, "summary", "", "", "", "user"].join("\t"));
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const waited = Date.now() - root.badgeStageStarted;
            root.badgeCheck(waited < 10000, "timed out");
            switch (root.badgeStage) {
            case 0:
                if (waited < 300) return;
                systemHealthModel.open();
                root.badgeStage++;
                root.badgeStageStarted = Date.now();
                return;
            case 1:
                // The window's own scan (helpers are `true`) has ended.
                if (!systemHealthWindow.visible || systemHealthModel.busy || waited < 300) return;
                root.check("storage", "error", "disk-root");
                root.check("storage", "warn", "disk-home");
                root.check("storage", "restricted", "storage-usage");
                root.check("network", "warn", "resolver");
                root.check("desktop", "info", "picom-process");
                root.check("desktop", "ok", "quickshell-version");
                root.badgeStage++;
                return;
            case 2: {
                const counts = {
                    "storage": [root.badge("storage", "warning"), root.badge("storage", "error")],
                    "network": [root.badge("network", "warning"), root.badge("network", "error")],
                    "desktop": [root.badge("desktop", "warning"), root.badge("desktop", "error")],
                    "overview": [root.badge("overview", "warning"), root.badge("overview", "error")]
                };
                root.badgeCheck(JSON.stringify(counts) === JSON.stringify({
                    "storage": [2, 1], "network": [1, 0], "desktop": [0, 0], "overview": [3, 1]
                }), "counts: " + JSON.stringify(counts));
                const warning = root.badgeFind("healthBadge-storage-warning");
                const error = root.badgeFind("healthBadge-storage-error");
                root.badgeCheck(Qt.colorEqual(warning.color, Theme.warning) && Qt.colorEqual(error.color, Theme.danger),
                    "badge fills");
                // Warnings to the left of errors, both at the tab's right.
                const w = warning.mapToItem(null, 0, 0).x;
                const e = error.mapToItem(null, 0, 0).x;
                root.badgeCheck(w < e, "the warning badge is not before the error badge: " + w + " " + e);
                // A check changing updates the badges: the error fixed.
                root.check("storage", "ok", "disk-root");
                root.badgeCheck(root.badge("storage", "error") === 0 && root.badge("overview", "error") === 0,
                    "a fixed error still counted");
                root.check("network", "error", "resolver");
                root.badgeCheck(root.badge("network", "warning") === 0 && root.badge("network", "error") === 1,
                    "a warning that became an error");
                console.log("Health badges: PASS");
                Qt.quit();
                return;
            }
            }
        }
    }
