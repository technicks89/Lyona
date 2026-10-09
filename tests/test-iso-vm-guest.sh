#!/usr/bin/env bash
set -euo pipefail

# #310: the image postinstall installs the QEMU/KVM guest utilities on a VM and
# nothing on bare metal, asking systemd-detect-virt on the live medium: inside
# arch-chroot it answers container-other, and no VM ever got them.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
sed -n '/^install_qemu_guest_utils() {$/,/^}$/p' "$postinstall" >"$work/guest.sh"
grep -q '^install_qemu_guest_utils() {$' "$work/guest.sh" || fail 'install_qemu_guest_utils not found in the postinstall'
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -q 'arch-chroot "$TARGET" systemd-detect-virt' "$work/guest.sh" &&
	fail 'the hypervisor is still detected inside arch-chroot'

# The stubs and TARGET are used by the sourced function.
# shellcheck disable=SC2034,SC2329
run_case() { # VIRT: prints what was installed and enabled
	(
		systemd-detect-virt() {
			[[ $1 == --vm ]] || return 2
			printf '%s\n' "$STUB_VIRT"
			[[ $STUB_VIRT != none ]]
		}
		arch-chroot() { shift && printf '%s\n' "$*"; }
		dwm_packages() { printf '%s\n' qemu-guest-agent spice-vdagent; }
		STUB_VIRT=$1 TARGET=/mnt
		# shellcheck source=/dev/null
		. "$work/guest.sh"
		install_qemu_guest_utils
	)
}

kvm=$(run_case kvm)
grep -Fq 'pacman -S --noconfirm --needed qemu-guest-agent spice-vdagent' <<<"$kvm" || fail "a KVM guest got no guest utilities: $kvm"
grep -Fq 'systemctl enable qemu-guest-agent.service' <<<"$kvm" || fail "a KVM guest's agent was not enabled: $kvm"
[[ $(run_case qemu) == *'pacman -S'* ]] || fail 'a QEMU guest got no guest utilities'
metal=$(run_case none)
[[ $metal != *'pacman -S'* && $metal != *'systemctl enable'* ]] || fail "bare metal got guest utilities: $metal"
grep -Fq 'no QEMU/KVM hypervisor detected' <<<"$metal" || fail "bare metal was not reported: $metal"

printf 'Image install VM guest utilities (KVM, QEMU, bare metal): PASS\n'
