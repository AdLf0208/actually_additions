#!/usr/bin/env bash
# 0.2.12 SDK ladder logs (test / clippy / fmt) and the content rule. Run inside a build slot lease.
set -uo pipefail
PORT=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/actuallyadditions
EV=/home/adlf/Desktop/all_the_mods_10_rust_rewrite/ports/_shared/evidence/actuallyadditions
cd "$PORT" || exit 1
cargo clean -p actuallyadditions
rm -f Cargo.lock
{
    echo "== cargo test --offline =="
    cargo test --offline 2>&1
    echo "exit=$?"
} >"$EV/sdk-test.log"
rm -f Cargo.lock
{
    echo "== cargo clippy --all-targets --offline -- -D warnings =="
    cargo clippy --all-targets --offline -- -D warnings 2>&1
    echo "exit=$?"
} >"$EV/sdk-clippy.log"
rm -f Cargo.lock
{
    echo "== cargo fmt --check =="
    cargo fmt --check 2>&1
    echo "exit=$?"
} >"$EV/sdk-fmt.log"
{
    echo "== python3 tools/check_recipe_keys.py =="
    python3 tools/check_recipe_keys.py 2>&1
    echo "exit=$?"
} >"$EV/check-recipe-keys.log"
rm -f Cargo.lock
grep -E "Compiling actuallyadditions|^test result|^exit=" "$EV/sdk-test.log"
echo "clippy warnings: $(grep -cE '^warning' "$EV/sdk-clippy.log")"
grep -E "^exit=" "$EV/sdk-clippy.log" "$EV/sdk-fmt.log" "$EV/check-recipe-keys.log"
tail -2 "$EV/check-recipe-keys.log"
echo "lock in tree: $(test -f Cargo.lock && echo present || echo absent)"
