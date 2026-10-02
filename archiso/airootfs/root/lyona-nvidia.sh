# shellcheck shell=bash
# Which NVIDIA GPUs the current Arch driver supports, for the installer and the
# postinstall (Sync Sprint 12 S12-15, S12-17). Sourced, not run.

# nvidia-open needs Turing (GTX 16xx, RTX 20xx) or newer. Every older NVIDIA GPU
# has a PCI device ID below 0x1e00, and every Turing or newer one is at or above
# it. Until Sync Sprint 14 S14-02's table lands, this keeps the older cards on
# nouveau: nvidia-utils blacklists nouveau, so installing a driver that can't
# load would leave them with none.
nvidia_open_supported() {
	local class device seen=0
	for class in 0300 0302 0380; do
		while read -r device; do
			[[ $device =~ ^[0-9a-f]{4}$ ]] || continue
			seen=1
			if ((16#$device < 16#1e00)); then
				printf 'lyona: NVIDIA GPU 10de:%s predates Turing; nvidia-open does not support it.\n' "$device"
				return 1
			fi
		done < <(lspci -n -mm -d "10de::$class" 2>/dev/null | awk '{ gsub(/"/, "", $4); print $4 }')
	done
	((seen)) || printf 'lyona: could not read the NVIDIA GPU device ID.\n'
	((seen))
}
