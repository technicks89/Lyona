pragma Singleton

import Quickshell

Singleton {
    id: root

    property bool dark: true

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
    property string textMuted: "#D8DEE9"
    property string placeholder: "#4C566A"
    property string accent: "#81A1C1"
    property string accentSecondary: "#81A1C1"
    property string accentText: "#2E3440"
    property string success: "#A3BE8C"
    property string warning: "#EBCB8B"
    property string danger: "#BF616A"
    property string dangerSurface: "#3B4252"
    readonly property string shadow: transparent

    readonly property string popupBackground: bg
    readonly property string popupBorder: borderStrong
    readonly property string popupText: text
    readonly property string menuBackground: bg
    readonly property string menuText: text
    readonly property string menuMutedText: textMuted
    readonly property string menuActionText: accent
    readonly property string menuHoverBackground: surfaceHover
    readonly property string menuHoverText: textStrong
    readonly property string menuSelectedBackground: surfaceActive
    readonly property string menuSelectedText: accentSecondary
    readonly property string controlNormalFill: surface
    readonly property string controlNormalBorder: border
    readonly property string controlNormalText: text
    readonly property string controlHoverFill: surfaceHover
    readonly property string controlHoverBorder: borderStrong
    readonly property string controlHoverText: text
    readonly property string controlFocusFill: surface
    readonly property string controlFocusBorder: accent
    readonly property string controlFocusText: text
    readonly property string controlSelectedFill: surfaceActive
    readonly property string controlSelectedBorder: accentSecondary
    readonly property string controlSelectedText: accentSecondary
    readonly property string controlDisabledFill: barBackground
    readonly property string controlDisabledBorder: border
    readonly property string controlDisabledText: textMuted

    function applyAppearanceColors(colors, darkMode) {
        root.dark = darkMode;
        root.bg = colors.background;
        root.barBackground = colors["bar-background"];
        root.surface = colors.surface;
        root.surfaceHover = colors["surface-hover"];
        root.surfaceActive = colors["surface-active"];
        root.border = colors.border;
        root.borderStrong = colors["border-strong"];
        root.text = colors.text;
        root.textStrong = colors["text-strong"];
        root.textMuted = colors["text-muted"];
        root.placeholder = colors.placeholder;
        root.accent = colors.accent;
        root.accentSecondary = colors["accent-secondary"];
        root.accentText = colors["accent-text"];
        root.success = colors.success;
        root.warning = colors.warning;
        root.danger = colors.danger;
        root.dangerSurface = colors["danger-surface"];
    }

    property string fontFamily: "MesloLGS Nerd Font Mono"
    property real fontScale: 1.0
    readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"

    function applyFontPreferences(family, scale) {
        root.fontFamily = family.length > 0 ? family : "MesloLGS Nerd Font Mono";
        root.fontScale = Math.max(0.8, Math.min(1.5, scale));
    }

    property int displayDpi: 96
    readonly property real uiScale: Math.max(0.75, Math.min(3.0, root.displayDpi / 96))

    function applyDisplayDpi(dpi) {
        const value = Math.round(Number(dpi));
        root.displayDpi = (isFinite(value) && value >= 72 && value <= 384) ? value : 96;
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

    readonly property int fontCaptionSize: Math.max(dp(8), Math.round(10 * fontScale * uiScale))
    readonly property int fontBodySmallSize: Math.max(dp(10), Math.round(12 * fontScale * uiScale))
    readonly property int fontBodySize: Math.max(dp(10), Math.round(13 * fontScale * uiScale))
    readonly property int fontSubtitleSize: Math.max(dp(11), Math.round(14 * fontScale * uiScale))
    readonly property int fontTitleSize: Math.max(dp(14), Math.round(18 * fontScale * uiScale))
    readonly property int largeSurfaceTitleSize: Math.max(dp(18), Math.round(24 * fontScale * uiScale))
    readonly property int panelIconFontSize: dp(13)

    readonly property int controlHeight: dp(30)
    readonly property int controlRowHeight: dp(32)
    readonly property int controlPaddingX: dp(9)
    readonly property int controlBorderWidth: dp(1)
    readonly property int controlFocusBorderWidth: dp(2)
    readonly property int controlRadius: dp(6)
    readonly property int menuHeaderHeight: dp(26)
    readonly property int popupPadding: spacingHuge
    readonly property int popupRadius: controlRadius
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
    readonly property int animationFast: 120
    readonly property int animationNormal: 180
    readonly property int buttonHeight: controlHeight
    readonly property int chipHeight: dp(28)
    readonly property int workspaceButtonSize: dp(22)
    readonly property int compactButtonHeight: dp(40)
    readonly property int confirmButtonHeight: dp(48)
    readonly property int notificationAccentWidth: dp(4)
    readonly property int notificationAccentRadius: dp(2)
    readonly property int largeSurfaceMargin: dp(22)
    readonly property int largeSurfaceNavWidth: dp(248)
    readonly property int largeSurfaceSearchHeight: dp(44)
    readonly property int largeSurfaceCardRadius: dp(8)
    readonly property int titleFontSize: fontTitleSize
    readonly property int bodyFontSize: fontSubtitleSize
    readonly property int panelFontSize: fontBodySize
    readonly property int smallFontSize: fontBodySmallSize
    readonly property int tinyFontSize: fontCaptionSize
    readonly property int inputFontSize: Math.max(dp(12), Math.round(16 * fontScale * uiScale))
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
