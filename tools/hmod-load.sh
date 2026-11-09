#!/usr/bin/env bash
# Proves the built content package (content/actuallyadditions.hmod) loads on a
# real game: the shared, unmodded 1d63e0a5 game with `--dev-mod <the .hmod>`
# must register the two machine blocks and their items. A second launch WITHOUT
# `--dev-mod` is the negative control: the same ids must be unknown there, so
# the check cannot pass vacuously.
set -euo pipefail
export LC_ALL=C

CLONE=${CAMPAIGN_ROOT:?set CAMPAIGN_ROOT to a checkout of the ATM10-Horizon campaign tree}
PIN_BIN=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$PIN_BIN/horizon-ctl}
GAME=${GAME:-$PIN_BIN/horizon-client}
HMOD=${HMOD:-$(cd "$(dirname "$0")/.." && pwd)/content/actuallyadditions.hmod}
RES=${RES:-${HORIZON_RES:-.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/actuallyadditions-hmod.sock}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -f "$HMOD" ] || { echo "missing package: $HMOD" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/actuallyadditions-hmod-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
rm -f "$SOCK"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "${KEEP:-0}" = 1 ]; then echo "kept scratch: $SCRATCH" >&2; else rm -rf "$SCRATCH" 2>/dev/null || true; fi
}
trap cleanup EXIT

launch() { # launch WORLD [--dev-mod PATH]
    local world=$1; shift
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$world" --seed 20261105 --creative --headless --wait \
        --resources "$RES" "$@" >/dev/null
    ctl wait-ready 120
    ctl wait 20
}

echo "== launch WITH the package (--dev-mod $HMOD) =="
launch ActuallyAdditionsHmod --dev-mod "$HMOD"
ctl command "execute in minecraft:the_end run tp @s 0.5 64 3.5" >/dev/null
ctl wait 10
ctl command "execute in minecraft:the_end run setblock 0 64 0 actuallyadditions:coal_generator" >/dev/null
ctl command "execute in minecraft:the_end run setblock 2 64 0 actuallyadditions:crusher" >/dev/null
ctl wait 4
for pos in "0 64 0 actuallyadditions:coal_generator" "2 64 0 actuallyadditions:crusher"; do
    set -- $pos
    block=$(ctl block "$1" "$2" "$3" | jq -r '.name // .block // empty')
    echo "block $1,$2,$3 = $block"
    [ "$block" = "$4" ] || fail "the package did not register $4"
done
ctl give actuallyadditions:coal_generator 1 >/dev/null
ctl give actuallyadditions:crusher 1 >/dev/null
ctl wait 4
ctl inventory | jq -e '[.hotbar[] | select(.item == "actuallyadditions:coal_generator")] | length >= 1' >/dev/null \
    || fail "the package did not register the coal generator item"
ctl inventory | jq -e '[.hotbar[] | select(.item == "actuallyadditions:crusher")] | length >= 1' >/dev/null \
    || fail "the package did not register the crusher item"
echo "items: $(ctl inventory | jq -c '[.hotbar[] | select(.item | startswith("actuallyadditions:"))]')"
ctl quit >/dev/null 2>&1 || true
sleep 2

echo "== negative control: the SAME ids without --dev-mod =="
launch ActuallyAdditionsHmodControl
ctl command "execute in minecraft:the_end run tp @s 0.5 64 3.5" >/dev/null
ctl wait 10
out=$(ctl command "execute in minecraft:the_end run setblock 0 64 0 actuallyadditions:coal_generator")
echo "setblock reply: $out"
if grep -q 'Changed the block' <<<"$out"; then
    fail "the unmodded game accepted actuallyadditions:coal_generator (the check is vacuous)"
fi
block=$(ctl block 0 64 0 | jq -r '.name // .block // empty')
echo "control block 0,64,0 = $block"
[ "$block" != "actuallyadditions:coal_generator" ] || fail "the control block is the generator"
ctl give actuallyadditions:crusher 1 >/dev/null || true
ctl wait 4
ctl inventory | jq -e '[.hotbar[] | select(.item == "actuallyadditions:crusher")] | length == 0' >/dev/null \
    || fail "the unmodded game gave an Actually Additions crusher item"

echo "PASS: actuallyadditions.hmod registered the coal generator and the crusher (blocks + items) on a real game, and the same ids are unknown without the package"
echo "EXIT:0"
