#!/usr/bin/env bash
# 0.2.15 package build: two builds from the final tree, `cmp` identical, no Cargo.lock (R9).
# Run inside a build slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
rm -f Cargo.lock
{
    echo "== rm -f Cargo.lock && cargo horizon-mod build =="
    cargo horizon-mod build 2>&1
    echo "exit=$?"
    echo "lock in tree after the build: $(test -f Cargo.lock && echo present || echo absent)"
} >"$EV/sdk-build.log"
cp target/horizon-mod/actuallyadditions.hmod /tmp/aa-0.2.15-build1.hmod
rm -f Cargo.lock
{
    echo "== rm -f Cargo.lock && cargo horizon-mod build, second run =="
    cargo horizon-mod build 2>&1
    echo "exit=$?"
    echo "lock in tree after the build: $(test -f Cargo.lock && echo present || echo absent)"
} >"$EV/sdk-build-second.log"
cp target/horizon-mod/actuallyadditions.hmod ./actuallyadditions.hmod
if cmp -s /tmp/aa-0.2.15-build1.hmod target/horizon-mod/actuallyadditions.hmod; then
    echo "CMP_OK: the two builds are byte-identical"
else
    echo "CMP_FAILED"
fi
sha256sum target/horizon-mod/actuallyadditions.hmod | tee "$EV/sdk-sha256.txt"
echo "size: $(stat -c %s target/horizon-mod/actuallyadditions.hmod) bytes"
echo "entries: $(unzip -l target/horizon-mod/actuallyadditions.hmod | awk '/files$/ {print $2}')"
echo "--- lock/README entries in the package"
unzip -l target/horizon-mod/actuallyadditions.hmod | grep -E "Cargo.lock|README|Cargo.toml" || true
echo "--- packed Cargo.toml version"
unzip -p target/horizon-mod/actuallyadditions.hmod Cargo.toml | grep -E '^version|^name'
echo "--- packed horizon-mod.toml version"
unzip -p target/horizon-mod/actuallyadditions.hmod horizon-mod.toml | grep -E '^version|^id'
rm -f Cargo.lock
