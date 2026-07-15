#!/usr/bin/env bash
# stage.sh <src-dir-from-zig-package-cache> <dst-dir>
#
# The Zig package cache must never be mutated (a configure/make build
# writes all over its tree and would poison the content-addressed
# cache), so we copy the source into a writable working directory.
# A marker file keyed on the source path lets us skip re-staging when
# the pinned dependency hasn't changed.
set -euo pipefail

src="$1"
dst="$2"

marker="$dst/.staged-from"
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$src" ]; then
    exit 0
fi

rm -rf "$dst"
mkdir -p "$dst"
cp -a "$src/." "$dst/"
chmod -R u+w "$dst"
printf '%s' "$src" > "$marker"
echo "staged: $src -> $dst"
