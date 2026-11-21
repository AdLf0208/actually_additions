#!/usr/bin/env bash
# In-game check for Actually Additions slice 2: the Coal Generator and the Crusher, and the state
# a broken machine keeps on its own item.
#
# 0.2.2 is one flat SDK package (mod API 0.2), built by the launcher, so the game carries the
# package itself and there is no `--dev-mod` folder any more.
#
# The arena is built in the Overworld at y=100 (a stone floor, clear air), so every block read and
# right click is in the player's own dimension.
#
# Default run:
#  - a generator with no fuel makes no FE for 40 ticks (control);
#  - coal in its fuel slot starts the burn, the coal stack shrinks by one and FE rises;
#  - the adjacent crusher receives the generator's FE (the energy capability move);
#  - coal ore fed to the crusher becomes 3 coal after ~100 ticks and the input is consumed;
#  - a crusher away from any generator crushes nothing and has 0 FE (differential control);
#  - stone is refused as fuel by the generator and as an input by the crusher, and is not placed
#    on either (the click is claimed);
#  - a *broken* generator keeps its FE, burn and burn maximum on its own item: mined in survival,
#    picked up and placed again, the machine reads the same buffer and burn (slice 2, upstream's
#    `actuallyadditions:energy` component); a machine given fresh by the harness starts at 0 (the
#    differential).
#  - the machines keep their FE/burn and the crusher's output survives `save` + quit + relaunch;
#  - with CONTROL_GAME set, an unmodded game on the same scratch home knows neither id
#    (`setblock` answers `Unknown block type`), so the ids are the package's.
#
# SELFTEST=1 flips the "the placed machine kept its FE" assertion (it must FAIL), proving the
# scenario can fail.
#
#   GAME=<launcher-built horizon-client> [CTL=<horizon-ctl>] [CONTROL_GAME=<unmodded game>] \
#       [SELFTEST=1] tools/e2e.sh
set -euo pipefail
export LC_ALL=C

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/actuallyadditions
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/actuallyadditions-e2e.sock}
GSOCK=${GSOCK:-/tmp/opencode/actuallyadditions-e2e-guest.sock}
SELFTEST=${SELFTEST:-0}
KEEP=${KEEP:-0}
GAME=${GAME:-}
CONTROL_GAME=${CONTROL_GAME:-}
CTL=${CTL:-$PORT/target/horizon-cargo/fast/horizon-ctl}
WORLD=ActuallyAdditionsE2E
CONTROL_WORLD=ActuallyAdditionsE2EControl
# Where the broken generator is placed again, clear of the working pair.
RESTORE_X=6
RESTORE_Z=-2

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL (set CTL=)" >&2; exit 1; }
if [ -z "$GAME" ]; then
    echo "missing GAME: this package's game is built by the launcher" >&2
    echo "  ports/tools/launcher-game.sh build actuallyadditions   # then GAME=<that horizon-client>" >&2
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
# The LAN guest's own control client (its own socket and home): a guest's command runs on the
# server at the guest's own permission level, which is 0 with guest commands off (`lan open 0`).
gctl() { "$CTL" --socket "$GSOCK" "$@"; }
# The centre of a block coordinate, for a teleport.
centre() { awk -v v="$1" 'BEGIN { printf "%.1f", v + 0.5 }'; }
say() { ctl chat "/$1" >/dev/null; }
fail() { echo "FAIL: $*" >&2; ctl logs --lines 80 >&2 || true; exit 1; }

