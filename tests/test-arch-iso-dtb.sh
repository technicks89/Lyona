#!/usr/bin/env bash
set -euo pipefail

# The aarch64 medium's device-tree step (ARM6-02), statically and stubbed:
# the copy of mkarchiso that fuses the Snapdragon X device trees into the
# kernel is made from archiso 91's, with each edit checked against the exact
# text it changes; the function that does the fusing picks its trees from the
# kernel package's own directory (the Snapdragon X family, no -el2) and calls
# ukify with systemd's stub and hardware-ID table. The real mkarchiso was
# checked by hand against archiso 91 (docs/evidence/arm6-01-snapdragon-spike.md);
# this test uses a stand-in with the same delimiters.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

patcher=$repo/scripts/lyona-mkarchiso-dtb
fuse=$repo/scripts/lyona-mkarchiso-fuse.sh
builder=$repo/scripts/build-lyona-arch-iso.sh
bash -n "$patcher" "$fuse"

# A stand-in for archiso 91's mkarchiso: the three places the patcher edits,
# shaped as archiso writes them (4-space indents), around lines of its own.
write_mkarchiso() { # FILE [omit-gate|two-functions|no-call|no-ukify|no-switch]
	local file=$1 variant=${2:-}
	{
		printf '%s\n' '#!/usr/bin/env bash' 'shopt -s extglob'
		printf '%s\n' '_make_stubble_efi() {' '    _msg_info "the original step"' '}'
		if [[ $variant == two-functions ]]; then
			printf '%s\n' '_make_stubble_efi() {' '    _msg_info "again"' '}'
		fi
		printf '%s\n' '_validate_requirements() {'
		printf '%s\n' "    if [[ \"\$arch\" == 'aarch64' ]]; then"
		[[ $variant == no-switch ]] || printf '%s\n' '        use_stubble=1'
		printf '%s\n' ''
		if [[ $variant != omit-gate ]]; then
			printf '%s\n' '        # shellcheck disable=SC2076' \
				"        if [[ ! \" \${pkg_list[*]} \" =~ ' stubble ' ]]; then" \
				"            _msg_warning \"'stubble' is not in the package list.\"" \
				'            use_stubble=0' \
				'        fi'
		fi
		if [[ $variant != no-ukify ]]; then
			printf '%s\n' '        if ! command -v ukify &>/dev/null; then' \
				"            _msg_warning \"'ukify' is not available on this host.\"" \
				'            use_stubble=0' \
				'        fi'
		fi
		printf '%s\n' '    fi' '}'
		printf '%s\n' '_build_iso_image() {' '    _run_once _copy_boot_out_of_pacstrap_dir' ''
		if [[ $variant != no-call ]]; then
			printf '%s\n' '    if (( use_stubble )); then' '        _run_once _make_stubble_efi' '    fi'
		fi
		printf '%s\n' '}'
	} >"$file"
}

# 1. The edit: the gate gone, the function replaced, the switch, the ukify
#    check and the call kept; the original untouched; the result executable.
write_mkarchiso "$work/mkarchiso"
cp "$work/mkarchiso" "$work/mkarchiso.orig"
"$patcher" "$work/mkarchiso" "$fuse" "$work/mkarchiso.lyona"
cmp -s "$work/mkarchiso" "$work/mkarchiso.orig" || fail 'the patcher modified its input'
[[ -x $work/mkarchiso.lyona ]] || fail 'the patched mkarchiso is not executable'
bash -O extglob -n "$work/mkarchiso.lyona" || fail 'the patched mkarchiso is not valid bash'
if grep -Fq "' stubble '" "$work/mkarchiso.lyona"; then fail 'the stubble package gate is still there'; fi
if grep -Fq 'the original step' "$work/mkarchiso.lyona"; then fail "archiso's own _make_stubble_efi is still there"; fi
grep -Fq 'Fusing the Snapdragon X device trees' "$work/mkarchiso.lyona" || fail 'the replacement function is not in the patched mkarchiso'
grep -Fxq '        use_stubble=1' "$work/mkarchiso.lyona" || fail 'the use_stubble switch was lost'
grep -Fxq '        if ! command -v ukify &>/dev/null; then' "$work/mkarchiso.lyona" || fail 'the ukify check was lost'
grep -Fxq '        _run_once _make_stubble_efi' "$work/mkarchiso.lyona" || fail 'the call to the step was lost'
[[ $(grep -c '^_make_stubble_efi() {$' "$work/mkarchiso.lyona") == 1 ]] || fail 'the patched mkarchiso does not have exactly one _make_stubble_efi'

