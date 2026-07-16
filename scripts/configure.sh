#!/usr/bin/env bash
# configure.sh <otp-src-dir> <target-triple> <ssl-prefix> <static|system> <ncurses-prefix>
#
# Runs OTP's ./configure with every probe compiled by zig cc pinned to
# the generic target. Host arch == target arch, and host glibc >= the
# pinned floor, so configure's compile-and-run probes execute correctly
# while still linking only old symbols.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

src="$1"
target="$2"
ssl_prefix="$(pwd)/$3"
ssl_mode="$4"
ncurses_prefix="$(pwd)/$5"

make_toolchain "$target"

cd "$src"
export ERL_TOP="$(pwd)"

# zig cc searches no host system paths at all (not even /usr/include or
# /usr/lib), so erts configure's plain AC_CHECK_LIB(tinfo, tgetent, ...)
# probe would otherwise never find a termcap library - OTP has no
# --with-termcap=PATH option, it relies on the compiler's own search
# path. Point it at the pinned static ncurses build instead of the host's.
export CPPFLAGS="-I$ncurses_prefix/include${CPPFLAGS:+ $CPPFLAGS}"
export LDFLAGS="-L$ncurses_prefix/lib${LDFLAGS:+ $LDFLAGS}"

# Re-running configure is cheap relative to the build, but skip it when
# nothing changed (marker carries the exact argument fingerprint).
ssl_args=()
if [ "$ssl_mode" = "static" ]; then
    ssl_args+=(--with-ssl="$ssl_prefix" --disable-dynamic-ssl-lib)
else
    ssl_args+=(--with-ssl)
fi

args=(
    # Generic-release policy: no GUI/Java/ODBC deps, JIT on (x86-64 is
    # BeamAsm's primary arch), bundled zlib/zstd so we don't pick up
    # host libs, year-2038 safe by default on 64-bit.
    --enable-jit
    --enable-kernel-poll
    --enable-builtin-zlib
    --without-wx
    --without-observer
    --without-debugger
    --without-et
    --without-odbc
    --without-javac
    --without-jinterface
    "${ssl_args[@]}"
)

fingerprint="target=$target ssl=$ssl_mode ${args[*]}"
if [ -f .zig-configured ] && [ "$(cat .zig-configured)" = "$fingerprint" ]; then
    echo "configure: up to date"
    exit 0
fi

./configure "${args[@]}"

printf '%s' "$fingerprint" > .zig-configured
echo "configure: done"
