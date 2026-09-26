#!/usr/bin/env bash
# Create the upstream-sync sprints on GitHub: one milestone per sprint and one
# issue per sprint item, assigned to its milestone. Optionally also a GitHub
# Projects (v2) board with a "Sprint" field. Milestones and user-owned Projects
# are both available on free GitHub plans.
#
# Requires: github-cli (`sudo pacman -S github-cli`), then `gh auth login`.
# Projects also need the project scope: `gh auth refresh -s project`.
#
# Usage:
#   docs/sync-sprints-github.sh [--dry-run] [--project] [--repo OWNER/NAME]
#                               [--start YYYY-MM-DD] [--days N]
#
#   --dry-run   print what would be created, change nothing
#   --project   also create/fill a Projects board "Lyona upstream sync"
#   --start     first sprint's start date (default: today); sets milestone due dates
#   --days      sprint length in days (default: 14)
#
# Safe to re-run: existing milestones, labels, issues (matched by exact title)
# and project items are left alone.
set -euo pipefail

repo=technicks89/Lyona
dry_run=0
with_project=0
start=$(date +%F)
days=14

while (($#)); do
	case $1 in
	--dry-run) dry_run=1 ;;
	--project) with_project=1 ;;
	--repo) repo=${2:?}; shift ;;
	--start) start=${2:?}; shift ;;
	--days) days=${2:?}; shift ;;
	-h | --help) sed -n '2,22p' "$0"; exit 0 ;;
	*) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
	esac
	shift
done

command -v gh >/dev/null || { echo 'gh not found: sudo pacman -S github-cli' >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo 'not logged in: gh auth login' >&2; exit 1; }

