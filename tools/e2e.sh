#!/usr/bin/env bash
# In-game check for Actually Additions slice 1: the Coal Generator and the Crusher.
#
# 0.2.0 is one flat SDK package (mod API 0.2). Its game binary is built by the launcher —
# `horizon-launcher native-build .` — and loads the package itself, so there is no `--dev-mod`
# folder any more and a native `.hmod` cannot load on an unmodded game. `horizon-launcher` is not
# installed in this environment, so no 0.2.0 run exists; the 0.1.0 runs in
# `ports/_shared/evidence/actuallyadditions/` (e2e.log, e2e-selftest.log) are the behaviour's
# evidence for a `src/runtime.rs` that did not change. This script is kept, updated for the
# launcher-built game, so the next slice can run it.
#
# The arena is built in the Overworld at y=100 (a stone floor, clear air), so every block read and
# right click is in the player's own dimension: `ctl tp` is reliable there, while cross-dimension
# `execute in ... run tp` left the player in the void in early runs.
#
# Default run:
#  - a generator with no fuel makes no FE for 40 ticks (control);
#  - coal in its fuel slot starts the burn, the coal stack shrinks by one and FE rises;
#  - the adjacent crusher receives the generator's FE (the energy capability move);
#  - coal ore fed to the crusher becomes 3 coal after ~100 ticks and the input is consumed;
#  - a crusher away from any generator crushes nothing and has 0 FE (differential control);
#  - stone is refused as fuel by the generator and as an input by the crusher, and is not placed
#    on either (the click is claimed);
#  - the machines keep their FE/burn and the crusher's output survives `save` + quit + relaunch;
#  - with CONTROL_GAME set, an unmodded game on the same scratch home knows neither id
#    (`setblock` answers `Unknown block type`), so the ids are the package's.
#
# SELFTEST=1 flips the generator's energy assertion (it must FAIL), proving the scenario can fail.
#
#   GAME=<launcher-built horizon-client> [CTL=<horizon-ctl>] [CONTROL_GAME=<unmodded game>] \
#       [SELFTEST=1] tools/e2e.sh
set -euo pipefail
export LC_ALL=C

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/actuallyadditions
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/actuallyadditions-e2e.sock}
SELFTEST=${SELFTEST:-0}
KEEP=${KEEP:-0}
# The game built by `horizon-launcher native-build .` against this package. There is none here.
GAME=${GAME:-}
# An unmodded game of the same build, for the negative control that the ids are the package's.
CONTROL_GAME=${CONTROL_GAME:-}
CTL=${CTL:-$PORT/target/horizon-cargo/fast/horizon-ctl}
WORLD=ActuallyAdditionsE2E
CONTROL_WORLD=ActuallyAdditionsE2EControl

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL (set CTL=)" >&2; exit 1; }
if [ -z "$GAME" ]; then
    echo "missing GAME: this package's game is built by the launcher, which is not installed here" >&2
    echo "  horizon-launcher native-build $PORT   # then GAME=<that horizon-client> tools/e2e.sh" >&2
    exit 1
fi
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/actuallyadditions-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$XDG_CONFIG_HOME"
rm -f "$SOCK"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
say() { ctl chat "/$1" >/dev/null; }
fail() { echo "FAIL: $*" >&2; ctl logs --lines 80 >&2 || true; exit 1; }

# The non-null slots of the container at a position, as JSON.
slots() { ctl container "$1" "$2" "$3" | jq -c '[.slots[] | select(. != null)]'; }
# has X Y Z ITEM COUNT: the container holds exactly COUNT of ITEM.
has() { # has X Y Z ITEM COUNT
    local got
    got=$(slots "$1" "$2" "$3")
    jq -e --arg item "$4" --argjson count "$5" \
        '[.[] | select(.item == $item) | .count] | add // 0 | . == $count' <<<"$got" >/dev/null \
        || fail "expected $5 x $4 at $1,$2,$3; got $got"
    echo "  has($1,$2,$3) $4 x$5: ok"
}
info() { # info X Y Z: this machine's status line, after a fresh reply arrives
    local out line before
    before=$(ctl messages 20 | jq -r '.chat[]' | grep -E "(Coal Generator|Crusher) at $1,$2,$3:" | head -1)
    say "actuallyadditions info $1 $2 $3"
    for _ in $(seq 1 25); do
        ctl wait 4 >/dev/null
        out=$(ctl messages 20)
        line=$(jq -r '.chat[]' <<<"$out" | grep -E "(Coal Generator|Crusher) at $1,$2,$3:|No Actually Additions machine" | head -1)
        if [ -n "$line" ] && [ "$line" != "$before" ]; then
            echo "$line"
            return
        fi
    done
    echo "NO-INFO $(jq -c '{chat,action_bar}' <<<"$out")"
}
expect_info() { # expect_info X Y Z SUBSTRING
    local line
    line=$(info "$1" "$2" "$3")
    echo "  info($1,$2,$3): $line"
    case "$line" in
        *"$4"*) ;;
        *) fail "expected /actuallyadditions info to say '$4', got '$line'" ;;
    esac
}

