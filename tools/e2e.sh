#!/usr/bin/env bash
# In-game check for Actually Additions: the Coal Generator and the Crusher, the state a broken machine
# keeps on its own item, and (0.2.4) the crafting chain's first two pieces, so the Coal Generator's own
# recipe crafts.
#
# 0.2.2 is one flat SDK package (mod API 0.2), built by the launcher, so the game carries the
# package itself and there is no `--dev-mod` folder any more.
#
# The arena is built in the Overworld at y=100 (a stone floor, clear air), so every block read and
# right click is in the player's own dimension.
#
# `--offscreen`, not `--headless`: the crafting phase clicks the table's grid slots, and a slot click
# needs the screen's rendered layout (`horizon-ctl click-slot` answers "no renderer yet" under
# `--headless`). Nothing else in the scenario depends on the renderer.
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
#  - a *loaded* crusher keeps its FE and progress and never its stacks (0.2.3): mined in survival
#    with a coal ore inside and an operation under way, the drop's `Item` tag carries `energy` and
#    `progress`, carries no `Items`, and the input spills as its own plain drop; placed again the
#    machine reads its FE back and its container is empty (the engine's spill, not the payload);
#    an empty crusher's payload is zeros (the differential).
#  - the machines keep their FE/burn and the crusher's output survives `save` + quit + relaunch;
#  - (0.2.4) the Coal Generator's own recipe unlocks and crafts in a vanilla crafting table from four
#    cobblestone (via the `c:cobblestones` tag, including its mossy member), two iron casings and a
#    coal, all nine items consumed; the same grid with iron ingots in the casing cells and with
#    stone in the cobblestone cells stays empty, and the Crusher's recipe is still absent from the
#    recipe manager (blocked on `restonia_crystal`, whose only upstream source is the
#    Atomic Reconstructor's laser conversion, which this port does not ship);
#  - (0.2.5) the Black Quartz Ore's data path: placed and read back, mined in survival from 3.5
#    blocks it drops `actuallyadditions:black_quartz` from its own carried loot table, stone mined
#    the same way drops cobblestone (the differential), silk touch drops the ore block and no gem,
#    it smelts and blasts into one Black Quartz each and crushes into two, and the Iron Casing's
#    own recipe (`#c:ingots/iron` + `#c:rods/wooden` + the gem) crafts one from the tag members
#    with all nine items consumed, its two tag keys each proved not to be a wildcard. The ore's
#    *generation* is `blocked(configured-feature-not-registered)` at this pin and the leg asserts
#    the gap (a content package's configured features do not reach the feature registry; the
#    placed feature is merged and skipped, the data-file biome modifier is read) — the day the pin
#    merges them the phase fails, which is the signal to restore the generation assertion;
#  - (0.2.6) the Atomic Reconstructor: a placed one faces away from the player who placed it; a
#    generator beside it charges its 300,000 CF buffer through the energy push; one 1,040 CF shot
#    (the 1,000 CF `ENERGY_USE` gate plus redstone dust's 40 CF conversion) turns the redstone
#    wire in its beam into a `restonia_crystal` drop, removes the block and leaves the buffer
#    empty; the same shot at stone spends its 1,000 CF and converts nothing; 1,039 CF pays the
#    gate but not the conversion; the beam reaches a block ten away and not one eleven away; a
#    shot converts every convertible block of the 3x3 plane it hits (two wires both go at
#    1,120 CF, one goes at 1,040) in upstream's order; a redstone block freezes the cycle and its
#    removal resumes it; a broken one keeps its buffer on its item; and the jar's other two
#    block-reachable `laser/` recipes convert and empty the buffer (sands → soul sand at 20,000
#    CF, red mushroom → a nether wart crop at 150,000 CF; both results are blocks, so the beam
#    places them, as upstream's `BlockItem` branch does). The Crusher's recipe, uncraftable until the beam
#    could make a crystal, now crafts (tools/craft_check.py);
#  - (0.2.7) the beam's item half: a dropped redstone item in the beam becomes a Restonia Crystal
#    (count conserved, the buffer paying the 1,000 CF gate plus the recipe's 40 CF, and the output
#    entity carrying upstream's `aa_cnv` marker so a later beam step cannot convert it again); the
#    same item two blocks across the beam stays redstone (the differential); a stack of three
#    converts exactly one and leaves two, the remainder unmarked; a west-facing beam converts its
#    item too (upstream's box is inverted on that facing); and the two `laser/` recipes whose terms
#    only ever match a dropped item convert at their own energy (rotten flesh -> leather at 20,000
#    CF, quartz -> prismarine shard at 30,000 CF);
#  - (0.2.8) the reconstructor's redstone mode: a fresh machine reads `pulse off` and a click with
#    any other item leaves it there; a click holding `minecraft:redstone_torch` (upstream's
#    `redstoneConfigurator` default) switches it to `pulse on` and the torch is never placed; in
#    pulse mode the cycle does not run and no shot is paid without a signal; a redstone block beside
#    it fires exactly one 1,040 CF shot per rising edge (two edges, two shots, a 2,080 CF buffer
#    emptied, the cycle untouched and the torch's cell still air); the differential — the same
#    machine without the toggle — keeps its cycle frozen on the same signal and spends nothing;
#  - (0.2.10) the lens items and the slot: the crafted lens (eight `#c:glass_blocks` members and a
#    Black Quartz, all nine consumed) fills the reconstructor's empty lens slot on a right click and
#    `info` reads `lens actuallyadditions:lens x1`; a non-lens and a second lens are refused; and a
#    dropped lens in the beam becomes `lens_of_color` for the 1,000 CF gate plus the 5,000 CF
#    conversion, while a dropped non-lens stays and the shot spends only its gate;
#  - (0.2.11) the miner lens's own beam effect: the harness-given miner lens (its craft needs
#    crystals this package does not carry) fills the slot, and a 61,000 CF shot at a stone block
#    (1,000 gate + the lens's 60,000) replaces it with one of the nine mining-lens ores, read back
#    with `ctl block`, while a fresh machine with the default lens keeps its stone and spends only
#    the 1,000 CF gate;
#  - (0.2.12) the detonator lens's own beam effect: the harness-given detonator lens fills the slot
#    and the readout names its 250,000 CF price; a 251,000 CF shot sets off the real sourceless
#    radius-10 blast (`fire=true`), spending 250,000 CF and lighting fire in the arena, while the
#    sighted stone STAYS — upstream's `ExplosionInteraction.NONE` keeps blocks at this pin, so the
#    brief's proposed crater is not artefact-true. The default-lens differential keeps 250,000 CF,
#    starts no fire and keeps its stone;
#  - (0.2.13) the killer lens's own beam effect: the harness-given `lens_of_the_killer` (NOT
#    `lens_of_certain_death`, which is plain LensDeath) makes a 3,500 CF shot hurt a NoAI cow in the
#    sighted air cell for 20 damage through a fake player's `player_attack` at 2,500 CF, killing it
#    (health 0, still briefly listed by `ctl entities` at this pin, so the parsed assertion is on
#    health > 0) and emptying the buffer, while the readout names `killer @ 2500 CF` at a solid
#    sight; the default-lens differential keeps its cow and spends only the 1,000 CF gate;
#  - with CONTROL_GAME set, an unmodded game on the same scratch home knows neither id
#    (`setblock` answers `Unknown block type`), so the ids are the package's.
#
# SELFTEST=1 flips the "the placed generator kept its FE" assertion (it must FAIL), proving the
# scenario can fail; SELFTEST=drops flips the payload assertion ("the container's `Items` travel"),
# which passes only on the defect this version fixes, so it must fail too; SELFTEST=ore flips the
# ore's drop assertion ("the generated ore drops nothing"), which the carried table makes false, so
# it must fail; SELFTEST=laser flips the beam's crystal assertion ("the beam makes nothing"), which
# the restonia conversion makes false, so it must fail; SELFTEST=item flips the item half's assertion
# ("the beam converts no dropped item"), which the drop makes false, so it must fail; SELFTEST=pulse
# flips the pulse phase's first assertion ("a rising edge fires nothing"), which the toggle makes
# false, so it must fail; SELFTEST=lens flips the lens-slot assertion ("the slot stays empty"), which
# the right-click makes false, so it must fail too; SELFTEST=lens-effect flips the miner assertion
# ("the stone stays"), which the 60,000 CF ore swap makes false; SELFTEST=detonation flips the
# blast assertion ("nothing was spent and no fire was lit"), which the 250,000 CF blast makes
# false; SELFTEST=killer flips the kill assertion ("the cow survives and only the gate is spent"),
# which the 2,500 CF fake-player hit makes false; SELFTEST=disenchant flips the move assertion
# ("both items stay unchanged and only the gate is spent"), which the 250,000 CF enchantment move
# makes false. NEGATIVE=1 flips the crafting phase's recipe-book assertion ("the Coal Generator's
# recipe is not unlocked"), which is the pre-0.2.4 state, so it must fail on this package.
#
#   GAME=<launcher-built horizon-client> [CTL=<horizon-ctl>] [CONTROL_GAME=<unmodded game>] \
#       [SELFTEST=1|drops|ore|laser|item|pulse|lens|lens-effect|detonation|killer|disenchant] [NEGATIVE=1] tools/e2e.sh
set -euo pipefail
export LC_ALL=C

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/actuallyadditions
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/actuallyadditions-e2e.sock}
GSOCK=${GSOCK:-/tmp/opencode/actuallyadditions-e2e-guest.sock}
SELFTEST=${SELFTEST:-0}
NEGATIVE=${NEGATIVE:-0}
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

SCRATCH_ROOT=${E2E_TMP:-/tmp/opencode}
mkdir -p "$SCRATCH_ROOT"
SCRATCH=$(mktemp -d "$SCRATCH_ROOT/actuallyadditions-home.XXXXXX")
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
    # No earlier reply for this position is not an error: `grep` exits 1 when it finds none, and
    # `pipefail` would make the assignment fatal.
    before=$(ctl messages 20 | jq -r '.chat[]' | grep -E "(Coal Generator|Crusher|Atomic Reconstructor) at $1,$2,$3:" | head -1 || true)
    say "actuallyadditions info $1 $2 $3"
    for _ in $(seq 1 25); do
        ctl wait 4 >/dev/null
        out=$(ctl messages 20)
        line=$(jq -r '.chat[]' <<<"$out" | grep -E "(Coal Generator|Crusher|Atomic Reconstructor) at $1,$2,$3:|No Actually Additions machine" | head -1)
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

# The energy in an info line: the number before "/60000" or "/300000".
energy_of() { sed -nE 's/.*(Coal Generator|Crusher|Atomic Reconstructor) at [-0-9]+,[-0-9]+,[-0-9]+: ([0-9]+)\/[0-9]+ (FE|CF).*/\2/p' <<<"$1"; }
burning_of() { sed -nE 's/.*burning ([0-9]+)\/([0-9]+).*/\1/p' <<<"$1"; }
burn_max_of() { sed -nE 's/.*burning [0-9]+\/([0-9]+).*/\1/p' <<<"$1"; }
progress_of() { sed -nE 's/.*progress ([0-9]+)\/[0-9]+.*/\1/p' <<<"$1"; }
cycle_of() { sed -nE 's/.*cycle ([0-9]+)\/[0-9]+.*/\1/p' <<<"$1"; }
pulse_of() { sed -nE 's/.*pulse (on|off),.*/\1/p' <<<"$1"; }
facing_of() { sed -nE 's/.*facing ([a-z]+),.*/\1/p' <<<"$1"; }
sight_of() { sed -nE 's/.*sight (.*), t=[0-9]+.*/\1/p' <<<"$1"; }
block_state_of() { ctl block "$1" "$2" "$3" | jq -r '.state // .name // .block // empty'; }
# expect_block X Y Z ID: the state at that position is ID (its properties, if any, follow).
expect_block() { # expect_block X Y Z ID
    local got
    got=$(block_state_of "$1" "$2" "$3")
    case "$got" in
        "$4"*) echo "  block($1,$2,$3) = $got" ;;
        *) fail "expected $4 at $1,$2,$3, got '$got'" ;;
    esac
}
# expect_air X Y Z: nothing stands there any more.
expect_air() { # expect_air X Y Z
    local got
    got=$(block_state_of "$1" "$2" "$3")
    case "$got" in
        "minecraft:air"|"minecraft:cave_air"|"") echo "  block($1,$2,$3) = air" ;;
        *) fail "expected air at $1,$2,$3, got '$got'" ;;
    esac
}
# charge X Y Z AMOUNT: fill the machine's buffer through its energy capability, the way a cable
# would (`/actuallyadditions charge`, a harness addition this slice adds: a single-player world has
# no charger). Prints the command's own reply.
charge() { # charge X Y Z AMOUNT
    local out line before
    before=$(ctl messages 20 | jq -r '.chat[]' | grep -E "charged .* at $1,$2,$3:" | head -1 || true)
    say "actuallyadditions charge $1 $2 $3 $4"
    for _ in $(seq 1 20); do
        ctl wait 4 >/dev/null
        out=$(ctl messages 20)
        line=$(jq -r '.chat[]' <<<"$out" | grep -E "charged .* at $1,$2,$3:" | head -1)
        if [ -n "$line" ] && [ "$line" != "$before" ]; then
            echo "$line"
            return
        fi
    done
    echo "NO-CHARGE $(jq -c '{chat,action_bar}' <<<"$out")"
}
# ground ITEM: how many of ITEM lie as item entities near the player (the beam's drops).
ground() { ctl entities 12 item | jq --arg i "$1" '[.entities[] | select(.item.item == $i) | (.item.count // 1)] | add // 0'; }

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
trap 'echo "FAIL: the command at line $LINENO exited $?: $BASH_COMMAND" >&2' ERR

launch() {
    rm -f "$SOCK"
    cd "$SCRATCH"
    "$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$WORLD" --seed 20261105 --creative --offscreen --wait \
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
    # (0.2.5) The ore block and the gem are the package's too: without it the block does not
    # exist, and so does not the feature. (The package's own generation is `blocked
    # (configured-feature-not-registered)` at this pin, so this leg proves the ids, which is
    # what a content port can prove here.)
    local ore_reply
    ore_reply=$(ctl command "setblock 0 100 -1 actuallyadditions:black_quartz_ore" 2>&1 || true)
    echo "  setblock the ore without the package: $ore_reply"
    case "$ore_reply" in
        *"Unknown block"*) ;;
        *) fail "an unmodded game placed actuallyadditions:black_quartz_ore ($ore_reply)" ;;
    esac
    ore_reply=$(ctl command "place feature actuallyadditions:ore_black_quartz 8 30 8" 2>&1 || true)
    echo "  place feature without the package: $ore_reply"
    case "$ore_reply" in
        *"Can't find element"*) ;;
        *) fail "the feature id resolved without the package ($ore_reply)" ;;
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
# Stand 3.5 blocks off, not 2: an item entity within ~1 block of a player is picked up after
# its 10-tick pickup delay and the drop drifts a little, so a nearer stance sometimes put the
# drop in the inventory before this leg could read it (measured: the drop's advancement fired
# mid-leg).
ctl tp "$((RESTORE_X + 4)).5" 100 "$((RESTORE_Z - 3)).5" >/dev/null
ctl wait 6
BREAK=$(ctl break $((RESTORE_X + 4)) 100 "$RESTORE_Z") || fail "the charged generator did not break"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$BREAK")"
ctl wait 30
GONE=$(ctl block $((RESTORE_X + 4)) 100 "$RESTORE_Z" | jq -r '.name // .block // empty')
[ "$GONE" = "minecraft:air" ] || fail "the generator was not broken ($GONE)"
# `horizon-ctl break` watches the item entities its own break makes for 20 ticks and reports
# them (`drops`), plus what reached the inventory (`picked_up`): the drop record, not a scrape
# of the ground that a pickup can race.
jq -e '((.drops["actuallyadditions:coal_generator"] // 0) + (.picked_up["actuallyadditions:coal_generator"] // 0)) >= 1' \
    <<<"$BREAK" >/dev/null || fail "the broken generator did not drop itself: $BREAK"
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
    DROP=$(ctl entities 12 item | jq -r '[.entities[] | select(.item.item == "actuallyadditions:coal_generator") | .position] | first // empty | @csv')
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