# 2. Another archiso: each shape that changed is named, nothing is written.
expect_patch_failure() { # VARIANT MESSAGE
	write_mkarchiso "$work/odd" "$1"
	rm -f "$work/odd.out"
	if "$patcher" "$work/odd" "$fuse" "$work/odd.out" 2>"$work/odd.err"; then
		fail "the patcher accepted an mkarchiso with the shape: $1"
	fi
	grep -Fq "$2" "$work/odd.err" || fail "the patcher's message for $1 was: $(cat "$work/odd.err")"
	[[ ! -e $work/odd.out ]] || fail "the patcher wrote an output for $1"
}
expect_patch_failure omit-gate 'the stubble package gate was found 0 times'
expect_patch_failure two-functions '2 _make_stubble_efi() definitions'
expect_patch_failure no-call 'switch, ukify check or call is not as expected'
expect_patch_failure no-ukify 'switch, ukify check or call is not as expected'
expect_patch_failure no-switch 'switch, ukify check or call is not as expected'
printf '%s\n' '# no function here' >"$work/empty-fuse.sh"
write_mkarchiso "$work/odd"
if "$patcher" "$work/odd" "$work/empty-fuse.sh" "$work/odd.out" 2>"$work/odd.err"; then
	fail 'the patcher accepted a function file with no function'
fi
grep -Fq 'no _make_stubble_efi() { ... } block' "$work/odd.err" || fail "wrong message for an empty function file: $(cat "$work/odd.err")"
if "$patcher" "$work/mkarchiso" "$fuse" "$work/mkarchiso" 2>/dev/null; then fail 'the patcher overwrote its input'; fi
if "$patcher" "$work/missing" "$fuse" "$work/odd.out" 2>/dev/null; then fail 'the patcher accepted a missing input'; fi

# 3. The function itself, run against a fake root with a stub ukify.
fake=$work/fake
pacstrap_dir=$fake/pacstrap
boot_dir=$fake/boot
dtbs=$pacstrap_dir/boot/dtbs/qcom
mkdir -p "$pacstrap_dir/usr/lib/systemd/boot/efi" "$pacstrap_dir/usr/lib/systemd/boot/hwids/aa64" \
	"$dtbs" "$pacstrap_dir/usr/lib/modules/7.3.1-2-aarch64-ARCH" "$boot_dir" "$work/bin"
: >"$pacstrap_dir/usr/lib/systemd/boot/efi/linuxaa64.efi.stub"
: >"$pacstrap_dir/usr/lib/systemd/boot/hwids/aa64/x.json"
printf 'kernel\n' >"$boot_dir/vmlinuz-linux"
# Snapdragon X trees (kept), their EL2 siblings, and trees of other SoCs (left out).
for tree in x1e80100-dell-xps13-9345 x1e80100-crd x1p42100-asus-zenbook-a14 x1e78100-lenovo-thinkpad-t14s \
	x1e80100-dell-xps13-9345-el2 x1p42100-crd-el2 sc7180-acer-aspire1 sm8550-hdk glymur-crd apq8016-sbc; do
	: >"$dtbs/$tree.dtb"
done
mkdir -p "$dtbs/subdir"
: >"$dtbs/subdir/x1e80100-nested.dtb"

cat >"$work/bin/ukify" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$UKIFY_LOG"
for arg in "$@"; do
	case $arg in --output=*) printf 'FUSED\n' >"${arg#--output=}" ;; esac
done
EOF
chmod +x "$work/bin/ukify"

sed -n '/^_make_stubble_efi() {$/,/^}$/p' "$work/mkarchiso.lyona" >"$work/fused-function.sh"
run_function() { # runs the function with the fake root
	(
		# shellcheck disable=SC2034 # read by the function
		arch=aarch64
		# shellcheck disable=SC2034
		declare -A uefi_arch=(['aarch64']='AA64')
		# shellcheck disable=SC2329 # called by the sourced function
		_msg_info() { printf 'info: %s\n' "$*"; }
		# shellcheck disable=SC2329 # called by the sourced function
		_msg_error() {
			printf 'error: %s\n' "$1" >&2
			exit "${2:-0}"
		}
		export UKIFY_LOG=$work/ukify.args
		PATH=$work/bin:$PATH
		# shellcheck disable=SC1091
		. "$work/fused-function.sh"
		_make_stubble_efi
	)
}
run_function >"$work/function.out" 2>&1 || fail "the fusing function failed: $(cat "$work/function.out")"

grep -Fxq -- "--stub=$pacstrap_dir/usr/lib/systemd/boot/efi/linuxaa64.efi.stub" "$work/ukify.args" || fail "ukify was not given systemd's aarch64 stub: $(cat "$work/ukify.args")"
grep -Fxq -- "--linux=$boot_dir/vmlinuz-linux" "$work/ukify.args" || fail 'ukify was not given the medium kernel'
grep -Fxq -- "--hwids=$pacstrap_dir/usr/lib/systemd/boot/hwids/aa64/" "$work/ukify.args" || fail 'ukify was not given the hardware-ID directory'
grep -Fxq -- '--uname=7.3.1-2-aarch64-ARCH' "$work/ukify.args" || fail 'ukify was not given the kernel version'
mapfile -t fused < <(sed -n 's/^--devicetree-auto=//p' "$work/ukify.args")
expected=("$dtbs/x1e78100-lenovo-thinkpad-t14s.dtb" "$dtbs/x1e80100-crd.dtb" "$dtbs/x1e80100-dell-xps13-9345.dtb" "$dtbs/x1p42100-asus-zenbook-a14.dtb")
[[ ${fused[*]} == "${expected[*]}" ]] ||
	fail "the fused device trees are not the Snapdragon X trees without -el2, sorted: ${fused[*]}"