# The harness reads a machine through `/actuallyadditions info` (a mod block entity's slots
# live in the mod's own view, not in the engine's vanilla container, so `ctl container` does
# not reach them). `field_of LINE NAME` answers "item xN" or "empty" for input/out0/out1.
field_of() { # field_of LINE NAME
    sed -nE "s/.*[ ,(] *$2 ([a-z0-9_:]+ x[0-9]+|empty).*/\1/p" <<<"$1"
}
# has X Y Z ITEM COUNT: the machine holds exactly COUNT of ITEM in input, out0, out1 or fuel.
has() { # has X Y Z ITEM COUNT
    local line field
    line=$(info "$1" "$2" "$3")
    for field in input out0 out1 fuel; do
        if [ "$(field_of "$line" "$field")" = "$4 x$5" ]; then
            echo "  has($1,$2,$3) $4 x$5: ok ($field)"
            return 0
        fi
    done
    fail "expected $5 x $4 at $1,$2,$3; got $line"
}
# no_item X Y Z ITEM: the machine holds none of ITEM anywhere.
no_item() { # no_item X Y Z ITEM
    local line field
    line=$(info "$1" "$2" "$3")
    for field in input out0 out1 fuel; do
        case "$(field_of "$line" "$field")" in
            "$4 x"*) fail "$4 is in the machine at $1,$2,$3 ($field): $line" ;;
        esac
    done
    echo "  no $4 at $1,$2,$3: ok"
}
# feed X Y Z ITEM: stand beside the machine and right-click it with ITEM in hand, the
# player's own insertion path.
feed() { # feed X Y Z ITEM
    ctl command "execute in minecraft:overworld run tp @s $1.5 100 $(( $3 - 2 )).5" >/dev/null
    ctl wait 6
    ctl command "item replace entity @s hotbar.0 with $4 1" >/dev/null
    ctl wait 4
    ctl select 1 >/dev/null
    ctl wait 3
    ctl look-at-block "$1" "$2" "$3" up >/dev/null
    ctl wait 2
    ctl interact "$1" "$2" "$3" >/dev/null 2>&1 || true
    ctl wait 4
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
burn_max_of() { sed -nE 's/.*burning [0-9]+\/([0-9]+).*/\1/p' <<<"$1"; }
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
# A command that exits under `set -e` before its own assertion prints nothing otherwise: name it.
trap 'echo "FAIL: the command at line $LINENO exited $?" >&2' ERR

launch() {
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$WORLD" --seed 20261105 --creative --headless --wait \
        --resources "$RES" >/dev/null
    ctl wait-ready 120 >/dev/null
    ctl wait 40 >/dev/null
}

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

control() {
    [ -n "$CONTROL_GAME" ] || return 0
    echo "== control: an unmodded game knows neither id =="
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$CONTROL_GAME" --world "$CONTROL_WORLD" --seed 20261105 --creative --headless --wait \
        --resources "$RES" >/dev/null
    ctl wait-ready 120 >/dev/null
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

PACKAGE=$PORT/actuallyadditions.hmod
if [ -f "$PACKAGE" ]; then
    echo "package: $PACKAGE, $(stat -c %s "$PACKAGE") bytes, sha256 $(sha256sum "$PACKAGE" | cut -d' ' -f1)"
fi
echo "game: $GAME"

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

echo "== a component-bearing item does not merge with the plain stack =="
# The input slot keeps the caller's own stack (components included) and only merges with a
# compatible one: a named coal must not be swallowed by the plain coal already in the fuel
# slot, which would rebuild it as a plain stack (and lose the name for good).
NAMED_REPLY=$(ctl command "item replace entity @s hotbar.0 with minecraft:coal[minecraft:custom_name='{\"text\":\"Named\"}'] 1" 2>&1 || true)
echo "  named coal: $NAMED_REPLY"
ctl wait 4
ctl select 1 >/dev/null
ctl wait 3
HELD_BEFORE=$(ctl inventory | jq -c '.held | {item, count, components}')
echo "  held before: $HELD_BEFORE"
jq -e '.item == "minecraft:coal" and (.components != null) and .count == 1' <<<"$HELD_BEFORE" >/dev/null \
    || fail "the hand does not hold one component-bearing coal: $HELD_BEFORE"
ctl look-at-block 0 100 0 up >/dev/null
ctl wait 2
ctl interact 0 100 0 >/dev/null 2>&1 || true
ctl wait 6
HELD_AFTER=$(ctl inventory | jq -c '.held | {item, count, components}')
echo "  held after: $HELD_AFTER"
[ "$HELD_AFTER" = "$HELD_BEFORE" ] \
    || fail "the named coal left the hand ($HELD_BEFORE -> $HELD_AFTER)"
LINE=$(info 0 100 0)
[ "$(field_of "$LINE" fuel)" = "minecraft:coal x4" ] \
    || fail "the fuel slot is not the four plain coal after a mismatched merge: $LINE"
echo "  the named coal stayed in the hand; the slot still holds 4 plain coal"

echo "== control: a crusher with no source crushes nothing =="
feed 4 100 0 minecraft:coal_ore
ctl wait 120
line=$(info 4 100 0)
echo "  $line"
[ "$(energy_of "$line")" = 0 ] || fail "the far crusher got FE with no source: $line"
[ "$(progress_of "$line")" = 0 ] || fail "the far crusher progressed with no FE: $line"
has 4 100 0 minecraft:coal_ore 1
no_item 4 100 0 minecraft:coal
echo "  far crusher: no output"

echo "== the generator feeds an adjacent crusher =="
ctl command "setblock 1 100 0 actuallyadditions:crusher" >/dev/null
ctl wait 6
line=$(info 1 100 0)
echo "  $line"
[ "$(energy_of "$line")" -gt 0 ] || fail "the adjacent crusher got no FE from the generator: $line"

echo "== coal ore becomes 3 coal, powered by the generator =="
feed 1 100 0 minecraft:coal_ore
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
no_item 1 100 0 minecraft:coal_ore

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
no_item 0 100 0 minecraft:stone
[ "$(ctl block 0 101 0 | jq -r '.name // .block // empty')" = "minecraft:air" ] \
    || fail "stone was placed on the generator instead of being claimed"
ctl look-at-block 1 100 0 up >/dev/null
ctl wait 2
echo "  crusher click: $(ctl interact 1 100 0 | jq -c '{ok, block: .block.block, inventory_change}')"
ctl wait 6
echo "  crusher action bar: $(ctl messages 4 | jq -c '.action_bar')"
no_item 1 100 0 minecraft:stone
[ "$(ctl block 1 101 0 | jq -r '.name // .block // empty')" = "minecraft:air" ] \
    || fail "stone was placed on the crusher instead of being claimed"
echo "  stone refused by both machines (no item taken, no block placed)"

echo "== a broken generator keeps its FE and burn on its item (slice 2) =="
# The machine to break is charged and burning; it stands alone so the crushers keep their own
# state. A survival break runs the loot table and `block_drops`, which puts the block entity's
# saved compound on the dropped item.
ctl command "setblock $((RESTORE_X + 4)) 100 $RESTORE_Z actuallyadditions:coal_generator" >/dev/null
ctl wait 4
feed $((RESTORE_X + 4)) 100 "$RESTORE_Z" minecraft:coal
ctl wait 60
BEFORE_BREAK=$(info $((RESTORE_X + 4)) 100 "$RESTORE_Z")
echo "  before the break: $BEFORE_BREAK"
BEFORE_ENERGY=$(energy_of "$BEFORE_BREAK")
BEFORE_BURN=$(burning_of "$BEFORE_BREAK")
BEFORE_MAX=$(burn_max_of "$BEFORE_BREAK")
[ "$BEFORE_ENERGY" -gt 0 ] || fail "the generator to break has no FE: $BEFORE_BREAK"
[ "$BEFORE_BURN" -gt 0 ] || fail "the generator to break is not burning: $BEFORE_BREAK"
# Survival, an iron pickaxe, and the player beside it: the real player break.
ctl command "gamemode survival @s" >/dev/null
ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
ctl wait 4
ctl select 1 >/dev/null
ctl wait 3
ctl tp "$((RESTORE_X + 4)).5" 100 "$((RESTORE_Z - 2)).5" >/dev/null
ctl wait 6
ctl break $((RESTORE_X + 4)) 100 "$RESTORE_Z" >/dev/null || fail "the charged generator did not break"
ctl wait 30
GONE=$(ctl block $((RESTORE_X + 4)) 100 "$RESTORE_Z" | jq -r '.name // .block // empty')
[ "$GONE" = "minecraft:air" ] || fail "the generator was not broken ($GONE)"
DROPS=$(ctl entities 8 item | jq -c '[.entities[] | select(.kind == "item" and .item.item == "actuallyadditions:coal_generator") | .item]')
echo "  dropped: $DROPS"
jq -e 'length == 1' <<<"$DROPS" >/dev/null || fail "the broken generator did not drop itself: $DROPS"
# `ctl entities`/`encode_components` leaves `minecraft:block_entity_data` out of the printed
# patch (measured), so the drop is proven by placing it again and reading the machine back.
# Pick it up (walk onto the drop and take it), place it again, read the machine. Back to
# creative first: the break needed survival, the pickup does not, and a mob that found the
# player in the arena must not decide whether the scenario runs.
ctl command "gamemode creative @s" >/dev/null
ctl wait 4
ctl tp "$(centre $((RESTORE_X + 4)))" 100 "$(centre "$RESTORE_Z")" >/dev/null
ctl wait 40
for _ in 1 2 3; do
    ctl select actuallyadditions:coal_generator >/dev/null 2>&1 && break
    DROP=$(ctl entities 8 item | jq -r '[.entities[] | select(.item.item == "actuallyadditions:coal_generator") | .position] | first // empty | @csv')
    [ -n "$DROP" ] || break
    echo "  the drop lies at $DROP"
    IFS=, read -r dx dy dz <<<"$DROP"
    ctl tp "$dx" "$dy" "$dz" >/dev/null
    ctl wait 20
done
HELD=$(ctl inventory | jq -r '.held.item // empty')
echo "  held after the walk: ${HELD:-none}"
[ "$HELD" = "actuallyadditions:coal_generator" ] \
    || fail "the broken generator was not picked up: $(ctl inventory | jq -c '.counts')"
echo "  step: walk to the restore site"
ctl tp "$((RESTORE_X)).5" 100 "$((RESTORE_Z + 2)).5" >/dev/null
ctl wait 6
echo "  step: place it"
ctl place "$RESTORE_X" 100 "$RESTORE_Z" >/dev/null || fail "the generator could not be placed again"
ctl wait 10
PLACED=$(ctl block "$RESTORE_X" 100 "$RESTORE_Z" | jq -r '.name // .block // empty')
[ "$PLACED" = "actuallyadditions:coal_generator" ] || fail "the placed machine is not a generator: $PLACED"
AFTER_PLACE=$(info "$RESTORE_X" 100 "$RESTORE_Z")
echo "  after placing it again: $AFTER_PLACE"
AFTER_ENERGY=$(energy_of "$AFTER_PLACE")
AFTER_BURN=$(burning_of "$AFTER_PLACE")
AFTER_MAX=$(burn_max_of "$AFTER_PLACE")
echo "  FE $BEFORE_ENERGY -> $AFTER_ENERGY, burn $BEFORE_BURN/$BEFORE_MAX -> $AFTER_BURN/$AFTER_MAX"
if [ "$SELFTEST" = 1 ]; then
    # The counterfactual: the same scenario with the restore assertion flipped. This run must
    # fail here, or the assertion below proves nothing.
    [ "$AFTER_ENERGY" = 0 ] || fail "SELFTEST flipped: the placed machine kept $AFTER_ENERGY FE, not 0"
    fail "SELFTEST: the flipped assertion passed (it must fail)"
fi
[ "$AFTER_ENERGY" -ge "$BEFORE_ENERGY" ] \
    || fail "the placed machine lost FE ($BEFORE_ENERGY -> $AFTER_ENERGY): $AFTER_PLACE"
[ "$AFTER_MAX" = "$BEFORE_MAX" ] \
    || fail "the placed machine lost its burn maximum ($BEFORE_MAX -> $AFTER_MAX)"
# The burn may have advanced a tick or two between the two reads; it must not restart from full.
[ "$AFTER_BURN" -gt 0 ] && [ "$AFTER_BURN" -le "$BEFORE_BURN" ] \
    || fail "the burn did not continue across the break ($BEFORE_BURN -> $AFTER_BURN)"
echo "  the broken machine kept its FE and its burn"

echo "== differential: a fresh machine starts empty =="
ctl command "setblock $((RESTORE_X + 2)) 100 $RESTORE_Z actuallyadditions:coal_generator" >/dev/null
ctl wait 8
FRESH=$(info $((RESTORE_X + 2)) 100 "$RESTORE_Z")
echo "  a harness-given machine: $FRESH"
[ "$(energy_of "$FRESH")" = 0 ] || fail "a fresh machine has FE: $FRESH"
[ "$(burning_of "$FRESH")" = 0 ] || fail "a fresh machine is burning: $FRESH"

echo "== the readout is operator-only: a level-0 LAN guest is refused, level-0 commands answer =="
# `/actuallyadditions info` names a crusher's input and recipe anywhere in the level, so it is a
# level-2 command. `op`/`deop` cannot make a non-operator on an integrated server (both are
# dedicated-only: `commands/profiles.rs`, `dedicated_lists`), and the refusal text alone is
# ambiguous — an earlier version grepped for it and matched the failed `deop`'s own refusal,
# proving nothing (HANDOVER §9d 6). The route that works is a LAN guest at permission level 0 and
# a differential: the same guest must be able to run level-0 commands, and only then is its
# refusal of the level-2 command evidence.
line=$(info 1 100 0)
echo "  as the world's owner: $line"
case "$line" in
    "Crusher at 1,100,0:"*) ;;
    *) fail "the owner could not read the crusher: $line" ;;
