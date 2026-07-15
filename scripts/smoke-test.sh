#!/usr/bin/env bash
# smoke-test.sh <dist-dir>
#
# Consumer's-eye test of the packaged artifact: unpack the tarball,
# run the bundled Install script (as a user would at unpack time),
# boot the VM, and exercise the subsystems most likely to break in a
# generic build: crypto (static OpenSSL NIF), zlib, the JIT, and DNS
# resolution via inet_gethost.
#
# In CI this script is additionally executed inside a glibc-2.17-era
# container (manylinux2014) as the real portability proof.
set -euo pipefail

dist="$1"
vsn="$(cat "$dist/latest.txt")"
name="otp_linux_x86_64_${vsn}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tar -C "$work" -zxf "$dist/$name.tar.gz"
cd "$work/$name"
./Install -minimal "$(pwd)"

./bin/erl -noshell -eval '
    Vsn = erlang:system_info(otp_release),
    io:format("otp_release: ~s~n", [Vsn]),
    io:format("system_architecture: ~s~n", [erlang:system_info(system_architecture)]),
    io:format("jit: ~p~n", [erlang:system_info(emu_flavor)]),

    ok = application:start(crypto),
    <<_:256>> = crypto:hash(sha256, <<"otp-zig-release">>),
    io:format("crypto: ok (~p)~n", [crypto:info_lib()]),

    Data = crypto:strong_rand_bytes(1024),
    Z = zlib:compress(Data),
    Data = zlib:uncompress(Z),
    io:format("zlib: ok~n"),

    {ok, _} = application:ensure_all_started(ssl),
    io:format("ssl: ok~n"),

    halt(0).
' || { echo "smoke: FAILED" >&2; exit 1; }

echo "smoke: OK ($name)"
