#!/usr/bin/env bash
# Regenerate sdk-test.log from the FINAL 0.2.15 tree, after the package build. Run in a slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
rm -f Cargo.lock
{
    echo "== cargo test --offline (final 0.2.15 tree) =="
    cargo test --offline 2>&1
    echo "exit=$?"
} >"$EV/sdk-test.log"
rm -f Cargo.lock
grep -E "Compiling actuallyadditions|^test result|^exit=" "$EV/sdk-test.log"
