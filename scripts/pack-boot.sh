#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: bash $0 SOURCE_BOOT.img MIUI_ANYKERNEL.zip [OUTPUT_BOOT.img]"
    echo "Use MAGISKBOOT=/path/to/magiskboot to select a native Linux binary."
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

if [[ ${1-} == -h || ${1-} == --help ]]; then
    usage
    exit 0
fi
if (( $# < 2 || $# > 3 )); then
    usage >&2
    exit 2
fi

source_boot=$(realpath -e -- "$1")
kernel_zip=$(realpath -e -- "$2")
output=$(realpath -ms -- "${3:-boot-nova.img}")
[[ -f "$source_boot" && -f "$kernel_zip" ]] || fail "Input files are required."
[[ ! -e "$output" && ! -L "$output" ]] || fail "Output already exists: $output"
command -v unzip >/dev/null || fail "Install unzip first."

read -r header_version < <(od -An --endian=little -tu4 -j40 -N4 -- "$source_boot")
[[ "$header_version" == 3 ]] || fail "Expected an Android boot image with header v3."

work=$(mktemp -d -- "$(dirname -- "$output")/.pack-boot.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/input" "$work/output"

if [[ -n ${MAGISKBOOT-} ]]; then
    magiskboot=$(command -v -- "$MAGISKBOOT") || fail "Cannot find MAGISKBOOT: $MAGISKBOOT"
    boottool=("$(realpath -e -- "$magiskboot")")
else
    unzip -p "$kernel_zip" tools/magiskboot > "$work/magiskboot"
    chmod u+x "$work/magiskboot"
    case "$(uname -m)" in
        armv*l) boottool=("$work/magiskboot") ;;
        *)
            qemu=$(command -v qemu-arm || command -v qemu-arm-static) ||
                fail "Install qemu-user, or set MAGISKBOOT to a native Linux binary."
            boottool=("$(realpath -e -- "$qemu")" "$work/magiskboot")
            ;;
    esac
fi

unzip -p "$kernel_zip" kernels/Image > "$work/Image"
[[ -s "$work/Image" ]] || fail "The ZIP is missing kernels/Image."

cd "$work/input"
"${boottool[@]}" unpack -n -h "$source_boot"
[[ -s kernel && -s ramdisk.cpio ]] || fail "The source boot image must contain a kernel and ramdisk."
cp -- "$work/Image" kernel
PATCHVBMETAFLAG=false "${boottool[@]}" repack "$source_boot" "$work/boot.img"

cd "$work/output"
"${boottool[@]}" unpack -n -h "$work/boot.img"
cmp -s ramdisk.cpio "$work/input/ramdisk.cpio" || fail "Ramdisk verification failed."
cmp -s header "$work/input/header" || fail "Boot metadata verification failed."
# In a v3 header, only the kernel-size field should change.
cmp -s -i 12 -n 4084 -- "$source_boot" "$work/boot.img" || fail "Boot header verification failed."
if ! cmp -s kernel "$work/Image"; then
    "${boottool[@]}" decompress kernel kernel.raw
    cmp -s kernel.raw "$work/Image" || fail "Kernel verification failed."
fi
(( $(stat -c '%s' "$work/boot.img") <= $(stat -c '%s' "$source_boot") )) ||
    fail "The repacked image is larger than the source."

mv -nT -- "$work/boot.img" "$output"
[[ ! -e "$work/boot.img" ]] || fail "Output already exists: $output"
sha256sum -- "$output"