owner=${repo%%/*}
blob="https://github.com/$repo/blob/main/docs"
label=upstream-sync

run() {
	if ((dry_run)); then printf 'DRY: %s\n' "$*"; else "$@"; fi
}

# Sprint number | title | plan document
sprints=(
	"1|Sync Sprint 1 — System management + manual CI|SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md"
	"2|Sync Sprint 2 — System information|SYNC-SPRINT-2-SYSTEM-INFORMATION.md"
	"3|Sync Sprint 3 — Displays and Settings|SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md"
	"4|Sync Sprint 4 — Compositor, defaults, release|SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md"
	"5|Sync Sprint 5 — Settings load stability, Flathub, floating toggles|SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md"
	"6|Sync Sprint 6 — Theme consistency and window overview|SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md"
	"7|Sync Sprint 7 — Cross-tag overview: foundation|SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md"
	"8|Sync Sprint 8 — Cross-tag overview: interaction|SYNC-SPRINT-8-OVERVIEW-INTERACTION.md"
	"9|Sync Sprint 9 — Cross-tag overview: polish|SYNC-SPRINT-9-OVERVIEW-POLISH.md"
)

# Sprint | item id | heading anchor | title | upstream refs
items=(
	"1|S1-01|s1-01-manual-full-suite-ci-workflow|Manual full-suite CI workflow|Lyona request"
	"1|S1-02|s1-02-close-the-sync-phase-9-tracking-gap|Close the Sync Phase 9 (#33) tracking gap|—"
	"1|S1-03|s1-03-native-discovery-and-native-origins-in-qml|Native discovery and native origins in QML|#251, #259, #261, #262"
	"1|S1-04|s1-04-confirmed-delegated-administration|Confirmed delegated administration|#266, #267"
	"1|S1-05|s1-05-regional-settings-model-and-controls|Regional settings model and controls|#268, #269"
	"1|S1-06|s1-06-shared-timezone-aware-minute-clock|Shared timezone-aware minute clock|#270"
	"1|S1-07|s1-07-helper-ntp-sample-interruption-recovery-watch-time|Helper: NTP sample, interruption recovery, watch-time|#271, #272, #273"
	"1|S1-08|s1-08-qml-time-observations-owner-arrivals-ntp-sampling|QML time observations, owner arrivals, NTP sampling|#274, #275, #276"
	"1|S1-09|s1-09-package-progress-and-user-service-session-evidence|Package progress and user-service session evidence|#291 (system half)"
	"1|S1-10|s1-10-carried-over-open-items|Carried-over open items (D-4, harness gaps)|—"
	"2|S2-01|s2-01-local-hardware-and-filesystem-readers|Local, hardware, and filesystem readers|#277, #278, #279"
	"2|S2-02|s2-02-security-status-readers|Security status readers (decide D-5)|#280, #281"
	"2|S2-03|s2-03-automatic-screen-lock-evidence|Automatic screen-lock evidence|#282"
	"2|S2-04|s2-04-mount-change-monitor|Mount change monitor|#284"
	"2|S2-05|s2-05-information-snapshot-records-and-lifecycle|Information snapshot records and lifecycle|#285, #286"
	"2|S2-06|s2-06-settings-information-card-and-health-navigation|Settings information card and Health navigation|#287"
	"2|S2-07|s2-07-close-roadmapmd-phase-6|Close ROADMAP.md Phase 6|#288"
	"3|S3-01|s3-01-relative-monitor-placement-and-numbered-preview|Relative monitor placement and numbered preview|#289"
	"3|S3-02|s3-02-docked-and-undocked-display-profiles|Docked and undocked display profiles|#290"
	"3|S3-03|s3-03-hide-dock-profiles-without-a-system-battery|Hide dock profiles without a system battery|upstream issue #310"
	"3|S3-04|s3-04-control-center-compaction|Control Center compaction|c3e9a18"
	"3|S3-05|s3-05-settings-readiness-and-startup-work|Settings readiness, lazy panes, no layout shift|#291, #294, #295, issue #315"
	"3|S3-06|s3-06-power-menu-settings-full-screen-cursor-reload-tray-self-heal|Power menu, full-screen Settings, cursor reload, tray, Self-Heal|#307 (issues #302–#306)"
	"3|S3-07|s3-07-appearance-simplification-and-desktop-typography|Appearance simplification and desktop typography (decide D-7)|#327, 68a0d1f"
	"3|S3-08|s3-08-panel-stays-sharp-under-popups|Panel stays sharp under popups|#324"
	"3|S3-09|s3-09-pre-survey-gaps-183-188-191|Pre-survey gaps|#183, #188, #191"
	"4|S4-01|s4-01-configuration-backed-picom-controls|Configuration-backed Picom controls|#312, #313, #314 (issue #309)"
	"4|S4-02|s4-02-media-and-image-defaults-on-fresh-installs|Media and image defaults on fresh installs|issue #308, #317"
	"4|S4-03|s4-03-icon-themes-and-first-login-theme-convergence|Icon themes, first-login theme convergence, XSETTINGS lock|#301, #328"
	"4|S4-04|s4-04-installer-and-session-fixes|Installer and session fixes|#283, 44800ba"
	"4|S4-05|s4-05-terminal-dwmterm|Terminal: dwmterm (decline, partial port)|#255"
	"4|S4-06|s4-06-desktop-update-experience|Desktop update experience (decide D-8)|#318–#323 (issue #311)"
	"4|S4-07|s4-07-declined-fedora-image-and-release-work|Record declined Fedora/image/release work|various"
	"4|S4-08|s4-08-re-survey-and-release-qualification|Re-survey upstream and release qualification|—"
	"5|S5-01|s5-01-settings-panes-stay-hidden-until-their-data-has-loaded|Settings panes stay hidden until their data has loaded|#335, completes #315"
	"5|S5-02|s5-02-verify-the-flathub-remote-before-a-flatpak-install|Verify the Flathub remote before a Flatpak install|#332, #334"
	"5|S5-03|s5-03-floating-toggles-visibly-shrink-the-window|Floating toggles visibly shrink the window (decision D-9)|#331, #333"
	"6|S6-01|s6-01-live-panel-tooltip-position-on-window-resize|Live panel tooltip position on window resize|#343 (2461027)"
	"6|S6-02|s6-02-thunar-and-other-gtk-apps-stay-light-under-dark-themes|Thunar and other GTK apps stay light under dark themes|issue #348"
	"6|S6-03|s6-03-hover-states-that-hide-text-in-light-themes|Hover states that hide text in light themes|issue #349"
	"6|S6-04|s6-04-cross-tag-window-overview|Cross-tag window overview|issue #350"
	"7|S7-01|s7-01-per-window-data-in-dwm-quickshell-state|Per-window data in dwm-quickshell-state|issue #350"
	"7|S7-02|s7-02-dwmstateqml-gains-the-window-list|DwmState.qml gains the window list|issue #350"
	"7|S7-03|s7-03-the-overview-popup-mouse-only|The overview popup, mouse-only|issue #350"
	"8|S8-01|s8-01-keyboard-navigation|Keyboard navigation|issue #350"
	"8|S8-02|s8-02-multi-monitor-labels-and-a-window-closing-mid-use|Multi-monitor labels and a window closing mid-use|issue #350"
	"8|S8-03|s8-03-type-to-filter|Type-to-filter|issue #350"
	"8|S8-04|s8-04-close-a-window-from-its-card|Close a window from its card|issue #350"
	"9|S9-01|s9-01-live-per-window-thumbnails-a-spike|Live per-window thumbnails (a spike)|issue #350"
	"9|S9-02|s9-02-motion-and-visual-polish|Motion and visual polish|issue #350"
	"9|S9-03|s9-03-accessibility-pass|Accessibility pass|issue #350"
	"9|S9-04|s9-04-idle-cpu-and-many-window-performance|Idle-CPU and many-window performance|issue #350"
)

run gh label create "$label" --repo "$repo" --color 5319e7 \
	--description "Port from ChrisTitusTech/dwm-titus" 2>/dev/null || true

declare -A milestone_title milestone_doc
for sprint in "${sprints[@]}"; do
	IFS='|' read -r n title doc <<<"$sprint"
	milestone_title[$n]=$title
	milestone_doc[$n]=$doc
	due=$(date -u -d "$start + $((n * days)) days" +%Y-%m-%dT23:59:59Z)
	exists=$(gh api "repos/$repo/milestones?state=all&per_page=100" \
		--jq ".[] | select(.title == \"$title\") | .number")
	if [[ -n $exists ]]; then
		printf 'milestone exists: %s\n' "$title"
		continue
	fi
	run gh api "repos/$repo/milestones" -X POST -f title="$title" -f due_on="$due" \
		-f description="Plan: $blob/$doc" >/dev/null
	printf 'milestone: %s (due %s)\n' "$title" "${due%%T*}"
done

project_number=
if ((with_project)); then
	project_title="Lyona upstream sync"
	project_number=$(gh project list --owner "$owner" --format json \
		--jq ".projects[] | select(.title == \"$project_title\") | .number" 2>/dev/null || true)
	if [[ -z $project_number ]]; then
		if ((dry_run)); then
			echo "DRY: gh project create --owner $owner --title \"$project_title\""
		else
			project_number=$(gh project create --owner "$owner" --title "$project_title" \
				--format json --jq .number)
			gh project field-create "$project_number" --owner "$owner" --name Sprint \
				--data-type SINGLE_SELECT --single-select-options "Sprint 1,Sprint 2,Sprint 3,Sprint 4" >/dev/null
			gh project link "$project_number" --owner "$owner" --repo "$repo" >/dev/null || true
		fi
	fi
	[[ -n $project_number ]] && printf 'project: #%s %s\n' "$project_number" "$project_title"
fi

for item in "${items[@]}"; do
	IFS='|' read -r n id anchor title refs <<<"$item"
	full_title="[$id] $title"
	existing=$(gh issue list --repo "$repo" --state all --label "$label" --limit 200 \
		--search "\"[$id]\" in:title" --json number,title \
		--jq ".[] | select(.title == \"$full_title\") | .number")
	if [[ -n $existing ]]; then
		printf 'issue exists: #%s %s\n' "$existing" "$full_title"
		url="https://github.com/$repo/issues/$existing"
	else
		body=$(printf '%s\n\n**Upstream:** %s\n\n**Plan:** [%s §%s](%s/%s#%s)\n\nPart of **%s**. Index: [UPSTREAM-SYNC.md](%s/UPSTREAM-SYNC.md).\n\nDone when the plan section'"'"'s verification passes and `TASKS.md`, `CHANGELOG.md` and `docs/evidence/` are updated in the same PR.\n' \
			"$title" "$refs" "${milestone_doc[$n]}" "$id" "$blob" "${milestone_doc[$n]}" "$anchor" \
			"${milestone_title[$n]}" "$blob")
		if ((dry_run)); then
			printf 'DRY: issue %s -> %s\n' "$full_title" "${milestone_title[$n]}"
			continue
		fi
		url=$(gh issue create --repo "$repo" --title "$full_title" --body "$body" \
			--label "$label" --milestone "${milestone_title[$n]}")
		printf 'issue: %s %s\n' "$url" "$full_title"
	fi
	if [[ -n $project_number ]] && ((!dry_run)); then
		item_id=$(gh project item-add "$project_number" --owner "$owner" --url "$url" \
			--format json --jq .id)
		project_id=$(gh project view "$project_number" --owner "$owner" --format json --jq .id)
		field_json=$(gh project field-list "$project_number" --owner "$owner" --format json)
		field_id=$(jq -r '.fields[] | select(.name == "Sprint") | .id' <<<"$field_json")
		option_id=$(jq -r ".fields[] | select(.name == \"Sprint\") | .options[] | select(.name == \"Sprint $n\") | .id" <<<"$field_json")
		gh project item-edit --id "$item_id" --project-id "$project_id" \
			--field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
	fi
done