echo "== a loaded crusher keeps its state and never its stacks (0.2.3) =="
# The generator leg above proves a *generator* comes back with its FE. The crusher shares the
# hook, and upstream's loot copies its FE and progress too — but its saved compound also holds
# the container's `Items`, which the engine spills by itself. A payload that repeated them would
# drop every stack twice and load them back into the placed machine (HANDOVER §9m), so the
# carrier is an allowlist: `energy` and `progress`, never `Items`.
CT=12; CT_Z=5; CT_RESTORE_X=14; CT_FRESH_X=16; CT_FRESH_RESTORE_X=18
# A container machine's break produces two item entities — the loot table's machine and the
# engine's spill of the container. A player standing close can take either one before the reads
# (see the break below), so the leg steps back and, as insurance, rebuilds the machine and breaks
# it again if one of the two is still missing; three misses in a row are a failure.
DROP_ITEM=""
SPILL_ITEM=""
break_attempt=0
while :; do
    break_attempt=$((break_attempt + 1))
    if [ "$break_attempt" -gt 3 ]; then
        fail "the engine lost the crusher's drop or its container spill on 3 breaks in a row (drop: ${DROP_ITEM:-none}; spill: ${SPILL_ITEM:-none})"
    fi
    # Clear the ground so the pickup below can only find this attempt's drop.
    ctl command "kill @e[type=item]" >/dev/null
    ctl wait 4
    ctl command "setblock $CT 100 $((CT_Z - 1)) actuallyadditions:coal_generator" >/dev/null
    ctl command "setblock $CT 100 $CT_Z actuallyadditions:crusher" >/dev/null
    ctl wait 6
    feed $CT 100 $((CT_Z - 1)) minecraft:coal
    ctl wait 400
    CHARGED=$(info $CT 100 $CT_Z)
    echo "  charged crusher: $CHARGED"
    [ "$(energy_of "$CHARGED")" -gt 7000 ] \
        || fail "the crusher beside the burning generator did not charge: $CHARGED"
    # Cut the generator before the operation starts, so the crusher's own buffer is what it spends
    # and the break's ticks cannot run the operation to its end (100 ticks) under a live feed.
    ctl command "setblock $CT 100 $((CT_Z - 1)) minecraft:air" >/dev/null
    ctl wait 2
    feed $CT 100 $CT_Z minecraft:coal_ore
    ctl wait 6
    BEFORE_CRUSH=$(info $CT 100 $CT_Z)
    echo "  before breaking the loaded crusher: $BEFORE_CRUSH"
    [ "$(energy_of "$BEFORE_CRUSH")" -gt 0 ] || fail "the loaded crusher has no FE: $BEFORE_CRUSH"
    [ "$(progress_of "$BEFORE_CRUSH")" -gt 0 ] \
        || fail "the loaded crusher has not started its operation: $BEFORE_CRUSH"
    [ "$(field_of "$BEFORE_CRUSH" input)" = "minecraft:coal_ore x1" ] \
        || fail "the loaded crusher does not hold the coal ore: $BEFORE_CRUSH"
    CRUSH_ENERGY=$(energy_of "$BEFORE_CRUSH")
    CRUSH_PROGRESS=$(progress_of "$BEFORE_CRUSH")
    # Survival break with a real tool, the player within reach: the player's own break runs the loot
    # table and `block_drops`.
    ctl command "gamemode survival @s" >/dev/null
    ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
    ctl wait 4
    ctl select 1 >/dev/null
    ctl wait 3
    # 3.5 blocks off (see the generator's break): close enough to mine, too far to pick up.
    ctl tp "$CT.5" 100 "$((CT_Z - 3)).5" >/dev/null
    ctl wait 6
    BREAK=$(ctl break $CT 100 "$CT_Z") || fail "the loaded crusher did not break"
    echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$BREAK")"
    ctl wait 30
    GONE=$(ctl block $CT 100 "$CT_Z" | jq -r '.name // .block // empty')
    [ "$GONE" = "minecraft:air" ] || fail "the loaded crusher was not broken ($GONE)"
    echo "  items near the break: $(ctl entities 12 item | jq -c '[.entities[] | select(.kind == "item") | {item: .item.item, count: .item.count, position}]')"
    # The carrier itself, read from the dropped stack: vanilla's `Item` component patch is what the
    # placement applies, and `data get` prints it whole (`ctl entities` leaves
    # `minecraft:block_entity_data` out, which is why the earlier leg asserts by placing).
    DROP_ITEM=""
    for _ in $(seq 1 12); do
        DROP_ITEM=$(ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"actuallyadditions:crusher\"}},limit=1,sort=nearest] Item" 2>&1 || true)
        case "$DROP_ITEM" in
            *"following entity data"*) break ;;
        esac
        ctl wait 5 >/dev/null
    done
    echo "  the crusher drop's Item tag: $DROP_ITEM"
    # The input is the engine's to spill: it lies in the world as its own plain coal ore, with none
    # of the machine's state on it.
    SPILL_ITEM=""
    for _ in $(seq 1 12); do
        SPILL_ITEM=$(ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"minecraft:coal_ore\"}},limit=1,sort=nearest] Item" 2>&1 || true)
        case "$SPILL_ITEM" in
            *"minecraft:coal_ore"*) break ;;
        esac
        ctl wait 5 >/dev/null
    done
    # The break's own reply is the drop record; the entity reads above add the payload tag.
    if jq -e '(.drops["actuallyadditions:crusher"] // 0) >= 1 and (.drops["minecraft:coal_ore"] // 0) >= 1' \
            <<<"$BREAK" >/dev/null; then
        case "$DROP_ITEM" in
            *"following entity data"*)
                case "$SPILL_ITEM" in *"minecraft:coal_ore"*) break ;; esac ;;
        esac
    fi
    echo "  attempt $break_attempt: the drop record or the reads were incomplete; rebuilding the machine"
done
case "$DROP_ITEM" in
    *"following entity data"*) ;;
    *) fail "could not read the crusher drop's Item tag: $DROP_ITEM" ;;
esac
grep -qE 'energy: *[0-9]+' <<<"$DROP_ITEM" || fail "the crusher drop carries no energy: $DROP_ITEM"
grep -qE 'progress: *[0-9]+' <<<"$DROP_ITEM" || fail "the crusher drop carries no progress: $DROP_ITEM"
PAYLOAD_ENERGY=$(sed -nE 's/.*energy: *([0-9]+).*/\1/p' <<<"$DROP_ITEM")
PAYLOAD_PROGRESS=$(sed -nE 's/.*progress: *([0-9]+).*/\1/p' <<<"$DROP_ITEM")
echo "  payload: energy $PAYLOAD_ENERGY (machine $CRUSH_ENERGY), progress $PAYLOAD_PROGRESS (machine $CRUSH_PROGRESS)"
# The generator beside it keeps pushing FE until the block is gone, and the operation keeps
# ticking, so the payload's numbers are the machine's own at the moment of the break, not the
# values read a second earlier; the empty machine's zero payload below is the differential.
[ "$PAYLOAD_ENERGY" -gt 0 ] && [ "$PAYLOAD_ENERGY" -le 60000 ] \
    || fail "the payload's FE is not a charged machine's own ($PAYLOAD_ENERGY): $DROP_ITEM"
[ "$PAYLOAD_PROGRESS" -ge "$CRUSH_PROGRESS" ] && [ "$PAYLOAD_PROGRESS" -lt 100 ] \
    || fail "the payload's progress is not the operation's own ($PAYLOAD_PROGRESS vs $CRUSH_PROGRESS): $DROP_ITEM"
# The counterfactual: the flipped assertion ("the container's `Items` ride the payload") passes
# only on the defect, so it must fail on this package.
if [ "$SELFTEST" = drops ]; then
    grep -q 'Items' <<<"$DROP_ITEM" \
        || fail "SELFTEST drops: the payload carries no Items (the fixed behaviour); the flipped assertion 'Items travel' fails, so the real assertion can fail"
    fail "SELFTEST drops: the payload carried the container's Items, which is the defect this version fixes"
fi
grep -q 'Items' <<<"$DROP_ITEM" \
    && fail "the payload carries the container's Items, which the engine spills by itself: $DROP_ITEM"
echo "  the drop carries energy and progress and no Items"
echo "  the spilled input's Item tag: $SPILL_ITEM"
case "$SPILL_ITEM" in
    *"minecraft:coal_ore"*) ;;
    *) fail "the crushed input did not spill as its own drop: $SPILL_ITEM" ;;
esac
grep -q 'block_entity_data\|energy' <<<"$SPILL_ITEM" \
    && fail "the spilled input carried the machine's state: $SPILL_ITEM"
# Place it back: the FE comes back with it, and the container is empty because the contents
# spilled instead of riding the payload.
ctl command "gamemode creative @s" >/dev/null
ctl wait 4
ctl command "clear @s" >/dev/null
ctl wait 2
ctl tp "$CT.5" 100 "$(centre "$CT_Z")" >/dev/null
ctl wait 40
for _ in 1 2 3; do
    HELD=$(ctl inventory | jq -r '.held.item // empty')
    [ "$HELD" = "actuallyadditions:crusher" ] && break
    DROP=$(ctl entities 12 item | jq -r '[.entities[] | select(.item.item == "actuallyadditions:crusher") | .position] | first // empty | @csv')
    [ -n "$DROP" ] || break
    IFS=, read -r dx dy dz <<<"$DROP"
    ctl tp "$dx" "$dy" "$dz" >/dev/null
    ctl wait 20
done
HELD=$(ctl inventory | jq -r '.held.item // empty')
echo "  held after the walk: ${HELD:-none}"
[ "$HELD" = "actuallyadditions:crusher" ] \
    || fail "the broken crusher was not picked up: $(ctl inventory | jq -c '.counts')"
ctl tp "$CT_RESTORE_X.5" 100 "$((CT_Z - 1)).5" >/dev/null
ctl wait 6
ctl place $CT_RESTORE_X 100 "$CT_Z" >/dev/null || fail "the crusher could not be placed again"
ctl wait 10
PLACED=$(ctl block $CT_RESTORE_X 100 "$CT_Z" | jq -r '.name // .block // empty')
[ "$PLACED" = "actuallyadditions:crusher" ] || fail "the placed machine is not a crusher: $PLACED"
AFTER_CRUSH=$(info $CT_RESTORE_X 100 "$CT_Z")
echo "  after placing it again: $AFTER_CRUSH"
AFTER_CRUSH_ENERGY=$(energy_of "$AFTER_CRUSH")
echo "  crusher FE $CRUSH_ENERGY -> $AFTER_CRUSH_ENERGY"
[ "$AFTER_CRUSH_ENERGY" -gt 0 ] \
    || fail "the placed crusher lost its FE ($CRUSH_ENERGY -> $AFTER_CRUSH_ENERGY): $AFTER_CRUSH"
for field in input out0 out1; do
    [ "$(field_of "$AFTER_CRUSH" "$field")" = "empty" ] \
        || fail "the placed crusher restored its container ($field): $AFTER_CRUSH"
done
# Progress rides the payload (asserted above) and is cleared by the machine's own rule the moment
# it ticks with an empty input (`runtime::Crusher::tick`), so an empty placed machine reads 0; the
# point of the assertion is that the *stacks* did not ride along.
echo "  the placed crusher kept its FE and came back with an empty container"

echo "== differential: an empty crusher's payload is zeros =="
# The same break on a machine that holds nothing: its payload carries energy 0 and progress 0, so
# the values restored above are the broken machine's own and not a default the placement invents.
ctl command "setblock $CT_FRESH_X 100 $CT_Z actuallyadditions:crusher" >/dev/null
ctl wait 8
FRESH_CRUSH=$(info $CT_FRESH_X 100 $CT_Z)
echo "  a harness-given crusher: $FRESH_CRUSH"
[ "$(energy_of "$FRESH_CRUSH")" = 0 ] || fail "the fresh crusher has FE: $FRESH_CRUSH"
[ "$(progress_of "$FRESH_CRUSH")" = 0 ] || fail "the fresh crusher has progress: $FRESH_CRUSH"
# Clear the ground first: an empty machine's drop is the only item entity this phase needs to
# find, so the nearest item is unambiguous.
ctl command "kill @e[type=item]" >/dev/null
ctl wait 4
ctl command "gamemode survival @s" >/dev/null
ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
ctl wait 4
ctl select 1 >/dev/null
ctl wait 3
# 3.5 blocks off (see the generator's break): close enough to mine, too far to pick up.
ctl tp "$CT_FRESH_X.5" 100 "$((CT_Z - 3)).5" >/dev/null
ctl wait 6
BREAK=$(ctl break $CT_FRESH_X 100 "$CT_Z") || fail "the empty crusher did not break"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$BREAK")"
jq -e '((.drops["actuallyadditions:crusher"] // 0) + (.picked_up["actuallyadditions:crusher"] // 0)) >= 1' \
    <<<"$BREAK" >/dev/null || fail "the empty crusher did not drop itself: $BREAK"
ctl wait 30
FRESH_GONE=$(ctl block $CT_FRESH_X 100 "$CT_Z" | jq -r '.name // .block // empty')
[ "$FRESH_GONE" = "minecraft:air" ] || fail "the empty crusher was not broken ($FRESH_GONE)"
echo "  items near the empty break: $(ctl entities 12 item | jq -c '[.entities[] | select(.kind == "item") | .item.item]')"
# The drop may lie in the world or have been taken into the inventory before the step-back
# above (a player within ~1 block picks an item up after its 10-tick delay). Both outcomes prove
# the same thing; a world drop additionally lets the raw `Item` tag be read, and a picked-up
# stack is proven by placing it again below.
FRESH_DROP=""
FRESH_IN_HAND=false
for _ in $(seq 1 16); do
    FRESH_DROP=$(ctl command "data get entity @e[type=minecraft:item,limit=1,sort=nearest,distance=..8] Item" 2>&1 || true)
    case "$FRESH_DROP" in
        *"following entity data"*) break ;;
    esac
    if [ "$(ctl inventory | jq -r '.counts["actuallyadditions:crusher"] // 0')" -ge 1 ]; then
        FRESH_IN_HAND=true
        break
    fi
    ctl wait 5 >/dev/null
done
if [ "$FRESH_IN_HAND" = true ]; then
    echo "  the empty crusher's drop went into the inventory, not the ground: $FRESH_DROP"
    ctl command "gamemode creative @s" >/dev/null
    ctl wait 4
