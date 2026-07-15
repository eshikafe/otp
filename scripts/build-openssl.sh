#!/usr/bin/env bash
# build-openssl.sh <ssl-src-dir> <install-prefix> <target-triple> <jobs>
#
# Builds a static-only OpenSSL with the same pinned zig-cc target as the
# rest of the release, so the crypto NIF carries its own OpenSSL and the
# resulting OTP release does not depend on the host's libssl/libcrypto.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

src="$1"
prefix="$(pwd)/$2"
target="$3"
jobs="$4"

if [ -f "$prefix/.done" ]; then
    echo "openssl: already built at $prefix"
    exit 0
fi

make_toolchain "$target"

cd "$src"

# no-shared      -> static libcrypto.a/libssl.a only
# no-module      -> no dlopen'd providers (keeps the NIF self-contained)
# no-tests/docs  -> faster CI
./Configure linux-x86_64 \
    no-shared no-module no-tests \
    --prefix="$prefix" \
    --libdir=lib \
    -fPIC

make -j"$jobs"
make install_sw
touch "$prefix/.done"
echo "openssl: installed to $prefix"
