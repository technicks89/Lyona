pragma Singleton

import Quickshell

Singleton {
    id: root

    property bool dark: true
    property bool highContrast: false
    property bool reducedMotion: false

    readonly property string transparent: "#00000000"
    property string bg: "#2E3440"
    property string barBackground: "#434C5E"
    property string surface: "#434C5E"
    property string surfaceHover: "#4C566A"
    property string surfaceActive: "#434C5E"
    property string border: "#3B4252"
    property string borderStrong: "#81A1C1"
    property string text: "#D8DEE9"
    property string textStrong: "#ECEFF4"
    property string paletteTextMuted: "#D8DEE9"
    readonly property string textMuted: highContrast ? text : paletteTextMuted
    property string placeholder: "#4C566A"
    property string accent: "#81A1C1"
    property string accentSecondary: "#81A1C1"
    property string accentText: "#2E3440"
    readonly property string accentHoverText: readableText(accentText, accentSecondary)
    property string success: "#A3BE8C"
    property string warning: "#EBCB8B"
    property string danger: "#BF616A"
    property string dangerSurface: "#3B4252"
    readonly property string shadow: transparent

    readonly property string popupBackground: bg
    readonly property string popupBorder: highContrast ? textStrong : borderStrong
    readonly property string popupText: text
    readonly property string menuBackground: bg
    readonly property string menuText: dark ? text : readableTextOnSurfaces(text, [menuBackground, menuHoverBackground])
    readonly property string menuMutedText: dark ? textMuted : readableTextOnSurfaces(textMuted, [menuBackground, menuHoverBackground])
    readonly property string menuActionText: readableText(accent, menuBackground)
    readonly property string menuHoverBackground: surfaceHover
    readonly property string menuHoverText: readableText(textStrong, menuHoverBackground)
    readonly property string menuSelectedBackground: surfaceActive
    readonly property string menuSelectedText: readableText(accentSecondary, menuSelectedBackground)
    readonly property string controlNormalFill: surface
    readonly property string controlNormalBorder: highContrast ? textStrong : border
    readonly property string controlNormalText: dark ? readableText(text, controlNormalFill) : readableTextOnSurfaces(text, [controlNormalFill, controlHoverFill])
    readonly property string controlHoverFill: surfaceHover
    readonly property string controlHoverBorder: highContrast ? textStrong : borderStrong
    readonly property string controlHoverText: readableText(text, controlHoverFill)
    readonly property string controlFocusFill: surface
    readonly property string controlFocusBorder: highContrast ? textStrong : accent
    readonly property string controlFocusText: readableText(text, controlFocusFill)
    readonly property string controlSelectedFill: surfaceActive
    readonly property string controlSelectedBorder: highContrast ? textStrong : accentSecondary
    readonly property string controlSelectedText: readableText(accentSecondary, controlSelectedFill)
    readonly property string controlDisabledFill: barBackground
    readonly property string controlDisabledBorder: highContrast ? textStrong : border
    readonly property string controlDisabledText: textMuted

    // WCAG relative luminance of "#RRGGBB", or "#AARRGGBB" (how QML stringifies a
    // colour that has alpha; the alpha byte is skipped).
    function luminance(color) {
        const rgb = color.length === 9 ? color.slice(3) : color.slice(1);
        const channels = [0, 2, 4].map(function(offset) {
            const value = parseInt(rgb.slice(offset, offset + 2), 16) / 255;
            return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        });
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }

    // The foreground itself when it reads at 4.5:1 on the background, otherwise
    // black or white, whichever is the better fit.
    function readableText(foreground, background) {
        const fg = luminance(foreground);
        const bg = luminance(background);
        if ((Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05) >= 4.5)
            return foreground;
        return bg > 0.179 ? "#000000" : "#ffffff";
    }

    function readableTextOnSurfaces(foreground, backgrounds) {
        // Some controls intentionally keep one text role while their fill
        // changes on hover. Check that role against both actual surfaces.
        function minimumContrast(color) {
            const fg = luminance(color);
            return Math.min.apply(null, backgrounds.map(function(background) {
                const bg = luminance(background);
                return (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
            }));
        }
        if (minimumContrast(foreground) >= 4.5)
            return foreground;
        return minimumContrast("#000000") > minimumContrast("#ffffff") ? "#000000" : "#ffffff";
    }

    function lightHover(background, foreground) {
        // ANSI bright-black is a terminal foreground, not a light UI surface.
        return "#" + [1, 3, 5].map(function(offset) {
            const bg = parseInt(background.slice(offset, offset + 2), 16);
            const fg = parseInt(foreground.slice(offset, offset + 2), 16);
            return Math.round(bg * 0.92 + fg * 0.08).toString(16).padStart(2, "0");
        }).join("");
    }

    function applyAppearanceColors(colors, darkMode) {
        root.dark = darkMode;
        root.bg = colors.background;
        root.barBackground = colors["bar-background"];
        root.surface = colors.surface;
        root.surfaceHover = darkMode ? colors["surface-hover"]
            : lightHover(colors.background, colors["text-strong"]);
        root.surfaceActive = colors["surface-active"];
        root.border = colors.border;
        root.borderStrong = colors["border-strong"];
        root.text = colors.text;
        root.textStrong = colors["text-strong"];
        root.paletteTextMuted = colors["text-muted"];
        root.placeholder = colors.placeholder;
        root.accent = colors.accent;
        root.accentSecondary = colors["accent-secondary"];
        root.accentText = readableText(colors["accent-text"], colors.accent);
        root.success = colors.success;
        root.warning = colors.warning;
        root.danger = colors.danger;
        root.dangerSurface = colors["danger-surface"];
    }

    property string fontFamily: "MesloLGS Nerd Font Mono"
    property real requestedFontScale: 1.0
    readonly property real fontScale: requestedFontScale
    readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"

    function applyFontPreferences(family, scale) {
        root.fontFamily = family.length > 0 ? family : "MesloLGS Nerd Font Mono";
        root.requestedFontScale = Math.max(0.75, Math.min(2.0, scale));
    }

    function scaledFontSize(value, minimum) {
        return Math.max(dp(minimum), Math.round(value * root.fontScale * root.uiScale));
    }

    property int displayDpi: 96
    readonly property real uiScale: Math.max(0.75, Math.min(3.0, root.displayDpi / 96))

    function applyDisplayDpi(dpi) {
        const value = Math.round(Number(dpi));
        root.displayDpi = (isFinite(value) && value >= 72 && value <= 384) ? value : 96;
    }

    function applyAccessibility(highContrastEnabled, reducedMotionEnabled) {
        root.highContrast = highContrastEnabled;
        root.reducedMotion = reducedMotionEnabled;
    }

    /* A zero stays zero -- a metric set to 0 means "no border/no margin", not
     * "the smallest possible one". Everything else keeps at least one pixel. */
    function dp(px) {
        if (px <= 0)
            return 0;
        return Math.max(1, Math.round(px * root.uiScale));
    }

    readonly property int spacingXxs: dp(2)
    readonly property int spacingXs: dp(3)
    readonly property int spacingSm: dp(4)
    readonly property int spacingMd: dp(6)
    readonly property int spacingLg: dp(8)
    readonly property int spacingXl: dp(10)
    readonly property int spacingXxl: dp(12)
    readonly property int spacingXxxl: dp(14)
    readonly property int spacingHuge: dp(18)

    readonly property int fontCaptionSize: scaledFontSize(10, 8)
    readonly property int fontBodySmallSize: scaledFontSize(12, 10)
    readonly property int fontBodySize: scaledFontSize(13, 10)
    readonly property int fontSubtitleSize: scaledFontSize(14, 11)
    readonly property int fontTitleSize: scaledFontSize(18, 14)
    readonly property int largeSurfaceTitleSize: scaledFontSize(24, 18)
    readonly property int panelIconFontSize: scaledFontSize(14, 8)

    readonly property int controlHeight: dp(30)
    readonly property int controlRowHeight: dp(32)
    readonly property int controlPaddingX: dp(9)
    readonly property int controlBorderWidth: dp(highContrast ? 2 : 1)
    readonly property int controlFocusBorderWidth: controlBorderWidth
    readonly property int controlRadius: dp(6)
    readonly property int menuHeaderHeight: dp(26)
    readonly property int popupPadding: spacingHuge
    readonly property int popupRadius: 0
    readonly property int panelHeroIconSize: dp(32)
    readonly property real panelMetaLetterSpacing: 1.2 * uiScale
    readonly property int panelSliderHeight: dp(32)
    readonly property int panelSliderTrackHeight: dp(6)
    readonly property int panelSliderKnobSize: dp(16)
    readonly property int panelToggleWidth: dp(40)
    readonly property int panelToggleHeight: dp(22)
    readonly property int panelToggleKnobSize: dp(14)
    readonly property int panelToggleInset: dp(3)

    readonly property int panelHeight: dp(30)
    readonly property int panelMargin: 0
    readonly property int panelEdgeMargin: 0
    readonly property int panelGap: spacingSm
    readonly property int popupMargin: popupPadding
    readonly property int popupSpacing: spacingXxl
    readonly property int controlCenterX: dp(6)
    readonly property int controlCenterWidth: dp(276)
    readonly property int rowSpacing: spacingXl
    readonly property int listSpacing: spacingSm
    readonly property int compactSpacing: spacingXxs
    readonly property int tightSpacing: spacingXs
    readonly property int sectionSpacing: spacingXxxl
    readonly property int radius: controlRadius
    readonly property int smallRadius: controlRadius
    readonly property int barRadius: 0
    readonly property int pillRadius: dp(6)
    readonly property int pillHeight: dp(26)
    readonly property int pillHorizontalPadding: dp(9)
    readonly property int compactWidgetSize: dp(22)
    readonly property int compactWidgetHorizontalPadding: dp(6)
    readonly property real networkWidgetHorizontalPadding: 4.5 * uiScale
    readonly property int pillBorderWidth: controlBorderWidth
    readonly property int animationFast: reducedMotion ? 0 : 120
    readonly property int animationNormal: reducedMotion ? 0 : 180
    readonly property int buttonHeight: controlHeight
    readonly property int chipHeight: dp(28)
    readonly property int workspaceButtonSize: dp(22)
    readonly property int compactButtonHeight: dp(40)
    readonly property int confirmButtonHeight: dp(48)
    readonly property int notificationAccentWidth: dp(4)
    readonly property int notificationAccentRadius: 0
    readonly property int largeSurfaceMargin: dp(22)
    readonly property int largeSurfaceNavWidth: dp(248)
    readonly property int settingsNavWidth: dp(232)
    readonly property int largeSurfaceSearchHeight: dp(44)
    readonly property int largeSurfaceCardRadius: dp(8)
    readonly property int titleFontSize: fontTitleSize
    readonly property int bodyFontSize: fontSubtitleSize
    readonly property int panelFontSize: fontBodySize
    readonly property int smallFontSize: fontBodySmallSize
    readonly property int tinyFontSize: fontCaptionSize
    readonly property int inputFontSize: scaledFontSize(16, 12)
    readonly property int iconSize: dp(28)
    readonly property int trayItemSize: dp(24)
    readonly property int trayIconSize: dp(18)
    readonly property int closeButtonSize: dp(30)

    /*
     * The status vocabulary shared by the provider-backed Settings panes and
     * the Settings window itself. DefaultsSettingsPane keeps its own copy on
     * purpose: it colours a generic capability list where "unsupported" is a
     * neutral fact rather than a fault, so folding it in here would turn
     * legitimately grey rows red.
     */
    function statusColor(state) {
        if (state === "available")
            return success;
        if (state === "partial" || state === "restricted")
            return warning;
        if (state === "unavailable" || state === "failed")
            return danger;
        return menuMutedText;
    }

    /* Whole hours and whole minutes read better than a raw second count. */
    function formatDuration(seconds) {
        if (seconds >= 3600 && seconds % 3600 === 0)
            return (seconds / 3600) + "h";
        if (seconds >= 60 && seconds % 60 === 0)
            return (seconds / 60) + "m";
        return seconds + "s";
    }
}