else
    echo "  the empty crusher's Item tag: $FRESH_DROP"
    case "$FRESH_DROP" in
        *"following entity data"*) ;;
        *) fail "the empty crusher neither dropped nor was picked up: $FRESH_DROP" ;;
    esac
    # An idle machine writes nothing back (`BlockEntityTickReply::Unchanged`), so its saved
    # compound holds no state keys at all and the allowlist carries only the `id`: a zero payload
    # either way.
    grep -qE 'energy: *[1-9]' <<<"$FRESH_DROP" \
        && fail "an empty crusher's payload carries FE: $FRESH_DROP"
    grep -qE 'progress: *[1-9]' <<<"$FRESH_DROP" \
        && fail "an empty crusher's payload carries progress: $FRESH_DROP"
    ctl command "gamemode creative @s" >/dev/null
    ctl wait 4
    ctl command "clear @s" >/dev/null
    ctl wait 2
    ctl tp "$CT_FRESH_X.5" 100 "$(centre "$CT_Z")" >/dev/null
    ctl wait 40
    for _ in 1 2 3; do
        HELD=$(ctl inventory | jq -r '.held.item // empty')
        [ "$HELD" = "actuallyadditions:crusher" ] && break
        DROP=$(ctl entities 12 item | jq -r '[.entities[] | select(.item.item == "actuallyadditions:crusher") | .position] | first // empty | @csv')
        [ -n "$DROP" ] || break
        IFS=, read -r dx dy dz <<<"$DROP"
        ctl tp "$dx" "$dy" "$dz" >/dev/null
        ctl wait 20
    done
fi
HELD=$(ctl inventory | jq -r '.held.item // empty')
if [ "$HELD" != "actuallyadditions:crusher" ]; then
    ctl select actuallyadditions:crusher >/dev/null 2>&1 \
        || fail "the empty crusher's drop is in neither the world nor the hand: $(ctl inventory | jq -c '.counts')"
    ctl wait 3
fi
ctl tp "$CT_FRESH_RESTORE_X.5" 100 "$((CT_Z - 1)).5" >/dev/null
ctl wait 6
ctl place $CT_FRESH_RESTORE_X 100 "$CT_Z" >/dev/null || fail "the empty crusher could not be placed again"
ctl wait 10
PLACED=$(ctl block $CT_FRESH_RESTORE_X 100 "$CT_Z" | jq -r '.name // .block // empty')
[ "$PLACED" = "actuallyadditions:crusher" ] || fail "the placed machine is not a crusher: $PLACED"
FRESH_AFTER=$(info $CT_FRESH_RESTORE_X 100 "$CT_Z")
echo "  the empty crusher placed again: $FRESH_AFTER"
[ "$(energy_of "$FRESH_AFTER")" = 0 ] || fail "an empty crusher came back with FE: $FRESH_AFTER"
echo "  a broken empty crusher comes back empty"

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

echo "== the Coal Generator's own recipe crafts (slice 3, 0.2.4) =="
# The recipe is carried from the jar (`data/actuallyadditions/recipe/coal_generator.json`,
# `CIC / CAC / CIC`). Until 0.2.4 the loader dropped it — `#c:cobblestones` and
# `actuallyadditions:iron_casing` did not resolve — so the machine had no recipe at all. The table,
# the grid fill, the tag members and the two controls live in tools/craft_check.py (the same tool
# shape bigreactors uses for its nine recipes).
CRAFT_X=20; CRAFT_Z=8
ctl command "gamemode creative @s" >/dev/null
ctl wait 4
NEGATIVE_FLAG=""
if [ "$NEGATIVE" = 1 ]; then NEGATIVE_FLAG="--negative"; fi
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" $CRAFT_X 100 $CRAFT_Z $NEGATIVE_FLAG \
    || fail "the Coal Generator's recipe phase failed (see the FAIL line above)"

# ---------------------------------------------------------------------------
# M: the lens items and the lens slot (0.2.10)
# ---------------------------------------------------------------------------
echo "== the lens items and the lens slot (0.2.10) =="
# click_with and the dropped-item summon are used by later phases too; the definitions here are
# identical to those further down (bash redefinition is harmless) and keep this phase self-contained.
click_with() { # click_with ITEM X Y Z
    ctl command "execute in minecraft:overworld run tp @s $2.5 100 $(( $4 - 2 )).5" >/dev/null
    ctl wait 6
    ctl command "item replace entity @s hotbar.0 with $1 1" >/dev/null
    ctl wait 4
    ctl select 1 >/dev/null
    ctl wait 3
    ctl look-at-block "$2" "$3" "$4" up >/dev/null
    ctl wait 2
    ctl interact "$2" "$3" "$4" >/dev/null 2>&1 || true
    ctl wait 4
}
lens_drop() { # lens_drop ITEM COUNT X Y Z
    ctl command "kill @e[type=item]" >/dev/null
    ctl command "summon minecraft:item $3 $4 $5 {Item:{id:\"$1\",count:$2},PickupDelay:32767s}" >/dev/null
    ctl wait 10
}
LENS_Z=40
ctl command "fill -8 99 36 24 99 48 minecraft:stone" >/dev/null
ctl command "fill -8 100 36 24 110 48 minecraft:air" >/dev/null
LENS_X=0
ctl command "setblock $LENS_X 100 $LENS_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl tp "$((LENS_X + 4)).5" 100 "$(centre "$LENS_Z")" >/dev/null
ctl wait 20
line=$(info "$LENS_X" 100 "$LENS_Z")
echo "  the machine as placed: $line"
case "$line" in
    *"lens default"*) ;;
    *) fail "a fresh reconstructor does not read lens default: $line" ;;
esac

# M1: the lens crafted by craft_check.py (left in the inventory) fills the empty slot.
click_with actuallyadditions:lens "$LENS_X" 100 "$LENS_Z"
line=$(info "$LENS_X" 100 "$LENS_Z")
echo "  after the lens click: $line"
if [ "$SELFTEST" = lens ]; then
    # The flipped assertion says the slot stays empty. It passes only on a package without the
    # acceptance rule, so this run must fail.
    case "$line" in
        *"lens default"*) ;;
        *) fail "SELFTEST lens: the slot accepted the lens (the real assertion); the flipped assertion 'it stays empty' fails, so the real one can fail" ;;
    esac
    fail "SELFTEST lens: the flipped assertion passed (the slot refused the lens), so it proves nothing"
fi
case "$line" in
    *"lens actuallyadditions:lens x1"*) ;;
    *) fail "the lens click did not fill the slot: $line" ;;
esac

# M2: a non-lens is refused, leaving the installed lens in place.
click_with minecraft:stick "$LENS_X" 100 "$LENS_Z"
line=$(info "$LENS_X" 100 "$LENS_Z")
echo "  after a stick click: $line"
case "$line" in
    *"lens actuallyadditions:lens x1"*) ;;
    *) fail "a non-lens replaced the installed lens: $line" ;;
esac

# M3: a second lens is refused by the occupied slot, not stacked and not swapped.
ctl command "give @s actuallyadditions:lens 1" >/dev/null
ctl wait 4
click_with actuallyadditions:lens "$LENS_X" 100 "$LENS_Z"
line=$(info "$LENS_X" 100 "$LENS_Z")
echo "  after a second lens click: $line"
case "$line" in
    *"lens actuallyadditions:lens x1"*) ;;
    *) fail "the occupied slot took a second lens: $line" ;;
esac
SECOND_HELD=$(ctl inventory | jq -r '.held.item // empty')
echo "  the refused lens is still in hand: $SECOND_HELD"
[ "$SECOND_HELD" = actuallyadditions:lens ] || fail "the occupied slot consumed the second lens: $SECOND_HELD"

# M4: a dropped lens in the beam becomes lens_of_color. 6,040 CF pays the 1,000 CF gate (5,040
# left) and the 5,000 CF ring conversion, leaving 40 — the item half the port already ships.
ctl command "give @s actuallyadditions:lens 1" >/dev/null
ctl wait 4
lens_drop actuallyadditions:lens 1 "$(centre "$((LENS_X + 2))")" 100 "$(centre "$LENS_Z")"
ctl tp "$((LENS_X + 6)).5" 100 "$(centre "$LENS_Z")" >/dev/null
charge "$LENS_X" 100 "$LENS_Z" 6040 >/dev/null
ctl wait 120
COLOUR=$(ground actuallyadditions:lens_of_color)
LEFT_LENS=$(ground actuallyadditions:lens)
line=$(info "$LENS_X" 100 "$LENS_Z")
echo "  a dropped lens in the beam: $COLOUR lens_of_color, $LEFT_LENS lens left; $line"
[ "$COLOUR" = 1 ] || fail "the dropped lens did not convert to lens_of_color ($COLOUR)"
[ "$LEFT_LENS" = 0 ] || fail "the converted lens is still on the ground ($LEFT_LENS)"
[ "$(energy_of "$line")" = 40 ] || fail "6,040 CF is not the gate plus the 5,000 CF lens conversion: $line"

# M5: the differential — a dropped non-lens stays and the shot spends only its gate.
DIFF_LENS_X=8
ctl command "setblock $DIFF_LENS_X 100 $LENS_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
lens_drop minecraft:stick 1 "$(centre "$((DIFF_LENS_X + 2))")" 100 "$(centre "$LENS_Z")"
ctl tp "$((DIFF_LENS_X + 6)).5" 100 "$(centre "$LENS_Z")" >/dev/null
charge "$DIFF_LENS_X" 100 "$LENS_Z" 1040 >/dev/null
ctl wait 120
[ "$(ground minecraft:stick)" = 1 ] || fail "a non-lens in the beam was converted"
# `lens_drop` clears item entities first, so the earlier M4 output is gone: any lens_of_color
# here would be this shot's, and the non-lens recipe must produce none.
COLOUR_AFTER=$(ground actuallyadditions:lens_of_color)
[ "$COLOUR_AFTER" = 0 ] || fail "the differential made a lens_of_color ($COLOUR_AFTER)"
line=$(info "$DIFF_LENS_X" 100 "$LENS_Z")
echo "  the differential after its shot: $line"
[ "$(energy_of "$line")" = 40 ] || fail "the differential's shot did not spend exactly its gate: $line"

ctl command "clear @s" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
# Restore the arena stance: the block legs after this one break blocks at negative z from here.
ctl command "tp @s 0.5 100 3.5" >/dev/null
ctl wait 6

ctl command "clear @s" >/dev/null
ctl close >/dev/null 2>&1 || true
ctl wait 4

echo "== the Iron Casing block places, reads back and drops itself =="
# The jar's `iron_casing` is a block (`Blocks.IRON_CASING`, `ActuallyBlocks.java:42`), not just the
# item the Coal Generator recipe keys on: it must place, read back, refuse an id the package does
# not declare, and drop itself from its carried loot table.
CASING_X=22; CASING_Z=-6
ctl command "clear @s" >/dev/null
ctl command "gamemode creative @s" >/dev/null
ctl wait 4
ctl command "setblock $CASING_X 100 $CASING_Z actuallyadditions:iron_casing" >/dev/null
ctl wait 6
CASING_AT=$(ctl block "$CASING_X" 100 "$CASING_Z" | jq -r '.name // .block // empty')
echo "  block($CASING_X,100,$CASING_Z) = $CASING_AT"
[ "$CASING_AT" = "actuallyadditions:iron_casing" ] || fail "the Iron Casing block did not place: $CASING_AT"
ctl give actuallyadditions:iron_casing 1 >/dev/null
ctl wait 4
GIVEN=$(ctl inventory | jq -c '.counts')
echo "  given: $GIVEN"
case "$GIVEN" in
    *"actuallyadditions:iron_casing"*) ;;
    *) fail "the Iron Casing item was not given: $GIVEN" ;;
esac
UNKNOWN=$(ctl give actuallyadditions:does_not_exist 1 2>&1 || true)
echo "  give an unknown id: $UNKNOWN"
case "$UNKNOWN" in
    *"unknown item"*) ;;
    *) fail "an id the package does not declare was accepted: $UNKNOWN" ;;
esac
# Break it in survival with a real tool: the carried loot table drops the block itself.
ctl command "clear @s" >/dev/null
ctl command "gamemode survival @s" >/dev/null
ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
ctl wait 4
ctl select 1 >/dev/null
ctl wait 3
# 3.5 blocks off (see the generator's break above): close enough to mine, too far to pick up.
# It stands at z=$CASING_Z, clear of the crafting table at (20, 100, 8): a block between the eye and
# the target is what `ctl break`'s aim refuses ("... is in the way").
ctl tp "$CASING_X.5" 100 "$((CASING_Z + 3)).5" >/dev/null
ctl wait 6
echo "  at $(ctl state | jq -c '.player.position')"
BREAK=$(ctl break $CASING_X 100 "$CASING_Z") || fail "the Iron Casing did not break: $BREAK"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$BREAK")"
jq -e '((.drops["actuallyadditions:iron_casing"] // 0) + (.picked_up["actuallyadditions:iron_casing"] // 0)) >= 1' \
    <<<"$BREAK" >/dev/null || fail "the Iron Casing did not drop itself: $BREAK"
ctl wait 20
CASING_GONE=$(ctl block "$CASING_X" 100 "$CASING_Z" | jq -r '.name // .block // empty')
[ "$CASING_GONE" = "minecraft:air" ] || fail "the Iron Casing was not broken ($CASING_GONE)"
echo "  the Iron Casing dropped itself (asserted from the break's own drop record)"
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl wait 4

echo "== worldgen gap: the ore's feature does not reach the registry at this pin (asserted) =="
# Measured at 0a875da, the same gap `silentgems` recorded on 2026-11-21: a content package's
# `worldgen/configured_feature` files are not merged into the content root's `worldgen/features.json`
# (it stays a symlink to vanilla's bundle), so the placed feature is skipped and no ore generates.
# What this package *does* contribute is provable: the data-file biome modifier reaches
# `biome-modifiers.json` (`neoforge:add_features`), and the block, the gem, the loot table and
# every recipe work. This phase fails the day the pin merges the features — the signal to restore
# the generation assertion.
ctl command "gamemode creative @s" >/dev/null
ctl tp 0.5 100 3.5 >/dev/null
ctl wait 20
ZERO=$(ctl find-block actuallyadditions:black_quartz_ore 64)
echo "  find-block around spawn: $(jq -c '{block, count}' <<<"$ZERO")"
[ "$(jq -r '.count' <<<"$ZERO")" = 0 ] \
    || fail "the pin now generates the ore: restore the generation assertion (the worldgen gap closed)"
FEATURE_REPLY=$(ctl command "place feature actuallyadditions:ore_black_quartz 8 30 8" 2>&1)
echo "  place feature: $FEATURE_REPLY"
case "$FEATURE_REPLY" in
    *"Can't find element 'actuallyadditions:ore_black_quartz' in registry 'minecraft:worldgen/feature'"*) ;;
    *) fail "the placed feature resolved at this pin (the worldgen gap closed): $FEATURE_REPLY" ;;
esac
LOG=$(ctl logs --lines 400)
grep -q "unknown feature reference actuallyadditions:ore_black_quartz" <<<"$LOG" \
    || fail "the worldgen loader did not report the placed feature as an unknown reference"
echo "  blocked(configured-feature-not-registered): the placed feature is merged and skipped,"
echo "    the configured feature never reaches minecraft:worldgen/feature, so no ore generates"

echo "== the placed ore, its loot table and its recipes (0.2.5) =="
# The data path the gap does not block: place the ore (a generated ore is what the worldgen
# assertion would use), mine it in survival from 3.5 blocks and read the break's own drop record.
ORE_X=10; ORE_Z=-4
SILK_X=14; STONE_X=12
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "setblock $ORE_X 100 $ORE_Z actuallyadditions:black_quartz_ore" >/dev/null
ctl wait 6
ORE_AT=$(ctl block "$ORE_X" 100 "$ORE_Z" | jq -r '.name // .block // empty')
echo "  block($ORE_X,100,$ORE_Z) = $ORE_AT"
[ "$ORE_AT" = "actuallyadditions:black_quartz_ore" ] || fail "the Black Quartz Ore block did not place: $ORE_AT"
ctl command "gamemode survival @s" >/dev/null
ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
ctl wait 4
ctl select 1 >/dev/null
ctl wait 3
# The block centre is z+0.5; standing at z+4 is exactly 3.5 blocks off (the campaign's stance:
# within reach, outside the ~1-block pickup radius).
ctl tp "$ORE_X.5" 100 "$((ORE_Z + 4))" >/dev/null
ctl wait 6
echo "  at $(ctl state | jq -c '.player.position')"
ORE_BREAK=$(ctl break "$ORE_X" 100 "$ORE_Z") || fail "the Black Quartz Ore did not break: $ORE_BREAK"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$ORE_BREAK")"
jq -e '(.drops["actuallyadditions:black_quartz"] // 0) >= 1' <<<"$ORE_BREAK" >/dev/null \
    || fail "the ore did not drop Black Quartz from its carried loot table: $ORE_BREAK"
