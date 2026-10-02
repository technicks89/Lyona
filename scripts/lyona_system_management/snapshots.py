"""The snapshots Settings reads: information, native, managed, and the combined build_snapshot."""

from __future__ import annotations

import os
from typing import Sequence

from . import (
    delegated_tools,
    operation_journal,
    packagekit,
    regional_settings,
    shared,
    system_information,
    system_services,
    update_plans,
    user_accounts,
)


SNAPSHOT_MINOR = 2
NATIVE_SNAPSHOT_MINOR = 1

INFORMATION_LOCAL_IDS = (
    "os-name", "os-version", "kernel-release", "architecture", "cpu-model",
    "logical-cpus", "memory-total-bytes", "memory-available-bytes",
    "swap-total-bytes", "swap-free-bytes", "uptime-seconds",
)
# Lyona adaptation (D-5): upstream's single "firewalld" identifier is
# generalized to the three real, distinct firewall units Arch/CachyOS can
# ship (firewalld, ufw, nftables), each surfaced through its own identifier.
INFORMATION_SECURITY_IDS = ("selinux", "secure-boot", "firewalld", "ufw", "nftables",
    "root-encryption", "screen-lock")


class InformationSnapshotSources:
    """Fixed readers, invoked only when an information snapshot is requested."""

    def __init__(self, *, storage_ready: bool = True):
        self.storage_ready = storage_ready

    def local(self):
        return system_information.read_local_information()

    def hardware(self):
        return system_information.read_hardware_information()

    def filesystems(self):
        if not self.storage_ready:
            return system_information.FilesystemInformation(system_information.InformationState("partial", "unknown",
                "Mount monitoring is not ready; reload storage status to retry", "missing-provider"))
        return system_information.read_filesystem_information()

    def security(self, identifier):
        if identifier in shared.FIREWALL_UNITS:
            return system_services.read_firewall_status(identifier)
        readers = {"selinux": system_information.read_selinux_status, "secure-boot": system_information.read_secure_boot_status,
            "root-encryption": system_information.read_root_encryption, "screen-lock": system_information.read_screen_lock}
        return readers[identifier]()


def build_information_snapshot(sources: InformationSnapshotSources) -> list[str]:
    """Assemble the closed information records without journal or action admission.

    This internal formatter deliberately does not activate a snapshot minor or
    initiate reads from startup recovery. The caller owns visible-pane readiness.
    """
    groups = {owner: {"states": [], "errors": [], "statuses": []}
              for owner in ("information", "storage", "security")}

    def state(owner, identifier, value):
        group = groups[owner]
        group["statuses"].append(value.status)
        group["states"].append("\t".join(("state", identifier, value.status,
            shared.clean_text(value.value, truncate=False), shared.clean_text(value.detail))))
        if value.error_code:
            group["errors"].append("\t".join(("error", owner, value.error_code, shared.clean_text(value.detail))))

    for read, identifiers in ((sources.local, INFORMATION_LOCAL_IDS),
            (sources.hardware, tuple(shared.HARDWARE_INFORMATION_FIELDS.values()))):
        try:
            values = read()
        except InterruptedError:
            raise
        except (OSError, shared.SnapshotFailure) as failure:
            values = dict.fromkeys(identifiers, system_information.information_unknown(failure))
        for identifier in identifiers:
            state("information", identifier, values.get(identifier, system_information.information_unknown(
                shared.SnapshotFailure("malformed", "Information reader omitted a required state"))))

    for identifier in INFORMATION_SECURITY_IDS:
        try:
            value = sources.security(identifier)
        except InterruptedError:
            raise
        except (OSError, shared.SnapshotFailure) as failure:
            value = system_information.information_unknown(failure)
        state("security", identifier, value)

    filesystem_lines = []
    try:
        filesystems = sources.filesystems()
        # Buffer the complete encoded list before publishing its summary. This
        # budget includes record prefixes, separators, and terminating newlines.
        if len(filesystems.rows) > shared.FILESYSTEM_RECORDS:
            raise shared.SnapshotFailure("malformed", "Filesystem inventory exceeds its record limit")
        seen, size = set(), 0
        for row in filesystems.rows:
            if row.mount_id in seen:
                raise shared.SnapshotFailure("malformed", "Filesystem inventory repeats a mount identity")
            seen.add(row.mount_id)
            fields = ("filesystem", row.mount_id, row.status, row.source, row.target,
                row.fstype, row.size_bytes, row.used_bytes, row.available_bytes, row.detail)
            line = "\t".join(shared.clean_text(field, truncate=False) for field in fields)
            size += len(line.encode("utf-8")) + 1
            if size > 384 * 1024:
                raise shared.SnapshotFailure("malformed", "Filesystem inventory exceeds its byte limit")
            filesystem_lines.append(line)
    except InterruptedError:
        raise
    except (OSError, shared.SnapshotFailure) as failure:
        filesystems = system_information.FilesystemInformation(system_information.information_unknown(failure))
        filesystem_lines = []
    state("storage", "filesystem-summary", filesystems.summary)

    lines = []
    for owner, group in groups.items():
        statuses = group["statuses"]
        if all(value == "available" for value in statuses) and not group["errors"]:
            status = "available"
        elif any(value in {"available", "partial"} for value in statuses):
            status = "partial"
        elif all(value == "unsupported" for value in statuses):
            status = "unsupported"
        elif all(value == "restricted" for value in statuses):
            status = "restricted"
        else:
            status = "unavailable"
        lines.append("\t".join(("provider", owner, status, "read-only",
            "dwm-system-management", "Bounded read-only observations; inspect individual state details")))
        lines.extend(group["states"])
        if owner == "storage":
            lines.extend(filesystem_lines)
        lines.extend(dict.fromkeys(group["errors"]))
    lines.extend((
        "provider\tdiagnostics\tavailable\tuser-session\tdwm-system-health\tExisting health scan, diagnostics, and fixed repair workflow",
        "action\thealth-open\tavailable\tuser-session\tdiagnostics\tOpen system health\tOpen the existing health view and read-only scan; repairs require separate confirmation",
    ))
    validate_snapshot_size(lines)
    return lines