esac
LAN_PORT=$(ctl lan open 0 | jq -r '.port')
[ "$LAN_PORT" != "null" ] || fail "the host did not open its world to LAN"
echo "  LAN port $LAN_PORT (guest commands off: a guest joins at level 0)"
rm -f "$GSOCK"
HORIZON_HOME=$SCRATCH/guest "$CTL" --socket "$GSOCK" launch \
    --game "$GAME" --headless --resources "$RES" --no-pause >/dev/null
sleep 3
CONNECT=$(gctl connect "127.0.0.1:$LAN_PORT" Guest 2>&1 || true)
echo "  guest connect: $CONNECT"
JOINED=false
for _ in $(seq 1 60); do
    if [ "$(gctl status 2>/dev/null | jq -r '.server.joined // false')" = true ] \
        && [ "$(gctl status 2>/dev/null | jq -r '.server.loaded // false')" = true ]; then
        JOINED=true
        break
    fi
    sleep 2
done
[ "$JOINED" = true ] || fail "the guest never joined the LAN world"
gctl command "/help" >/dev/null
HELP_REPLY=""
for _ in $(seq 1 20); do
    HELP_REPLY=$(gctl messages 12 | jq -r '.chat[]' 2>/dev/null | grep -m1 '^/' || true)
    [ -n "$HELP_REPLY" ] && break
    sleep 1
