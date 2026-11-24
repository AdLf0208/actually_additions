#!/usr/bin/env bash
# 0.2.15 red proof: the per-machine comparator formula does not exist yet. Run inside a build slot.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
rm -f Cargo.lock
{
    echo "== cargo test --offline (analog_strength is still todo!()) =="
    cargo test --offline 2>&1
    echo "exit=$?"
} >"$EV/sdk-test-red-comparator.log"
rm -f Cargo.lock
grep -E "not yet implemented|^test result|^exit=|each_machine_reports" "$EV/sdk-test-red-comparator.log" | head -30
