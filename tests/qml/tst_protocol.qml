import QtQuick
import QtTest
import "../../config/quickshell/core/Protocol.js" as Protocol

/*
 * The one header rule for helper protocols (Sync Sprint 16 R16-53): the name
 * and major match, the minor is any number, and nothing follows it.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "Protocol"

    function test_accepts() {
        verify(Protocol.isHeader(["power-protocol", "1", "0"], "power-protocol", 1));
        // Append-only: a later minor of the same major is read.
        verify(Protocol.isHeader(["power-protocol", "1", "7"], "power-protocol", 1));
        // Two fields: a header without a minor.
        verify(Protocol.isHeader(["dpi-state-protocol", "1"], "dpi-state-protocol", 1));
        verify(Protocol.validHeader(["x", "2", "0"], 2));
    }

    function test_refuses() {
        verify(!Protocol.isHeader(["power-protocol", "2", "0"], "power-protocol", 1));
        verify(!Protocol.isHeader(["audio-protocol", "1", "0"], "power-protocol", 1));
        verify(!Protocol.isHeader(["power-protocol", "1", "0", "extra"], "power-protocol", 1));
        verify(!Protocol.isHeader(["power-protocol", "1", "x"], "power-protocol", 1));
        verify(!Protocol.isHeader(["power-protocol", "1", ""], "power-protocol", 1));
        verify(!Protocol.isHeader(["power-protocol", "01", "0"], "power-protocol", 1));
        verify(!Protocol.isHeader(["power-protocol"], "power-protocol", 1));
        verify(!Protocol.isHeader([], "power-protocol", 1));
    }
}
