#!/usr/bin/env bash
# Shared helpers: pins the zig-cc toolchain wrappers for a given target.
# Every native object in the release is produced through these wrappers,
# which is the single mechanism that makes the build "generic".
set -euo pipefail

make_toolchain() {
    # $1 = target triple (e.g. x86_64-linux-gnu.2.17)
    # Creates wrapper executables under build-work/toolchain and exports
    # CC/CXX/LD/AR/RANLIB/DED_* pointing at them.
    local target="$1"
    local tooldir
    tooldir="$(pwd)/build-work/toolchain"
    mkdir -p "$tooldir"

    local zig
    zig="$(command -v zig)"
    if [ -z "$zig" ]; then
        echo "error: zig not found on PATH" >&2
        exit 1
    fi

    cat > "$tooldir/zcc" << WRAP
#!/usr/bin/env bash
exec "$zig" cc -target $target "\$@"
WRAP
    cat > "$tooldir/zcxx" << WRAP
#!/usr/bin/env bash
exec "$zig" c++ -target $target "\$@"
WRAP
    cat > "$tooldir/zar" << WRAP
#!/usr/bin/env bash
exec "$zig" ar "\$@"
WRAP
    cat > "$tooldir/zranlib" << WRAP
#!/usr/bin/env bash
exec "$zig" ranlib "\$@"
WRAP
    chmod +x "$tooldir"/z*

    export CC="$tooldir/zcc"
    export CXX="$tooldir/zcxx"
    export LD="$tooldir/zcc"
    export AR="$tooldir/zar"
    export RANLIB="$tooldir/zranlib"

    # Dynamically loaded Erlang drivers/NIFs must go through the same
    # pinned toolchain, or they would reintroduce host-glibc symbols.
    # OTP's configure honours the DED_LD* family (set all or none).
    export DED_LD="$tooldir/zcc"
    export DED_LDFLAGS="-shared"
    export DED_LDFLAGS_CONFTEST="-shared"
    export DED_LD_FLAG_RUNTIME_LIBRARY_PATH="-Wl,-rpath,"

    # Perl can misbehave under exotic locales during the OTP build.
    export LANG=C LC_ALL=C
}
