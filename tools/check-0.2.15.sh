#!/usr/bin/env bash
# 0.2.15 registry checks: check, two fits runs (the pin and a different build).
# Run inside a build slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
{
    echo "== cargo horizon-mod check actuallyadditions.hmod =="
    cargo horizon-mod check actuallyadditions.hmod 2>&1
    echo "exit=$?"
} >"$EV/sdk-check.log"
{
    echo "== cargo horizon-mod fits actuallyadditions.hmod --build 0a875da =="
    cargo horizon-mod fits actuallyadditions.hmod --build 0a875da 2>&1
    echo "exit=$?"
} >"$EV/sdk-fits.log"
{
    echo "== cargo horizon-mod fits actuallyadditions.hmod --build 0b14f8a =="
    cargo horizon-mod fits actuallyadditions.hmod --build 0b14f8a 2>&1
    echo "exit=$?"
} >"$EV/sdk-fits-other.log"
echo "--- check"
cat "$EV/sdk-check.log"
echo "--- fits (pin)"
cat "$EV/sdk-fits.log"
echo "--- fits (other build)"
cat "$EV/sdk-fits-other.log"
echo "--- delivered artifact"
sha256sum actuallyadditions.hmod
stat -c '%s bytes' actuallyadditions.hmod
echo "--- Cargo.lock in the package (must be 0)"
unzip -l actuallyadditions.hmod | grep -c "Cargo.lock" || true
