#!/usr/bin/env bash
# package.sh <otp-src-dir> <release-root> <out-dir> <glibc-floor>
#
# Names and packages the release following the upstream OTP artifact
# convention (otp_src_<vsn>.tar.gz, otp_win64_<vsn>.exe, ...):
#
#     otp_linux_x86_64_<vsn>.tar.gz          unpacks to otp_linux_x86_64_<vsn>/
#     otp_linux_x86_64_<vsn>.tar.gz.sha256   sha256sum -c compatible
#     latest.txt                             plain version pointer
#
# The version is read from OTP_VERSION inside the tree that was actually
# built, so the artifact name can never drift from its contents.
set -euo pipefail

src="$1"
release_root="$2"
out="$3"
glibc_floor="$4"

vsn="$(tr -d ' \n' < "$src/OTP_VERSION")"
if [ -z "$vsn" ]; then
    echo "error: could not read OTP_VERSION from $src" >&2
    exit 1
fi

name="otp_linux_x86_64_${vsn}"
mkdir -p "$out"
stage_parent="$(mktemp -d)"
trap 'rm -rf "$stage_parent"' EXIT

cp -a "$release_root" "$stage_parent/$name"

# Strip native binaries and shared objects (keep beams untouched).
find "$stage_parent/$name" -type f \( -name '*.so' -o -perm -u+x \) | while read -r f; do
    case "$(file -b "$f")" in
        ELF*) strip --strip-unneeded "$f" 2>/dev/null || true ;;
    esac
done

# Record provenance inside the tarball.
{
    echo "otp_version: $vsn"
    echo "target: x86_64-linux-gnu.$glibc_floor"
    echo "glibc_floor: $glibc_floor"
    echo "zig: $(zig version 2>/dev/null || echo unknown)"
    echo "built_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$stage_parent/$name/BUILD_INFO"

tar -C "$stage_parent" -zcf "$out/$name.tar.gz" "$name"
( cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256" )
printf '%s\n' "$vsn" > "$out/latest.txt"

echo "package: $out/$name.tar.gz"