class NativeSnapshotSources:
    """Fixed read-only sources; construction neither reads state nor starts tools."""

    def time_state(self):
        return regional_settings.RegionalRead("time-state").run()

    def locale_state(self):
        return regional_settings.RegionalRead("locale-state").run()

    def accounts(self):
        return user_accounts.AccountRead().run()

    def printers(self):
        return system_services.CupsRead().run()

    def repositories(self):
        return system_services.RepositoryRead().run()

    def delegate(self, action):
        if not hasattr(os, "POSIX_SPAWN_CLOSEFROM"):
            raise shared.SnapshotFailure("unsupported", "Isolated administration launches are unavailable", "unsupported")
        return delegated_tools.delegated_command(action)

    def admission(self):
        """Check advisory native admission without PackageKit, logind, or a lease.

        Upstream also gates this on read_fedora_identity() -- Lyona is
        Arch-only by construction, so an "is this Fedora" check is either
        always-false (breaking every native action outright) or a pointless
        tautology. Deleted outright, matching Sync Phase 6's precedent for
        the same gate in require_mutation_safe().
        """
        try:
            with operation_journal.open_journal_directory() as chain:
                with operation_journal.open_writable_journal(chain) as journal:
                    operation_journal.prepare_journal_admission(journal)
        except (operation_journal.JournalAdmissionError, operation_journal.JournalLockError) as error:
            raise shared.SnapshotFailure("conflict", "Another operation or recovery state blocks administration; reload status") from error
        except (operation_journal.JournalFrameError, operation_journal.JournalRecordError, OSError) as error:
            raise shared.SnapshotFailure("internal", "Durable journal storage is unavailable; inspect recovery guidance and reload status") from error


def native_list_lines(records, limit: int, byte_limit: int) -> list[str]:
    """Retain a complete bounded source result, never an apparently complete prefix."""
    if len(records) > limit:
        raise shared.SnapshotFailure("malformed", "System management list exceeds its record limit")
    result, seen, size = [], set(), 0
    for record in records:
        fields = record.fields()
        if not fields[1] or fields[1] in seen:
            raise shared.SnapshotFailure("malformed", "System management list has a missing or duplicate identity")
        seen.add(fields[1])
        for field in fields[1:]:
            shared.clean_text(field, truncate=False)
            if "\t" in field or "\n" in field or "\r" in field:
                raise shared.SnapshotFailure("malformed", "System management list has unsafe text")
        line = "\t".join(fields)
        size += len(line.encode("utf-8")) + 1
        if size > byte_limit:
            raise shared.SnapshotFailure("malformed", "System management list exceeds its byte limit")
        result.append(line)
    return result


