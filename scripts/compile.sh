#!/usr/bin/env bash
# compile.sh <otp-src-dir> <jobs>
#
# Runs the OTP build. C/C++ goes through the pinned zig-cc wrappers
# (exported again here because make re-reads the environment); the
# Erlang side bootstraps from the pre-built beams shipped in the
# release tarball, then recompiles the world with the fresh compiler.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

src="$1"
jobs="$2"

# Target already baked into the wrappers created by configure.sh; we
# only need the wrappers back on the environment. Recreate them from
# the recorded fingerprint to stay self-contained.
target="$(sed -n 's/^target=\([^ ]*\).*/\1/p' "$src/.zig-configured")"
make_toolchain "$target"

cd "$src"
export ERL_TOP="$(pwd)"

make -j"$jobs"
echo "compile: done"
