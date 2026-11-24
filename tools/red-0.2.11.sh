#!/usr/bin/env bash
# 0.2.11 red proof: the miner-lens rules at todo!(). Run inside a build slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
rm -f Cargo.lock
{
    echo "== cargo test --offline (the miner-lens rules are todo!()) =="
    cargo test --offline 2>&1
    echo "exit=$?"
} >"$EV/sdk-test-red-lens-effect.log"
rm -f Cargo.lock
grep -E "panicked at|not yet implemented|^test result|^exit=" "$EV/sdk-test-red-lens-effect.log"
