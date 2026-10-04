.pragma library

// The Settings sections, and the search over them. Each section's keywords are
// what its pane holds, as headings and the words people look for: the name and
// the description alone found neither "weather" nor "battery".

var sections = [
    { "id": "displays", "label": "Displays", "description": "Resolution, refresh rate, and layouts",
        "keywords": ["monitor", "screen", "resolution", "refresh rate", "scaling", "dpi", "rotation",
            "arrangement", "layout", "profile", "multi-monitor", "dock"] },
    { "id": "input", "label": "Input", "description": "Keyboard, pointer, and touchpad",
        "keywords": ["keyboard", "layout", "mouse", "pointer", "touchpad", "trackpad", "speed",
            "acceleration", "scroll", "tap"] },
    { "id": "network", "label": "Network", "description": "Connections and VPN providers",
        "keywords": ["wifi", "wi-fi", "wireless", "ethernet", "wired", "vpn", "internet",
            "connection"] },
    { "id": "bluetooth", "label": "Bluetooth", "description": "Adapters and devices",
        "keywords": ["pair", "pairing", "headphones", "headset", "speaker", "controller",
            "devices"] },
    { "id": "audio", "label": "Audio", "description": "Outputs, inputs, and streams",
        "keywords": ["sound", "volume", "speaker", "headphones", "microphone", "mic", "mute",
            "output", "input"] },
    { "id": "power", "label": "Power", "description": "DPMS, locking, and session policy",
        "keywords": ["battery", "charging", "power profile", "performance", "suspend", "sleep",
            "lid", "screen lock", "lock", "blank", "idle", "screensaver", "shutdown", "reboot",
            "log out"] },
    { "id": "defaults", "label": "Defaults", "description": "Applications and autostart",
        "keywords": ["default applications", "browser", "terminal", "file manager", "file types",
            "mime", "startup applications", "autostart"] },
    { "id": "appearance", "label": "Appearance", "description": "Themes and accessibility",
        "keywords": ["theme", "wallpaper", "background", "font", "text size", "cursor", "icons",
            "gtk", "qt", "dark", "notifications", "do not disturb", "panel", "bar", "widgets",
            "weather", "location", "city", "temperature", "contrast", "reduced motion",
            "compositor", "picom", "transparency", "corners"] },
    { "id": "system", "label": "System", "description": "Health and administration",
        "keywords": ["update", "upgrade", "packages", "flatpak", "lyona", "rollback", "backup",
            "timezone", "time", "locale", "language", "accounts", "password", "printers",
            "software sources", "information", "about", "kernel", "memory", "storage",
            "diagnostics", "firewall", "secure boot", "encryption"] }
];

// The sections whose name, description or a keyword contains QUERY (any case).
function filter(list, query) {
    const needle = String(query || "").trim().toLowerCase();
    if (needle.length === 0) return list;
    return list.filter(function(section) {
        return section.label.toLowerCase().indexOf(needle) >= 0
            || section.description.toLowerCase().indexOf(needle) >= 0
            || (section.keywords || []).some(function(keyword) {
                return keyword.indexOf(needle) >= 0;
            });
    });
}
