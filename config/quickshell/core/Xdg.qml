pragma Singleton

import Quickshell

/*
 * The XDG base directories, the way dwm-xdg.sh's lyona_xdg_dirs lenient gives
 * them to the shell scripts (#282): a set value only when it is absolute, as
 * the XDG Base Directory specification requires, else the fallback under HOME,
 * and empty when there is no HOME to fall back on. Every QML file reads them
 * here; tests/test-quickshell-xdg.sh forbids Quickshell.env("XDG_ elsewhere.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHome: root.resolve("XDG_CONFIG_HOME", ".config")
    readonly property string dataHome: root.resolve("XDG_DATA_HOME", ".local/share")
    readonly property string stateHome: root.resolve("XDG_STATE_HOME", ".local/state")
    readonly property string cacheHome: root.resolve("XDG_CACHE_HOME", ".cache")
    // No fallback: without a runtime directory there is none to guess.
    readonly property string runtimeDir: root.absolute(Quickshell.env("XDG_RUNTIME_DIR") || "")

    function absolute(value) {
        return String(value).startsWith("/") ? String(value) : "";
    }

    function resolve(name, fallback) {
        const value = root.absolute(Quickshell.env(name) || "");
        if (value.length > 0) return value;
        return root.home.length > 0 ? root.home + "/" + fallback : "";
    }
}
