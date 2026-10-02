# shellcheck shell=bash
# Which driver an NVIDIA GPU needs, for the installer and the postinstall (Sync
# Sprint 12 S12-15 and S12-17, Sync Sprint 14 S14-02). Sourced, not run.
#
# The answer is one of:
#   open         nvidia-open (Turing, GTX 16xx and RTX 20xx, or newer)
#   580xx 470xx  a legacy driver the medium installs (Maxwell to Volta; Kepler)
#   unsupported  no packaged driver supports it, so nouveau stays
#
# config/nvidia-legacy-gpus.tsv maps the device IDs NVIDIA lists as legacy. An
# ID it does not list is open, unless it is below 0x1e00, the first Turing ID:
# every newer card than the table is open, and an older card the table somehow
# lacks keeps nouveau rather than getting a driver that cannot load
# (nvidia-utils blacklists nouveau, which would leave it with none).

lyona_nvidia_table=${LYONA_NVIDIA_TABLE:-/root/lyona/config/nvidia-legacy-gpus.tsv}

# lyona_nvidia_branch DEVICE: the branch for one PCI device ID (4 hex digits).
lyona_nvidia_branch() {
	local device=${1,,} branch=
	if [[ ! $device =~ ^[0-9a-f]{4}$ ]]; then
		printf 'unsupported\n'
		return
	fi
	if [[ -r $lyona_nvidia_table ]]; then
		branch=$(awk -F '\t' -v device="$device" '$1 == device { print $2; exit }' "$lyona_nvidia_table")
	fi
	case $branch in
	580xx | 470xx | unsupported) ;;
	*) if ((16#$device < 16#1e00)); then branch=unsupported; else branch=open; fi ;;
	esac
	printf '%s\n' "$branch"
}

# nvidia_gpu_branch: the branch for this machine's NVIDIA GPU, the first one
# lspci lists when there are several, and its device ID, as "BRANCH DEVICE".
# Fails when no NVIDIA display device is found.
nvidia_gpu_branch() {
	local class device
	for class in 0300 0302 0380; do
		device=$(lspci -n -mm -d "10de::$class" 2>/dev/null | awk '{ gsub(/"/, "", $4); print $4; exit }')
		if [[ $device =~ ^[0-9a-fA-F]{4}$ ]]; then
			printf '%s %s\n' "$(lyona_nvidia_branch "$device")" "${device,,}"
			return 0
		fi
	done
	return 1
}
