#!/usr/bin/env bash
# 0.2.12 registry checks: `check`, two `fits` runs (the pin, and a different build), then the
# deliverable copied to the port root. Run inside a build slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
# The build step left the deliverable at the package root; the forwarder's re-sync excludes
# target/, so do not look for it there.
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
unzip -l actuallyadditions.hmod | awk 'NR>3 && $4 != "" {print $4}' | grep -v '^$' >"$EV/sdk-entries.txt" || true
echo "--- check"
cat "$EV/sdk-check.log"
echo "--- fits (pin)"
cat "$EV/sdk-fits.log"
echo "--- fits (other build)"
cat "$EV/sdk-fits-other.log"
echo "--- delivered artifact"
sha256sum actuallyadditions.hmod
stat -c '%s bytes' actuallyadditions.hmod
echo "--- lock in the package (must be 0)"
unzip -l actuallyadditions.hmod | grep -c "Cargo.lock" || true