done
echo "  the level-0 guest runs /help: ${HELP_REPLY:-<none>}"
[ -n "$HELP_REPLY" ] \
    || fail "the level-0 guest cannot run /help, so a refusal below would prove nothing"
gctl command "/list" >/dev/null
LIST_REPLY=""
for _ in $(seq 1 20); do
    LIST_REPLY=$(gctl messages 6 | jq -r '.chat[]' 2>/dev/null | grep -m1 'players online' || true)
    [ -n "$LIST_REPLY" ] && break
    sleep 1
done
echo "  the level-0 guest runs /list: ${LIST_REPLY:-<none>}"
[ -n "$LIST_REPLY" ] || fail "the level-0 guest cannot run /list either"
gctl command "/actuallyadditions info 1 100 0" >/dev/null
GUEST_WINDOW=""
for _ in $(seq 1 20); do
    GUEST_WINDOW=$(gctl messages 4 | jq -r '.chat[]' 2>/dev/null || true)
    grep -qiE 'unknown or incomplete command|permission|incorrect argument' <<<"$GUEST_WINDOW" && break
    sleep 1
done
echo "  as a level-0 guest: $(tr '\n' ' ' <<<"$GUEST_WINDOW")"
grep -qiE 'unknown or incomplete command|permission|incorrect argument' <<<"$GUEST_WINDOW" \
    || fail "a level-0 guest was not refused: $GUEST_WINDOW"
if grep -qE 'Crusher at 1,100,0:' <<<"$GUEST_WINDOW"; then
    fail "a level-0 guest received the readout: $GUEST_WINDOW"
fi
gctl quit >/dev/null 2>&1 || true
sleep 1
ctl lan close >/dev/null 2>&1 || true
line=$(info 1 100 0)
echo "  as the owner after the guest left: $line"
case "$line" in
    "Crusher at 1,100,0:"*) ;;
    *) fail "the owner lost the readout after the guest leg: $line" ;;
esac

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

echo "PASS: a fuelled generator made FE, the adjacent crusher took it and crushed coal ore into 3 coal, an unfuelled generator made nothing, a crusher without FE crushed nothing, stone was refused by both, a broken generator kept its FE and burn on its item and came back with them when placed again (a fresh machine did not), and the machines survived a relaunch"
