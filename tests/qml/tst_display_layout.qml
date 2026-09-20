import QtQuick
import QtTest
import "../../config/quickshell/settings/DisplayLayout.js" as Layout

/*
 * Direct, non-UI tests for the pure display-placement math library (Sync
 * Sprint 3 S3-01, docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md, ported from
 * upstream's 55dbd76 (#289) tests/quickshell-display-layout.qml -- an
 * ad-hoc QtObject/Component.onCompleted script upstream runs outside
 * qmltestrunner. Converted here into Lyona's own tst_*.qml/TestCase
 * convention (matching tst_system_information_protocol.qml's precedent for
 * testing a pure library directly), so it's automatically picked up by
 * `qmltestrunner -input tests/qml` with no new Makefile target needed. Every
 * assertion below is upstream's own, just split into named test functions.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "DisplayLayout"

    function baseOutputs() {
        return [
            { name: "eDP-1", enabled: false, mode: "2560x1600_90.00", x: 0, y: 0, rotation: "normal" },
            { name: "DVI-I-2-2", enabled: true, primary: true, mode: "2560x1440", x: 2560, y: 0, rotation: "normal" },
            { name: "DVI-I-1-1", enabled: true, mode: "2560x1440", x: 0, y: 0, rotation: "normal" }
        ];
    }

    function test_targets_excludes_self_and_disabled_outputs() {
        const outputs = baseOutputs();
        compare(Layout.targets(outputs, 1).length, 1, "Only other enabled monitors can be anchors");
    }

    function test_place_matches_relation_keeps_origin_nonnegative_and_preserves_primary() {
        const outputs = baseOutputs();
        const original = JSON.stringify(outputs);
        for (const direction of ["left", "right", "above", "below"]) {
            const placed = Layout.place(outputs, 1, 2, direction);
            compare(Layout.relation(placed, 1, 2), direction, "Placement must match " + direction);
            verify(placed.filter(item => item.enabled).every(item => item.x >= 0 && item.y >= 0),
                "Origin must be non-negative");
            verify(placed[1].primary, "Primary must be preserved");
            const bounds = Layout.preview(placed);
            verify(bounds.tiles.length === 2 && bounds.tiles[0].number === 2,
                "Preview numbers must match cards including disabled gaps");
            compare(bounds.width, direction === "left" || direction === "right" ? 5120 : 2560, "Preview width");
            compare(bounds.height, direction === "above" || direction === "below" ? 2880 : 1440, "Preview height");
        }
        compare(JSON.stringify(outputs), original, "Placement cannot mutate discovered state");
    }

    function test_place_normalizes_and_preserves_relative_positions_of_other_monitors() {
        const three = baseOutputs().map(item => Object.assign({}, item));
        three[0].enabled = true;
        three[0].x = -2560;
        three[0].y = -1600;
        const arranged = Layout.place(three, 1, 2, "above");
        verify(arranged[0].x - arranged[2].x === three[0].x - three[2].x
            && arranged[0].y - arranged[2].y === three[0].y - three[2].y,
            "Normalization preserves the other monitors' relative placement");
        compare(Layout.preview(arranged).tiles.length, 3, "All enabled monitors appear");
    }

    function test_place_accounts_for_rotation() {
        const outputs = baseOutputs();
        outputs[1].rotation = "left";
        outputs[2].mode = "1920x1080";
        const left = Layout.place(outputs, 1, 2, "left");
        verify(left[2].x === 1440 && left[1].x === 0, "Rotated own width sets left distance");
        const below = Layout.place(outputs, 2, 1, "below");
        compare(below[2].y, 2560, "Rotated anchor height sets below distance");
    }

    function test_place_rejects_self_disabled_anchor_and_invalid_direction() {
        const outputs = baseOutputs();
        outputs[1].rotation = "left";
        outputs[2].mode = "1920x1080";
        compare(Layout.place(outputs, 1, 1, "left"), null, "No self reference");
        compare(Layout.place(outputs, 1, 0, "right"), null, "No disabled anchor");
        compare(Layout.place(outputs, 1, 2, "unknown"), null, "Reject invalid direction");
    }

    function test_place_rejects_invalid_geometry_and_preview_of_empty_stays_finite() {
        const outputs = baseOutputs();
        outputs[1].mode = "h:";
        compare(Layout.place(outputs, 1, 2, "left"), null, "Reject invalid geometry");
        compare(Layout.preview([]).width, 1, "Empty preview stays finite");
    }

    function test_custom_mode_names_use_reported_pixel_dimensions() {
        const outputs = baseOutputs();
        outputs[1].mode = "native";
        outputs[1].pixelWidth = 2560;
        outputs[1].pixelHeight = 1440;
        outputs[1].rotation = "left";
        compare(Layout.size(outputs[1]).width, 1440, "Custom mode uses actual rotated pixel dimensions");
        compare(Layout.targets(outputs, 2).length, 1, "Custom modes remain usable as anchors");
        compare(Layout.place(outputs, 2, 1, "below")[2].y, 2560, "Custom mode placement uses actual height");
        compare(Layout.preview(outputs).tiles.length, 2, "Custom modes appear in the preview");
    }
}
