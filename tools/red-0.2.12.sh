#!/usr/bin/env bash
# 0.2.12 red proof: the detonation-lens rules do not exist yet. Run inside a build slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
rm -f Cargo.lock
{
    echo "== cargo test --offline (the detonation-lens rules do not exist yet) =="
    cargo test --offline 2>&1
    echo "exit=$?"
} >"$EV/sdk-test-red-detonation.log"
rm -f Cargo.lock
grep -E "error\[E|error: cannot find|^test result|^exit=" "$EV/sdk-test-red-detonation.log" | head -30
