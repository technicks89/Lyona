pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Singleton {
    id: root

    // A window class's desktop-entry icon (#498, upstream dwm-titus #426):
    // class -> the entry's Icon= value, "" when no entry matches. Asked of the
    // launcher helper only for a class with no themed icon, a batch at a time,
    // and kept for the session. Shared by every panel, so one screen or five
    // ask once, and nothing is read while no new class appears.
    property var desktopIcons: ({})
    // Read by windowIcon, so its callers bind again when an answer arrives.
    property int desktopIconRevision: 0
    // The classes waiting for a lookup, and those the running one asks for.
    // A plain object, not properties: windowIcon queues from inside its
    // callers' bindings, and a property read and written there is a loop.
    readonly property var iconLookup: ({ pending: [], asked: [] })

    // The icon for a window: its class as a themed icon name, else its desktop
    // entry's icon, else launcherIcon's fallbacks. A class not yet looked up
    // shows the fallback until the answer arrives.
    function windowIcon(appClass) {
        const windowClass = appClass || "";
        void root.desktopIconRevision;
        if (windowClass.length > 0 && Quickshell.hasThemeIcon(windowClass)) {
            return Quickshell.iconPath(windowClass);
        }
        if (validIconClass(windowClass)) {
            if (Object.prototype.hasOwnProperty.call(root.desktopIcons, windowClass)) {
                const entryIcon = entryIconSource(root.desktopIcons[windowClass]);
                if (entryIcon.length > 0) {
                    return entryIcon;
                }
            } else {
                requestDesktopIcon(windowClass);
            }
        }
        return launcherIcon("");
    }

    // What the helper accepts: one field, bounded.
    function validIconClass(windowClass) {
        return windowClass.length > 0 && windowClass.length <= 256 && !/[\t\n]/.test(windowClass);
    }

    // An entry's Icon= is a themed name or an absolute file.
    function entryIconSource(value) {
        if (value.length === 0) {
            return "";
        }
        if (value.charAt(0) === "/") {
            return looksLikeIconFilePath(value) ? "file://" + value : "";
        }
        return Quickshell.hasThemeIcon(value) ? Quickshell.iconPath(value) : "";
    }

    function requestDesktopIcon(windowClass) {
        const lookup = root.iconLookup;
        if (lookup.pending.indexOf(windowClass) >= 0 || lookup.asked.indexOf(windowClass) >= 0) {
            return;
        }
        lookup.pending.push(windowClass);
        // Not from inside the caller's binding: the classes that ask in the
        // same pass go in one batch.
        Qt.callLater(root.startDesktopIconLookup);
    }

    // One lookup at a time; classes that ask meanwhile wait for the next.
    function startDesktopIconLookup() {
        const lookup = root.iconLookup;
        if (desktopIconProcess.running || lookup.pending.length === 0) {
            return;
        }
        lookup.asked = lookup.pending;
        lookup.pending = [];
        desktopIconProcess.command = Commands.launcherHelperCommand("icons-for", lookup.asked);
        desktopIconProcess.running = true;
    }

    // Every asked class gets an answer, "" when the helper gave none or
    // failed, so a missing helper is not asked again on every binding.
    function finishDesktopIconLookup(output) {
        const lookup = root.iconLookup;
        const icons = Object.assign({}, root.desktopIcons);
        for (const windowClass of lookup.asked) {
            icons[windowClass] = "";
        }
        for (const line of (output || "").split("\n")) {
            const tab = line.indexOf("\t");
            if (tab <= 0) {
                continue;
            }
            const windowClass = line.slice(0, tab);
            if (lookup.asked.indexOf(windowClass) >= 0) {
                icons[windowClass] = line.slice(tab + 1);
            }
        }
        lookup.asked = [];
        root.desktopIcons = icons;
        root.desktopIconRevision++;
        if (lookup.pending.length > 0) {
            Qt.callLater(root.startDesktopIconLookup);
        }
    }

    Process {
        id: desktopIconProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        // The pipe closes when the helper ends, however it ends: a failed
        // lookup finishes with whatever it printed, and every class it did
        // not answer is recorded as having no entry icon.
        stdout: StdioCollector {
            onStreamFinished: root.finishDesktopIconLookup(this.text)
        }
    }

    // The themed icon for iconName, else the generic application icon, else ""
    // when the theme has neither: a window class is often not an icon name, and
    // the generic one is missing from some themes, where it drew Qt's
    // "missing image" checkerboard (#280 VM). Callers show the name's initial
    // for "" (initialFor).
    function launcherIcon(iconName) {
        for (const name of [iconName, "application-x-executable"]) {
            if (name.length > 0 && Quickshell.hasThemeIcon(name)) {
                return Quickshell.iconPath(name);
            }
        }
        return "";
    }

    // The first letter of a name, upper case, for an item with no icon.
    function initialFor(name) {
        const trimmed = (name || "").trim();
        return trimmed.length > 0 ? trimmed.charAt(0).toUpperCase() : "?";
    }

    function trayIconSource(trayItem) {
        const sources = trayIconSources(trayItem);
        return sources.length > 0 ? sources[0] : "";
    }

    function addIconSource(sources, source) {
        if (typeof source !== "string" && !(source instanceof String)) {
            return;
        }

        if (source.length === 0) {
            return;
        }

        if (sources.indexOf(source) < 0) {
            sources.push(source);
        }
    }

    function decodeIconPart(value) {
        try {
            return decodeURIComponent(value);
        } catch (error) {
            return value;
        }
    }

    function looksLikeIconFilePath(path) {
        return /\.(ico|png|svg|tga|webp|xpm)$/i.test(path);
    }

    function iconNameFallbacks(iconName) {
        const names = [iconName];

        if (iconName.indexOf("-symbolic") < 0) {
            names.push(iconName + "-symbolic");
        }

        if (iconName === "blueman" || iconName === "blueman-tray") {
            names.push("blueman-tray");
            names.push("blueman");
            names.push("blueman-active");
            names.push("bluetooth-active-symbolic");
            names.push("bluetooth-symbolic");
        } else if (iconName === "org.remmina.Remmina-status") {
            names.push("org.remmina.Remmina");
            names.push("org.remmina.Remmina-symbolic");
        }

        return names;
    }

    function addIconThemeFileSources(sources, themeRoot, iconName) {
        if (themeRoot.length === 0 || iconName.length === 0) {
            return;
        }

        const rootPath = themeRoot.replace(/\/+$/, "");
        const names = iconNameFallbacks(iconName);
        const sizes = ["24x24", "32x32", "22x22", "16x16", "48x48", "scalable"];
        const categories = ["status", "apps", "devices", "actions", "emblems"];
        const extensions = ["svg", "png"];

        for (let nameIndex = 0; nameIndex < names.length; nameIndex++) {
            const name = names[nameIndex];

            for (let sizeIndex = 0; sizeIndex < sizes.length; sizeIndex++) {
                const size = sizes[sizeIndex];

                for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex++) {
                    const category = categories[categoryIndex];

                    for (let extensionIndex = 0; extensionIndex < extensions.length; extensionIndex++) {
                        addIconSource(sources, "file://" + rootPath + "/" + size + "/" + category + "/" + name + "." + extensions[extensionIndex]);
                    }
                }
            }

            for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex++) {
                const category = categories[categoryIndex];

                for (let extensionIndex = 0; extensionIndex < extensions.length; extensionIndex++) {
                    addIconSource(sources, "file://" + rootPath + "/" + category + "/" + name + "." + extensions[extensionIndex]);
                }
            }

            addIconSource(sources, "file://" + rootPath + "/" + name);

            for (let extensionIndex = 0; extensionIndex < extensions.length; extensionIndex++) {
                addIconSource(sources, "file://" + rootPath + "/" + name + "." + extensions[extensionIndex]);
            }
        }
    }

    function addHicolorFallbacks(sources, iconName) {
        // A relative XDG_DATA_HOME is ignored, as the specification requires (#282).
        const home = Xdg.home;
        const xdgDataHome = Xdg.dataHome;

        addIconThemeFileSources(sources, "/usr/share/icons/hicolor", iconName);
        addIconThemeFileSources(sources, "/usr/local/share/icons/hicolor", iconName);

        if (xdgDataHome.length > 0) {
            addIconThemeFileSources(sources, xdgDataHome + "/icons/hicolor", iconName);
        }

        if (home.length > 0) {
            addIconThemeFileSources(sources, home + "/.icons/hicolor", iconName);
        }
    }

    function addCheckedThemeSources(sources, iconName) {
        const names = iconNameFallbacks(iconName);

        for (let index = 0; index < names.length; index++) {
            addIconSource(sources, Quickshell.iconPath(names[index], true));
        }
    }

    function addThemeFallbacks(sources, iconName) {
        if (iconName === "dialog-password") {
            addIconSource(sources, "file:///usr/share/icons/Adwaita/symbolic/status/dialog-password-symbolic.svg");
            addIconSource(sources, "file:///usr/share/icons/AdwaitaLegacy/24x24/legacy/dialog-password.png");
            addIconSource(sources, "image://icon/dialog-password-symbolic");
        } else if (iconName === "steam_tray_mono") {
            addIconSource(sources, "file:///usr/share/pixmaps/steam_tray_mono.png");
        }
    }

    function trayIconSources(trayItem) {
        const icon = trayItem && trayItem.icon;
        const sources = [];

        if (typeof icon !== "string" && !(icon instanceof String)) {
            return sources;
        }

        if (icon.length === 0) {
            return sources;
        }

        if (icon.indexOf("image://icon/") === 0) {
            const queryIndex = icon.indexOf("?path=");
            const iconStart = "image://icon/".length;
            const iconName = decodeIconPart(queryIndex >= 0 ? icon.substring(iconStart, queryIndex) : icon.substring(iconStart));

            if (iconName.indexOf("/") === 0) {
                addIconSource(sources, "file://" + iconName);
                addIconSource(sources, icon);
                return sources;
            }

            if (queryIndex >= 0) {
                let iconPath = icon.substring(queryIndex + "?path=".length);
                const iconPathEnd = iconPath.indexOf("&");

                if (iconPathEnd >= 0) {
                    iconPath = iconPath.substring(0, iconPathEnd);
                }

                iconPath = decodeIconPart(iconPath);
                if (iconName.indexOf("/") !== 0) {
                    if (iconPath.indexOf("/") === 0 && looksLikeIconFilePath(iconPath)) {
                        addIconSource(sources, "file://" + iconPath);
                    }

                    addIconSource(sources, "file://" + iconPath + "/" + iconName);
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".png");
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".svg");
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".ico");
                    addIconSource(sources, "file://" + iconPath + "/" + iconName + ".tga");
                    addIconThemeFileSources(sources, iconPath, iconName);
                }
            }

            addThemeFallbacks(sources, iconName);
            addHicolorFallbacks(sources, iconName);
            addCheckedThemeSources(sources, iconName);
            addIconSource(sources, icon);
            return sources;
        }

        if (icon.indexOf("image://") === 0 || icon.indexOf("file://") === 0 || icon.indexOf("qrc:") === 0) {
            addIconSource(sources, icon);
            return sources;
        }

        if (icon.indexOf("/") === 0 && icon.indexOf("file://") !== 0) {
            addIconSource(sources, "file://" + icon);
            return sources;
        }

        if (icon === "dialog-password") {
            addIconSource(sources, Quickshell.iconPath("dialog-password-symbolic", true));
        }

        addThemeFallbacks(sources, icon);
        addHicolorFallbacks(sources, icon);
        addCheckedThemeSources(sources, icon);
        addIconSource(sources, icon);
        return sources;
    }
}
