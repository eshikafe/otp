#!/usr/bin/env bash
# update-otp.sh [--check-only]
#
# Points the `otp` dependency in build.zig.zon at the latest upstream
# release. Detection is via the GitHub releases API; the repin is done
# with `zig fetch --save=otp`, which downloads the tarball, computes the
# content hash, and rewrites build.zig.zon in one step.
#
# Exit codes: 0 = updated (or already latest with --check-only prints it),
#             3 = already up to date (nothing to do).
set -euo pipefail

api="https://api.github.com/repos/erlang/otp/releases/latest"

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

release_json="$(mktemp)"
trap 'rm -f "$release_json"' EXIT
curl -fsSL "${auth[@]}" "$api" -o "$release_json"
latest_tag="$(grep -m1 '"tag_name"' "$release_json" | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
# tag_name looks like "OTP-27.3"
latest_vsn="${latest_tag#OTP-}"

if [ -z "$latest_vsn" ] || [[ "$latest_tag" != OTP-* ]]; then
    echo "error: could not determine latest OTP version from $api (got '$latest_tag')" >&2
    exit 1
fi

current_vsn="$(sed -n 's#.*erlang/otp/releases/download/OTP-\([^/]*\)/otp_src_.*#\1#p' build.zig.zon | head -n1)"

echo "current: ${current_vsn:-<none>}  latest: $latest_vsn"

if [ "${current_vsn:-}" = "$latest_vsn" ]; then
    echo "already up to date"
    exit 3
fi

if [ "${1:-}" = "--check-only" ]; then
    echo "update available: $latest_vsn"
    exit 0
fi

url="https://github.com/erlang/otp/releases/download/OTP-${latest_vsn}/otp_src_${latest_vsn}.tar.gz"
echo "repinning otp -> $url"
zig fetch --save=otp "$url"

echo "updated build.zig.zon to OTP-$latest_vsn"
echo "$latest_vsn" > .otp-latest