echo "  the ore dropped Black Quartz (asserted from the break's own drop record)"
if [ "$SELFTEST" = ore ]; then
    jq -e '(.drops["actuallyadditions:black_quartz"] // 0) == 0' <<<"$ORE_BREAK" >/dev/null \
        || fail "SELFTEST ore: the ore dropped Black Quartz (the real assertion); the flipped assertion 'it drops nothing' fails, so the real one can fail"
    fail "SELFTEST ore: the flipped assertion passed (the ore dropped nothing), so it proves nothing"
fi
ctl wait 15
ORE_GONE=$(ctl block "$ORE_X" 100 "$ORE_Z" | jq -r '.name // .block // empty')
[ "$ORE_GONE" = "minecraft:air" ] || fail "the ore was not broken ($ORE_GONE)"

# Differential: plain stone, mined the same way from the same stance, drops vanilla cobblestone —
# so the drop above is the ore's own table, not the harness.
ctl command "setblock $STONE_X 100 $ORE_Z minecraft:stone" >/dev/null
ctl wait 6
ctl tp "$STONE_X.5" 100 "$((ORE_Z + 4))" >/dev/null
ctl wait 6
STONE_BREAK=$(ctl break "$STONE_X" 100 "$ORE_Z") || fail "the differential stone did not break: $STONE_BREAK"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$STONE_BREAK")"
jq -e '(.drops["minecraft:cobblestone"] // 0) >= 1' <<<"$STONE_BREAK" >/dev/null \
    || fail "the same break on stone did not drop cobblestone: $STONE_BREAK"
echo "  stone at the same depth dropped cobblestone (the same break path, a vanilla table)"

# Silk touch: the jar's table has two alternatives, and the first is the ore itself, so an
# enchanted pickaxe must drop the ore block and no gem. The enchantment is given *with* the tool
# (`give …[minecraft:enchantments=…]`), not added by `ctl enchant`: measured on this pin, `ctl
# enchant` shows the component in `ctl inventory` but the break's own tool snapshot has lost it,
# and the same break through a fresh `give` keeps it (the drop below is the proof).
ctl command "kill @e[type=item]" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "setblock $SILK_X 100 $ORE_Z actuallyadditions:black_quartz_ore" >/dev/null
ctl wait 6
ctl command 'give @s minecraft:iron_pickaxe[minecraft:enchantments={"minecraft:silk_touch":1}]' >/dev/null
# `ctl give`/`give` lands on the next tick: `select` reads the inventory immediately and answers
# "no minecraft:iron_pickaxe" without the wait (measured 2026-11-23).
ctl wait 4
ctl select minecraft:iron_pickaxe >/dev/null
ctl tp "$SILK_X.5" 100 "$((ORE_Z + 4))" >/dev/null
ctl wait 8
SILK_HELD=$(ctl inventory)
echo "  held: $(jq -c '.held' <<<"$SILK_HELD")"
grep -q "silk_touch" <<<"$SILK_HELD" || fail "the pickaxe given for the silk-touch leg has no enchantment: $SILK_HELD"
SILK_BREAK=$(ctl break "$SILK_X" 100 "$ORE_Z") || fail "the silk-touch ore did not break: $SILK_BREAK"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$SILK_BREAK")"
jq -e '(.drops["actuallyadditions:black_quartz_ore"] // 0) >= 1' <<<"$SILK_BREAK" >/dev/null \
    || fail "silk touch did not drop the ore block: $SILK_BREAK"
jq -e '(.drops["actuallyadditions:black_quartz"] // 0) == 0' <<<"$SILK_BREAK" >/dev/null \
    || fail "silk touch dropped the gem as well: $SILK_BREAK"
echo "  silk touch dropped the ore block and no gem (the table's other alternative)"

echo "== the ore smelts and blasts into Black Quartz (the carried recipes) =="
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl tp 17.5 100 -3.5 >/dev/null
ctl wait 20
SMELT_X=16; BLAST_X=18; FURN_Z=-6
ctl command "setblock $SMELT_X 100 $FURN_Z minecraft:furnace" >/dev/null
ctl command "setblock $BLAST_X 100 $FURN_Z minecraft:blast_furnace" >/dev/null
ctl wait 6
ctl container $SMELT_X 100 $FURN_Z actuallyadditions:black_quartz_ore 1 >/dev/null
ctl container $SMELT_X 100 $FURN_Z minecraft:coal 1 >/dev/null
ctl container $BLAST_X 100 $FURN_Z actuallyadditions:black_quartz_ore 1 >/dev/null
ctl container $BLAST_X 100 $FURN_Z minecraft:coal 1 >/dev/null
echo "  furnace before: $(ctl container $SMELT_X 100 $FURN_Z | jq -c '.slots')"
echo "  blast furnace before: $(ctl container $BLAST_X 100 $FURN_Z | jq -c '.slots')"
ctl wait 240
SMELTED=$(ctl container $SMELT_X 100 $FURN_Z)
BLASTED=$(ctl container $BLAST_X 100 $FURN_Z)
echo "  furnace after 240 ticks: $(jq -c '.slots' <<<"$SMELTED")"
echo "  blast furnace after 240 ticks: $(jq -c '.slots' <<<"$BLASTED")"
jq -e '.slots[0] == null and .slots[2].item == "actuallyadditions:black_quartz" and .slots[2].count >= 1' \
    <<<"$SMELTED" >/dev/null || fail "the ore did not smelt into Black Quartz: $SMELTED"
jq -e '.slots[0] == null and .slots[2].item == "actuallyadditions:black_quartz" and .slots[2].count >= 1' \
    <<<"$BLASTED" >/dev/null || fail "the ore did not blast into Black Quartz: $BLASTED"
echo "  both cooking recipes produced one Black Quartz from one ore (the ore slot emptied)"

echo "== the crusher's black_quartz_ore recipe yields 2 Black Quartz =="
# The carried `crushing/black_quartz_ore.json` could not run before this slice: its input did
# not exist. A fresh crusher beside the generator takes its FE, and one ore becomes two gems.
ctl command "setblock 0 100 -1 actuallyadditions:crusher" >/dev/null
ctl wait 6
ctl tp 0.5 100 3.5 >/dev/null
ctl wait 6
ctl command "item replace entity @s hotbar.0 with minecraft:coal 1" >/dev/null
ctl wait 3
feed 0 100 0 minecraft:coal
# The generator's own buffer reads 0 while it burns: it gives its 20 FE a tick away to both
# adjacent crushers, so the charge to wait for is the new crusher's, not the generator's.
CHARGE_LINE=""
for _ in $(seq 1 30); do
    CHARGE_LINE=$(info 0 100 -1)
    [ "$(energy_of "$CHARGE_LINE")" -ge 4000 ] && break
    ctl wait 20
done
echo "  fresh crusher: $CHARGE_LINE"
[ "$(energy_of "$CHARGE_LINE")" -ge 4000 ] || fail "the generator did not charge the fresh crusher: $CHARGE_LINE"
feed 0 100 -1 actuallyadditions:black_quartz_ore
has 0 100 -1 actuallyadditions:black_quartz_ore 1
CRUSH_LINE=""
for _ in $(seq 1 20); do
    CRUSH_LINE=$(info 0 100 -1)
    [ "$(field_of "$CRUSH_LINE" out0)" = "actuallyadditions:black_quartz x2" ] && break
    ctl wait 20
done
echo "  crusher: $CRUSH_LINE"
[ "$(field_of "$CRUSH_LINE" out0)" = "actuallyadditions:black_quartz x2" ] \
    || fail "one ore did not crush into 2 Black Quartz: $CRUSH_LINE"
no_item 0 100 -1 actuallyadditions:black_quartz_ore
echo "  one crushed ore became 2 Black Quartz and the input was consumed"
ctl command "clear @s" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl wait 4

echo "== the Atomic Reconstructor: placement, charge, and the laser conversion (0.2.6) =="
# Every number below is the artefact's, not a guess: 300,000 CF buffer, a 1,000 CF shot gate, the
# converting recipe's own energy on top (40 for redstone dust, 20,000 for sands, 150,000 for a red
# mushroom), a 10-block beam and a 100-tick cycle. A shot that converts nothing still spends the
# 1,000 CF, which is what the stone / distance-11 / 1,039 phases assert.
ctl command "gamemode creative @s" >/dev/null
ctl command "clear @s" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl wait 6
# A: `getNearestLookingDirection().getOpposite()` — stand north of the target, look south, and the
# machine faces north (away from the player's look).
PLACE_X=2; PLACE_Z=14
ctl give actuallyadditions:atomic_reconstructor 2 >/dev/null
ctl wait 3
ctl select actuallyadditions:atomic_reconstructor >/dev/null
ctl wait 3
ctl tp "$((PLACE_X)).5" 100 "$((PLACE_Z - 2)).5" >/dev/null
ctl look 0 0 >/dev/null
ctl wait 4
ctl place "$PLACE_X" 100 "$PLACE_Z" >/dev/null || fail "the Atomic Reconstructor could not be placed"
ctl wait 6
PLACED_STATE=$(block_state_of "$PLACE_X" 100 "$PLACE_Z")
echo "  placed at $PLACE_X,100,$PLACE_Z from the north looking south: $PLACED_STATE"
case "$PLACED_STATE" in
    "actuallyadditions:atomic_reconstructor[facing=north]"*) ;;
    *) fail "the placed reconstructor does not face away from the player: $PLACED_STATE" ;;
esac
line=$(info "$PLACE_X" 100 "$PLACE_Z")
echo "  $line"
[ "$(energy_of "$line")" = 0 ] || fail "a fresh reconstructor holds CF: $line"
[ "$(facing_of "$line")" = north ] || fail "the readout does not name the facing: $line"

# B: a generator beside it charges the buffer (the energy push now reaches the reconstructor).
GEN_X=0; GEN_Z=16
ctl command "setblock $GEN_X 100 $GEN_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((GEN_X - 1)) 100 $GEN_Z actuallyadditions:coal_generator" >/dev/null
ctl wait 6
feed $((GEN_X - 1)) 100 "$GEN_Z" minecraft:coal
CHARGE_LINE=""
for _ in $(seq 1 20); do
    CHARGE_LINE=$(info $GEN_X 100 $GEN_Z)
    [ "$(energy_of "$CHARGE_LINE")" -gt 0 ] && break
    ctl wait 10
done
echo "  generator-charged: $CHARGE_LINE"
[ "$(energy_of "$CHARGE_LINE")" -gt 0 ] \
    || fail "the generator beside the reconstructor charged nothing: $CHARGE_LINE"
ctl command "setblock $((GEN_X - 1)) 100 $GEN_Z minecraft:air" >/dev/null
ctl wait 4

# C: one shot at an adjacent redstone wire: 1,000 CF gate + 40 CF conversion = 1,040.
RECON_X=2; RECON_Z=18; DUST_X=$((RECON_X + 1))
ctl command "setblock $RECON_X 100 $RECON_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $DUST_X 100 $RECON_Z minecraft:redstone_wire" >/dev/null
ctl wait 6
expect_block "$DUST_X" 100 "$RECON_Z" minecraft:redstone_wire
CHARGE_REPLY=$(charge "$RECON_X" 100 "$RECON_Z" 1040)
echo "  $CHARGE_REPLY"
line=$(info "$RECON_X" 100 "$RECON_Z")
echo "  charged: $line"
[ "$(energy_of "$line")" = 1040 ] || fail "the buffer did not take 1,040 CF: $line"
case "$(sight_of "$line")" in
    "minecraft:redstone_wire -> actuallyadditions:restonia_crystal @ 40 CF"*) ;;
    *) fail "the readout does not sight the crystal conversion: $line" ;;
esac
ctl tp "$((RECON_X + 7)).5" 100 "$RECON_Z" >/dev/null
ctl wait 120
expect_air "$DUST_X" 100 "$RECON_Z"
CRYSTALS=$(ground actuallyadditions:restonia_crystal)
echo "  restonia crystals on the ground: $CRYSTALS"
if [ "$SELFTEST" = laser ]; then
    # The counterfactual: the flipped assertion says the beam converts nothing. It passes only on
    # a broken machine, so this run must fail.
    [ "$CRYSTALS" = 0 ] || fail "SELFTEST laser: the beam made a crystal (the real assertion); the flipped assertion 'it makes none' fails, so the real one can fail"
    fail "SELFTEST laser: the flipped assertion passed (no crystal), so it proves nothing"
fi
[ "$CRYSTALS" -ge 1 ] || fail "the beam made no restonia crystal ($CRYSTALS); the drop list: $(ctl entities 12 item | jq -c '[.entities[] | .item.item]')"
line=$(info "$RECON_X" 100 "$RECON_Z")
echo "  after the shot: $line"
[ "$(energy_of "$line")" = 0 ] || fail "1,040 CF was not exactly the shot plus one conversion: $line"

# D: the differential — the same shot at stone spends its 1,000 CF and converts nothing.
STONE_X=6; STONE_Z=18
ctl command "setblock $STONE_X 100 $STONE_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((STONE_X + 1)) 100 $STONE_Z minecraft:stone" >/dev/null
ctl wait 6
ctl command "kill @e[type=item]" >/dev/null
charge "$STONE_X" 100 "$STONE_Z" 1040 >/dev/null
line=$(info "$STONE_X" 100 "$STONE_Z")
echo "  stone: $line"
case "$(sight_of "$line")" in
    "minecraft:stone -> nothing"*) ;;
    *) fail "the readout does not see stone as inconvertible: $line" ;;
esac
ctl tp "$((STONE_X + 7)).5" 100 "$STONE_Z" >/dev/null
ctl wait 120
expect_block "$((STONE_X + 1))" 100 "$STONE_Z" minecraft:stone
line=$(info "$STONE_X" 100 "$STONE_Z")
echo "  after the shot: $line"
[ "$(energy_of "$line")" = 40 ] \
    || fail "the shot at stone did not spend exactly its 1,000 CF gate: $line"
[ "$(ground actuallyadditions:restonia_crystal)" = 0 ] || fail "the stone shot dropped a crystal"

# E: 1,039 CF pays the 1,000 CF gate but not the 40 CF conversion.
SHORT_X=10; SHORT_Z=18
ctl command "setblock $SHORT_X 100 $SHORT_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((SHORT_X + 1)) 100 $SHORT_Z minecraft:redstone_wire" >/dev/null
ctl wait 6
charge "$SHORT_X" 100 "$SHORT_Z" 1039 >/dev/null
ctl tp "$((SHORT_X + 5)).5" 100 "$SHORT_Z" >/dev/null
ctl wait 120
expect_block "$((SHORT_X + 1))" 100 "$SHORT_Z" minecraft:redstone_wire
line=$(info "$SHORT_X" 100 "$SHORT_Z")
echo "  1,039 CF after the shot: $line"
[ "$(energy_of "$line")" = 39 ] || fail "1,039 CF did not leave 39 after the gate: $line"

