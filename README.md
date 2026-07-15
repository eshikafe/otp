# Zig build system for Erlang/OTP

Automated, generic Erlang/OTP binary releases for **x86_64 Linux**, built
with the **Zig build system** and `zig cc` pinned to `x86_64-linux-gnu.2.17`.

Each new upstream OTP release is detected daily and published as:

```
otp_linux_x86_64_<vsn>.tar.gz          # unpacks to otp_linux_x86_64_<vsn>/
otp_linux_x86_64_<vsn>.tar.gz.sha256   # sha256sum -c compatible
```

The name follows the upstream artifact convention (`otp_src_<vsn>.tar.gz`,
`otp_win64_<vsn>.exe`, ...). Release tags mirror upstream (`OTP-<vsn>`).

## Consuming a release

```sh
curl -fLO https://github.com/<you>/otp-zig-release/releases/download/OTP-27.3/otp_linux_x86_64_27.3.tar.gz
curl -fLO https://github.com/<you>/otp-zig-release/releases/download/OTP-27.3/otp_linux_x86_64_27.3.tar.gz.sha256
sha256sum -c otp_linux_x86_64_27.3.tar.gz.sha256
tar -zxf otp_linux_x86_64_27.3.tar.gz
cd otp_linux_x86_64_27.3
./Install -minimal "$(pwd)"      # relocatable; run again if you move it
./bin/erl
```

Runs on any x86_64 Linux with glibc >= 2.17 (RHEL/CentOS 7 era and newer).
crypto/ssl carry a statically linked, pinned OpenSSL — no host libssl needed.

## Building locally

Prerequisites: `zig` (pinned, see `.github/workflows/release.yml`),
`make`, `perl`, `file`, `binutils` (for `strip`/`objdump`), a C runtime
capable host (the Erlang bootstrap executes on the build host).

One-time bootstrap (populates the dependency hashes):

```sh
zig fetch --save=otp     https://github.com/erlang/otp/releases/download/OTP-27.3/otp_src_27.3.tar.gz
zig fetch --save=openssl https://github.com/openssl/openssl/releases/download/openssl-3.3.1/openssl-3.3.1.tar.gz
```

Then:

```sh
zig build package        # -> zig-out/dist/otp_linux_x86_64_<vsn>.tar.gz
zig build verify         # glibc symbol floor gate
zig build smoke          # unpack + Install + boot + crypto/zlib/ssl checks
```

Individual phases for debugging: `zig build stage | openssl | configure |
compile | release`.

Options: `-Djobs=N`, `-Dglibc=2.17`, `-Dstatic-ssl=true|false`.

## How it works

```
build.zig.zon        pins otp + openssl source tarballs (content-hashed)
build.zig            step graph + options; no shell logic
scripts/common.sh    generates zig-cc wrapper toolchain (CC/CXX/AR/DED_LD...)
scripts/stage.sh     copies read-only package cache -> writable build-work/
scripts/build-openssl.sh  static OpenSSL with the same pinned target
scripts/configure.sh OTP ./configure under the pinned toolchain
scripts/compile.sh   make (C via zig cc, Erlang bootstrap via shipped beams)
scripts/release.sh   make release RELEASE_ROOT=...
scripts/package.sh   reads OTP_VERSION -> otp_linux_x86_64_<vsn>.tar.gz
scripts/verify-glibc.sh  objdump gate: no symbol above the glibc floor
scripts/smoke-test.sh    consumer's-eye boot test (also run in manylinux2014)
scripts/update-otp.sh    repins to the latest upstream release (CI cron)
```

Design decisions (the two that define "generic"):

1. **glibc floor via `zig cc -target x86_64-linux-gnu.2.17`.** Every
   native object — VM, support programs, NIFs, drivers, and the bundled
   OpenSSL — goes through the same pinned wrappers, including OTP's
   `DED_LD` path for dynamically loaded drivers/NIFs. Dynamic loading
   keeps working (unlike a static-musl build), so user NIFs are fine.
2. **Static, pinned OpenSSL** (`no-shared no-module`, built with the same
   target) linked into the crypto NIF via `--with-ssl=<prefix>
   --disable-dynamic-ssl-lib`, so releases don't depend on host OpenSSL.

Two portability gates run on every build:

* `verify`: `objdump -T` over every ELF; fails on any `GLIBC_x.y` above
  the floor.
* smoke test inside `quay.io/pypa/manylinux2014_x86_64` (glibc 2.17).

## Automation

* Daily cron queries the GitHub releases API; a new `OTP-<vsn>` triggers
  `zig fetch --save=otp <tarball>` and an automated bump PR (one-line
  `build.zig.zon` diff).
* Merge to main builds, gates, and publishes `OTP-<vsn>` with the tarball
  and checksum. Patch releases flow through untouched.
* A weekly canary builds upstream `master` so major-version breakage
  (new configure options, source layout changes) surfaces early.
* The Zig version is pinned; Zig upgrades are their own PRs.
* The OpenSSL pin is bumped manually on purpose — crypto bumps deserve a
  human review.

## Known sharp edges

* **configure vs `zig cc`**: OTP's configure occasionally trips on
  compilers that aren't literally gcc/clang binaries (flag probing,
  `-Wl,` handling). The wrapper-script approach (`build-work/toolchain/zcc`)
  avoids the multi-word `CC` problems; if a specific OTP version's probe
  misfires, override the corresponding `erl_xcomp_*`/cache variable in
  `scripts/configure.sh` rather than patching the tree.
* **Terminal library**: the shell's line editing needs termcap/terminfo.
  The default here links against ncurses found at configure time; for a
  fully host-independent tty layer, install a *static* ncurses/tinfo in
  the build image and point configure at it, or accept
  `--without-termcap` (degraded shell). The glibc gate will tell you if
  the chosen path leaks host symbols.
* **JIT**: BeamAsm is C++ (vendored asmjit) built via `zig c++`. If a new
  OTP bumps its C++ requirements past the pinned Zig's clang, the canary
  will catch it.
* **Phase 2**: `build.zig` deliberately owns only the step graph, so the
  `compile` step can later be replaced by a native
  `addCSourceFiles`-based ERTS build (per-target `config.h`, wrapped Perl
  generators) without changing artifacts, names, gates, or CI.
