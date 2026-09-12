#!/usr/bin/python3
"""Contract tests for the bounded, read-only update snapshot and discovery.

Sync Phase 2 (docs/SYNC-P2-UPDATE-SNAPSHOT.md). Ported from upstream's
tests/test-system-management.py at PR #208 (bd87fd3c) and retargeted:
Fedora/RPM cases dropped (this provider never had them — see the phase
document's "Correction, found during implementation" note), plus new
coverage for the Arch-only restart heuristic. Sync Phase 4
(docs/SYNC-P4-DISCOVERY-EVENTS.md) adds UpdateEventMonitorTests, ported
from upstream's `a30f5fed` (#238) nearly unchanged — the monitor is
distro-neutral (it never touches PackageKit's alpm-vs-dnf backend, only
the manager's own D-Bus signals).
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import importlib.machinery
import io
import pathlib
import shutil
import subprocess
import sys
import time
import unittest
from unittest import mock


REPO = pathlib.Path(__file__).resolve().parent.parent
PROVIDER_PATH = REPO / "scripts" / "dwm-system-management"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_loader(
    "dwm_system_management",
    importlib.machinery.SourceFileLoader("dwm_system_management", str(PROVIDER_PATH)),
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load dwm-system-management")
provider = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = provider
SPEC.loader.exec_module(provider)


class FixtureBackend:
    def __init__(
        self,
        *,
        refresh_age=42,
        updates=(),
        restart_types=(),
        plan=(),
        refresh_failure=None,
        updates_failure=None,
        plan_failure=None,
    ):
        self.refresh_age = refresh_age
        self.update_records = tuple(updates)
        self.restart_types = tuple(restart_types)
        self.plan_records = tuple(plan)
        self.refresh_failure = refresh_failure
        self.updates_failure = updates_failure
        self.plan_failure = plan_failure
        self.simulated_ids = None

    def last_refresh_age(self):
        if self.refresh_failure:
            raise self.refresh_failure
        return self.refresh_age

    def updates(self):
        if self.updates_failure:
            raise self.updates_failure
        return provider.TransactionResult(self.update_records, self.restart_types)

    def simulate(self, package_ids):
        self.simulated_ids = tuple(package_ids)
        if self.plan_failure:
            raise self.plan_failure
        return provider.TransactionResult(self.plan_records)


def package(info, package_id, summary):
    return provider.Package(info, package_id, summary)


def rows(lines, kind):
    return [line.split("\t") for line in lines if line.startswith(f"{kind}\t")]


class UpdateEventMonitorTests(unittest.TestCase):
    def monitor(self):
        class BusError(Exception):
            pass

        glib = mock.Mock(Error=BusError, SOURCE_REMOVE=False, SOURCE_CONTINUE=True,
            PRIORITY_DEFAULT=0)
        gio = mock.Mock()
        unix = mock.Mock()
        emitted = []
        monitor = provider.UpdateEventMonitor(gio, glib, unix, emitted.append)
        monitor.deadline = time.monotonic() + 10
        monitor.deadline_source = 7
        monitor.match_rules = ["fixture"]
        monitor.connection = mock.Mock()
        return monitor, emitted, gio, glib, unix

    def test_subscriptions_are_fixed_and_setup_never_calls_packagekit(self):
        monitor, emitted, gio, _glib, _unix = self.monitor()
        monitor.match_rules = []
        connection = gio.bus_get_finish.return_value
        monitor.connected(None, object(), None)
        calls = connection.signal_subscribe.call_args_list
        self.assertEqual([call.args[:4] for call in calls], [
            (None, provider.PACKAGEKIT_INTERFACE, member, provider.PACKAGEKIT_PATH)
            for member in ("UpdatesChanged", "InstalledChanged", "RepoListChanged")
        ] + [("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus")])
        self.assertEqual(calls[-1].args[4], provider.PACKAGEKIT_NAME)
        self.assertEqual(connection.call.call_args.args[:4],
            ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch"))
        self.assertTrue(all(call.args[5] == gio.DBusSignalFlags.NO_MATCH_RULE for call in calls))
        self.assertEqual(len(monitor.match_rules), 4)
        self.assertEqual(emitted, [])

    def test_setup_events_coalesce_and_ready_precedes_pending_invalidation(self):
        monitor, emitted, _gio, glib, _unix = self.monitor()
        for _ in range(1000):
            monitor.changed()
        self.assertEqual(emitted, [])
        monitor.match_finished(mock.Mock(), object(), "fixture")
        self.assertEqual(emitted, [])
        connection = mock.Mock()
        connection.call_finish.return_value.unpack.return_value = (":1.2",)
        monitor.owner_resolved(connection, object(), 0)
        self.assertEqual(emitted, ["update-event\tready", "update-event\tchanged"])
        glib.source_remove.assert_called_once_with(7)
        self.assertFalse(monitor.dirty)
        self.assertEqual(monitor.deadline_source, 0)
        monitor.changed()
        self.assertEqual(len(emitted), 3)

    def test_readiness_requires_all_four_successful_match_replies(self):
        monitor, emitted, gio, _glib, _unix = self.monitor()
        monitor.match_rules = []
        monitor.connected(None, object(), None)
        connection = gio.bus_get_finish.return_value
        for index, rule in enumerate(monitor.match_rules):
            self.assertEqual(emitted, [])
            monitor.changed()
            monitor.match_finished(connection, object(), rule)
            self.assertEqual(len(monitor.installed_rules), index + 1)
        self.assertEqual(connection.call.call_count, 5)
        self.assertEqual(connection.call.call_args.args[3], "GetNameOwner")
        self.assertEqual(emitted, [])
        connection.call_finish.return_value.unpack.return_value = (":1.2",)
        monitor.owner_resolved(connection, object(), 0)
        self.assertEqual(emitted, ["update-event\tready", "update-event\tchanged"])

    def test_denied_match_after_partial_setup_never_reports_ready(self):
        monitor, emitted, gio, glib, _unix = self.monitor()
        monitor.match_rules = []
        monitor.connected(None, object(), None)
        connection = gio.bus_get_finish.return_value
        monitor.match_finished(connection, object(), monitor.match_rules[0])
        connection.call_finish.side_effect = glib.Error("Policy denied subscription")
        monitor.match_finished(connection, object(), monitor.match_rules[1])
        self.assertTrue(monitor.stopped)
        self.assertEqual(len(monitor.installed_rules), 1)
        self.assertEqual(emitted, [])

    def test_expired_setup_and_late_callbacks_cannot_publish_ready(self):
        for callback in ("connected", "match_finished", "owner_resolved"):
            with self.subTest(callback=callback):
                monitor, emitted, gio, _glib, _unix = self.monitor()
                monitor.deadline = time.monotonic() - 1
                getattr(monitor, callback)(mock.Mock(), object(), None)
                self.assertTrue(monitor.stopped)
                self.assertEqual(monitor.exit_code, 1)
                monitor.changed()
                monitor.match_finished(mock.Mock(), object(), None)
                monitor.connected(None, object(), None)
                self.assertEqual(emitted, [])
                gio.bus_get_finish.assert_not_called()

    def test_connection_barrier_and_output_failures_stop_without_success(self):
        for stage in ("connection", "barrier", "output"):
            with self.subTest(stage=stage):
                monitor, emitted, gio, glib, _unix = self.monitor()
                connection = mock.Mock()
                if stage == "connection":
                    gio.bus_get_finish.side_effect = glib.Error("private error")
                    monitor.connected(None, object(), None)
                elif stage == "barrier":
                    connection.call_finish.side_effect = glib.Error("private error")
                    monitor.match_finished(connection, object(), "fixture")
                else:
                    monitor.emit = mock.Mock(side_effect=BrokenPipeError())
                    connection.call_finish.return_value.unpack.return_value = (":1.2",)
                    monitor.owner_resolved(connection, object(), 0)
                self.assertTrue(monitor.stopped)
                self.assertEqual(monitor.exit_code, 1)
                self.assertEqual(emitted, [])
                monitor.stop(0)
                self.assertEqual(monitor.exit_code, 1)

    def test_owner_resolution_absence_is_not_authorization_denial(self):
        for missing in (True, False):
            monitor, emitted, gio, glib, _unix = self.monitor()
            connection = mock.Mock()
            connection.call_finish.side_effect = glib.Error("Owner lookup failed")
            gio.dbus_error_get_remote_error.return_value = "org.freedesktop.DBus.Error." + (
                "NameHasNoOwner" if missing else "AccessDenied")
            monitor.owner_resolved(connection, object(), 0)
            self.assertEqual(monitor.ready, missing)
            self.assertEqual(monitor.stopped, not missing)
            self.assertEqual(emitted, ["update-event\tready"] if missing else [])

    def test_owner_notification_wins_lookup_race_and_filters_old_senders(self):
        monitor, emitted, _gio, _glib, _unix = self.monitor()
        parameters = mock.Mock()
        parameters.unpack.return_value = (provider.PACKAGEKIT_NAME, ":1.2", ":1.3")
        monitor.owner_changed(None, None, None, None, None, parameters, None)
        connection = mock.Mock()
        connection.call_finish.return_value.unpack.return_value = (":1.2",)
        monitor.owner_resolved(connection, object(), 0)
        self.assertEqual(monitor.owner, ":1.3")
        self.assertEqual(emitted, ["update-event\tready", "update-event\tchanged"])
        monitor.global_changed(None, ":1.2", None, None, None, None, None)
        self.assertEqual(len(emitted), 2)
        monitor.global_changed(None, ":1.3", None, None, None, None, None)
        self.assertEqual(len(emitted), 3)

    def test_run_cleanup_cancels_callbacks_and_removes_all_sources(self):
        monitor, _emitted, gio, glib, unix = self.monitor()
        monitor.match_rules = []
        connection = gio.bus_get_finish.return_value
        connection.signal_subscribe.side_effect = [20, 21, 22, 23]
        connection.connect.return_value = 24
        glib.timeout_add.return_value = 10
        unix.signal_add.side_effect = [11, 12, 13]
        def run():
            monitor.connected(None, object(), None)
            monitor.match_finished(connection, object(), monitor.match_rules[0])
            monitor.stop(0)
        monitor.loop.run.side_effect = run
        self.assertEqual(monitor.run(), 0)
        self.assertEqual([call.args[0] for call in connection.signal_unsubscribe.call_args_list], [20, 21, 22, 23])
        connection.disconnect.assert_called_once_with(24)
        self.assertEqual(connection.call.call_args.args[3], "RemoveMatch")
        self.assertEqual([call.args[0] for call in glib.source_remove.call_args_list], [11, 12, 13, 10])
        self.assertTrue(monitor.cancellable.cancel.called)
        self.assertEqual(gio.bus_get.call_args.args[0], gio.BusType.SYSTEM)

    def test_watch_cli_is_argument_free_and_does_not_open_the_backend(self):
        with mock.patch.object(provider, "watch_update_events", return_value=0) as watch, \
                mock.patch.object(provider, "PackageKitBackend") as backend, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(provider.main(["watch-updates"]), 0)
            for arguments in (["watch-updates", "extra"], ["watch-updates", "--system"]):
                self.assertEqual(provider.main(arguments), 2)
            watch.assert_called_once_with()
            backend.assert_not_called()

    def test_real_private_bus_signals_lifecycle_and_lost_output(self):
        if shutil.which("dbus-run-session") is None:
            self.skipTest("dbus-run-session is unavailable")
        try:
            import gi

            gi.require_version("Gio", "2.0")
        except (ImportError, ValueError):
            self.skipTest("System Python GObject bindings are unavailable")
        result = subprocess.run(["dbus-run-session", "--", "/usr/bin/python3",
            str(REPO / "tests/fixtures/system-update-events-bus.py"), str(PROVIDER_PATH)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "PackageKit private-bus event monitor: PASS\n")


class SnapshotTests(unittest.TestCase):
    def test_complete_read_only_snapshot(self):
        backend = FixtureBackend(
            updates=(
                package(26, "kernel;6.18.1;x86_64;updates", "Critical kernel"),
                package(9, "held;2.0;x86_64;updates", "Blocked update"),
                package(2, "bash;5.3;x86_64;updates", "Shell\tupdate\nsummary"),
            ),
            restart_types=(2, 5, 4),
            plan=(
                package(11, "kernel;6.18.1;x86_64;updates", "Critical kernel"),
                package(11, "bash;5.3;x86_64;updates", "Shell update"),
                package(12, "dependency;1.0;x86_64;updates", "New dependency"),
                package(15, "old-dependency;0.9;x86_64;installed", "Old dependency"),
            ),
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(output[0], "system-management-protocol\t1\t0")
        self.assertEqual(output[-1], "complete\tsnapshot")
        self.assertEqual(len(rows(output, "provider")), 2)
        self.assertEqual(len(rows(output, "state")), 3)
        self.assertEqual(len(rows(output, "action")), 3)
        self.assertEqual(len(rows(output, "update")), 3)
        self.assertEqual(len(rows(output, "package-change")), 4)
        self.assertEqual(rows(output, "error"), [])
        self.assertEqual(
            backend.simulated_ids,
            ("bash;5.3;x86_64;updates", "kernel;6.18.1;x86_64;updates"),
        )
        self.assertIn(
            [
                "state",
                "update-summary",
                "available",
                "3",
                "PackageKit update discovery completed",
            ],
            rows(output, "state"),
        )
        self.assertIn(
            [
                "state",
                "update-restart",
                "available",
                "security-system",
                "PackageKit restart guidance from update discovery",
            ],
            rows(output, "state"),
        )
        bash_row = next(
            row for row in rows(output, "update") if row[1].startswith("bash;")
        )
        self.assertEqual(bash_row[2:4], ["unknown", "installable"])
        self.assertEqual(bash_row[-1], "Shell update summary")
        self.assertEqual(
            output[1],
            "snapshot-generation\t"
            "e0aa055cc95ffda6ee74fe1af3cca0d159f4fdb431a38f9c70f46f8792162ab6",
        )

    def test_empty_snapshot_has_stable_generation_and_skips_simulation(self):
        backend = FixtureBackend()
        output = provider.build_snapshot(backend)

        expected = hashlib.sha256(b"lyona-update-plan-v1").hexdigest()
        self.assertEqual(output[1], f"snapshot-generation\t{expected}")
        self.assertEqual(backend.simulated_ids, None)
        self.assertIn(
            [
                "state",
                "update-summary",
                "available",
                "0",
                "PackageKit update discovery completed",
            ],
            rows(output, "state"),
        )

    def test_generation_changes_with_dependency_preview(self):
        update = package(8, "openssl;4.0;x86_64;updates", "TLS library")
        first = FixtureBackend(
            updates=(update,), plan=(package(11, update.package_id, "TLS library"),)
        )
        second = FixtureBackend(
            updates=(update,),
            plan=(
                package(11, update.package_id, "TLS library"),
                package(12, "crypto-policy;2;x86_64;updates", "Policy data"),
            ),
        )

        first_generation = provider.build_snapshot(first)[1]
        second_generation = provider.build_snapshot(second)[1]

        self.assertNotEqual(first_generation, second_generation)

    def test_no_refresh_history_is_explicit_without_an_error(self):
        output = provider.build_snapshot(FixtureBackend(refresh_age=provider.G_MAXUINT))

        self.assertIn(
            [
                "state",
                "update-last-refresh",
                "partial",
                "unknown",
                "PackageKit has no successful refresh history",
            ],
            rows(output, "state"),
        )
        self.assertEqual(rows(output, "error"), [])

    def test_source_failures_preserve_the_complete_protocol_shape(self):
        backend = FixtureBackend(
            refresh_failure=provider.SnapshotFailure(
                "timeout", "PackageKit refresh history timed out", "unavailable"
            ),
            updates_failure=provider.SnapshotFailure(
                "missing-provider", "PackageKit service is unavailable", "unavailable"
            ),
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(output[-1], "complete\tsnapshot")
        self.assertEqual(len(rows(output, "provider")), 2)
        self.assertEqual(len(rows(output, "state")), 3)
        self.assertEqual(len(rows(output, "action")), 3)
        self.assertEqual(rows(output, "update"), [])
        self.assertEqual(rows(output, "package-change"), [])
        self.assertEqual(
            [row[2] for row in rows(output, "error")],
            ["timeout", "missing-provider"],
        )
        install_action = next(
            row for row in rows(output, "action") if row[1] == "updates-install-all"
        )
        self.assertIn("dependency preview is unavailable", install_action[-1])

    def test_invalid_update_classification_discards_the_inventory(self):
        backend = FixtureBackend(
            updates=(package(999, "bad;1;x86_64;updates", "Invalid"),)
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(rows(output, "update"), [])
        self.assertIn(
            [
                "state",
                "update-summary",
                "partial",
                "unknown",
                "PackageKit returned an unsupported update classification",
            ],
            rows(output, "state"),
        )
        self.assertEqual(rows(output, "error")[0][2], "malformed")


class JournalFrameTests(unittest.TestCase):
    def frame_with_header(self, frame, *, offset, value):
        changed = bytearray(frame)
        changed[offset : offset + len(value)] = value
        length = int.from_bytes(changed[12:16], "little")
        payload = changed[provider.JOURNAL_PAYLOAD_OFFSET :][:length]
        changed[32:64] = hashlib.sha256(changed[:32] + payload).digest()
        return bytes(changed)

    def test_golden_frame_layout_and_initial_image(self):
        payload = "op-0123456789abcdef0123456789abcdef\tupdate"
        frame = provider.encode_journal_frame(0x0102030405060708, payload)

        self.assertEqual(len(frame), 8192)
        self.assertEqual(frame[:8], b"DWMJNL1\0")
        self.assertEqual(frame[8:10], b"\x01\x00")
        self.assertEqual(frame[10:12], b"\x00\x00")
        self.assertEqual(
            int.from_bytes(frame[12:16], "little"), len(payload.encode("utf-8"))
        )
        self.assertEqual(frame[16:24], b"\x08\x07\x06\x05\x04\x03\x02\x01")
        self.assertEqual(frame[24:32], bytes(8))
        self.assertEqual(
            frame[32:64],
            hashlib.sha256(frame[:32] + payload.encode("utf-8")).digest(),
        )
        self.assertEqual(frame[64 : 64 + len(payload)], payload.encode("utf-8"))
        self.assertEqual(frame[64 + len(payload) :], bytes(8128 - len(payload)))
        self.assertEqual(
            provider.decode_journal_frame(frame),
            provider.JournalFrame(0x0102030405060708, payload),
        )

        initial = provider.initial_journal_image("00")
        self.assertEqual(len(initial), 16384)
        self.assertEqual(initial[8192:], bytes(8192))
        self.assertEqual(
            provider.select_journal_frame(initial),
            (0, provider.JournalFrame(1, "00")),
        )

    def test_maximum_utf8_payload_round_trips(self):
        payload = "x" * provider.JOURNAL_PAYLOAD_MAX
        frame = provider.encode_journal_frame(2, payload)

        self.assertEqual(provider.decode_journal_frame(frame).payload, payload)
        with self.assertRaisesRegex(provider.JournalFrameError, "too large"):
            provider.encode_journal_frame(2, payload + "x")

    def test_payload_and_sequence_validation(self):
        for payload in ("nul\0byte", "line\nbreak", "carriage\rreturn"):
            with self.subTest(payload=payload):
                with self.assertRaises(provider.JournalFrameError):
                    provider.encode_journal_frame(1, payload)
        with self.assertRaisesRegex(provider.JournalFrameError, "not UTF-8"):
            provider.encode_journal_frame(1, "unpaired-\udcff")
        for sequence in (0, -1, provider.JOURNAL_SEQUENCE_MAX + 1, True):
            with self.subTest(sequence=sequence):
                with self.assertRaises(provider.JournalFrameError):
                    provider.encode_journal_frame(sequence, "")

    def test_decoder_rejects_every_canonical_boundary_violation(self):
        base = provider.encode_journal_frame(4, "payload")
        cases = {
            "size": base[:-1],
            "magic": self.frame_with_header(base, offset=0, value=b"BADJNL1\0"),
            "major": self.frame_with_header(base, offset=8, value=b"\x02\x00"),
            "minor": self.frame_with_header(base, offset=10, value=b"\x01\x00"),
            "length": self.frame_with_header(
                base,
                offset=12,
                value=(provider.JOURNAL_PAYLOAD_MAX + 1).to_bytes(4, "little"),
            ),
            "sequence": self.frame_with_header(base, offset=16, value=bytes(8)),
            "reserved": self.frame_with_header(base, offset=24, value=b"\x01"),
            "digest": base[:32] + bytes(32) + base[64:],
            "padding": base[:-1] + b"\x01",
        }
        for name, image in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalFrameError):
                    provider.decode_journal_frame(image)

        invalid_utf8 = bytearray(provider.encode_journal_frame(4, "x"))
        invalid_utf8[64] = 0xFF
        invalid_utf8[32:64] = hashlib.sha256(
            invalid_utf8[:32] + invalid_utf8[64:65]
        ).digest()
        with self.assertRaisesRegex(provider.JournalFrameError, "not UTF-8"):
            provider.decode_journal_frame(bytes(invalid_utf8))

        forbidden = bytearray(provider.encode_journal_frame(4, "x"))
        forbidden[64] = 0
        forbidden[32:64] = hashlib.sha256(forbidden[:32] + forbidden[64:65]).digest()
        with self.assertRaisesRegex(provider.JournalFrameError, "forbidden"):
            provider.decode_journal_frame(bytes(forbidden))

    def test_selector_uses_highest_valid_sequence_and_survives_torn_peer(self):
        older = provider.encode_journal_frame(9, "older")
        newer = provider.encode_journal_frame(10, "newer")

        self.assertEqual(
            provider.select_journal_frame(older + newer),
            (1, provider.JournalFrame(10, "newer")),
        )
        torn = newer[:40] + bytes(provider.JOURNAL_FRAME_SIZE - 40)
        self.assertEqual(
            provider.select_journal_frame(older + torn),
            (0, provider.JournalFrame(9, "older")),
        )

    def test_selector_rejects_ambiguous_or_exhausted_files(self):
        first = provider.encode_journal_frame(7, "first")
        second = provider.encode_journal_frame(7, "second")
        exhausted = provider.encode_journal_frame(provider.JOURNAL_SEQUENCE_MAX, "")

        with self.assertRaisesRegex(provider.JournalFrameError, "conflicting"):
            provider.select_journal_frame(first + second)
        with self.assertRaisesRegex(provider.JournalFrameError, "no valid"):
            provider.select_journal_frame(bytes(provider.JOURNAL_FILE_SIZE))
        with self.assertRaisesRegex(provider.JournalFrameError, "exhausted"):
            provider.select_journal_frame(
                exhausted + bytes(provider.JOURNAL_FRAME_SIZE)
            )
        self.assertEqual(
            provider.select_journal_frame(first + first),
            (0, provider.JournalFrame(7, "first")),
        )


class SnapshotValidationTests(unittest.TestCase):
    def test_duplicate_plan_preserves_readable_updates(self):
        update = package(8, "openssl;4.0;x86_64;updates", "TLS library")
        backend = FixtureBackend(
            updates=(update,),
            plan=(
                package(11, update.package_id, "TLS library"),
                package(11, update.package_id, "Duplicate"),
            ),
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(len(rows(output, "update")), 1)
        self.assertEqual(rows(output, "package-change"), [])
        self.assertEqual(rows(output, "error")[0][2], "malformed")
        install_action = next(
            row for row in rows(output, "action") if row[1] == "updates-install-all"
        )
        self.assertIn("duplicate plan identity", install_action[-1])

    def test_plan_rejects_packagekit_intent_enums(self):
        package_id = "example;2;x86_64;updates"
        for info in (27, 28, 29, 30):
            with self.subTest(info=info):
                with self.assertRaisesRegex(
                    provider.SnapshotFailure, "unsupported plan classification"
                ):
                    provider.normalize_plan(
                        (package(info, package_id, "Intent enum"),), (package_id,)
                    )

    def test_reinstall_and_downgrade_plan_remains_visible_but_unsupported(self):
        update = package(8, "openssl;4.0;x86_64;updates", "TLS library")
        for extra_info, extra_id in (
            (19, "openssl;4.0;x86_64;installed"),
            (20, "compat-lib;1.0;x86_64;updates"),
        ):
            with self.subTest(extra_info=extra_info):
                backend = FixtureBackend(
                    updates=(update,),
                    plan=(
                        package(11, update.package_id, "TLS library"),
                        package(extra_info, extra_id, "Unsupported change"),
                    ),
                )

                output = provider.build_snapshot(backend)

                self.assertEqual(
                    {row[1] for row in rows(output, "package-change")},
                    {update.package_id, extra_id},
                )
                self.assertIn("unsupported", [row[2] for row in rows(output, "error")])
                install_action = next(
                    row
                    for row in rows(output, "action")
                    if row[1] == "updates-install-all"
                )
                self.assertIn("unsupported reinstall or downgrade", install_action[-1])

    def test_unlisted_packagekit_errors_fall_back_to_internal(self):
        backend = object.__new__(provider.PackageKitBackend)

        self.assertEqual(backend._transaction_failure(10, "download").code, "package")
        self.assertEqual(backend._transaction_failure(4, "internal").code, "internal")

    def test_blocked_updates_are_not_simulated(self):
        backend = FixtureBackend(
            updates=(package(9, "held;2.0;x86_64;updates", "Blocked"),)
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(backend.simulated_ids, None)
        self.assertEqual(rows(output, "update")[0][3], "blocked")

    def test_unsafe_or_duplicate_identities_fail_closed(self):
        cases = (
            (package(8, "bad\tid;1;x86_64;updates", "Unsafe"),),
            (
                package(8, "same;1;x86_64;updates", "First"),
                package(8, "same;1;x86_64;updates", "Second"),
            ),
        )
        for records in cases:
            with self.subTest(records=records):
                output = provider.build_snapshot(FixtureBackend(updates=records))
                self.assertEqual(rows(output, "update"), [])
                self.assertEqual(rows(output, "error")[0][2], "malformed")

    def test_restart_aggregation_rejects_unknown_values(self):
        update = package(9, "held;2.0;x86_64;updates", "Blocked")
        output = provider.build_snapshot(
            FixtureBackend(updates=(update,), restart_types=(99,))
        )

        self.assertEqual(len(rows(output, "update")), 1)
        summary = next(
            row for row in rows(output, "state") if row[1] == "update-summary"
        )
        self.assertEqual(summary[2:4], ["available", "1"])
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["partial", "unknown"])
        self.assertEqual(rows(output, "error")[0][2], "malformed")

    def test_record_count_limit_discards_the_whole_inventory(self):
        packages = tuple(
            package(2, f"pkg-{number};1;x86_64;updates", "Update")
            for number in range(provider.MAX_LIST_RECORDS + 1)
        )

        output = provider.build_snapshot(FixtureBackend(updates=packages))

        self.assertEqual(rows(output, "update"), [])
        self.assertEqual(rows(output, "error")[0][2], "malformed")

    # --- Arch-only restart heuristic (not present upstream; see the phase
    # document's discussion of section 5, "Restart requirements") ---

    def test_restart_heuristic_flags_kernel_update_as_system(self):
        output = provider.build_snapshot(
            FixtureBackend(
                updates=(
                    package(5, "linux-cachyos;6.18.1;x86_64;updates", "Kernel"),
                )
            )
        )
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["available", "system"])
        self.assertIn("heuristic", restart[-1])

    def test_restart_heuristic_flags_glibc_update_as_system(self):
        output = provider.build_snapshot(
            FixtureBackend(
                updates=(package(5, "glibc;2.42;x86_64;updates", "libc"),)
            )
        )
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["available", "system"])

    def test_restart_heuristic_reports_unknown_for_unrelated_leaf_package(self):
        output = provider.build_snapshot(
            FixtureBackend(
                updates=(package(5, "some-app;1.0;x86_64;updates", "App"),)
            )
        )
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["available", "unknown"])
        self.assertIn("heuristic", restart[-1])

    def test_restart_heuristic_does_not_override_real_backend_signals(self):
        output = provider.build_snapshot(
            FixtureBackend(
                updates=(package(5, "linux-cachyos;6.18.1;x86_64;updates", "Kernel"),),
                restart_types=(2,),
            )
        )
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["available", "application"])
        self.assertNotIn("heuristic", restart[-1])

    def test_restart_heuristic_does_not_apply_when_nothing_is_pending(self):
        output = provider.build_snapshot(FixtureBackend())
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["available", "none"])


if __name__ == "__main__":
    unittest.main()