# F: the beam reaches ten blocks and not eleven (an air path in between).
FAR_X=0; FAR_Z=22
ctl command "setblock $FAR_X 100 $FAR_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((FAR_X + 10)) 100 $FAR_Z minecraft:redstone_wire" >/dev/null
ctl wait 6
charge "$FAR_X" 100 "$FAR_Z" 1040 >/dev/null
ctl tp "$((FAR_X + 14)).5" 100 "$FAR_Z" >/dev/null
ctl wait 120
expect_air "$((FAR_X + 10))" 100 "$FAR_Z"
echo "  a block ten away in the beam converted"
TOO_FAR_X=0; TOO_FAR_Z=23
ctl command "setblock $TOO_FAR_X 100 $TOO_FAR_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((TOO_FAR_X + 11)) 100 $TOO_FAR_Z minecraft:redstone_wire" >/dev/null
ctl wait 6
charge "$TOO_FAR_X" 100 "$TOO_FAR_Z" 1040 >/dev/null
ctl tp "$((TOO_FAR_X + 15)).5" 100 "$TOO_FAR_Z" >/dev/null
ctl wait 120
expect_block "$((TOO_FAR_X + 11))" 100 "$TOO_FAR_Z" minecraft:redstone_wire
line=$(info "$TOO_FAR_X" 100 "$TOO_FAR_Z")
echo "  eleven away, after the shot: $line"
[ "$(energy_of "$line")" = 40 ] || fail "the eleven-away shot did not spend its gate: $line"

# G: a shot converts every convertible block of the plane the beam hits, in upstream's order.
PLANE_X=14; PLANE_Z=14; PLANE_AT=$((PLANE_X + 1))
ctl command "setblock $PLANE_X 100 $PLANE_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $PLANE_AT 100 $((PLANE_Z - 1)) minecraft:redstone_wire" >/dev/null
ctl command "setblock $PLANE_AT 100 $((PLANE_Z + 1)) minecraft:redstone_wire" >/dev/null
ctl wait 6
ctl command "kill @e[type=item]" >/dev/null
charge "$PLANE_X" 100 "$PLANE_Z" 1120 >/dev/null
ctl tp "$((PLANE_X + 6)).5" 100 "$PLANE_Z" >/dev/null
ctl wait 120
expect_air "$PLANE_AT" 100 "$((PLANE_Z - 1))"
expect_air "$PLANE_AT" 100 "$((PLANE_Z + 1))"
BOTH=$(ground actuallyadditions:restonia_crystal)
echo "  both plane blocks converted: $BOTH crystal(s)"
[ "$BOTH" -ge 2 ] || fail "1,120 CF did not convert both plane blocks ($BOTH crystals)"
# The same plane with only 1,040 CF: the first block in the order converts and the second stays.
ctl command "kill @e[type=item]" >/dev/null
ctl command "setblock $PLANE_AT 100 $((PLANE_Z - 1)) minecraft:redstone_wire" >/dev/null
ctl command "setblock $PLANE_AT 100 $((PLANE_Z + 1)) minecraft:redstone_wire" >/dev/null
charge "$PLANE_X" 100 "$PLANE_Z" 1040 >/dev/null
ctl wait 120
expect_air "$PLANE_AT" 100 "$((PLANE_Z - 1))"
expect_block "$PLANE_AT" 100 "$((PLANE_Z + 1))" minecraft:redstone_wire

# H: redstone freezes the cycle (upstream's `isRedstonePowered`).
FREEZE_X=18; FREEZE_Z=14
ctl command "setblock $FREEZE_X 100 $FREEZE_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl wait 6
CYCLE_A=$(cycle_of "$(info "$FREEZE_X" 100 "$FREEZE_Z")")
ctl wait 20
CYCLE_B=$(cycle_of "$(info "$FREEZE_X" 100 "$FREEZE_Z")")
echo "  cycle without redstone: $CYCLE_A -> $CYCLE_B"
[ "$CYCLE_A" != "$CYCLE_B" ] || fail "the cycle did not advance without redstone ($CYCLE_A)"
ctl command "setblock $FREEZE_X 100 $((FREEZE_Z - 1)) minecraft:redstone_block" >/dev/null
ctl wait 6
CYCLE_C=$(cycle_of "$(info "$FREEZE_X" 100 "$FREEZE_Z")")
ctl wait 20
CYCLE_D=$(cycle_of "$(info "$FREEZE_X" 100 "$FREEZE_Z")")
echo "  cycle beside a redstone block: $CYCLE_C -> $CYCLE_D"
[ "$CYCLE_C" = "$CYCLE_D" ] || fail "a redstone-powered reconstructor kept cycling ($CYCLE_C -> $CYCLE_D)"
ctl command "setblock $FREEZE_X 100 $((FREEZE_Z - 1)) minecraft:air" >/dev/null
ctl wait 24
CYCLE_E=$(cycle_of "$(info "$FREEZE_X" 100 "$FREEZE_Z")")
echo "  cycle after the redstone was removed: $CYCLE_D -> $CYCLE_E"
[ "$CYCLE_E" != "$CYCLE_D" ] || fail "the cycle did not resume after the redstone was removed"

# I: a broken reconstructor keeps its buffer on its own item.
KEEP_X=22; KEEP_Z=14
ctl command "setblock $KEEP_X 100 $KEEP_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl wait 6
charge "$KEEP_X" 100 "$KEEP_Z" 5000 >/dev/null
KEEP_BEFORE=$(info "$KEEP_X" 100 "$KEEP_Z")
echo "  before the break: $KEEP_BEFORE"
[ "$(energy_of "$KEEP_BEFORE")" -gt 0 ] || fail "the machine to break holds no CF: $KEEP_BEFORE"
ctl command "kill @e[type=item]" >/dev/null
ctl command "gamemode survival @s" >/dev/null
ctl command "item replace entity @s hotbar.0 with minecraft:iron_pickaxe 1" >/dev/null
ctl wait 4
ctl select 1 >/dev/null
ctl tp "$KEEP_X.5" 100 "$((KEEP_Z - 3)).5" >/dev/null
ctl wait 6
KEEP_BREAK=$(ctl break "$KEEP_X" 100 "$KEEP_Z") || fail "the reconstructor did not break"
echo "  break: $(jq -c '{drops, picked_up, items_left_on_ground}' <<<"$KEEP_BREAK")"
jq -e '(.drops["actuallyadditions:atomic_reconstructor"] // 0) >= 1' <<<"$KEEP_BREAK" >/dev/null \
    || fail "the reconstructor did not drop itself: $KEEP_BREAK"
KEEP_TAG=""
for _ in $(seq 1 12); do
    KEEP_TAG=$(ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"actuallyadditions:atomic_reconstructor\"}},limit=1,sort=nearest] Item" 2>&1 || true)
    case "$KEEP_TAG" in *"following entity data"*) break ;; esac
    ctl wait 5 >/dev/null
done
echo "  the drop's Item tag: $KEEP_TAG"
grep -qE 'energy: *[1-9]' <<<"$KEEP_TAG" \
    || fail "the broken reconstructor's payload carries no energy: $KEEP_TAG"
PAYLOAD_CF=$(sed -nE 's/.*energy: *([0-9]+).*/\1/p' <<<"$KEEP_TAG")
echo "  payload: $PAYLOAD_CF CF"
[ "$PAYLOAD_CF" -le 5000 ] || fail "the payload's CF is more than the buffer had: $KEEP_TAG"
ctl command "gamemode creative @s" >/dev/null
ctl wait 4
ctl command "clear @s" >/dev/null
ctl tp "$KEEP_X.5" 100 "$(centre "$KEEP_Z")" >/dev/null
ctl wait 40
for _ in 1 2 3; do
    HELD=$(ctl inventory | jq -r '.held.item // empty')
    [ "$HELD" = "actuallyadditions:atomic_reconstructor" ] && break
    DROP=$(ctl entities 12 item | jq -r '[.entities[] | select(.item.item == "actuallyadditions:atomic_reconstructor") | .position] | first // empty | @csv')
    [ -n "$DROP" ] || break
    IFS=, read -r dx dy dz <<<"$DROP"
    ctl tp "$dx" "$dy" "$dz" >/dev/null
    ctl wait 20
done
ctl tp "$((KEEP_X - 3)).5" 100 "$KEEP_Z.5" >/dev/null
ctl wait 4
ctl place "$((KEEP_X - 2))" 100 "$KEEP_Z" --item actuallyadditions:atomic_reconstructor >/dev/null \
    || fail "the reconstructor could not be placed again"
ctl wait 8
KEEP_AFTER=$(info "$((KEEP_X - 2))" 100 "$KEEP_Z")
echo "  placed again: $KEEP_AFTER"
[ "$(energy_of "$KEEP_AFTER")" -gt 0 ] \
    || fail "the reconstructor lost its CF across a break: $KEEP_AFTER"

# J: the two vanilla conversions the jar's `laser/` recipes declare for blocks. Both results are
# `BlockItem`s, so upstream's block branch *places* them (`MethodHandler.invokeConversionLens`):
# the sand becomes soul sand in place, and the mushroom becomes a nether wart crop — which needs
# soul sand under it, so the cell is prepared that way (a crop on stone would pop and drop, which
# is vanilla's outcome but proves less).
SAND_X=2; SAND_Z=10
ctl command "setblock $SAND_X 100 $SAND_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((SAND_X + 1)) 100 $SAND_Z minecraft:sand" >/dev/null
ctl wait 6
ctl command "kill @e[type=item]" >/dev/null
charge "$SAND_X" 100 "$SAND_Z" 21000 >/dev/null
line=$(info "$SAND_X" 100 "$SAND_Z")
echo "  sand: $(sight_of "$line")"
ctl tp "$((SAND_X + 7)).5" 100 "$SAND_Z" >/dev/null
ctl wait 120
expect_block "$((SAND_X + 1))" 100 "$SAND_Z" minecraft:soul_sand
line=$(info "$SAND_X" 100 "$SAND_Z")
[ "$(energy_of "$line")" = 0 ] || fail "the 20,000 CF conversion did not leave an empty buffer: $line"
WART_X=6; WART_Z=10
ctl command "setblock $WART_X 100 $WART_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((WART_X + 1)) 99 $WART_Z minecraft:soul_sand" >/dev/null
ctl command "setblock $((WART_X + 1)) 101 $WART_Z minecraft:stone" >/dev/null
ctl command "setblock $((WART_X + 1)) 100 $WART_Z minecraft:red_mushroom" >/dev/null
ctl wait 6
expect_block "$((WART_X + 1))" 100 "$WART_Z" minecraft:red_mushroom
ctl command "kill @e[type=item]" >/dev/null
charge "$WART_X" 100 "$WART_Z" 151000 >/dev/null
line=$(info "$WART_X" 100 "$WART_Z")
echo "  red mushroom: $(sight_of "$line")"
ctl tp "$((WART_X + 7)).5" 100 "$WART_Z" >/dev/null
ctl wait 120
expect_block "$((WART_X + 1))" 100 "$WART_Z" minecraft:nether_wart
line=$(info "$WART_X" 100 "$WART_Z")
[ "$(energy_of "$line")" = 0 ] || fail "the 150,000 CF conversion did not leave an empty buffer: $line"
# K: the beam's item half (0.2.7). `MethodHandler.invokeConversionLens` converts the blocks of the
# plane first and then the *dropped items* in the box from the machine to the block the beam hit
# (`new AABB(tile, hit + 1).inflate(0.02).expandTowards(facing)`), one entity per beam step, as many
# items as the buffer can pay for, the output marked `aa_cnv` so it is never converted twice. A
# dropped item is summoned with its pickup delay at vanilla's sentinel so the player cannot collect
# the evidence, and the player stands four blocks off (a spawned result has a ten-tick delay).
echo "== the beam's item half: dropped items convert, one entity per step (0.2.7) =="
# `kill @e[type=item]` clears the previous phase's drops; the summon puts one stack where the beam
# looks. `PickupDelay:32767s` is vanilla's "never", so neither the input nor the output is collected.
drop_item() { # drop_item ITEM COUNT X Y Z
    ctl command "kill @e[type=item]" >/dev/null
    ctl command "summon minecraft:item $3 $4 $5 {Item:{id:\"$1\",count:$2},PickupDelay:32767s}" >/dev/null
    ctl wait 10
}
# `data get entity … Tags` is how the marker is read back: upstream's `aa_cnv` persistent-data flag
# is this entity's scoreboard tag here (the pin has no entity persistent-data surface).
tag_of() { # tag_of ITEM
    ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"$1\"}},limit=1,sort=nearest] Tags" 2>&1 || true
}

ITEM_Z1=20
# K1: one dropped redstone in the beam becomes one Restonia Crystal; the buffer pays the 1,000 CF
# gate plus the recipe's 40 CF and the item's count is conserved.
ITEM_X=0
ctl command "setblock $ITEM_X 100 $ITEM_Z1 actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
drop_item minecraft:redstone 1 "$(centre "$((ITEM_X + 2))")" 100 "$(centre "$ITEM_Z1")"
ctl tp "$((ITEM_X + 6)).5" 100 "$(centre "$ITEM_Z1")" >/dev/null
SETTLED=$(ctl entities 12 item | jq -c '[.entities[] | {item: .item.item, count: (.item.count // 1), pos, distance}]')
echo "  the dropped item settled: $SETTLED"
[ "$(ground minecraft:redstone)" = 1 ] || fail "the dropped redstone is not in the world: $SETTLED"
charge "$ITEM_X" 100 "$ITEM_Z1" 1040 >/dev/null
ctl wait 120
CONVERTED=$(ground actuallyadditions:restonia_crystal)
LEFT=$(ground minecraft:redstone)
echo "  after the shot: $CONVERTED restonia crystal(s), $LEFT redstone left"
if [ "$SELFTEST" = item ]; then
    # The counterfactual: the flipped assertion says the beam converts no dropped item. It passes
    # only on a machine without the item half, so this run must fail.
    [ "$CONVERTED" = 0 ] || fail "SELFTEST item: the beam converted the dropped item (the real assertion); the flipped assertion 'it converts none' fails, so the real one can fail"
    fail "SELFTEST item: the flipped assertion passed (nothing converted), so it proves nothing"
fi
[ "$CONVERTED" = 1 ] || fail "the beam did not convert the dropped redstone ($CONVERTED crystals; $LEFT redstone; items: $(ctl entities 12 item | jq -c '[.entities[] | .item.item]'))"
[ "$LEFT" = 0 ] || fail "the converted redstone is still on the ground ($LEFT)"
TAGS=$(tag_of actuallyadditions:restonia_crystal)
echo "  the converted item's tags: $TAGS"
case "$TAGS" in
    *aa_cnv*) ;;
    *) fail "the converted item carries no aa_cnv marker, so a later beam step would convert it again: $TAGS" ;;
esac
line=$(info "$ITEM_X" 100 "$ITEM_Z1")
echo "  after the item shot: $line"
[ "$(energy_of "$line")" = 0 ] || fail "1,040 CF was not the gate plus one 40 CF conversion: $line"

# K2: the differential — the same dropped item outside the beam's box stays redstone, and the shot
# still spends its 1,000 CF gate. The item sits two blocks across the beam, outside the box's one.
DIFF_X=6
ctl command "setblock $DIFF_X 100 $ITEM_Z1 actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
drop_item minecraft:redstone 1 "$(centre "$((DIFF_X + 2))")" 100 "$(centre "$((ITEM_Z1 + 2))")"
ctl tp "$((DIFF_X + 6)).5" 100 "$(centre "$ITEM_Z1")" >/dev/null
echo "  the differential's item (two blocks across the beam): $(ctl entities 12 item | jq -c '[.entities[] | {item: .item.item, count: (.item.count // 1), pos, distance}]')"
[ "$(ground minecraft:redstone)" = 1 ] || fail "the differential's redstone is not in the world"
charge "$DIFF_X" 100 "$ITEM_Z1" 1040 >/dev/null
ctl wait 120
[ "$(ground minecraft:redstone)" = 1 ] \
    || fail "an item outside the beam's box was converted ($(ctl entities 12 item | jq -c '[.entities[] | .item.item]'))"