# The energy in an info line: the number before "/60000".
energy_of() { sed -nE 's/.*(Coal Generator|Crusher) at [-0-9]+,[-0-9]+,[-0-9]+: ([0-9]+)\/[0-9]+ FE.*/\2/p' <<<"$1"; }
burning_of() { sed -nE 's/.*burning ([0-9]+)\/([0-9]+).*/\1/p' <<<"$1"; }
progress_of() { sed -nE 's/.*progress ([0-9]+)\/[0-9]+.*/\1/p' <<<"$1"; }

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "$KEEP" = 1 ]; then
        echo "kept scratch: $SCRATCH" >&2
    else
        rm -rf "$SCRATCH" 2>/dev/null || true
    fi
}
finish() { local rc=$?; cleanup; echo "EXIT:$rc"; return $rc; }
trap finish EXIT

launch() {
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$WORLD" --seed 20261105 --creative --headless --wait \
        --resources "$RES" >/dev/null
    ctl wait-ready 120
    ctl wait 40
}

# A stone floor at y=99 with clear air above, in the Overworld, and the player
# standing on it at (0.5, 100, 3.5).
arena() {
    ctl tp 0.5 101 3.5 >/dev/null
    ctl wait 20
    ctl command "fill -8 99 -8 24 99 24 minecraft:stone" >/dev/null
    ctl command "fill -8 100 -8 24 110 24 minecraft:air" >/dev/null
    ctl command "kill @e[type=!player]" >/dev/null
    ctl tp 0.5 100 3.5 >/dev/null
    ctl wait 20
    local y feet floor
    y=$(ctl state | jq -r '.player.position[1] // 0')
    feet=$(ctl block 0 100 3 | jq -r '.name // .block // empty')
    floor=$(ctl block 0 99 3 | jq -r '.name // .block // empty')
    echo "  arena: y=$y floor(0,99,3)=$floor feet(0,100,3)=$feet"
    awk -v y="$y" 'BEGIN { exit !(y >= 99.9) }' || fail "the player is not on the arena floor (y=$y)"
    [ "$feet" = "minecraft:air" ] || fail "the arena volume is not clear ($feet at 0,100,3)"
    [ "$floor" = "minecraft:stone" ] || fail "the arena floor is missing ($floor at 0,99,3)"
}

# With CONTROL_GAME: an unmodded game of the same build must not know the ids, so the block and
# the behaviour the run asserts are the package's, not the engine's.
control() {
    [ -n "$CONTROL_GAME" ] || return 0
    echo "== control: an unmodded game knows neither id =="
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$CONTROL_GAME" --world "$CONTROL_WORLD" --seed 20261105 --creative --headless --wait \
        --resources "$RES" >/dev/null
    ctl wait-ready 120
    ctl wait 20
    local reply
    reply=$(ctl command "setblock 0 100 0 actuallyadditions:coal_generator" 2>&1 || true)
    echo "  setblock without the package: $reply"
    case "$reply" in
        *"Unknown block"*) ;;
        *) fail "an unmodded game placed actuallyadditions:coal_generator ($reply)" ;;
    esac
    ctl quit >/dev/null 2>&1 || true
}

echo "== launch (Overworld arena at y=100, the package's own content and code) =="
launch
arena

echo "== place the generator (alone at first) and a far crusher =="
ctl command "setblock 0 100 0 actuallyadditions:coal_generator" >/dev/null
ctl command "setblock 4 100 0 actuallyadditions:crusher" >/dev/null
ctl wait 6
for pos in "0 100 0 actuallyadditions:coal_generator" "4 100 0 actuallyadditions:crusher"; do
    set -- $pos
    got=$(ctl block "$1" "$2" "$3" | jq -r '.name // .block // empty')
    echo "  block($1,$2,$3) = $got"
    [ "$got" = "$4" ] || fail "expected $4 at $1,$2,$3, got '$got'"
done

echo "== control: no fuel means no FE =="
line=$(info 0 100 0)
echo "  $line"
[ "$(energy_of "$line")" = 0 ] || fail "a generator with no fuel stored FE: $line"
[ "$(burning_of "$line")" = 0 ] || fail "a generator with no fuel is burning: $line"
ctl wait 40
line=$(info 0 100 0)
echo "  after 40 ticks: $line"
[ "$(energy_of "$line")" = 0 ] || fail "a generator with no fuel made FE: $line"
expect_info 4 100 0 "Crusher at 4,100,0: 0/60000 FE"

echo "== a coal right click fuels the generator =="
ctl give minecraft:coal 5 >/dev/null
ctl wait 3
ctl select minecraft:coal >/dev/null
ctl wait 3
ctl look-at-block 0 100 0 up >/dev/null
ctl wait 2
echo "  click: $(ctl interact 0 100 0 | jq -c '{ok, block: .block.block, inventory_change}')"
ctl wait 40
line=$(info 0 100 0)
echo "  after the click: $line"
[ "$(burning_of "$line")" -gt 0 ] || fail "the coal click did not start the burn: $line"
has 0 100 0 minecraft:coal 4