[[ $(cat "$boot_dir/vmlinuz-linux") == FUSED ]] || fail 'the medium kernel was not replaced by the fused one'
[[ ! -e $boot_dir/vmlinuz-linux.fused ]] || fail 'a temporary .fused file was left behind'
grep -Fq '4 device trees fused' "$work/function.out" || fail "the function did not report its count: $(cat "$work/function.out")"

# The set comes from the kernel's directory: a new Snapdragon X tree is fused
# with no change to the function, and no laptop is named in it.
: >"$dtbs/x1e80100-brand-new.dtb"
printf 'kernel\n' >"$boot_dir/vmlinuz-linux"
run_function >/dev/null 2>&1 || fail 'the fusing function failed with a new tree'
grep -Fxq -- "--devicetree-auto=$dtbs/x1e80100-brand-new.dtb" "$work/ukify.args" || fail 'a new Snapdragon X tree was not fused'
if sed -n '/^_make_stubble_efi() {$/,/^}$/p' "$fuse" | grep -Eiq 'xps|dell|inspiron|latitude|thinkpad|vivobook|zenbook|yoga'; then
	fail 'the fusing function names a laptop: the set must come from the kernel package'
fi

# Each missing input is named, and the kernel is left as it was.
expect_function_failure() { # DESCRIPTION MESSAGE
	local description=$1 message=$2
	printf 'kernel\n' >"$boot_dir/vmlinuz-linux"
	if run_function >"$work/function.out" 2>&1; then fail "the function succeeded with $description"; fi
	grep -Fq "$message" "$work/function.out" || fail "the message for $description was: $(cat "$work/function.out")"
	[[ $(cat "$boot_dir/vmlinuz-linux") == kernel ]] || fail "the kernel was changed with $description"
}
mkdir -p "$fake/saved"
mv "$pacstrap_dir/usr/lib/systemd/boot/efi/linuxaa64.efi.stub" "$fake/saved/"
expect_function_failure 'no EFI stub' 'EFI stub'
mv "$fake/saved/linuxaa64.efi.stub" "$pacstrap_dir/usr/lib/systemd/boot/efi/"
mv "$pacstrap_dir/usr/lib/systemd/boot/hwids" "$fake/saved/hwids"
expect_function_failure 'no hardware-ID directory' 'hwids'
mv "$fake/saved/hwids" "$pacstrap_dir/usr/lib/systemd/boot/hwids"
mkdir "$pacstrap_dir/usr/lib/modules/second"
expect_function_failure 'two kernels' 'Expected one kernel'
rmdir "$pacstrap_dir/usr/lib/modules/second"
find "$dtbs" -maxdepth 1 -name 'x1*' -delete
expect_function_failure 'no Snapdragon X trees' 'no Snapdragon X device trees'

# 4. The builder: ukify is required on an aarch64 host, the patched copy is made
#    from the repo's scripts and is the one that runs, in place of the stock one.
grep -Fq 'command -v ukify' "$builder" || fail 'the builder does not require ukify'
awk '/ukify not found/ { found = 1 } END { exit !found }' "$builder" || fail 'the builder does not say what to install for ukify'
# shellcheck disable=SC2016 # the builder's literal text
grep -Fq 'scripts/lyona-mkarchiso-dtb" "$mkarchiso_run"' "$builder" || fail 'the builder does not make the patched mkarchiso'
# shellcheck disable=SC2016 # the builder's literal text
grep -Fq '"$repo_dir/scripts/lyona-mkarchiso-fuse.sh" "$work_dir/mkarchiso"' "$builder" || fail 'the builder does not give the patcher the fusing function'
# shellcheck disable=SC2016 # the builder's literal text
grep -Fq '"$mkarchiso_run" -v -w "$work_dir/build"' "$builder" || fail 'the builder does not run the patched mkarchiso'
step=$(grep -n 'lyona-mkarchiso-dtb' "$builder" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016 # the builder's literal text
run=$(grep -n '"$mkarchiso_run" -v -w' "$builder" | head -1 | cut -d: -f1)
[[ $step -lt $run ]] || fail 'the patched mkarchiso is made after it should have run'
# x86_64 keeps the stock mkarchiso: the patch is for aarch64 only.
# shellcheck disable=SC2016 # a pattern for the builder's literal text
sed -n '/^if \[\[ \$arch == aarch64 \]\]; then$/,/^fi$/p' "$builder" | grep -Fq 'lyona-mkarchiso-dtb' ||
	fail 'the patched mkarchiso is not confined to aarch64'

printf 'Arch ISO device-tree step: PASS\n'