def build_native_snapshot(sources: NativeSnapshotSources,
                          blocker: shared.SnapshotFailure | None) -> list[str]:
    """Produce every minor-one record, isolating failures to its fixed owner."""
    groups = {name: {"states": [], "actions": [], "lists": [], "errors": [], "statuses": []}
              for name in ("regional", "accounts", "printers", "sources")}

    def error(owner, failure):
        groups[owner]["errors"].append(failure)

    def state(owner, identifier, status, value, detail):
        groups[owner]["statuses"].append(status)
        groups[owner]["states"].append("\t".join(("state", identifier, status, value, shared.clean_text(detail))))

    def action(owner, identifier, label, detail, failure=None):
        failure = failure or blocker
        groups[owner]["actions"].append("\t".join(("action", identifier,
            "unavailable" if failure else "available", "delegated", owner, label,
            shared.clean_text(failure.detail if failure else detail))))

    try:
        clock = sources.time_state()
    except shared.SnapshotFailure as failure:
        error("regional", failure)
        for identifier in ("timezone", "ntp-enabled", "ntp-synchronized"):
            state("regional", identifier, failure.status, "unknown", failure.detail)
        action("regional", "timezone-set", "Change timezone", "", failure)
        action("regional", "ntp-set", "Configure network time", "", failure)
    else:
        state("regional", "timezone", "available", clock.timezone, "System timezone")
        state("regional", "ntp-enabled", "available", "yes" if clock.ntp_enabled else "no", "Network time enablement")
        state("regional", "ntp-synchronized", "available", "yes" if clock.ntp_synchronized else "no", "Network time synchronization at this read")
        action("regional", "timezone-set", "Change timezone", "Requires a fresh selected timezone preview and explicit confirmation")
        ntp_failure = None if clock.can_ntp else shared.SnapshotFailure("unsupported", "No supported network time service is available", "unsupported")
        action("regional", "ntp-set", "Configure network time", "Requires a fresh network time preview and explicit confirmation", ntp_failure)

    try:
        locale = sources.locale_state()
    except shared.SnapshotFailure as failure:
        error("regional", failure)
        state("regional", "locale", failure.status, "unknown", failure.detail)
        action("regional", "locale-set", "Change system language", "", failure)
    else:
        state("regional", "locale", "available", locale.lang, locale.detail)
        locale_failure = None
        try:
            # The old LANG will be replaced. Only preserved overrides can rule
            # out every future selection; choices and full preview remain fresh.
            overrides = tuple(value for value in locale.assignments if not value.startswith("LANG="))
            regional_settings.require_locale_service_arguments(regional_settings.parse_locale_configuration(("LANG=C", *overrides)))
        except shared.SnapshotFailure as failure:
            locale_failure = failure
            error("regional", failure)
        action("regional", "locale-set", "Change system language",
            "Requires a fresh installed locale preview; existing overrides are preserved", locale_failure)

    try:
        accounts = sources.accounts()
        account_lines = native_list_lines(accounts.records, shared.ACCOUNT_LIMIT, shared.ACCOUNT_LIST_BYTES)
    except shared.SnapshotFailure as failure:
        error("accounts", failure)
        state("accounts", "accounts-count", failure.status, "unknown", failure.detail)
    else:
        groups["accounts"]["lists"] = account_lines
        groups["accounts"]["errors"].extend(accounts.errors)
        state("accounts", "accounts-count", accounts.status,
            str(len(account_lines)) if accounts.status == "available" else "unknown",
            "AccountsService account inventory" if accounts.status == "available" else "Validated account subset; enumeration is incomplete")

    try:
        printers = sources.printers()
    except shared.SnapshotFailure as failure:
        error("printers", failure)
        state("printers", "cups-service", failure.status, "unknown", failure.detail)
    else:
        groups["printers"]["errors"].extend(printers.errors)
        state("printers", "cups-service", printers.status, printers.value,
            "Fixed CUPS scheduler and socket status; printer administration stays in its platform tool")

    try:
        repositories = native_list_lines(sources.repositories(), shared.REPOSITORY_MAX_ROWS, shared.REPOSITORY_MAX_BYTES)
    except shared.SnapshotFailure as failure:
        error("sources", failure)
        groups["sources"]["statuses"].append(failure.status)
    else:
        groups["sources"]["lists"] = repositories
        groups["sources"]["statuses"].append("available")

    for owner, identifier, label in (("accounts", "accounts-open", "Manage accounts"),
            ("accounts", "password-open", "Change my password"),
            ("printers", "printers-open", "Manage printers"),
            ("sources", "sources-open", "Manage software sources")):
        failure = None
        try:
            sources.delegate(identifier)  # Resolve fixed trusted argv only; never exec it.
        except shared.SnapshotFailure as unavailable:
            failure = unavailable
            error(owner, unavailable)
        action(owner, identifier, label, "Confirm opening the fixed platform tool; the tool owns authorization and completion", failure)

    lines = []
    owners = {"regional": "systemd timedated/localed", "accounts": "AccountsService",
              "printers": "CUPS/systemd", "sources": "PackageKit"}
    for owner, group in groups.items():
        if blocker is not None:
            error(owner, blocker)
        statuses = group["statuses"]
        if all(value == "available" for value in statuses) and not group["errors"]:
            status = "available"
        elif any(value in {"available", "partial"} for value in statuses):
            status = "partial"
        elif all(value == "unsupported" for value in statuses):
            status = "unsupported"
        elif all(value == "restricted" for value in statuses):
            status = "restricted"
        else:
            status = "unavailable"
        lines.append("\t".join(("provider", owner, status, "delegated", owners[owner],
            "Readable status and individually confirmed platform actions" if status == "available"
            else "Inspect individual state, action availability, and capability errors")))
        lines.extend(group["states"])
        lines.extend(group["actions"])
        lines.extend(group["lists"])
        seen = set()
        for failure in group["errors"]:
            record = f"error\t{owner}\t{failure.code}\t{shared.clean_text(failure.detail)}"
            if record not in seen:
                seen.add(record)
                lines.append(record)
    return lines