[ "$(ground actuallyadditions:restonia_crystal)" = 0 ] || fail "the differential shot made a crystal"
line=$(info "$DIFF_X" 100 "$ITEM_Z1")
echo "  the differential after its shot: $line"
[ "$(energy_of "$line")" = 40 ] \
    || fail "the differential's shot did not spend exactly its 1,000 CF gate: $line"

# K3: a stack of three at 1,040 CF converts exactly one and leaves two — upstream's
# `min(energy / recipe.energy, count)` — and the remainder is never marked.
STACK_X=10
ctl command "setblock $STACK_X 100 $ITEM_Z1 actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
drop_item minecraft:redstone 3 "$(centre "$((STACK_X + 2))")" 100 "$(centre "$ITEM_Z1")"
ctl tp "$((STACK_X + 6)).5" 100 "$(centre "$ITEM_Z1")" >/dev/null
charge "$STACK_X" 100 "$ITEM_Z1" 1040 >/dev/null
ctl wait 120
STACK_CRYSTALS=$(ground actuallyadditions:restonia_crystal)
STACK_LEFT=$(ground minecraft:redstone)
echo "  three redstone at 1,040 CF: $STACK_CRYSTALS crystal(s), $STACK_LEFT redstone left"
[ "$STACK_CRYSTALS" = 1 ] || fail "1,040 CF converted $STACK_CRYSTALS of a stack of three, not one"
[ "$STACK_LEFT" = 2 ] || fail "the remainder of the converted stack is $STACK_LEFT, not two"
LEFT_TAGS=$(tag_of minecraft:redstone)
echo "  the leftover input's tags: $LEFT_TAGS"
case "$LEFT_TAGS" in
    *aa_cnv*) fail "the leftover input was marked aa_cnv, so it could never convert: $LEFT_TAGS" ;;
esac

# K4: a west-facing beam converts its dropped item too — upstream's box is inverted on this facing
# and vanilla intersects nothing with it, which the port's ordered box fixes (notes.md, "Upstream
# defects fixed").
WEST_X=14
ctl command "setblock $WEST_X 100 $ITEM_Z1 actuallyadditions:atomic_reconstructor[facing=west]" >/dev/null
drop_item minecraft:redstone 1 "$(centre "$((WEST_X - 2))")" 100 "$(centre "$ITEM_Z1")"
ctl tp "$((WEST_X - 6)).5" 100 "$(centre "$ITEM_Z1")" >/dev/null
charge "$WEST_X" 100 "$ITEM_Z1" 1040 >/dev/null
ctl wait 120
WEST_CRYSTALS=$(ground actuallyadditions:restonia_crystal)
echo "  a west-facing beam's dropped item: $WEST_CRYSTALS crystal(s), $(ground minecraft:redstone) redstone left"
[ "$WEST_CRYSTALS" = 1 ] || fail "a west-facing beam converted no dropped item ($WEST_CRYSTALS crystals)"

# K5/K6: the two `laser/` recipes whose terms only ever match a dropped item, at their own energy on
# top of the 1,000 CF gate: rotten flesh -> leather at 20,000, quartz -> prismarine shard at 30,000.
ITEM_Z2=24
LEATHER_X=0
ctl command "setblock $LEATHER_X 100 $ITEM_Z2 actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
drop_item minecraft:rotten_flesh 1 "$(centre "$((LEATHER_X + 2))")" 100 "$(centre "$ITEM_Z2")"
ctl tp "$((LEATHER_X + 6)).5" 100 "$(centre "$ITEM_Z2")" >/dev/null
charge "$LEATHER_X" 100 "$ITEM_Z2" 21000 >/dev/null
ctl wait 120
LEATHER=$(ground minecraft:leather)
echo "  rotten flesh -> leather at 20,000 CF: $LEATHER leather, $(ground minecraft:rotten_flesh) rotten flesh left"
[ "$LEATHER" = 1 ] || fail "the 20,000 CF leather conversion made no leather ($LEATHER)"
line=$(info "$LEATHER_X" 100 "$ITEM_Z2")
[ "$(energy_of "$line")" = 0 ] || fail "the 20,000 CF conversion did not leave an empty buffer: $line"
SHARD_X=8
ctl command "setblock $SHARD_X 100 $ITEM_Z2 actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
drop_item minecraft:quartz 1 "$(centre "$((SHARD_X + 2))")" 100 "$(centre "$ITEM_Z2")"
ctl tp "$((SHARD_X + 6)).5" 100 "$(centre "$ITEM_Z2")" >/dev/null
charge "$SHARD_X" 100 "$ITEM_Z2" 31000 >/dev/null
ctl wait 120
SHARDS=$(ground minecraft:prismarine_shard)
echo "  quartz -> prismarine shard at 30,000 CF: $SHARDS shard(s), $(ground minecraft:quartz) quartz left"
[ "$SHARDS" = 1 ] || fail "the 30,000 CF prismarine conversion made no shard ($SHARDS)"
line=$(info "$SHARD_X" 100 "$ITEM_Z2")
[ "$(energy_of "$line")" = 0 ] || fail "the 30,000 CF conversion did not leave an empty buffer: $line"

ctl command "clear @s" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl command "gamemode creative @s" >/dev/null
ctl wait 4

# ---------------------------------------------------------------------------
# L: pulse mode and the redstone configurator (0.2.8)
# ---------------------------------------------------------------------------
# Upstream's `TileEntityAtomicReconstructor` is a redstone-toggle machine (`isRedstoneToggle`):
# `serverTick` runs the cycle only under `!isRedstonePowered && !isPulseMode`, and
# `BlockContainerBase.updateRedstoneState` calls `activateOnPulse` — one full shot — on a rising edge
# while `respondsToPulses()`. A click holding `CommonConfig.Other.redstoneConfigurator` (default
# `minecraft:redstone_torch`) flips the mode and claims the click, so the torch is never placed.
# A fresh row of arena, so nothing from the earlier phases can stand in the beam.
echo "== pulse mode and the wrench click (0.2.8) =="
PULSE_Z=30
PULSE_X=0
ctl command "fill -8 99 25 24 99 34 minecraft:stone" >/dev/null
ctl command "fill -8 100 25 24 110 34 minecraft:air" >/dev/null
# click_with ITEM X Y Z: stand beside the machine and right-click its top face with ITEM in hand
# (the player's own click, as `feed` does for a machine input).
click_with() { # click_with ITEM X Y Z
    ctl command "execute in minecraft:overworld run tp @s $2.5 100 $(( $4 - 2 )).5" >/dev/null
    ctl wait 6
    ctl command "item replace entity @s hotbar.0 with $1 1" >/dev/null
    ctl wait 4
    ctl select 1 >/dev/null
    ctl wait 3
    ctl look-at-block "$2" "$3" "$4" up >/dev/null
    ctl wait 2
    ctl interact "$2" "$3" "$4" >/dev/null 2>&1 || true
    ctl wait 4
}
ctl command "setblock $PULSE_X 100 $PULSE_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((PULSE_X + 1)) 100 $PULSE_Z minecraft:redstone_wire" >/dev/null
ctl tp "$((PULSE_X + 4)).5" 100 "$(centre "$PULSE_Z")" >/dev/null
ctl wait 20
line=$(info "$PULSE_X" 100 "$PULSE_Z")
echo "  the machine as placed: $line"
[ "$(pulse_of "$line")" = "off" ] || fail "a fresh reconstructor is not in pulse mode: $line"

# L1: the differential for the click — any other item is refused and leaves the mode alone.
click_with minecraft:stick "$PULSE_X" 100 "$PULSE_Z"
line=$(info "$PULSE_X" 100 "$PULSE_Z")
echo "  after a stick click: $line"
[ "$(pulse_of "$line")" = "off" ] || fail "a stick toggled the redstone mode: $line"

# L2: the configurator toggles it, and the torch is never placed on the machine.
click_with minecraft:redstone_torch "$PULSE_X" 100 "$PULSE_Z"
line=$(info "$PULSE_X" 100 "$PULSE_Z")
echo "  after a redstone-torch click: $line"
[ "$(pulse_of "$line")" = "on" ] || fail "the redstone configurator did not switch the machine to pulse mode: $line"
PULSE_MODE_ON="$line"
PULSE_BLOCK=$(block_state_of "$PULSE_X" 101 "$PULSE_Z")
echo "  the torch's own cell above the machine: ${PULSE_BLOCK:-air}"
case "$PULSE_BLOCK" in
    ""|"minecraft:air"|"minecraft:cave_air") ;;
    *) fail "the click placed the torch on the machine instead of claiming it: $PULSE_BLOCK" ;;
esac

# Stand clear of the drops before the shots: a player within ~1 block collects an item entity after
# its ten-tick delay (notes.md, harness fact 3), so a crystal that lands at the beam's block would be
# in the player's inventory rather than on the ground, and the shot count would read short.
ctl tp "$((PULSE_X + 8)).5" 100 "$(centre "$PULSE_Z")" >/dev/null
ctl wait 6

# L3: pulse mode never free-runs: with no signal the cycle stands still and no shot is paid. 140
# ticks is more than the machine's own 100-tick cycle, so a machine that ignored the mode (and so
# restarted and ran its cycle) would have fired and spent its 1,000 CF gate by now.
CYCLE_BEFORE=$(cycle_of "$PULSE_MODE_ON")
charge "$PULSE_X" 100 "$PULSE_Z" 2080 >/dev/null
ctl wait 140
line=$(info "$PULSE_X" 100 "$PULSE_Z")
echo "  140 ticks of pulse mode with no signal: $line"
[ "$(cycle_of "$line")" = "$CYCLE_BEFORE" ] || fail "the cycle ran in pulse mode (${CYCLE_BEFORE} -> $(cycle_of "$line")): $line"
[ "$(energy_of "$line")" = 2080 ] || fail "pulse mode fired without a signal: $line"

# L4: one shot per rising edge. A redstone block beside the machine is the edge; it is removed and
# put back for the second shot, with a fresh wire in the beam each time (the beam's own conversion
# removes the wire). 1,000 CF of gate plus redstone dust's 40 CF per shot.
ctl command "kill @e[type=item]" >/dev/null
ctl command "setblock $((PULSE_X - 1)) 100 $PULSE_Z minecraft:redstone_block" >/dev/null
ctl wait 40
line=$(info "$PULSE_X" 100 "$PULSE_Z")
SHOTS=$(ground actuallyadditions:restonia_crystal)
echo "  after the first rising edge: $line; $SHOTS crystal(s)"
if [ "$SELFTEST" = pulse ]; then
    # The counterfactual: the flipped assertion says a rising edge fires nothing. It passes only on
    # a machine without pulse mode, so this run must fail.
    [ "$SHOTS" = 0 ] || fail "SELFTEST pulse: the rising edge fired a shot (the real assertion); the flipped assertion 'it fires none' fails, so the real one can fail"
    fail "SELFTEST pulse: the flipped assertion passed (no shot), so it proves nothing"
fi
[ "$SHOTS" = 1 ] || fail "the first rising edge fired $SHOTS shot(s), not one"
[ "$(energy_of "$line")" = 1040 ] || fail "the first shot did not cost 1,040 CF: $line"
[ "$(cycle_of "$line")" = "$CYCLE_BEFORE" ] || fail "a pulse shot advanced the cycle: $line"
ctl command "setblock $((PULSE_X - 1)) 100 $PULSE_Z minecraft:air" >/dev/null
ctl wait 20
line=$(info "$PULSE_X" 100 "$PULSE_Z")
echo "  after the falling edge: $line"
[ "$(energy_of "$line")" = 1040 ] || fail "the falling edge fired: $line"
ctl command "setblock $((PULSE_X + 1)) 100 $PULSE_Z minecraft:redstone_wire" >/dev/null
echo "  the wire is back in the beam: $(info "$PULSE_X" 100 "$PULSE_Z")"
echo "  items before the second edge: $(ctl entities 12 item | jq -c '[.entities[] | {item: .item.item, count: (.item.count // 1), pos}]')"
ctl command "setblock $((PULSE_X - 1)) 100 $PULSE_Z minecraft:redstone_block" >/dev/null
ctl wait 40
line=$(info "$PULSE_X" 100 "$PULSE_Z")
SHOTS=$(ground actuallyadditions:restonia_crystal)
echo "  after the second rising edge: $line; $SHOTS crystal(s)"
echo "  items after the second edge: $(ctl entities 12 item | jq -c '[.entities[] | {item: .item.item, count: (.item.count // 1), pos}]')"
[ "$SHOTS" = 2 ] || fail "two rising edges fired $SHOTS conversion(s), not two"
[ "$(energy_of "$line")" = 0 ] || fail "two 1,040 CF shots did not empty a 2,080 CF buffer: $line"

# L5: the differential machine — the same arrangement without the toggle. Its cycle runs freely at
# first, then a constant signal freezes it (upstream's `!isRedstonePowered` branch) and it spends
# nothing: the mode, not the signal, is what turns a level into a shot.
DIFF_X=10
ctl command "setblock $DIFF_X 100 $PULSE_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((DIFF_X + 1)) 100 $PULSE_Z minecraft:redstone_wire" >/dev/null
ctl tp "$((DIFF_X + 4)).5" 100 "$(centre "$PULSE_Z")" >/dev/null
ctl wait 30
charge "$DIFF_X" 100 "$PULSE_Z" 2080 >/dev/null
ctl command "kill @e[type=item]" >/dev/null
# The signal first, then a settling wait: both reads below must be taken while it is already on,
# or the "before" sample is one the machine took while it was still running its cycle.
ctl command "setblock $((DIFF_X - 1)) 100 $PULSE_Z minecraft:redstone_block" >/dev/null
ctl wait 60
DIFF_BEFORE=$(info "$DIFF_X" 100 "$PULSE_Z")
ctl wait 140
line=$(info "$DIFF_X" 100 "$PULSE_Z")
echo "  the same machine without the toggle: $DIFF_BEFORE -> $line"
[ "$(pulse_of "$line")" = "off" ] || fail "the differential machine is in pulse mode: $line"
[ "$(energy_of "$line")" = 2080 ] || fail "a machine without pulse mode spent energy on a constant signal: $line"
[ "$(cycle_of "$line")" = "$(cycle_of "$DIFF_BEFORE")" ] || fail "a signal did not freeze the differential's cycle: $line"
[ "$(ground actuallyadditions:restonia_crystal)" = 0 ] || fail "a machine without pulse mode converted a block"

ctl command "clear @s" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl wait 4

# ---------------------------------------------------------------------------
# N: the miner lens's own beam effect (0.2.11)
# ---------------------------------------------------------------------------
echo "== the miner lens's own beam effect (0.2.11) =="
# Upstream `LensMining.invoke` is not a plain break: with 60,000 CF it swaps the sighted
# `stone_ore_replaceables` block for a weighted-random ore from `actuallyadditions:mining_lens`.
# The miner lens item is **given by the harness**, not crafted: its own recipe keys on empowered
# crystals this package does not carry. Nothing here dresses that give up as a craft.
MINER_Z=52
ctl command "fill -8 99 50 24 99 56 minecraft:stone" >/dev/null
ctl command "fill -8 100 50 24 110 56 minecraft:air" >/dev/null
MINER_X=0
MINER_TARGET=$((MINER_X + 2))
ctl command "setblock $MINER_X 100 $MINER_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $MINER_TARGET 100 $MINER_Z minecraft:stone" >/dev/null
ctl command "give @s actuallyadditions:lens_of_the_miner 1" >/dev/null
ctl wait 4
echo "  the miner lens is harness-given (its craft needs crystals this package lacks): $(ctl inventory | jq -c '.held.item // empty')"
click_with actuallyadditions:lens_of_the_miner "$MINER_X" 100 "$MINER_Z"
line=$(info "$MINER_X" 100 "$MINER_Z")
echo "  after the miner-lens click: $line"
case "$line" in
    *"lens actuallyadditions:lens_of_the_miner x1"*) ;;
    *) fail "the miner lens did not fill the slot: $line" ;;