ctl wait 40
line=$(info 0 100 0)
echo "  after 40 more burning ticks: $line"
energy=$(energy_of "$line")
if [ "$SELFTEST" = 1 ]; then
    echo "  SELFTEST: expecting 0 FE (this must fail)"
    [ "$energy" = 0 ] || fail "SELFTEST flipped: the generator made ${energy} FE, not 0"
fi
[ "${energy:-0}" -ge 400 ] || fail "burning made only ${energy:-0} FE: $line"
[ "$(burning_of "$line")" -lt 1600 ] || fail "the burn counter did not move: $line"
echo "  generator alone: ${energy} FE, burn $(burning_of "$line")"

echo "== control: a crusher with no source crushes nothing =="
ctl container 4 100 0 minecraft:coal_ore 1 >/dev/null
ctl wait 120
line=$(info 4 100 0)
echo "  $line"
[ "$(energy_of "$line")" = 0 ] || fail "the far crusher got FE with no source: $line"
[ "$(progress_of "$line")" = 0 ] || fail "the far crusher progressed with no FE: $line"
has 4 100 0 minecraft:coal_ore 1
got=$(slots 4 100 0)
jq -e '[.[] | select(.item == "minecraft:coal")] | length == 0' <<<"$got" >/dev/null \
    || fail "the far crusher produced coal without FE: $got"
echo "  far crusher: no output"

echo "== the generator feeds an adjacent crusher =="
ctl command "setblock 1 100 0 actuallyadditions:crusher" >/dev/null
ctl wait 6
line=$(info 1 100 0)
echo "  $line"
[ "$(energy_of "$line")" -gt 0 ] || fail "the adjacent crusher got no FE from the generator: $line"

echo "== coal ore becomes 3 coal, powered by the generator =="
ctl container 1 100 0 minecraft:coal_ore 1 >/dev/null
ctl wait 6
line=$(info 1 100 0)
echo "  started: $line"
case "$line" in
    *"input minecraft:coal_ore x1"*) ;;
    *) fail "the crusher did not take the coal ore: $line" ;;
esac
case "$line" in
    *"crushing into minecraft:coal x3"*) ;;
    *) fail "the crusher did not find the coal-ore recipe: $line" ;;
esac
ctl wait 110
line=$(info 1 100 0)
echo "  finished: $line"
[ "$(progress_of "$line")" = 0 ] || fail "the operation did not finish in 110 ticks: $line"
has 1 100 0 minecraft:coal 3
got=$(slots 1 100 0)
jq -e '[.[] | select(.item == "minecraft:coal_ore")] | length == 0' <<<"$got" >/dev/null \
    || fail "the crusher still holds the crushed ore: $got"

echo "== control: stone is neither fuel nor a crushing input =="
ctl give minecraft:stone 2 >/dev/null
ctl wait 3
ctl select minecraft:stone >/dev/null
ctl wait 3
ctl look-at-block 0 100 0 up >/dev/null
ctl wait 2
echo "  generator click: $(ctl interact 0 100 0 | jq -c '{ok, block: .block.block, inventory_change}')"
ctl wait 6
echo "  generator action bar: $(ctl messages 4 | jq -c '.action_bar')"
got=$(slots 0 100 0)
jq -e '[.[] | select(.item == "minecraft:stone")] | length == 0' <<<"$got" >/dev/null \
    || fail "the generator accepted stone: $got"
[ "$(ctl block 0 101 0 | jq -r '.name // .block // empty')" = "minecraft:air" ] \
    || fail "stone was placed on the generator instead of being claimed"
ctl look-at-block 1 100 0 up >/dev/null
ctl wait 2
echo "  crusher click: $(ctl interact 1 100 0 | jq -c '{ok, block: .block.block, inventory_change}')"
ctl wait 6
echo "  crusher action bar: $(ctl messages 4 | jq -c '.action_bar')"
got=$(slots 1 100 0)
jq -e '[.[] | select(.item == "minecraft:stone")] | length == 0' <<<"$got" >/dev/null \
    || fail "the crusher accepted stone: $got"
[ "$(ctl block 1 101 0 | jq -r '.name // .block // empty')" = "minecraft:air" ] \
    || fail "stone was placed on the crusher instead of being claimed"
echo "  stone refused by both machines (no item taken, no block placed)"

echo "== the machines survive save + quit + relaunch =="
before=$(info 0 100 0)
echo "  before: $before"
ctl save >/dev/null
ctl wait 5
ctl quit >/dev/null 2>&1 || true
sleep 3
launch
ctl tp 0.5 100 3.5 >/dev/null
ctl wait 20
after=$(info 0 100 0)
echo "  after relaunch: $after"
[ "$(burning_of "$after")" -gt 0 ] || fail "the generator lost its burn across a relaunch: $after"
has 1 100 0 minecraft:coal 3
line=$(info 1 100 0)
echo "  crusher after relaunch: $line"
[ "$(energy_of "$line")" -gt 0 ] || fail "the crusher lost its FE across a relaunch: $line"

control

echo "PASS: a fuelled generator made FE, the adjacent crusher took it and crushed coal ore into 3 coal, an unfuelled generator made nothing, a crusher without FE crushed nothing, stone was refused by both, and the machines survived a relaunch"
