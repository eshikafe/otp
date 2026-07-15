const std = @import("std");

// otp-zig-release
// ----------------
// Produces a generic Erlang/OTP binary release for x86_64 Linux:
//
//     otp_linux_x86_64_<OTP_VSN>.tar.gz  (+ .sha256)
//
// Strategy (phase 1, "orchestrated" build):
//   * The OTP source tarball and a pinned OpenSSL are Zig package
//     dependencies (see build.zig.zon). Bumping OTP to the latest
//     release is a one-line `zig fetch --save=otp <url>` (automated
//     by scripts/update-otp.sh + CI).
//   * All native code is compiled with `zig cc` / `zig c++` pinned to
//     -target x86_64-linux-gnu.2.17, which is what makes the release
//     "generic" (runs on any distro with glibc >= 2.17, RHEL7+ era).
//   * OTP's own configure/make drive the compile; build.zig owns the
//     step graph, toolchain pinning, OpenSSL, packaging, naming, and
//     the glibc-symbol portability gate.
//
// Native ERTS-in-Zig compilation (phase 2) can later replace the
// `make` step without changing the outer steps, names, or CI.
//
// Steps:
//   zig build package   (default) stage -> openssl -> configure ->
//                       compile -> release -> package
//   zig build verify    glibc symbol gate on the packaged tree
//   zig build smoke     boot test of the packaged release
//
// Tested against Zig 0.13.x std.Build APIs.

pub fn build(b: *std.Build) void {
    // ------------------------------------------------------------------
    // Options
    // ------------------------------------------------------------------
    const jobs = b.option(
        u32,
        "jobs",
        "Parallel make jobs (default: CPU count)",
    ) orelse @as(u32, @intCast(std.Thread.getCpuCount() catch 4));

    const static_ssl = b.option(
        bool,
        "static-ssl",
        "Statically link a pinned OpenSSL into the crypto NIF (default: true)",
    ) orelse true;

    const glibc = b.option(
        []const u8,
        "glibc",
        "glibc floor for the generic target triple (default: 2.17)",
    ) orelse "2.17";

    const target_triple = b.fmt("x86_64-linux-gnu.{s}", .{glibc});

    // ------------------------------------------------------------------
    // Sources (fetched + verified by the Zig package manager)
    // ------------------------------------------------------------------
    const otp = b.dependency("otp", .{});
    const openssl = b.dependency("openssl", .{});

    // Everything mutable happens under build-work/ (gitignored).
    const work_otp = "build-work/otp";
    const work_ssl = "build-work/openssl";
    const ssl_prefix = "build-work/openssl-install";
    const release_root = "build-work/release";
    const out_dir = "zig-out/dist";

    const jobs_arg = b.fmt("{d}", .{jobs});

    // ------------------------------------------------------------------
    // 1. Stage: copy read-only package-cache sources into a writable tree
    // ------------------------------------------------------------------
    const stage_otp = b.addSystemCommand(&.{ "bash", "scripts/stage.sh" });
    stage_otp.setCwd(b.path("."));
    stage_otp.addDirectoryArg(otp.path("."));
    stage_otp.addArg(work_otp);

    const stage_ssl = b.addSystemCommand(&.{ "bash", "scripts/stage.sh" });
    stage_ssl.setCwd(b.path("."));
    stage_ssl.addDirectoryArg(openssl.path("."));
    stage_ssl.addArg(work_ssl);

    // ------------------------------------------------------------------
    // 2. Static OpenSSL built with the same zig-cc target
    // ------------------------------------------------------------------
    const build_ssl = b.addSystemCommand(&.{
        "bash",           "scripts/build-openssl.sh",
        work_ssl,         ssl_prefix,
        target_triple,    jobs_arg,
    });
    build_ssl.setCwd(b.path("."));
    build_ssl.step.dependOn(&stage_ssl.step);

    // ------------------------------------------------------------------
    // 3. configure (probes run through zig cc, so results reflect the
    //    pinned target, and host == target arch so run-tests are valid)
    // ------------------------------------------------------------------
    const configure = b.addSystemCommand(&.{
        "bash",        "scripts/configure.sh",
        work_otp,      target_triple,
        ssl_prefix,    if (static_ssl) "static" else "system",
    });
    configure.setCwd(b.path("."));
    configure.step.dependOn(&stage_otp.step);
    if (static_ssl) configure.step.dependOn(&build_ssl.step);

    // ------------------------------------------------------------------
    // 4. Compile (C/C++ via zig cc; Erlang bootstrap via shipped beams)
    // ------------------------------------------------------------------
    const compile = b.addSystemCommand(&.{
        "bash", "scripts/compile.sh", work_otp, jobs_arg,
    });
    compile.setCwd(b.path("."));
    compile.step.dependOn(&configure.step);

    // ------------------------------------------------------------------
    // 5. make release RELEASE_ROOT=...
    // ------------------------------------------------------------------
    const release = b.addSystemCommand(&.{
        "bash", "scripts/release.sh", work_otp, release_root,
    });
    release.setCwd(b.path("."));
    release.step.dependOn(&compile.step);

    // ------------------------------------------------------------------
    // 6. Package: read OTP_VERSION from the built tree, rename to the
    //    convention otp_linux_x86_64_<vsn>/, strip, tar, sha256.
    // ------------------------------------------------------------------
    const package = b.addSystemCommand(&.{
        "bash",       "scripts/package.sh",
        work_otp,     release_root,
        out_dir,      glibc,
    });
    package.setCwd(b.path("."));
    package.step.dependOn(&release.step);

    const package_step = b.step("package", "Build and package the generic release (default)");
    package_step.dependOn(&package.step);
    b.default_step = package_step;

    // ------------------------------------------------------------------
    // Gates (also wired independently so CI can re-run them on artifacts)
    // ------------------------------------------------------------------
    const verify = b.addSystemCommand(&.{
        "bash", "scripts/verify-glibc.sh", release_root, glibc,
    });
    verify.setCwd(b.path("."));
    verify.step.dependOn(&package.step);
    const verify_step = b.step("verify", "Fail if any ELF needs glibc symbols above the floor");
    verify_step.dependOn(&verify.step);

    const smoke = b.addSystemCommand(&.{
        "bash", "scripts/smoke-test.sh", out_dir,
    });
    smoke.setCwd(b.path("."));
    smoke.step.dependOn(&package.step);
    const smoke_step = b.step("smoke", "Unpack + Install + boot test the packaged tarball");
    smoke_step.dependOn(&smoke.step);

    // Convenience: individual phases addressable for debugging.
    b.step("stage", "Stage sources into build-work/").dependOn(&stage_otp.step);
    b.step("openssl", "Build the pinned static OpenSSL").dependOn(&build_ssl.step);
    b.step("configure", "Run OTP configure with the zig-cc toolchain").dependOn(&configure.step);
    b.step("compile", "Run the OTP compile").dependOn(&compile.step);
    b.step("release", "Stage the OTP release tree").dependOn(&release.step);
}