def validate_snapshot_size(lines: Sequence[str]) -> None:
    """Keep the cumulative non-list reservation separate from bounded lists."""
    non_list = total = list_count = 0
    for line in lines:
        size = len(line.encode("utf-8")) + 1
        total += size
        if line.partition("\t")[0] in {"update", "package-change", "repository", "account", "filesystem"}:
            list_count += 1
        else:
            non_list += size
        if list_count > 9216 or non_list > 1024 * 1024 or total > 8 * 1024 * 1024:
            raise shared.SnapshotFailure("malformed", "System management snapshot exceeds its output reservation")


def build_managed_snapshot(backend: packagekit.PackageKitBackend, *,
                           native_sources: NativeSnapshotSources | None = None,
                           information_sources: InformationSnapshotSources | None = None) -> list[str]:
    """Combine readable discovery with independently validated durable recovery."""
    if information_sources is not None and native_sources is None:
        raise ValueError("Information snapshots require cumulative native sources")
    recovery = update_plans.read_recovery_snapshot(backend)
    state = recovery.state
    mutation_blocker = None
    mutation_failure = None
    if recovery.failures or state is None:
        mutation_blocker = "Complete durable recovery evidence is required; reload status and inspect recovery errors"
    elif state.active is not None or state.handoff is not None:
        mutation_blocker = "An operation or its unacknowledged result still owns the update workflow"
    else:
        try:
            backend.require_mutation_safe()
        except shared.SnapshotFailure as failure:
            mutation_failure = failure
            mutation_blocker = failure.detail
    # This is advisory availability, not admission. The mutation command repeats
    # its security, journal-ownership, session, and generation checks at dispatch.
    lines = build_snapshot(backend, mutation_blocker=mutation_blocker,
        mutation_failure=mutation_failure)
    restart = state.restart if state is not None else recovery.prior_restart
    value = "unknown"
    if restart is not None and restart.system != "unknown":
        value = update_plans.aggregate_restart((
            {"none": 1, "system": 4, "security-system": 6}[restart.system],
            {"none": 1, "session": 3, "security-session": 5}[restart.session],
            2 if restart.application else 1,
        ))
    partial = bool(recovery.failures) or state is None
    if state is None and value == "none":
        value = "unknown"
    detail = "Durable journal restart guidance; session and reboot satisfaction applied"
    if partial:
        detail = "Known restart guidance is retained; recovery evidence is incomplete. Refresh status and inspect recovery errors"
    for index, line in enumerate(lines):
        if line.startswith("provider\trecovery\t"):
            lines[index] = "\t".join(("provider", "recovery", "partial" if partial else "available",
                "user-session", "dwm-system-management", detail if partial else "Durable journal recovery completed"))
        elif line.startswith("state\tupdate-restart\t"):
            lines[index] = "\t".join(("state", "update-restart", "partial" if partial else "available", value, detail))
    lines.pop()  # Restore the single final completion after recovery records.
    if state is not None and state.active is not None:
        operation = state.active
        percent = recovery.evidence.percent if recovery.evidence is not None else None
        cancelable = recovery.evidence is not None and recovery.evidence.allow_cancel
        for index, line in enumerate(lines):
            if line.startswith("action\tupdates-cancel\t"):
                lines[index] = "\t".join(("action", "updates-cancel", "available" if cancelable else "unavailable",
                    "delegated", "updates", "Cancel update", "Exact PackageKit transaction permits cancellation"
                    if cancelable else "Exact PackageKit transaction does not currently permit cancellation"))
        lines.append("\t".join(("active-operation", operation.operation_id, operation.action_id,
            operation.kind, operation.state, "unknown" if percent is None else str(percent), "yes" if cancelable else "no",
            "Exact journaled operation remains active; use watch-operation to observe its result")))
    elif state is not None and state.handoff is not None:
        operation = state.terminals[state.handoff.slot]
        lines.append("\t".join(("terminal-handoff", operation.operation_id, operation.action_id, operation.kind)))
    lines.extend(f"error\trecovery\t{failure.code}\t{failure.detail}" for failure in recovery.failures)
    if native_sources is not None:
        native_blocker = None
        if state is None or state.active is not None or state.handoff is not None:
            native_blocker = shared.SnapshotFailure("conflict", "Complete idle journal recovery is required before administration; reload status")
        else:
            try:
                native_sources.admission()
            except shared.SnapshotFailure as failure:
                native_blocker = failure
        lines.extend(build_native_snapshot(native_sources, native_blocker))
        lines[0] = f"system-management-protocol\t{shared.PROTOCOL_MAJOR}\t{NATIVE_SNAPSHOT_MINOR}"
    if information_sources is not None:
        lines.extend(build_information_snapshot(information_sources))
        lines[0] = f"system-management-protocol\t{shared.PROTOCOL_MAJOR}\t{SNAPSHOT_MINOR}"
    lines.append("complete\tsnapshot")
    validate_snapshot_size(lines)
    return lines


