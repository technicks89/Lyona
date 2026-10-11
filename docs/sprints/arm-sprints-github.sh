#!/usr/bin/env bash
# Create the Lyona on ARM sprints on GitHub: one milestone per scheduled sprint
# and one issue per sprint item, each in its milestone and labelled arm64.
# Optionally also a GitHub Projects (v2) board with a "Sprint" field. The
# project's index is docs/sprints/ARM64.md; ARM-4 (GB10) and ARM5-05 (N1X)
# are deferred and not listed here.
#
# Requires: github-cli (`sudo pacman -S github-cli`), then `gh auth login`.
# Projects also need the project scope: `gh auth refresh -s project`.
#
# Usage:
#   docs/sprints/arm-sprints-github.sh [--dry-run] [--project] [--repo OWNER/NAME]
#                              [--start YYYY-MM-DD] [--days N]
#
#   --dry-run   print what would be created, change nothing
#   --project   also create/fill a Projects board "Lyona on ARM"
#   --start     first sprint's start date (default: today); sets milestone due dates
#   --days      sprint length in days (default: 14)
#
# Safe to re-run: existing milestones, labels, issues (matched by exact title)
# and project items are left alone, except that an existing issue with no
# milestone is put in its sprint's milestone.
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
	--repo)
		repo=${2:?}
		shift
		;;
	--start)
		start=${2:?}
		shift
		;;
	--days)
		days=${2:?}
		shift
		;;
	-h | --help)
		sed -n '2,22p' "$0"
		exit 0
		;;
	*)
		printf 'unknown argument: %s\n' "$1" >&2
		exit 2
		;;
	esac
	shift
done

command -v gh >/dev/null || {
	echo 'gh not found: sudo pacman -S github-cli' >&2
	exit 1
}
gh auth status >/dev/null 2>&1 || {
	echo 'not logged in: gh auth login' >&2
	exit 1
}

