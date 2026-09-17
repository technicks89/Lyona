import QtQuick
import QtTest
import "../../config/quickshell/systemmanagement/SystemRegionalPreflightProtocol.js" as Protocol

/*
 * Direct, non-UI tests for the pure regional-preflight stream parser
 * (Sync Phase 9, docs/SYNC-P9-REGIONAL-MUTATION.md). Protocol.js is plain
 * functions over a plain object with no QML dependency -- test it directly,
 * matching tst_system_discovery_cycle.qml's own precedent for testing a
 * pure library this way rather than only through SystemRegionalPreflightModel.
 *
 * Assertions are translated from upstream's tests/qml/SystemRegionalPreflightParser.qml
 * (a bespoke ShellRoot + Qt.quit() harness) into this repo's QtTest/TestCase
 * convention; every scenario upstream covers is preserved, just regrouped
 * into named test_* functions instead of one giant unitTests() body.
 *
 * Non-ASCII test fixtures are built with String.fromCharCode/fromCodePoint
 * rather than \u escapes or literal characters in this source file, since
 * those characters (control, bidi-override, line-separator) are unsafe to
 * carry as raw source bytes.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "SystemRegionalPreflightProtocol"

    property string generation: "a".repeat(64)

    function bytes(text) {
        const encoded = unescape(encodeURIComponent(text));
        const result = new Uint8Array(encoded.length);
        for (let i = 0; i < encoded.length; i++) result[i] = encoded.charCodeAt(i);
        return result.buffer;
    }
    function choicesStream(kind, values) {
        return "regional-choices-protocol\t1\t0\t" + kind + "\n"
            + values.map(value => "choice\t" + value + "\n").join("") + "complete\tregional-choices\n";
    }
    function previewStream(action, argument, current, detail) {
        return "regional-preview-protocol\t1\t0\n" + ["preview", action, argument, generation,
            current, action === "locale-set" ? argument.slice(5) : argument, detail].join("\t")
            + "\ncomplete\tregional-preview\n";
    }
    function observationHeader(command) { return command + "-protocol\t1\t0\n"; }
    function observationComplete(command) { return "complete\t" + command + "\n"; }
    function observationRow(command) {
        return command === "time-status" ? "time\tEtc/UTC\tyes\tno\tyes\n" : "sample\tyes\tno\n";
    }
    function observationStream(command) {
        return observationHeader(command) + observationRow(command) + observationComplete(command);
    }
    function observationValue(command) {
        return command === "time-status"
            ? { timezone: "Etc/UTC", canNtp: true, ntpEnabled: false, synchronized: true }
            : { canNtp: true, synchronized: false };
    }
    function parse(command, selection, argument, text, code, normal) {
        const parser = Protocol.create(command, selection, argument);
        return Protocol.consume(parser, bytes(text)) && Protocol.finish(parser, code, normal !== false);
    }
    function exactChoices(kind, values) {
        const parser = Protocol.create("regional-choices", kind, "");
        verify(Protocol.consume(parser, bytes(choicesStream(kind, values)))
            && Protocol.finish(parser, 0, true), kind + " catalog completion");
        compare(JSON.stringify(parser.choices), JSON.stringify(values), kind + " exact catalog identities and order");
    }
    // Euro sign (U+20AC) followed by U+1F600 GRINNING FACE, encoded via
    // codepoints rather than literal characters or \u escapes in this file.
    function wideDetail() {
        return "LC_TIME=" + String.fromCodePoint(0x20ac, 0x1f600) + ", LANGUAGE=en:de";
    }

    function test_choices_round_trip_and_empty_catalog() {
        for (const kind of ["timezone", "locale"]) {
            const values = kind === "timezone" ? ["America/Chicago", "Etc/UTC"] : ["C", "en_US.utf8"];
            exactChoices(kind, values);
            exactChoices(kind, []);
        }
    }

    function test_choices_rejects_malformed_streams() {
        for (const kind of ["timezone", "locale"]) {
            const values = kind === "timezone" ? ["America/Chicago", "Etc/UTC"] : ["C", "en_US.utf8"];
            const good = choicesStream(kind, values);
            const bad = [good.slice(0, -1), good + "\n", good + "complete\tregional-choices\n",
                good.replace("\t1\t0", "\t1\t1"), good.replace("\t1\t0", "\t2\t0"),
                good.replace("choice\t", "unknown\t"), good.replace("choice\t", "choice\textra\t"),
                good.replace("complete\tregional-choices", "complete\tregional-preview"),
                choicesStream(kind, [values[0], values[0]]), choicesStream(kind, values.slice().reverse()),
                choicesStream(kind, [""]), choicesStream(kind, ["bad\rvalue"]),
                choicesStream(kind, ["bad" + String.fromCharCode(0) + "value"]),
                choicesStream(kind, [String.fromCharCode(0xe9)]),
                good.replace("choice\t", "error\tregional\tinternal\tbad\nchoice\t")];
            for (const text of bad) verify(!parse("regional-choices", kind, "", text, 0), kind + " invalid catalog: " + text);
        }
    }

    function test_choices_rejects_wrong_exit_code_and_crash() {
        for (const kind of ["timezone", "locale"]) {
            const good = choicesStream(kind, ["C", "en_US.utf8"]);
            verify(!parse("regional-choices", kind, "", good, 1), kind + " wrong catalog exit");
            verify(!parse("regional-choices", kind, "", good, 0, false), kind + " crashed catalog");
        }
    }

    function test_choices_enforces_count_limit() {
        for (const kind of ["timezone", "locale"]) {
            const count = kind === "timezone" ? 2048 : 4096;
            const maximum = Array.from({length: count}, (_, i) => "Z" + String(i).padStart(4, "0"));
            verify(parse("regional-choices", kind, "", choicesStream(kind, maximum), 0), kind + " maximum count");
            maximum.push("Z9999");
            verify(!parse("regional-choices", kind, "", choicesStream(kind, maximum), 0), kind + " count overflow");
        }
    }

    function test_choices_enforces_identity_length_limit() {
        for (const kind of ["timezone", "locale"]) {
            const length = kind === "timezone" ? 255 : 128;
            verify(parse("regional-choices", kind, "", choicesStream(kind, ["x".repeat(length)]), 0), kind + " maximum identity");
            verify(!parse("regional-choices", kind, "", choicesStream(kind, ["x".repeat(length + 1)]), 0), kind + " identity overflow");
        }
    }

    function test_timezone_rejects_unsafe_segments() {
        for (const value of ["/Etc/UTC", "Etc//UTC", "Etc/../UTC", "Etc/./UTC", "Etc/UTC/"])
            verify(!parse("regional-choices", "timezone", "", choicesStream("timezone", [value]), 0), "unsafe timezone: " + value);
    }

    function test_locale_rejects_whitespace() {
        verify(!parse("regional-choices", "locale", "", choicesStream("locale", ["en US"]), 0), "locale whitespace");
    }

    function test_choices_enforces_timezone_payload_byte_limit() {
        const maximumBytes = Array.from({length: 2048}, (_, i) => String(i).padStart(4, "0") + "x".repeat(124));
        verify(parse("regional-choices", "timezone", "", choicesStream("timezone", maximumBytes), 0), "timezone payload at limit");
        maximumBytes[2047] += "x";
        verify(!parse("regional-choices", "timezone", "", choicesStream("timezone", maximumBytes), 0), "timezone payload overflow");
    }

    function test_preview_round_trip_across_every_utf8_split() {
        for (const request of [["timezone-set", "Etc/UTC", "America/Chicago"],
                ["ntp-set", "enabled", "disabled"], ["locale-set", "LANG=en_US.utf8", "C"]]) {
            const action = request[0], argument = request[1];
            const good = previewStream(action, argument, request[2], wideDetail());
            const all = bytes(good);
            for (let split = 0; split <= all.byteLength; split++) {
                const parser = Protocol.create("regional-preview", action, argument);
                verify(Protocol.consume(parser, all.slice(0, split)) && Protocol.consume(parser, all)
                    && Protocol.finish(parser, 0, true), action + " every UTF-8 split: " + split + " " + parser.failure);
                compare(parser.preview.detail, wideDetail(), action + " full detail retained");
            }
        }
    }

    function test_preview_rejects_malformed_streams() {
        for (const request of [["timezone-set", "Etc/UTC", "America/Chicago"],
                ["ntp-set", "enabled", "disabled"], ["locale-set", "LANG=en_US.utf8", "C"]]) {
            const action = request[0], argument = request[1];
            const good = previewStream(action, argument, request[2], wideDetail());
            for (const text of [good.replace(generation, "A".repeat(64)), good.replace(generation, "a".repeat(63)),
                    good.replace("preview\t" + action, "preview\tntp-unknown"), good.replace("\t" + argument + "\t", "\twrong\t"),
                    good.replace("\t" + (action === "locale-set" ? argument.slice(5) : argument) + "\tLC_TIME", "\twrong\tLC_TIME"),
                    good.replace("\ncomplete", "\textra\ncomplete"), good.slice(0, -1), good + good,
                    good.replace("preview\t", "error\tregional\tinternal\tfailure\npreview\t")])
                verify(!parse("regional-preview", action, argument, text, 0), action + " invalid preview");
        }
    }

    function test_preview_rejects_wrong_exit_code() {
        for (const request of [["timezone-set", "Etc/UTC", "America/Chicago"],
                ["ntp-set", "enabled", "disabled"], ["locale-set", "LANG=en_US.utf8", "C"]]) {
            const action = request[0], argument = request[1];
            const good = previewStream(action, argument, request[2], "detail");
            for (const code of [1, 2, -1]) verify(!parse("regional-preview", action, argument, good, code), action + " preview exit mismatch: " + code);
        }
    }

    function test_preview_rejects_unsafe_detail_text() {
        // DEL, NEL, right-to-left override, line separator, no-break space:
        // each built from a codepoint, never a literal character in this file.
        const unsafe = ["x".repeat(513), String.fromCodePoint(0x20ac).repeat(171),
            String.fromCharCode(0x7f), String.fromCharCode(0x85), String.fromCharCode(0x202e),
            String.fromCharCode(0x2028), String.fromCharCode(0xa0)];
        for (const request of [["timezone-set", "Etc/UTC", "America/Chicago"],
                ["ntp-set", "enabled", "disabled"], ["locale-set", "LANG=en_US.utf8", "C"]]) {
            const action = request[0], argument = request[1];
            for (const detail of unsafe)
                verify(!parse("regional-preview", action, argument, previewStream(action, argument, request[2], detail), 0),
                    action + " unsafe detail: " + detail.codePointAt(0) + "/" + detail.length);
        }
    }

    function test_preview_accepts_detail_at_byte_limit() {
        const atLimit = String.fromCodePoint(0x20ac).repeat(170) + "ab";
        for (const request of [["timezone-set", "Etc/UTC", "America/Chicago"],
                ["ntp-set", "enabled", "disabled"], ["locale-set", "LANG=en_US.utf8", "C"]]) {
            const action = request[0], argument = request[1];
            verify(parse("regional-preview", action, argument,
                previewStream(action, argument, request[2], atLimit), 0), action + " 512 UTF-8 bytes");
        }
    }

    function test_preview_typed_error_codes() {
        const header = "regional-preview-protocol\t1\t0\n";
        for (const code of ["network", "repository", "conflict", "signature", "package", "unsupported", "malformed",
                "missing-provider", "permission-denied", "canceled", "timeout", "interrupted", "internal"]) {
            const error = header + "error\tregional\t" + code + "\tNot available\ncomplete\tregional-preview\n";
            verify(parse("regional-preview", "ntp-set", "invalid selection", error, 1), "typed recognized-request error: " + code);
            verify(!parse("regional-preview", "ntp-set", "enabled", error, 0), "error cannot succeed: " + code);
            verify(!parse("regional-preview", "ntp-set", "enabled", error.replace("\tregional\t", "\tupdates\t"), 1), "wrong error owner: " + code);
        }
    }

    function test_observation_round_trip_across_every_split() {
        for (const command of ["time-status", "ntp-sample"]) {
            const good = observationStream(command);
            const all = bytes(good);
            for (let split = 0; split <= all.byteLength; split++) {
                const parser = Protocol.create(command, "", "");
                verify(Protocol.consume(parser, all.slice(0, split)) && Protocol.consume(parser, all)
                    && Protocol.finish(parser, 0, true), command + " every observation split: " + split);
                compare(JSON.stringify(parser.observation), JSON.stringify(observationValue(command)), command + " exact observation");
            }
        }
    }

    function test_observation_boolean_combinations() {
        for (const command of ["time-status", "ntp-sample"]) {
            const time = command === "time-status";
            const fieldCount = time ? 3 : 2;
            for (let bits = 0; bits < (1 << fieldCount); bits++) {
                const values = Array.from({length: fieldCount}, (_, i) => bits & (1 << i) ? "yes" : "no");
                const row = (time ? "time\tEtc/UTC\t" : "sample\t") + values.join("\t") + "\n";
                verify(parse(command, "", "", observationHeader(command) + row + observationComplete(command), 0),
                    command + " every boolean combination: " + values.join(","));
            }
        }
    }

    function test_observation_rejects_malformed_streams() {
        for (const command of ["time-status", "ntp-sample"]) {
            const time = command === "time-status";
            const good = observationStream(command);
            const row = observationRow(command);
            const error = "error\t" + command + "\tinternal\tNot available\n";
            const bad = [good.slice(0, -1), good + "\n", good + observationComplete(command),
                good.replace("\t1\t0", "\t1\t1"), good.replace("\t1\t0", "\t2\t0"),
                observationHeader(command) + observationComplete(command),
                observationHeader(command) + row + row + observationComplete(command),
                observationHeader(command) + row + error + observationComplete(command),
                observationHeader(command) + error + row + observationComplete(command),
                good.replace("yes", "true"), good.replace("no", "0"),
                good.replace(row, row.slice(0, -1) + "\textra\n"),
                good.replace(row, "choice\tEtc/UTC\n"),
                good.replace(row, "preview\tntp-set\tenabled\t" + generation + "\tdisabled\tenabled\tdetail\n"),
                good.replace(row, time ? "sample\tyes\tno\n" : "time\tEtc/UTC\tyes\tno\tyes\n"),
                good.replace(observationComplete(command), "complete\tregional-preview\n")];
            for (const text of bad) verify(!parse(command, "", "", text, 0), command + " invalid observation: " + text);
        }
    }

    function test_observation_rejects_wrong_exit_code_and_crash() {
        for (const command of ["time-status", "ntp-sample"]) {
            const good = observationStream(command);
            for (const code of [1, 2, -1]) verify(!parse(command, "", "", good, code), command + " observation exit mismatch: " + code);
            verify(!parse(command, "", "", good, 0, false), command + " crashed observation");
        }
    }

    function test_observation_typed_error_codes() {
        for (const command of ["time-status", "ntp-sample"]) {
            const header = observationHeader(command);
            const complete = observationComplete(command);
            const error = "error\t" + command + "\tinternal\tNot available\n";
            for (const code of ["missing-provider", "permission-denied", "unsupported", "timeout", "malformed", "internal"]) {
                const failed = header + error.replace("internal", code) + complete;
                verify(parse(command, "", "", failed, 1), command + " typed observation error: " + code);
                verify(!parse(command, "", "", failed, 0), command + " observation error cannot succeed: " + code);
            }
            for (const code of ["network", "interrupted", "canceled", "unknown"])
                verify(!parse(command, "", "", header + error.replace("internal", code) + complete, 1), command + " closed observation error code: " + code);
            verify(!parse(command, "", "", header + error.replace(command, "regional") + complete, 1), command + " wrong observation error owner");
            verify(!parse(command, "", "", header + error + error + complete, 1), command + " duplicate observation error");
        }
    }

    function test_observation_rejects_unsafe_detail_text() {
        for (const command of ["time-status", "ntp-sample"]) {
            const header = observationHeader(command);
            const complete = observationComplete(command);
            const error = "error\t" + command + "\tinternal\tNot available\n";
            for (const value of ["x".repeat(513), String.fromCodePoint(0x20ac).repeat(171), "bad" + String.fromCharCode(0x202e)])
                verify(!parse(command, "", "", header + error.replace("Not available", value) + complete, 1),
                    command + " bounded canonical observation detail: " + value.length);
        }
    }

    function test_observation_accepts_detail_at_byte_limit() {
        for (const command of ["time-status", "ntp-sample"]) {
            const header = observationHeader(command);
            const complete = observationComplete(command);
            const error = "error\t" + command + "\tinternal\tNot available\n";
            const atLimit = String.fromCodePoint(0x20ac).repeat(170) + "ab";
            verify(parse(command, "", "", header + error.replace("Not available", atLimit) + complete, 1),
                command + " 512-byte observation detail");
        }
    }

    function test_observation_invalid_request_grammar_rejected() {
        for (const command of ["time-status", "ntp-sample"])
            for (const request of [[command, "timezone", ""], [command, "", "extra"], [command, null, ""], [command, "", null]])
                verify(!!Protocol.create(...request).failure, command + " no observation arguments: " + JSON.stringify(request));
    }

    function test_observation_stream_limit() {
        for (const command of ["time-status", "ntp-sample"]) {
            const bounded = Protocol.create(command, "", "");
            verify(bounded.limit === 1024 && !Protocol.consume(bounded, new ArrayBuffer(1025)), command + " observation stream limit");
        }
    }

    function test_time_status_rejects_invalid_timezone() {
        const good = observationStream("time-status");
        for (const value of ["", "../UTC", "Etc//UTC", "x".repeat(256), String.fromCodePoint(0xe9)])
            verify(!parse("time-status", "", "", good.replace("Etc/UTC", value), 0), "invalid observed timezone: " + value);
    }

    function test_invalid_utf8_sequences_rejected() {
        for (const invalid of [[0xc0, 0x80], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xe2, 0x28, 0xa1], [0x80]]) {
            const parser = Protocol.create("regional-preview", "ntp-set", "enabled");
            verify(!Protocol.consume(parser, new Uint8Array(invalid).buffer), "invalid UTF-8: " + invalid.join(","));
        }
    }

    function test_truncated_utf8_rejected() {
        const truncated = Protocol.create("regional-preview", "ntp-set", "enabled");
        verify(Protocol.consume(truncated, new Uint8Array([0xe2]).buffer) && !Protocol.finish(truncated, 0, true), "truncated UTF-8");
    }

    function test_replaced_prefix_rejected() {
        const header = "regional-preview-protocol\t1\t0\n";
        const parser = Protocol.create("regional-preview", "ntp-set", "enabled");
        verify(Protocol.consume(parser, bytes(header)), "partial header");
        verify(!Protocol.consume(parser, bytes(header.replace("1", "2"))), "replaced same-length prefix");
    }

    function test_shrunk_collector_rejected() {
        const header = "regional-preview-protocol\t1\t0\n";
        const shrink = Protocol.create("regional-preview", "ntp-set", "enabled");
        verify(Protocol.consume(shrink, bytes(header)) && !Protocol.consume(shrink, bytes("short")), "shrunk collector");
    }

    // Sync Sprint 1 S1-08 (#274): a reused StdioCollector can deliver an
    // empty onDataChanged buffer when its underlying Process restarts,
    // before any real bytes arrive -- found via the real
    // SystemRegionalPreflightOwner.qml integration harness (this repo's own
    // coverage, not ported from upstream), where new Uint8Array() on that
    // exact empty-buffer object threw in this Qt/QML JS engine. A "0 new
    // bytes" delivery must be a no-op, not a crash or a rejection.
    function test_empty_buffer_is_a_no_op() {
        const fresh = Protocol.create("regional-choices", "timezone", "");
        verify(Protocol.consume(fresh, new ArrayBuffer(0)), "empty buffer on a fresh parser is a no-op");
        compare(fresh.offset, 0, "empty buffer does not advance a fresh parser");
        verify(!fresh.header, "empty buffer parses no header");

        const values = ["America/Chicago", "Etc/UTC"];
        const stream = choicesStream("timezone", values);
        const all = bytes(stream);
        const midway = Protocol.create("regional-choices", "timezone", "");
        verify(Protocol.consume(midway, all.slice(0, 10)), "partial stream consumed");
        const offsetBefore = midway.offset;
        verify(Protocol.consume(midway, all.slice(0, 10)), "empty-equivalent (same-length) redelivery is still accepted");
        compare(midway.offset, offsetBefore, "redelivering the same prefix does not advance past it again");
        verify(Protocol.consume(midway, all) && Protocol.finish(midway, 0, true), "stream still completes normally");
        compare(JSON.stringify(midway.choices), JSON.stringify(values), "exact catalog after an empty-buffer-adjacent read");
    }

    function test_invalid_request_grammar_rejected() {
        for (const request of [["unknown", "timezone", ""], ["regional-choices", "unknown", ""],
                ["regional-choices", "locale", "extra"], ["regional-preview", "unknown", ""], ["regional-preview", "ntp-set", null]])
            verify(!!Protocol.create(...request).failure, "invalid request: " + JSON.stringify(request));
    }

    function test_whole_stream_overflow_rejected() {
        for (const request of [["regional-choices", "timezone", ""], ["regional-choices", "locale", ""], ["regional-preview", "ntp-set", "enabled"]]) {
            const bounded = Protocol.create(...request);
            verify(!Protocol.consume(bounded, new ArrayBuffer(bounded.limit + 1)), "whole stream overflow: " + JSON.stringify(request));
        }
    }

    function test_finish_is_single_use() {
        const ended = Protocol.create("regional-choices", "locale", "");
        verify(Protocol.consume(ended, bytes(choicesStream("locale", []))) && Protocol.finish(ended, 0, true), "finish once");
        verify(!Protocol.finish(ended, 0, true), "duplicate finish");
    }
}