def build_snapshot(backend: update_plans.UpdateBackend, *,
                   mutation_blocker: str | None = "Managed recovery and backend safety have not been verified",
                   mutation_failure: shared.SnapshotFailure | None = None) -> list[str]:
    """Render bounded discovery; only the managed caller can offer mutations."""
    errors: list[tuple[str, str]] = []
    if mutation_failure is not None:
        errors.append((mutation_failure.code, mutation_failure.detail))
    last_refresh_status = "unavailable"
    last_refresh_value = "unknown"
    last_refresh_detail = "PackageKit refresh history is unavailable"
    try:
        refresh_age = backend.last_refresh_age()
        if refresh_age == shared.G_MAXUINT:
            last_refresh_status = "partial"
            last_refresh_detail = "PackageKit has no successful refresh history"
        elif isinstance(refresh_age, int) and 0 <= refresh_age < shared.G_MAXUINT:
            last_refresh_status = "available"
            last_refresh_value = str(refresh_age)
            last_refresh_detail = "Seconds since PackageKit last refreshed metadata"
        else:
            raise shared.SnapshotFailure(
                "malformed", "PackageKit returned a malformed refresh age"
            )
    except shared.SnapshotFailure as failure:
        last_refresh_status = failure.status
        last_refresh_detail = failure.detail
        errors.append((failure.code, failure.detail))

    update_rows: list[update_plans.UpdateRow] = []
    plan_rows: list[update_plans.PlanRow] = []
    summary_status = "unavailable"
    restart_status = "unavailable"
    restart_value = "unknown"
    summary_detail = "PackageKit update discovery is unavailable"
    restart_detail = "PackageKit restart guidance is unavailable"
    inventory_ok = False
    try:
        result = backend.updates()
    except shared.SnapshotFailure as failure:
        if failure.code == "malformed":
            mutation_blocker = mutation_blocker or failure.detail
        summary_status = failure.status
        restart_status = failure.status
        summary_detail = failure.detail
        restart_detail = failure.detail
        errors.append((failure.code, failure.detail))
    else:
        try:
            update_rows = update_plans.normalize_updates(result.packages)
            summary_status = "available"
            summary_detail = "PackageKit update discovery completed"
            inventory_ok = True
        except shared.SnapshotFailure as failure:
            mutation_blocker = mutation_blocker or failure.detail
            summary_status = failure.status
            summary_detail = failure.detail
            errors.append((failure.code, failure.detail))
        try:
            restart_value = update_plans.aggregate_restart(result.restart_types)
            restart_status = "available"
            restart_detail = "PackageKit restart guidance from update discovery"
            if not result.restart_types and update_rows:
                restart_value = update_plans._restart_heuristic_hint(update_rows)
                if restart_value != "none":
                    restart_detail = (
                        "PackageKit reported no restart requirements; guidance is "
                        "a heuristic over pending package names, not verified "
                        "backend data"
                    )
        except shared.SnapshotFailure as failure:
            restart_status = failure.status
            restart_detail = failure.detail
            errors.append((failure.code, failure.detail))

    installable_ids = [
        row.package_id for row in update_rows if row.installability == "installable"
    ]
    plan_ok = False
    plan_detail = (
        "No installable updates require a dependency preview"
        if inventory_ok
        else "PackageKit dependency preview is unavailable"
    )
    if inventory_ok and installable_ids:
        try:
            plan_rows = update_plans.normalize_plan(
                backend.simulate(installable_ids).packages, installable_ids
            )
            if any(row.action in {"reinstall", "downgrade"} for row in plan_rows):
                plan_detail = (
                    "PackageKit dependency preview requires unsupported reinstall "
                    "or downgrade flags"
                )
                errors.append(("unsupported", plan_detail))
            else:
                plan_ok = True
                plan_detail = "PackageKit dependency preview completed"
        except shared.SnapshotFailure as failure:
            plan_detail = failure.detail
            errors.append((failure.code, failure.detail))

    generation = update_plans.snapshot_generation(installable_ids, plan_rows)
    mutation_ready = mutation_blocker is None and mutation_failure is None
    provider_status = ("available" if mutation_ready and not errors else "partial") if inventory_ok else summary_status
    if provider_status not in {"available", "partial", "restricted", "unavailable", "unsupported"}:
        provider_status = "partial"

    lines = [
        f"system-management-protocol\t{shared.PROTOCOL_MAJOR}\t{shared.PROTOCOL_MINOR}",
        f"snapshot-generation\t{generation}",
        "\t".join(
            (
                "provider",
                "updates",
                provider_status,
                "delegated",
                "PackageKit",
                shared.clean_text(
                    "PackageKit discovery is readable; update actions require "
                    "explicit confirmation and platform authorization"
                    if inventory_ok
                    else summary_detail
                ),
            )
        ),
        "provider\trecovery\tunsupported\tuser-session\tdwm-system-management\t"
        "Managed update recovery is not enabled in this build",
        "\t".join(
            (
                "state",
                "update-summary",
                summary_status,
                str(len(update_rows)) if summary_status == "available" else "unknown",
                shared.clean_text(summary_detail),
            )
        ),
        "\t".join(
            (
                "state",
                "update-last-refresh",
                last_refresh_status,
                last_refresh_value,
                shared.clean_text(last_refresh_detail),
            )
        ),
        "\t".join(
            (
                "state",
                "update-restart",
                restart_status,
                restart_value if restart_status == "available" else "unknown",
                shared.clean_text(restart_detail),
            )
        ),
        "\t".join(("action", "updates-refresh", "available" if mutation_ready else "unavailable",
            "delegated", "updates", "Refresh updates", shared.clean_text(mutation_blocker or
                "Confirm a PackageKit metadata refresh; package installation is a separate action"))),
        "\t".join(
            (
                "action",
                "updates-install-all",
                "available" if mutation_ready and plan_ok else "unavailable",
                "delegated",
                "updates",
                "Install all updates",
                shared.clean_text(f"{mutation_blocker}; {plan_detail}" if mutation_blocker else plan_detail),
            )
        ),
        "action\tupdates-cancel\tunavailable\tdelegated\tupdates\tCancel update\t"
        "No managed update operation is active",
    ]
    lines.extend("\t".join(row.fields()) for row in update_rows)
    lines.extend("\t".join(row.fields()) for row in plan_rows)
    lines.extend(
        f"error\tupdates\t{code}\t{shared.clean_text(detail)}" for code, detail in errors
    )
    lines.append("complete\tsnapshot")
    return lines
