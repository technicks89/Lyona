import QtQuick
import QtTest
import "../../config/quickshell/systemmanagement/SystemInformationProtocol.js" as Information

/*
 * Direct, non-UI tests for the pure information/storage/security protocol
 * library (Sync Sprint 2 S2-05, docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md).
 * Protocol.js is plain functions with no QML dependency -- test it directly,
 * matching tst_system_regional_preflight_protocol.qml's own precedent for
 * testing a pure library this way rather than only through
 * SystemManagementModel.qml.
 *
 * Upstream never had a dedicated test file for SystemInformationProtocol.js
 * (its own coverage lives entirely inside SystemManagementModel.qml's own
 * protocol-parsing tests, which Lyona exercises through the xvfb integration
 * suite -- tests/test-quickshell-system-management-xvfb.sh). This file is a
 * Lyona-specific addition, per the sprint document's own suggestion, and
 * exists mainly to pin down D-5's adaptation: Lyona's securityIds() carries
 * 7 identifiers (selinux, secure-boot, firewalld, ufw, nftables,
 * root-encryption, screen-lock), not upstream's 5 (no separate ufw/nftables).
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "SystemInformationProtocol"

    function row(overrides) {
        const base = { id: "12", status: "available", source: "/dev/test", target: "/",
            fstype: "ext4", sizeBytes: "1000", usedBytes: "200", availableBytes: "800", detail: "Detail" };
        const merged = Object.assign({}, base, overrides || {});
        return ["filesystem", merged.id, merged.status, merged.source, merged.target, merged.fstype,
            merged.sizeBytes, merged.usedBytes, merged.availableBytes, merged.detail];
    }

    function test_information_ids_are_exactly_the_local_reader_fields() {
        compare(Information.informationIds().length, 13);
        compare(Information.informationIds().indexOf("os-name") >= 0, true);
        compare(Information.informationIds().indexOf("hardware-model") >= 0, true);
        compare(Information.informationIds().indexOf("uptime-seconds") >= 0, true);
    }

    function test_security_ids_carry_lyona_d5_firewall_split() {
        // D-5: firewalld/ufw/nftables are three distinct identifiers here,
        // not upstream's single "firewalld".
        const ids = Information.securityIds();
        compare(ids.length, 7);
        for (const expected of ["selinux", "secure-boot", "firewalld", "ufw", "nftables",
                "root-encryption", "screen-lock"]) {
            verify(ids.indexOf(expected) >= 0, expected + " missing from securityIds()");
        }
    }

    function test_state_ids_is_information_plus_filesystem_summary_plus_security() {
        const ids = Information.stateIds();
        // 13 information + 1 filesystem-summary + 7 security (D-5) = 21,
        // matching INFORMATION_LOCAL_IDS/HARDWARE_INFORMATION_FIELDS/
        // INFORMATION_SECURITY_IDS's combined size on the Python side and
        // InformationSnapshotTests's 21-state assertion on the QML side.
        compare(ids.length, 21);
        compare(ids.indexOf("filesystem-summary") >= 0, true);
        for (const identifier of Information.informationIds()) verify(ids.indexOf(identifier) >= 0, identifier);
        for (const identifier of Information.securityIds()) verify(ids.indexOf(identifier) >= 0, identifier);
    }

    function test_owners_is_the_fixed_four_information_domains() {
        compare(JSON.stringify(Information.owners()), JSON.stringify(["information", "storage", "security", "diagnostics"]));
    }

    function test_owner_routes_every_identifier_to_its_single_domain() {
        for (const identifier of Information.informationIds()) compare(Information.owner(identifier), "information", identifier);
        for (const identifier of Information.securityIds()) compare(Information.owner(identifier), "security", identifier);
        compare(Information.owner("filesystem-summary"), "storage");
        compare(Information.owner("timezone"), "", "a native (regional) identifier is not an information one");
        compare(Information.owner("health-open"), "", "an action identifier, not a state identifier");
        compare(Information.owner(""), "");
    }

    function test_provider_class_matches_read_only_owners_and_diagnostics() {
        compare(Information.providerClass("diagnostics"), "user-session");
        compare(Information.providerClass("information"), "read-only");
        compare(Information.providerClass("storage"), "read-only");
        compare(Information.providerClass("security"), "read-only");
        // Native (non-information) owners fall back to delegated -- the same
        // dispatcher SystemManagementModel.qml's parser now calls for every
        // provider record, native or information.
        compare(Information.providerClass("regional"), "delegated");
        compare(Information.providerClass("accounts"), "delegated");
        compare(Information.providerClass("printers"), "delegated");
        compare(Information.providerClass("sources"), "delegated");
    }

    function test_uint64_accepts_only_canonical_decimal_within_range() {
        verify(Information.uint64("0"));
        verify(Information.uint64("1"));
        verify(Information.uint64("18446744073709551615"), "exact uint64 maximum");
        verify(!Information.uint64("18446744073709551616"), "one past uint64 maximum");
        verify(!Information.uint64("99999999999999999999"), "20 digits but over maximum");
        verify(!Information.uint64("01"), "leading zero");
        verify(!Information.uint64("-1"), "negative");
        verify(!Information.uint64("1.0"), "non-integer");
        verify(!Information.uint64(""), "empty");
        verify(!Information.uint64(" 1"), "leading whitespace");
        verify(!Information.uint64("1 "), "trailing whitespace");
        verify(!Information.uint64(null));
        verify(!Information.uint64(undefined));
        verify(!Information.uint64(1), "a number, not a string, is never valid");
    }

    function test_valid_value_requires_unknown_for_every_non_available_status() {
        for (const identifier of Information.stateIds()) {
            for (const status of ["partial", "restricted", "unavailable", "unsupported"]) {
                verify(Information.validValue(identifier, status, "unknown"), identifier + "/" + status + "/unknown");
                verify(!Information.validValue(identifier, status, "enabled"), identifier + "/" + status + "/enabled");
            }
        }
    }

    function test_valid_value_bounds_filesystem_summary_and_cpu_and_memory_counters() {
        verify(Information.validValue("filesystem-summary", "available", "0"));
        verify(Information.validValue("filesystem-summary", "available", "256"));
        verify(!Information.validValue("filesystem-summary", "available", "257"), "exceeds FILESYSTEM_RECORDS");
        for (const identifier of ["memory-total-bytes", "memory-available-bytes", "swap-total-bytes",
                "swap-free-bytes", "uptime-seconds"]) {
            verify(Information.validValue(identifier, "available", "0"), identifier + " zero is a legitimate reading");
            verify(Information.validValue(identifier, "available", "18446744073709551615"), identifier + " uint64 max");
            verify(!Information.validValue(identifier, "available", "-1"), identifier + " negative");
        }
        // logical-cpus is the one exception: zero logical processors is
        // never a legitimate reading, unlike every other uint64 counter.
        verify(Information.validValue("logical-cpus", "available", "1"));
        verify(!Information.validValue("logical-cpus", "available", "0"));
    }

    function test_valid_value_enumerates_selinux_and_root_encryption() {
        for (const value of ["enforcing", "permissive", "disabled"]) verify(Information.validValue("selinux", "available", value), value);
        verify(!Information.validValue("selinux", "available", "unknown"));
        verify(!Information.validValue("selinux", "available", "enabled"));
        for (const value of ["encrypted", "unencrypted"]) verify(Information.validValue("root-encryption", "available", value), value);
        verify(!Information.validValue("root-encryption", "available", "enabled"));
    }

    function test_valid_value_security_ids_share_the_generic_enabled_disabled_check() {
        // D-5: firewalld/ufw/nftables/secure-boot/screen-lock all take the
        // same generic branch selinux and root-encryption bypass above.
        for (const identifier of ["secure-boot", "firewalld", "ufw", "nftables", "screen-lock"]) {
            verify(Information.validValue(identifier, "available", "enabled"), identifier + " enabled");
            verify(Information.validValue(identifier, "available", "disabled"), identifier + " disabled");
            verify(!Information.validValue(identifier, "available", "yes"), identifier + " yes is not a valid value");
            verify(!Information.validValue(identifier, "available", "unknown"), identifier + " unknown only valid when not available");
        }
    }

    function test_valid_value_information_identifiers_accept_any_nonempty_trimmed_string() {
        for (const identifier of ["os-name", "os-version", "kernel-release", "architecture",
                "hardware-vendor", "hardware-model", "cpu-model"]) {
            verify(Information.validValue(identifier, "available", "Arch Linux"), identifier);
            verify(!Information.validValue(identifier, "available", ""), identifier + " empty");
            verify(!Information.validValue(identifier, "available", "   "), identifier + " whitespace-only");
        }
    }

    function test_valid_filesystem_requires_complete_available_row() {
        verify(Information.validFilesystem(row()));
        verify(!Information.validFilesystem(row({ id: "abc" })), "non-numeric id");
        verify(!Information.validFilesystem(row({ id: "-1" })), "negative id");
        verify(!Information.validFilesystem(row({ status: "unavailable" })), "unavailable is not a filesystem row status");
        verify(!Information.validFilesystem(row({ source: "" })), "empty source");
        verify(!Information.validFilesystem(row({ target: "" })), "empty target");
        verify(!Information.validFilesystem(row({ fstype: "" })), "empty fstype");
        verify(!Information.validFilesystem(row({ sizeBytes: "-1" })), "negative size");
        verify(!Information.validFilesystem(row({ sizeBytes: "unknown" })), "unknown counters require partial status");
    }

    function test_valid_filesystem_partial_requires_at_least_one_unknown_counter() {
        verify(Information.validFilesystem(row({ status: "partial", sizeBytes: "unknown" })));
        verify(Information.validFilesystem(row({ status: "partial", usedBytes: "unknown", availableBytes: "unknown" })));
        // A "partial" row with every counter still numeric is not actually
        // partial about anything -- reject it the same as upstream's own
        // parser does server-side.
        verify(!Information.validFilesystem(row({ status: "partial" })), "partial with no unknown counter");
    }

    function test_filesystem_maps_fields_positionally() {
        const parsed = Information.filesystem(row({ id: "40", source: "/dev/nvme0n1p3[/@]", target: "/",
            fstype: "btrfs", sizeBytes: "999129026560", usedBytes: "38070935552",
            availableBytes: "955855282176", detail: "Filesystem bytes at this read" }));
        compare(parsed.id, "40");
        compare(parsed.status, "available");
        compare(parsed.source, "/dev/nvme0n1p3[/@]");
        compare(parsed.target, "/");
        compare(parsed.fstype, "btrfs");
        compare(parsed.sizeBytes, "999129026560");
        compare(parsed.usedBytes, "38070935552");
        compare(parsed.availableBytes, "955855282176");
        compare(parsed.detail, "Filesystem bytes at this read");
    }
}
