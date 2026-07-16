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

    # zig cc/c++'s clang frontend has a bug (present on every tested Zig
    # release, 0.13 through 0.16): feeding 2+ source files to one -M/-MM
    # invocation together with our versioned glibc-floor target corrupts
    # compiler-resource-header lookups from the 2nd file onward. It
    # surfaces differently per Zig version - a mangled target-triple
    # parse error on 0.15.x/0.16.0, or missing stddef.h/limits.h causing
    # a downstream "#error" on 0.13.0 - but single-file invocations are
    # clean on every version tested. erts' Makefiles batch many files
    # into one -M/-MM call to build a combined depend.mk, so the wrapper
    # splits those into one zig invocation per file instead.
    # zig cc/c++ also can't generate precompiled headers (-x c++-header
    # -c ... -o *.gch): it always fails with "ld.lld: error: ...: unknown
    # file type", reproduced even with a bare `zig c++` call and a
    # trivial one-line header, so it's a genuine upstream limitation, not
    # a flag/target issue. Clang treats a missing or invalid PCH as
    # optional - it falls back to textual inclusion of the plain header
    # with just a warning - so the wrapper skips real PCH generation and
    # drops an empty placeholder at the requested .gch path instead.
    cat > "$tooldir/zcc" << WRAP
#!/usr/bin/env bash
set -euo pipefail
args=("\$@")
pch_out=""
prev=""
for a in "\${args[@]}"; do
    if [ "\$prev" = "-o" ]; then
        pch_out="\$a"
    fi
    prev="\$a"
done
case " \${args[*]} " in
    *" c-header "*|*" c++-header "*)
        case "\$pch_out" in
            *.gch)
                mkdir -p "\$(dirname "\$pch_out")"
                : > "\$pch_out"
                exit 0
                ;;
        esac
        ;;
esac
is_dep=0
for a in "\${args[@]}"; do
    if [ "\$a" = "-M" ] || [ "\$a" = "-MM" ]; then
        is_dep=1
        break
    fi
done
if [ "\$is_dep" = "1" ]; then
    flags=("\${args[@]}")
    files=()
    while [ "\${#flags[@]}" -gt 0 ]; do
        last="\${flags[-1]}"
        case "\$last" in
            -*) break ;;
            *) files=("\$last" "\${files[@]}"); flags=("\${flags[@]:0:\${#flags[@]}-1}") ;;
        esac
    done
    if [ "\${#files[@]}" -gt 1 ]; then
        for f in "\${files[@]}"; do
            "$zig" cc -target $target "\${flags[@]}" "\$f"
        done
        exit 0
    fi
fi
exec "$zig" cc -target $target "\$@"
WRAP
    cat > "$tooldir/zcxx" << WRAP
#!/usr/bin/env bash
set -euo pipefail
args=("\$@")
pch_out=""
prev=""
for a in "\${args[@]}"; do
    if [ "\$prev" = "-o" ]; then
        pch_out="\$a"
    fi
    prev="\$a"
done
case " \${args[*]} " in
    *" c-header "*|*" c++-header "*)
        case "\$pch_out" in
            *.gch)
                mkdir -p "\$(dirname "\$pch_out")"
                : > "\$pch_out"
                exit 0
                ;;
        esac
        ;;
esac
is_dep=0
for a in "\${args[@]}"; do
    if [ "\$a" = "-M" ] || [ "\$a" = "-MM" ]; then
        is_dep=1
        break
    fi
done
if [ "\$is_dep" = "1" ]; then
    flags=("\${args[@]}")
    files=()
    while [ "\${#flags[@]}" -gt 0 ]; do
        last="\${flags[-1]}"
        case "\$last" in
            -*) break ;;
            *) files=("\$last" "\${files[@]}"); flags=("\${flags[@]:0:\${#flags[@]}-1}") ;;
        esac
    done
    if [ "\${#files[@]}" -gt 1 ]; then
        for f in "\${files[@]}"; do
            "$zig" c++ -target $target "\${flags[@]}" "\$f"
        done
        exit 0
    fi
fi
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