esac

# 61,000 CF = the 1,000 CF shot gate + the miner lens's own 60,000 CF (CommonConfig default).
# The brief's 1,040 CF cannot fire this lens; the artefact's number is the one used here.
ctl tp "$((MINER_X + 6)).5" 100 "$(centre "$MINER_Z")" >/dev/null
charge "$MINER_X" 100 "$MINER_Z" 61000 >/dev/null
# The 100-tick cycle is phase-derived from the machine's placement, so a fixed wait can sample
# either side of a shot: poll until the world changes, then read it back. Both the poll and the
# assertion use `ctl block`, never a command reply's wording.
for _ in $(seq 1 60); do
    ctl wait 4 >/dev/null
    MINER_GOT=$(block_state_of "$MINER_TARGET" 100 "$MINER_Z")
    case "$MINER_GOT" in
        minecraft:stone*) ;;
        *) break ;;
    esac
done
line=$(info "$MINER_X" 100 "$MINER_Z")
echo "  after the miner shot: $line"
echo "  the sighted block after the miner shot: $MINER_GOT"
if [ "$SELFTEST" = lens-effect ]; then
    # The flipped assertion says the stone stays — true only on the old default-beam package.
    case "$MINER_GOT" in
        minecraft:stone*) fail "SELFTEST lens-effect: the stone was replaced (the real assertion); the flipped assertion 'the stone stays' fails, so the real one can fail" ;;
    esac
    fail "SELFTEST lens-effect: the flipped assertion passed (the stone stayed), so it proves nothing"
fi
case "$MINER_GOT" in
    minecraft:stone*) fail "the miner lens left the sighted stone in place: $MINER_GOT" ;;
esac
case "$MINER_GOT" in
    actuallyadditions:black_quartz_ore*|minecraft:coal_ore*|minecraft:copper_ore*|minecraft:diamond_ore*|minecraft:emerald_ore*|minecraft:gold_ore*|minecraft:iron_ore*|minecraft:lapis_ore*|minecraft:redstone_ore*) echo "  the stone became one of the nine stone-tag mining-lens ores" ;;
    *) fail "the miner lens placed an unexpected block (not a mining-lens ore): $MINER_GOT" ;;
esac
[ "$(energy_of "$line")" = 0 ] || fail "61,000 CF did not pay the gate and the miner's 60,000 CF: $line"

# The differential: the same block in front of a fresh reconstructor with the default lens. It
# keeps its stone (no carried laser recipe converts stone) and spends only the 1,000 CF gate.
DIFF_MINER_X=8
DIFF_MINER_TARGET=$((DIFF_MINER_X + 2))
ctl command "setblock $DIFF_MINER_X 100 $MINER_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $DIFF_MINER_TARGET 100 $MINER_Z minecraft:stone" >/dev/null
ctl tp "$((DIFF_MINER_X + 6)).5" 100 "$(centre "$MINER_Z")" >/dev/null
charge "$DIFF_MINER_X" 100 "$MINER_Z" 61000 >/dev/null
# The default lens cannot convert stone, so its block never changes: read the energy once after a
# shot's worth of ticks and once more only if the first sample caught the cycle before its zero.
ctl wait 60 >/dev/null
DIFF_LINE=$(info "$DIFF_MINER_X" 100 "$MINER_Z")
if [ "$(energy_of "$DIFF_LINE")" = 61000 ]; then
    ctl wait 60 >/dev/null
    DIFF_LINE=$(info "$DIFF_MINER_X" 100 "$MINER_Z")
fi
DIFF_GOT=$(block_state_of "$DIFF_MINER_TARGET" 100 "$MINER_Z")
echo "  the plain lens's sighted block: $DIFF_GOT"
case "$DIFF_GOT" in
    minecraft:stone*) ;;
    *) fail "the plain lens changed the stone: $DIFF_GOT" ;;
esac
echo "  the plain lens's shot: $DIFF_LINE"
[ "$(energy_of "$DIFF_LINE")" = 60000 ] || fail "the plain lens spent more than the 1,000 CF gate: $DIFF_LINE"

ctl command "clear @s" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl wait 4

# ---------------------------------------------------------------------------
# O: the detonator lens's own beam effect (0.2.12)
# ---------------------------------------------------------------------------
echo "== the detonator lens's own beam effect (0.2.12) =="
# Upstream `LensDetonation.invoke` (cd9d9c6, LensDetonation.java:22-48): ENERGY_USE 250,000 CF
# on top of the shot's 1,000 CF gate, `explode(null, hit + 0.5, 10F, true,
# ExplosionInteraction.NONE)`, reach 30, and `return true` for any non-air sight. The artefact's
# `NONE` keeps blocks at this pin (the pin's own docs: "Blocks stay; entities are hurt and pushed"):
# the sighted stone therefore stays, and the blast is proved by the 250,000 CF it spends and the
# fire `fire=true` lights in the air over the stone floor. The brief's proposed crater is not
# artefact-true and is deliberately not asserted. The harness gives the lens: its own craft needs
# crystals this package does not carry.
DET_Z=60
ctl command "fill -10 99 55 22 99 65 minecraft:stone" >/dev/null
ctl command "fill -10 100 55 22 110 65 minecraft:air" >/dev/null
DET_X=0
DET_TARGET=$((DET_X + 2))
ctl command "setblock $DET_X 100 $DET_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $DET_TARGET 100 $DET_Z minecraft:stone" >/dev/null
ctl command "give @s actuallyadditions:lens_of_detonation 1" >/dev/null
ctl wait 4
echo "  the detonator lens is harness-given (its craft needs crystals this package lacks): $(ctl inventory | jq -c '.held.item // empty')"
click_with actuallyadditions:lens_of_detonation "$DET_X" 100 "$DET_Z"
line=$(info "$DET_X" 100 "$DET_Z")
echo "  after the detonator-lens click: $line"
case "$line" in
    *"lens actuallyadditions:lens_of_detonation x1"*) ;;
    *) fail "the detonator lens did not fill the slot: $line" ;;
esac
case "$(sight_of "$line")" in
    *"detonation @ 250000 CF"*) ;;
    *) fail "the readout did not name the detonation's price: $(sight_of "$line")" ;;
esac

ctl tp "$((DET_X + 6)).5" 100 "$(centre "$DET_Z")" >/dev/null
fire_in_box() { ctl blocks -10 100 55 22 104 65 | jq -r '.counts["minecraft:fire"] // 0'; }
DET_FIRE_BEFORE=$(fire_in_box)
charge "$DET_X" 100 "$DET_Z" 251000 >/dev/null
# The blast keeps blocks, so poll the buffer: a shot spends the 1,000 CF gate and the lens's
# 250,000 CF. The 100-tick cycle is phase-derived, so a fixed wait can sample either side.
for _ in $(seq 1 60); do
    ctl wait 4 >/dev/null
    DET_LINE=$(info "$DET_X" 100 "$DET_Z")
    [ "$(energy_of "$DET_LINE")" = 251000 ] || break
done
DET_ENERGY=$(energy_of "$DET_LINE")
DET_FIRE=$(fire_in_box)
DET_BLOCK=$(block_state_of "$DET_TARGET" 100 "$DET_Z")
echo "  after the detonation shot: $DET_LINE"
echo "  the sighted block after the shot: $DET_BLOCK"
echo "  fire in the blast box before and after: $DET_FIRE_BEFORE -> $DET_FIRE"
if [ "$SELFTEST" = detonation ]; then
    # The flipped assertion says nothing happened — true only on a package without the blast.
    if [ "$DET_ENERGY" = 250000 ] && [ "$DET_FIRE" = 0 ]; then
        fail "SELFTEST detonation: the flipped assertion passed (no blast), so it proves nothing"
    fi
    fail "SELFTEST detonation: the shot spent 250000 CF and lit $DET_FIRE fire block(s) (the real assertion); the flipped assertion 'nothing happened' fails, so the real one can fail"
fi
[ "$DET_ENERGY" = 0 ] || fail "the detonator did not spend its 250,000 CF: $DET_LINE"
[ "$DET_FIRE" -gt 0 ] || fail "the detonator set off no blast (no fire in the arena): before=$DET_FIRE_BEFORE after=$DET_FIRE"
case "$DET_BLOCK" in
    minecraft:stone*) echo "  the sighted stone stayed (the artefact's ExplosionInteraction.NONE keeps blocks)" ;;
    *) fail "the detonator broke the sighted stone (the artefact uses NONE, which keeps blocks): $DET_BLOCK" ;;
esac

# The differential: a fresh default-lens machine with the same charge keeps 250,000 CF (only the
# 1,000 CF gate is spent), sights the same stone, and sets off no blast at all.
DIFF_DET_X=14
DIFF_DET_TARGET=$((DIFF_DET_X + 2))
ctl command "setblock $DIFF_DET_X 100 $DET_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $DIFF_DET_TARGET 100 $DET_Z minecraft:stone" >/dev/null
ctl tp "$((DIFF_DET_X + 6)).5" 100 "$(centre "$DET_Z")" >/dev/null
DIFF_FIRE_BEFORE=$(fire_in_box)
charge "$DIFF_DET_X" 100 "$DET_Z" 251000 >/dev/null
ctl wait 60 >/dev/null
DIFF_DET_LINE=$(info "$DIFF_DET_X" 100 "$DET_Z")
if [ "$(energy_of "$DIFF_DET_LINE")" = 251000 ]; then
    ctl wait 60 >/dev/null
    DIFF_DET_LINE=$(info "$DIFF_DET_X" 100 "$DET_Z")
fi
DIFF_DET_FIRE=$(fire_in_box)
echo "  the plain lens's shot: $DIFF_DET_LINE"
echo "  the plain lens's fire before and after: $DIFF_FIRE_BEFORE -> $DIFF_DET_FIRE"
echo "  the plain lens's sighted block: $(block_state_of "$DIFF_DET_TARGET" 100 "$DET_Z")"
[ "$(energy_of "$DIFF_DET_LINE")" = 250000 ] || fail "the plain lens spent more than the 1,000 CF gate: $DIFF_DET_LINE"
[ "$DIFF_DET_FIRE" = "$DIFF_FIRE_BEFORE" ] || fail "the plain lens set off a blast: $DIFF_FIRE_BEFORE -> $DIFF_DET_FIRE"
case "$(block_state_of "$DIFF_DET_TARGET" 100 "$DET_Z")" in
    minecraft:stone*) ;;
    *) fail "the plain lens changed its sighted stone" ;;
esac

ctl command "kill @e[type=minecraft:cow]" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl wait 4

# ---------------------------------------------------------------------------
# P: the killer lens's own beam effect (0.2.13)
# ---------------------------------------------------------------------------
echo "== the killer lens's own beam effect (0.2.13) =="
# `LensKiller extends LensDeath` (cd9d9c6, LensKiller.java:21-30, LensDeath.java:29-60): the cell
# `AABB(hit.x, hit.y, hit.z, hit.x+1, hit.y+1, hit.z+1)` is asked for living entities BEFORE the
# `!hitState.isAir()` return, each is hurt for 20 from `playerAttack(FakePlayerFactory.getMinecraft)`
# at 2,500 CF, reach 15. The pin has no DamageSource object; `EntityRef::hurt` with the string
# `minecraft:player_attack` and a connectionless fake player as `causing` is the artefact's source.
# The item is `lens_of_the_killer` — `lens_of_certain_death` is plain LensDeath (350 CF) — and its
# craft needs an enchanted book, so the rig gives it.
KILL_Z=70
ctl command "fill -10 99 65 22 99 75 minecraft:stone" >/dev/null
ctl command "fill -10 100 65 22 110 75 minecraft:air" >/dev/null
cows() { ctl entities 12 cow | jq '[.entities[] | select(.type == "minecraft:cow")] | length'; }
# A dead cow stays in the entity list for a while at this pin (its health reads 0.0), so "gone"
# is asserted as "no cow with health > 0" — a parsed value, not the absence of a chat message.
cows_alive() { ctl entities 12 cow | jq '[.entities[] | select(.type == "minecraft:cow") | select((.health // 0) > 0)] | length'; }

# First the readout, with a solid sight and no cow: it proves the killer lens id selects its own
# rule and names the artefact's price. (A cow in an air cell makes the sight read "nothing", so the
# price cannot be asserted in the kill phase itself.)
READ_X=0
ctl command "setblock $READ_X 100 $KILL_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((READ_X + 2)) 100 $KILL_Z minecraft:stone" >/dev/null
ctl command "give @s actuallyadditions:lens_of_the_killer 1" >/dev/null
ctl wait 4
echo "  the killer lens is harness-given (its craft needs an enchanted book): $(ctl inventory | jq -c '.held.item // empty')"
click_with actuallyadditions:lens_of_the_killer "$READ_X" 100 "$KILL_Z"
line=$(info "$READ_X" 100 "$KILL_Z")
echo "  after the killer-lens click: $line"
case "$line" in
    *"lens actuallyadditions:lens_of_the_killer x1"*) ;;
    *) fail "the killer lens did not fill the slot: $line" ;;
esac
case "$(sight_of "$line")" in
    *"killer @ 2500 CF"*) ;;
    *) fail "the readout did not name the killer's price: $(sight_of "$line")" ;;
esac
ctl command "setblock $READ_X 100 $KILL_Z minecraft:air" >/dev/null
ctl command "setblock $((READ_X + 2)) 100 $KILL_Z minecraft:air" >/dev/null
ctl command "clear @s" >/dev/null

# The kill: a NoAI cow hovering in the sighted AIR cell (feet at y=100, body y=100..101.4), so the
# cell box intersects it. Upstream hurts entities in air cells too, then lets the beam walk on.
KILL_X=4
KILL_TARGET=$((KILL_X + 2))
ctl command "setblock $KILL_X 100 $KILL_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "summon minecraft:cow $((KILL_TARGET)).5 100 $(centre "$KILL_Z") {NoAI:1b,Silent:1b,PersistenceRequired:1b}" >/dev/null
ctl wait 6
COW_BEFORE=$(cows)
[ "$COW_BEFORE" -ge 1 ] || fail "the cow to kill was not found"
echo "  cows before the killer shot: $COW_BEFORE : $(ctl entities 12 cow | jq -c '[.entities[] | {id, type, pos, health}]')"
ctl tp "$((KILL_X + 6)).5" 100 "$(centre "$KILL_Z")" >/dev/null
click_with actuallyadditions:lens_of_the_killer "$KILL_X" 100 "$KILL_Z"
line=$(info "$KILL_X" 100 "$KILL_Z")
case "$line" in
    *"lens actuallyadditions:lens_of_the_killer x1"*) ;;
    *) fail "the killer lens did not fill the kill machine's slot: $line" ;;
esac
charge "$KILL_X" 100 "$KILL_Z" 3500 >/dev/null
# A 100-tick cycle is position-phased, so a fixed wait can sample either side of the shot.
for _ in $(seq 1 60); do
    ctl wait 4 >/dev/null
    KILL_LINE=$(info "$KILL_X" 100 "$KILL_Z")
    [ "$(energy_of "$KILL_LINE")" = 3500 ] || break
