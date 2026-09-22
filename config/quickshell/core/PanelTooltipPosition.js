.pragma library

// The pure position math behind PanelTooltip.qml's anchor.rect.x, split out
// so it is a plain, live property binding (recomputed whenever the anchor
// window's width, the tooltip's own width, or the anchor point changes,
// instead of only when Quickshell's onAnchoring happens to fire) and so it
// can be unit-tested directly without instantiating a Quickshell PopupWindow
// (see tests/qml/tst_panel_tooltip_position.qml).

// clampedX WINDOW_WIDTH TOOLTIP_WIDTH ANCHOR_X RIGHT_ALIGNED: the tooltip's x,
// left of the anchor point when right-aligned, otherwise starting at it, and
// always kept within [0, WINDOW_WIDTH - TOOLTIP_WIDTH] so it never clips off
// either edge of the anchor window.
function clampedX(windowWidth, tooltipWidth, anchorX, rightAligned) {
    const raw = rightAligned ? anchorX - tooltipWidth : anchorX;
    return Math.floor(Math.max(0, Math.min(windowWidth - tooltipWidth, raw))) | 0;
}
