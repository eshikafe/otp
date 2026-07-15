#!/usr/bin/env bash
# verify-glibc.sh <release-root> <glibc-floor>
#
# Hard portability gate: scans every ELF in the release for versioned
# GLIBC_x.y symbol references and fails if anything exceeds the floor.
# Catches regressions where a new OTP version (or a stray host library)
# pulls in a newer libc symbol than the pinned target allows.
set -euo pipefail

root="$1"
floor="$2"

floor_major="${floor%%.*}"
floor_minor="${floor#*.}"

fail=0
while IFS= read -r f; do
    case "$(file -b "$f")" in ELF*) ;; *) continue ;; esac
    syms="$(objdump -T "$f" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV || true)"
    [ -z "$syms" ] && continue
    while IFS= read -r s; do
        v="${s#GLIBC_}"
        major="${v%%.*}"
        rest="${v#*.}"
        minor="${rest%%.*}"
        if [ "$major" -gt "$floor_major" ] || { [ "$major" -eq "$floor_major" ] && [ "$minor" -gt "$floor_minor" ]; }; then
            echo "FAIL: $f requires $s (floor is GLIBC_$floor)"
            fail=1
        fi
    done <<< "$syms"
done < <(find "$root" -type f)

if [ "$fail" -ne 0 ]; then
    echo "verify-glibc: FAILED - release is not generic down to glibc $floor" >&2
    exit 1
fi
echo "verify-glibc: OK (no symbol above GLIBC_$floor)"