done
KILL_ENERGY=$(energy_of "$KILL_LINE")
KILL_COWS=$(cows_alive)
echo "  after the killer shot: $KILL_LINE"
echo "  cows after the killer shot: $KILL_COWS alive (before $COW_BEFORE) : $(ctl entities 12 cow | jq -c '[.entities[] | {id, type, pos, health}]')"
if [ "$SELFTEST" = killer ]; then
    # The flipped assertion is the differential's outcome: cow alive, only the 1,000 CF gate spent.
    if [ "$KILL_COWS" -ge 1 ] && [ "$KILL_ENERGY" = 2500 ]; then
        fail "SELFTEST killer: the flipped assertion passed (no kill), so it proves nothing"
    fi
    fail "SELFTEST killer: the cow's health is 0 and the buffer read 0 (the real assertion); the flipped assertion 'the cow survives and 2500 CF is left' fails, so the real one can fail"
fi
[ "$KILL_COWS" -eq 0 ] || fail "the killer lens did not kill the cow ($KILL_COWS still alive)"
[ "$KILL_ENERGY" = 0 ] || fail "the killer did not spend its 2,500 CF: $KILL_LINE"

# Differential: the same rig with the plain lens keeps the cow and spends only the gate.
DIFF_KILL_X=10
DIFF_KILL_TARGET=$((DIFF_KILL_X + 2))
ctl command "setblock $DIFF_KILL_X 100 $KILL_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "summon minecraft:cow $((DIFF_KILL_TARGET)).5 100 $(centre "$KILL_Z") {NoAI:1b,Silent:1b,PersistenceRequired:1b}" >/dev/null
ctl wait 6
DIFF_COW_BEFORE=$(cows_alive)
[ "$DIFF_COW_BEFORE" -ge 1 ] || fail "the differential cow was not found"
ctl tp "$((DIFF_KILL_X + 6)).5" 100 "$(centre "$KILL_Z")" >/dev/null
charge "$DIFF_KILL_X" 100 "$KILL_Z" 3500 >/dev/null
ctl wait 60 >/dev/null
DIFF_KILL_LINE=$(info "$DIFF_KILL_X" 100 "$KILL_Z")
if [ "$(energy_of "$DIFF_KILL_LINE")" = 3500 ]; then
    ctl wait 60 >/dev/null
    DIFF_KILL_LINE=$(info "$DIFF_KILL_X" 100 "$KILL_Z")
fi
DIFF_COW_AFTER=$(cows_alive)
echo "  the plain lens's shot: $DIFF_KILL_LINE"
echo "  cows alive after the plain lens's shot: $DIFF_COW_BEFORE -> $DIFF_COW_AFTER : $(ctl entities 12 cow | jq -c '[.entities[] | {id, type, pos, health}]')"
[ "$DIFF_COW_AFTER" -eq "$DIFF_COW_BEFORE" ] || fail "the plain lens killed the cow ($DIFF_COW_BEFORE -> $DIFF_COW_AFTER)"
[ "$(energy_of "$DIFF_KILL_LINE")" = 2500 ] || fail "the plain lens spent more than the 1,000 CF gate: $DIFF_KILL_LINE"

ctl command "tp @s 0.5 100 3.5" >/dev/null
ctl wait 6

# ---------------------------------------------------------------------------
# Q: the disenchanting lens's own beam effect (0.2.14)
# ---------------------------------------------------------------------------
echo "== the disenchanting lens's own beam effect (0.2.14) =="
# `LensDisenchanting.invoke` (cd9d9c6, LensDisenchanting.java:29-77) spends its own 250,000 CF on a
# book + enchanted-item pair in the hit cell's AABB(x,y,z,x+1,y+1,z+1) (no inflation), reaches 5, and
# returns true only when a disenchant happened. The artefact's item is `lens_of_disenchanting` —
# its craft needs eight empowered crystals this package lacks, so the rig gives it. The pin's
# `minecraft:stored_enchantments` / `minecraft:enchantments` components are the book/item halves.
DIS_Z=82
ctl command "fill -10 99 78 22 99 86 minecraft:stone" >/dev/null
ctl command "fill -10 100 78 22 110 86 minecraft:air" >/dev/null

# Q1: the readout, with a solid sight and no items, proves the lens id selects its own rule.
READ_X=0
ctl command "setblock $READ_X 100 $DIS_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "setblock $((READ_X + 2)) 100 $DIS_Z minecraft:stone" >/dev/null
ctl command "give @s actuallyadditions:lens_of_disenchanting 1" >/dev/null
ctl wait 4
ctl select actuallyadditions:lens_of_disenchanting >/dev/null
echo "  the disenchanting lens is harness-given (its craft needs empowered crystals): $(ctl inventory | jq -c '.held.item // empty')"
click_with actuallyadditions:lens_of_disenchanting "$READ_X" 100 "$DIS_Z"
line=$(info "$READ_X" 100 "$DIS_Z")
echo "  after the disenchanting-lens click: $line"
case "$line" in
    *"lens actuallyadditions:lens_of_disenchanting x1"*) ;;
    *) fail "the disenchanting lens did not fill the slot: $line" ;;
esac
case "$(sight_of "$line")" in
    *"disenchanting @ 250000 CF"*) ;;
    *) fail "the readout did not name the disenchanting price: $(sight_of "$line")" ;;
esac
ctl command "setblock $READ_X 100 $DIS_Z minecraft:air" >/dev/null
ctl command "setblock $((READ_X + 2)) 100 $DIS_Z minecraft:air" >/dev/null
ctl command "clear @s" >/dev/null

# Q2: a plain book and an enchanted diamond sword as item entities in the sighted AIR cell. Both
# sit in the same cell (x 6..7, y 100..101, z 82..83) with a never-expiring pickup delay, so the
# beam's box holds them; they are placed at different x so they do not shove each other out.
DIS_X=4
DIS_CELL=$((DIS_X + 2))
ctl command "setblock $DIS_X 100 $DIS_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl command "summon minecraft:item 6.2 100 $(centre "$DIS_Z") {Item:{id:\"minecraft:book\",count:1},PickupDelay:32767s}" >/dev/null
ctl command "summon minecraft:item 6.8 100 $(centre "$DIS_Z") {Item:{id:\"minecraft:diamond_sword\",count:1,components:{\"minecraft:enchantments\":{\"minecraft:sharpness\":1}}},PickupDelay:32767s}" >/dev/null
ctl wait 10
BOOK_NBT() { ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"minecraft:book\"}},limit=1,sort=nearest] Item" 2>&1 || true; }
SWORD_NBT() { ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"minecraft:diamond_sword\"}},limit=1,sort=nearest] Item" 2>&1 || true; }
BEFORE_BOOK=$(BOOK_NBT)
BEFORE_SWORD=$(SWORD_NBT)
echo "  the book before the shot: $BEFORE_BOOK"
echo "  the enchanted sword before the shot: $BEFORE_SWORD"
case "$BEFORE_SWORD" in
    *sharpness*) ;;
    *) fail "the summoned sword did not carry sharpness before the shot: $BEFORE_SWORD" ;;
esac
ctl tp "$((DIS_X + 6)).5" 100 "$(centre "$DIS_Z")" >/dev/null
click_with actuallyadditions:lens_of_disenchanting "$DIS_X" 100 "$DIS_Z"
line=$(info "$DIS_X" 100 "$DIS_Z")
case "$line" in
    *"lens actuallyadditions:lens_of_disenchanting x1"*) ;;
    *) fail "the disenchanting lens did not fill the shot machine's slot: $line" ;;
esac
charge "$DIS_X" 100 "$DIS_Z" 251000 >/dev/null
# A 100-tick cycle is position-phased, so a fixed wait can sample either side of the shot.
for _ in $(seq 1 60); do
    ctl wait 4 >/dev/null
    DIS_LINE=$(info "$DIS_X" 100 "$DIS_Z")
    [ "$(energy_of "$DIS_LINE")" = 251000 ] || break
done
DIS_ENERGY=$(energy_of "$DIS_LINE")
AFTER_BOOK=$(BOOK_NBT)
AFTER_SWORD=$(SWORD_NBT)
echo "  after the disenchant shot: $DIS_LINE"
echo "  the book after the shot: $AFTER_BOOK"
echo "  the sword after the shot: $AFTER_SWORD"
if [ "$SELFTEST" = disenchant ]; then
    # The flipped assertion is the differential's outcome: no stored enchantment moved and only
    # the 1,000 CF gate was spent. This package makes that false.
    if [ "$DIS_ENERGY" = 250000 ] && ! grep -q stored_enchantments <<<"$AFTER_BOOK"; then
        fail "SELFTEST disenchant: the flipped assertion passed (no disenchant), so it proves nothing"
    fi
    fail "SELFTEST disenchant: the book gained stored_enchantments and the buffer read 0 (the real assertion); the flipped assertion 'both unchanged, only the gate spent' fails, so the real one can fail"
fi
grep -q stored_enchantments <<<"$AFTER_BOOK" || fail "the enchantment did not move onto the book: $AFTER_BOOK"
grep -q sharpness <<<"$AFTER_BOOK" || fail "the book's stored enchantments do not name sharpness: $AFTER_BOOK"
! grep -q sharpness <<<"$AFTER_SWORD" || fail "the sword kept the moved enchantment: $AFTER_SWORD"
[ "$DIS_ENERGY" = 0 ] || fail "the disenchanting lens did not spend its 250,000 CF: $DIS_LINE"

# Q3: differential — the same rig with the plain lens leaves both items and spends only the gate.
DIFF_DIS_X=10
ctl command "setblock $DIFF_DIS_X 100 $DIS_Z actuallyadditions:atomic_reconstructor[facing=east]" >/dev/null
ctl command "kill @e[type=item]" >/dev/null
ctl command "summon minecraft:item 12.2 100 $(centre "$DIS_Z") {Item:{id:\"minecraft:book\",count:1},PickupDelay:32767s}" >/dev/null
ctl command "summon minecraft:item 12.8 100 $(centre "$DIS_Z") {Item:{id:\"minecraft:diamond_sword\",count:1,components:{\"minecraft:enchantments\":{\"minecraft:sharpness\":1}}},PickupDelay:32767s}" >/dev/null
ctl wait 10
ctl tp "$((DIFF_DIS_X + 6)).5" 100 "$(centre "$DIS_Z")" >/dev/null
charge "$DIFF_DIS_X" 100 "$DIS_Z" 251000 >/dev/null
ctl wait 120 >/dev/null
DIFF_DIS_LINE=$(info "$DIFF_DIS_X" 100 "$DIS_Z")
if [ "$(energy_of "$DIFF_DIS_LINE")" = 251000 ]; then
    ctl wait 60 >/dev/null
    DIFF_DIS_LINE=$(info "$DIFF_DIS_X" 100 "$DIS_Z")
fi
DIFF_BOOK=$(ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"minecraft:book\"}},limit=1,sort=nearest] Item" 2>&1 || true)
DIFF_SWORD=$(ctl command "data get entity @e[type=minecraft:item,nbt={Item:{id:\"minecraft:diamond_sword\"}},limit=1,sort=nearest] Item" 2>&1 || true)
echo "  the plain lens's shot: $DIFF_DIS_LINE"
echo "  the plain lens's book: $DIFF_BOOK"
echo "  the plain lens's sword: $DIFF_SWORD"
! grep -q stored_enchantments <<<"$DIFF_BOOK" || fail "the plain lens moved an enchantment onto the book: $DIFF_BOOK"
grep -q sharpness <<<"$DIFF_SWORD" || fail "the plain lens stripped the sword's enchantment: $DIFF_SWORD"
[ "$(energy_of "$DIFF_DIS_LINE")" = 250000 ] || fail "the plain lens spent more than the 1,000 CF gate: $DIFF_DIS_LINE"

ctl command "tp @s 0.5 100 3.5" >/dev/null
ctl wait 6

control

echo "PASS: the adjacent crusher took it and crushed coal ore into 3 coal, an unfuelled generator made nothing, a crusher without FE crushed nothing, stone was refused by both, a broken generator kept its FE and burn on its item and came back with them when placed again (a fresh machine did not), a broken loaded crusher kept its FE and progress without carrying its stacks and came back with an empty container (an empty one came back empty), the machines survived a relaunch, the Coal Generator's own recipe unlocked and crafted one machine from six cobblestone (all c:cobblestones tag members), two iron casings and a coal with every ingredient consumed (iron ingots in the casing cells and stone in the cobblestone cells stayed empty), the Iron Casing's own recipe crafted one from #c:ingots/iron, #c:rods/wooden and one Black Quartz with every item consumed (gold ingots and coal in the tag cells stayed empty), the Black Quartz Ore placed and dropped Black Quartz from its own loot table (stone the same way dropped cobblestone, silk touch dropped the ore block instead), the ore smelted and blasted into one Black Quartz each and crushed into two, the ore's generation is asserted as blocked(configured-feature-not-registered) at this pin (the placed feature is merged and skipped as an unknown feature reference, so no ore generates; the day it does, this phase fails), the Atomic Reconstructor faced away from the player who placed it, a generator beside it charged its 300,000 CF buffer, one 1,040 CF shot turned the redstone wire in its beam into a restonia crystal drop and left the block gone and the buffer empty (a stone block at the same distance stayed and the shot still spent its 1,000 CF; 1,039 CF converted nothing; the beam reached a block ten away and not one eleven away; two convertible blocks in one plane were both converted by 1,120 CF and only one by 1,040; a redstone block froze its cycle; a broken one kept its buffer on its item), the beam's item half converted a dropped redstone into one Restonia Crystal with its count conserved and its output marked aa_cnv (the same item two blocks across the beam stayed redstone while the shot spent only its 1,000 CF gate; a stack of three converted exactly one and left two, unmarked; a west-facing beam converted its item too), the two item-only laser recipes converted at their own energy (rotten flesh into leather at 20,000 CF and quartz into a prismarine shard at 30,000 CF, each leaving an empty buffer), the reconstructor's redstone mode started off and a stick left it there while a click holding a redstone torch switched it to pulse mode without placing the torch, pulse mode neither ran its cycle nor fired without a signal, a redstone block beside the machine fired exactly one 1,040 CF shot on each of two rising edges (two crystals, a 2,080 CF buffer emptied, the cycle untouched) while the same machine without the toggle stayed frozen on the same signal and spent nothing, and the Crusher's recipe — uncraftable until this slice — now crafts from two restonia crystals, proving the chain closed; the lens (eight glass and a Black Quartz, all nine consumed) crafted and right-clicked into the reconstructor's empty slot (info read lens actuallyadditions:lens x1), a second lens was refused by the occupied slot and a stick was refused by the slot, and a dropped lens in the beam became lens_of_color for the 1,000 CF gate plus the 5,000 CF ring conversion (40 CF left) while a dropped stick stayed and spent only its gate, and the harness-given miner lens in the slot made a 61,000 CF shot swap the sighted stone for one of the nine mining-lens ores (the block read back with ctl block) while a fresh default-lens machine kept its stone and spent only its gate, and the harness-given detonator lens in the slot made a 251,000 CF shot set off the artefact's sourceless radius-10 fiery blast — spending 250,000 CF and lighting fire in the arena while **keeping** the sighted stone, because upstream's ExplosionInteraction.NONE keeps blocks at this pin — whereas a fresh default-lens machine kept its 250,000 CF, started no fire and kept its stone, and the harness-given killer lens made a 3,500 CF shot hurt a NoAI cow in the sighted air cell for 20 damage from a fake player's player_attack at 2,500 CF (the cow's health 0, the buffer 0, the readout naming killer @ 2500 CF at a solid sight) while the default-lens differential kept its cow and spent only the 1,000 CF gate, the harness-given disenchanting lens made a 251,000 CF shot move sharpness from a dropped diamond sword onto a dropped book in the sighted cell (the book's stored_enchantments named sharpness, the sword lost it, the buffer 0, the readout naming disenchanting @ 250000 CF) while the default-lens differential left both items untouched and spent only the 1,000 CF gate"
