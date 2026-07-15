#!/usr/bin/env bash
# release.sh <otp-src-dir> <release-root>
#
# Stages the built system into a relocatable release tree using OTP's
# own `make release` target. The Install script is deliberately NOT run
# here - upstream binary conventions leave it to be run at unpack time,
# which is what keeps the tarball relocatable.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

src="$1"
release_root="$(pwd)/$2"

target="$(sed -n 's/^target=\([^ ]*\).*/\1/p' "$src/.zig-configured")"
make_toolchain "$target"

rm -rf "$release_root"
mkdir -p "$release_root"

cd "$src"
export ERL_TOP="$(pwd)"

make release RELEASE_ROOT="$release_root"
echo "release: staged at $release_root"
