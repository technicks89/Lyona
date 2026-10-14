#!/usr/bin/env bash
# Build the Arch Linux ARM base image the aarch64 Full suite job runs in
# (ARM1-05, decision A-9): the counterpart of archlinux:base-devel, which has no
# aarch64 build. Arch Linux ARM publishes no container image, so this imports
# its own generic root filesystem, ArchLinuxARM-aarch64-latest.tar.gz, after
# checking it:
#
#   - its signature, made by the Arch Linux ARM Build System key, whose
#     fingerprint is pinned below and whose public key is kept beside this
#     script (scripts/ci-archlinuxarm.asc);
#   - the checksum the mirror publishes beside it.
#
# The tarball is downloaded over HTTPS from the first mirror that answers. The
# signature, not the mirror, is what is trusted.
#
# Then, in the image: pacman's download sandbox is turned off (its Landlock
# rules and switch to the alpm user are refused inside a container build), the
# keyring is initialised from archlinuxarm-keyring, the kernel and firmware a
# container never boots are removed, the system is upgraded and base-devel is
# installed, as archlinux:base-devel has it. Packages are still checked against
# their signatures.
#
# Usage: scripts/ci-archlinuxarm-image.sh [TAG]   (default lyona-archlinuxarm:base-devel)
#
# Needs an aarch64 Docker host (GitHub's ubuntu-24.04-arm runner), curl, gpg
# and md5sum. Then: scripts/ci-local.sh --base-image TAG [TARGET].
set -euo pipefail

tag=${1:-lyona-archlinuxarm:base-devel}
tarball=ArchLinuxARM-aarch64-latest.tar.gz
# Arch Linux ARM Build System <builder@archlinuxarm.org>
signer=68B3537F39A313B3E574D06777193F152BDBE6A6
# Mirrors with a valid HTTPS certificate (mirror.archlinuxarm.org, the
# redirector, has none). ALARM_MIRRORS overrides the list.
read -r -a mirrors <<<"${ALARM_MIRRORS:-https://ca.us.mirror.archlinuxarm.org https://fl.us.mirror.archlinuxarm.org https://de3.mirror.archlinuxarm.org}"

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
key=$repo/scripts/ci-archlinuxarm.asc

die() {
	printf 'ci-archlinuxarm-image: %s\n' "$*" >&2
	exit 1
}

[[ $tag =~ ^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_.-]+)?$ ]] || die "invalid image tag: $tag"
# The root filesystem is aarch64; an x86_64 Docker host cannot run it without
# emulation, and the suite under emulation is not what this job measures.
[[ $HOSTTYPE == aarch64 ]] || die "this builds an aarch64 image and needs an aarch64 Docker host (this one is $HOSTTYPE)"
for tool in docker curl gpg md5sum sha256sum gzip tar; do
	command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
[[ -f $key ]] || die "the Arch Linux ARM signing key is missing: $key"

work_root=${RUNNER_TEMP:-${DWM_TEST_TMP_ROOT:-${HOME:?HOME is required}/tmp}}
mkdir -p -- "$work_root"
work=$(mktemp -d "$work_root/lyona-archlinuxarm.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -m 0700 "$work/gnupg" "$work/dl" "$work/context"

fetched=
for mirror in "${mirrors[@]}"; do
	[[ $mirror == https://* ]] || die "mirror is not HTTPS: $mirror"
	printf '==> Downloading %s from %s\n' "$tarball" "$mirror"
	if curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 5 \
		-o "$work/dl/$tarball.sig" "$mirror/os/$tarball.sig" &&
		curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 5 \
			-o "$work/dl/$tarball.md5" "$mirror/os/$tarball.md5" &&
		curl -fSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 5 --no-progress-meter \
			-o "$work/dl/$tarball" "$mirror/os/$tarball"; then
		fetched=$mirror
		break
	fi
	printf '==> %s failed; trying the next mirror\n' "$mirror" >&2
	rm -f -- "$work/dl/"*
done
[[ -n $fetched ]] || die "no mirror served $tarball"

# The signature: a good one, by the pinned key, and nothing else accepted.
gpg --homedir "$work/gnupg" --batch --quiet --import "$key" 2>/dev/null ||
	die "could not import $key"
status=$(gpg --homedir "$work/gnupg" --batch --status-fd 1 \
	--verify "$work/dl/$tarball.sig" "$work/dl/$tarball" 2>/dev/null) || true
# VALIDSIG's fields: the signing key, the signature's date, ..., and last the
# primary key's fingerprint.
signed=$(printf '%s\n' "$status" | awk -v fpr="$signer" \
	'$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $NF == fpr { print $4; exit }')
[[ $signed =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
	die "$tarball from $fetched is not signed by $signer; not using it"

# The mirror's checksum, read as data: one MD5 for this file name.
read -r want name <"$work/dl/$tarball.md5" || die "$tarball.md5 is empty"
[[ $want =~ ^[0-9a-f]{32}$ && $name == "$tarball" ]] || die "$tarball.md5 is not a checksum of $tarball"
have=$(md5sum "$work/dl/$tarball" | cut -d' ' -f1)
[[ $have == "$want" ]] || die "$tarball does not match its published checksum"

sha256=$(sha256sum "$work/dl/$tarball" | cut -d' ' -f1)
printf '==> %s: signed by %s on %s; checksum matches; SHA-256 %s\n' \
	"$tarball" "$signer" "$signed" "$sha256"

rootfs=lyona-archlinuxarm-rootfs:${sha256:0:12}
if ! docker image inspect "$rootfs" >/dev/null 2>&1; then
	# Without the kernel, its modules and the firmware (about 1.3 GB of the 2):
	# a container boots none of them, and the runner's disk is small.
	printf '==> Importing the root filesystem (without /boot, modules and firmware)\n'
	gzip -dc "$work/dl/$tarball" |
		tar --warning=no-unknown-keyword --delete -f - ./boot ./usr/lib/firmware ./usr/lib/modules |
		docker import - "$rootfs" >/dev/null
fi
rm -f -- "$work/dl/$tarball"

cat >"$work/context/Dockerfile" <<EOF
FROM $rootfs
RUN sed -i '/^\\[options\\]/a DisableSandbox' /etc/pacman.conf \\
 && pacman-key --init \\
 && pacman-key --populate archlinuxarm \\
 && pacman -R --noconfirm linux-aarch64 linux-firmware \\
 && pacman -Syu --noconfirm --needed base-devel \\
 && rm -rf /var/cache/pacman/pkg/*
LABEL org.lyona.archlinuxarm.sha256="$sha256" org.lyona.archlinuxarm.signed="$signed"
# As archlinux:base-devel sets it: without it Qt warns on stderr about the C
# locale, into output the tests compare.
ENV LANG=C.UTF-8
CMD ["/usr/bin/bash"]
EOF
printf '==> Building %s\n' "$tag"
docker build -t "$tag" "$work/context"
printf '==> %s is ready (Arch Linux ARM root filesystem signed %s, SHA-256 %s)\n' \
	"$tag" "$signed" "$sha256"