owner=${repo%%/*}
blob="https://github.com/$repo/blob/main/docs/sprints"
label=arm64

run() {
	if ((dry_run)); then printf 'DRY: %s\n' "$*"; else "$@"; fi
}

# Sprint number | order (sets the due date) | title | plan document.
# ARM-2 and ARM-3 run side by side after ARM-1, so they share a due date.
sprints=(
	"1|1|ARM Sprint 1 - Foundation|ARM-SPRINT-1-FOUNDATION.md"
	"2|2|ARM Sprint 2 - Generic aarch64 image|ARM-SPRINT-2-GENERIC-IMAGE.md"
	"3|2|ARM Sprint 3 - Raspberry Pi 4 and 5|ARM-SPRINT-3-RASPBERRY-PI.md"
	"5|3|ARM Sprint 5 - Release and support contract|ARM-SPRINT-5-RELEASE-AND-N1X.md"
)

# Sprint | item id | heading anchor | title
items=(
	"1|ARM1-01|arm1-01-the-support-contract-and-the-identity|The support contract and the identity (A-1)"
	"1|ARM1-02|arm1-02-the-dependency-map-on-aarch64|The dependency map on aarch64"
	"1|ARM1-03|arm1-03-aur-pins-and-downloaded-binaries-on-aarch64|AUR pins and downloaded binaries on aarch64"
	"1|ARM1-04|arm1-04-code-that-assumes-x86_64|Code that assumes x86_64"
	"1|ARM1-05|arm1-05-aarch64-ci|aarch64 CI (A-9)"
	"1|ARM1-06|arm1-06-validate-installsh-on-arch-linux-arm|Validate install.sh on Arch Linux ARM"
	"2|ARM2-01|arm2-01-builder-and-installer-spike|Builder and installer spike (A-2, A-3, A-4)"
	"2|ARM2-02|arm2-02-the-aarch64-live-medium|The aarch64 live medium"
	"2|ARM2-03|arm2-03-the-arm-installer-path|The ARM installer path"
	"2|ARM2-04|arm2-04-mirrors-keyring-and-what-the-installer-skips-on-arm|Mirrors, keyring and what the installer skips on ARM"
	"2|ARM2-05|arm2-05-validate-on-three-virtual-machines|Validate the generic image on three virtual machines"
	"3|ARM3-01|arm3-01-the-pi-image-builder|The Pi image builder (A-5)"
	"3|ARM3-02|arm3-02-the-first-boot-wizard|The Pi first-boot wizard"
	"3|ARM3-03|arm3-03-pi-boot-configuration-and-kernel|Pi boot configuration and kernel"
	"3|ARM3-04|arm3-04-the-desktop-on-v3d|The desktop on v3d"
	"3|ARM3-05|arm3-05-settings-on-a-pi|Settings on a Pi"
	"3|ARM3-06|arm3-06-validate-on-a-real-pi-4-and-pi-5|Validate on a real Pi 4 and Pi 5"
	"5|ARM5-01|arm5-01-the-release-workflow-for-arm-images|The release workflow for ARM images"
	"5|ARM5-02|arm5-02-updates-on-aarch64|Updates on aarch64"
	"5|ARM5-03|arm5-03-the-support-contract-per-target|The support contract per target"
	"5|ARM5-04|arm5-04-user-documentation|ARM user documentation"
)

run gh label create "$label" --repo "$repo" --color 0e8a16 \
	--description "Lyona on ARM (aarch64): docs/sprints/ARM64.md" 2>/dev/null || true

declare -A milestone_title milestone_doc
for sprint in "${sprints[@]}"; do
	IFS='|' read -r n order title doc <<<"$sprint"
	milestone_title[$n]=$title
	milestone_doc[$n]=$doc
	due=$(date -u -d "$start + $((order * days)) days" +%Y-%m-%dT23:59:59Z)
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
	project_title="Lyona on ARM"
	project_number=$(gh project list --owner "$owner" --format json \
		--jq ".projects[] | select(.title == \"$project_title\") | .number" 2>/dev/null || true)
	if [[ -z $project_number ]]; then
		if ((dry_run)); then
			echo "DRY: gh project create --owner $owner --title \"$project_title\""
		else
			project_number=$(gh project create --owner "$owner" --title "$project_title" \
				--format json --jq .number)
			gh project field-create "$project_number" --owner "$owner" --name Sprint \
				--data-type SINGLE_SELECT --single-select-options "ARM-1,ARM-2,ARM-3,ARM-5" >/dev/null
			gh project link "$project_number" --owner "$owner" --repo "$repo" >/dev/null || true
		fi
	fi
	[[ -n $project_number ]] && printf 'project: #%s %s\n' "$project_number" "$project_title"
fi

for item in "${items[@]}"; do
	IFS='|' read -r n id anchor title <<<"$item"
	full_title="[$id] $title"
	existing=$(gh issue list --repo "$repo" --state all --label "$label" --limit 200 \
		--search "\"[$id]\" in:title" --json number,title,milestone \
		--jq ".[] | select(.title == \"$full_title\") | \"\(.number) \(.milestone.title // \"\")\"")
	if [[ -n $existing ]]; then
		number=${existing%% *}
		printf 'issue exists: #%s %s\n' "$number" "$full_title"
		if [[ ${existing#* } != "${milestone_title[$n]}" ]]; then
			run gh issue edit "$number" --repo "$repo" --milestone "${milestone_title[$n]}" >/dev/null
			printf '  milestone set: %s\n' "${milestone_title[$n]}"
		fi
		url="https://github.com/$repo/issues/$number"
	else
		body=$(printf '%s\n\n**Plan:** [%s %s](%s/%s#%s)\n\nPart of **%s**. Index: [ARM64.md](%s/ARM64.md).\n\nDone when the plan section'"'"'s acceptance passes and `CHANGELOG.md` and `docs/evidence/` are updated in the same PR, with what was not tested said plainly.\n' \
			"$title" "${milestone_doc[$n]}" "$id" "$blob" "${milestone_doc[$n]}" "$anchor" \
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
		option_id=$(jq -r ".fields[] | select(.name == \"Sprint\") | .options[] | select(.name == \"ARM-$n\") | .id" <<<"$field_json")
		gh project item-edit --id "$item_id" --project-id "$project_id" \
			--field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
	fi
done
