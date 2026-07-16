#!/usr/bin/env bash
# build-ncurses.sh <ncurses-src-dir> <install-prefix> <target-triple> <jobs>
#
# Builds a static-only, terminfo-only ncurses (libtinfo.a) with the same
# pinned zig-cc target as the rest of the release, so the Erlang shell's
# line editing does not depend on the host's libtinfo/libncurses - the
# same portability rationale as the static OpenSSL build.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

src="$1"
prefix="$(pwd)/$2"
target="$3"
jobs="$4"

if [ -f "$prefix/.done" ]; then
    echo "ncurses: already built at $prefix"
    exit 0
fi

make_toolchain "$target"

cd "$src"

# --with-termlib      -> split out libtinfo.a (what OTP's tgetent probe
#                         links against) instead of only the full curses lib
# --without-shared     -> static archives only
# --without-cxx*        -> skip the C++ binding (not needed, avoids zcxx
#                         surface area)
# --without-manpages/progs/tests -> library only, faster build
# --disable-widec      -> classic (non-wide) terminfo is all OTP's erl_tty
#                         probe needs
./configure \
    --prefix="$prefix" \
    --with-termlib \
    --without-shared \
    --with-normal \
    --without-cxx \
    --without-cxx-binding \
    --without-ada \
    --without-manpages \
    --without-progs \
    --without-tests \
    --disable-widec \
    --enable-symlinks

make -j"$jobs"
make install.libs
touch "$prefix/.done"
echo "ncurses: installed to $prefix"
