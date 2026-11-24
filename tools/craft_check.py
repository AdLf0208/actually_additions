#!/usr/bin/env python3
"""Craft this package's recipes in a real crafting table.

Called by `tools/e2e.sh` with the open game's control socket. The harness's
crafting table exposes the 3x3 grid as slots 100-108 (row-major) and the result
as 200, and reports them through `ctl screen` (`craft_size` 3). A slot click
needs the rendered screen layout, which is why the e2e launches `--offscreen`.

The recipes under test are `data/actuallyadditions/recipe/*.json`. Until 0.2.4
the loader dropped the Coal Generator's — the load log named `#c:cobblestones`
and the three `actuallyadditions:` items it keys on — so the game had no Coal
Generator recipe at all. The phases:

  A  `recipe give @s actuallyadditions:coal_generator` unlocks exactly one
     recipe, and (0.2.6) `give actuallyadditions:restonia_crystal` now answers:
     the Atomic Reconstructor's beam makes the crystal, so the Crusher's recipe's
     last key exists;
  B  the pattern crafts one Coal Generator, and all nine items are
     consumed (six cobblestone — the pattern's six C cells — two iron casings, one coal) with an
     empty grid;
  C  the tag is a tag: the same pattern with `minecraft:mossy_cobblestone` in the
     cobblestone cells also crafts;
  D  two controls stay empty — `minecraft:iron_ingot` where the casings go (the
     brief's differential) and `minecraft:stone` in the cobblestone cells (a
     block the `c:cobblestones` tag must not contain);
  E  (0.2.6) the Crusher's own recipe (`RFC / BIB / CFR`) now crafts one machine
     from its nine keys — two restonia crystals, two flint, two cobblestone, two
     basic coils and one iron casing — every ingredient consumed. It was
     `blocked(restonia_crystal_source)` until the beam could make the crystal;
  F  the Iron Casing's own recipe (0.2.5, `WSW / SQS / WSW`) unlocks and crafts one
     casing from four iron ingots (`#c:ingots/iron`), four sticks (`#c:rods/wooden`)
     and one `actuallyadditions:black_quartz`, every ingredient consumed;
  G  a tag member that is not a member stays empty — gold ingots where the
     `#c:ingots/iron` cells go (a wildcard tag would craft);
  H  the same for `#c:rods/wooden` — coal in its cells leaves the result empty;
  I  (0.2.6) the Atomic Reconstructor's own recipe (`IRI / RCR / IRI`) crafts one
     machine from four iron ingots (`#c:ingots/iron`), four redstone
     (`#c:dusts/redstone`) and one iron casing, all nine consumed;
  J  its two tag keys are not wildcards — gold ingots in the iron cells and
     glowstone dust in the redstone cells each leave the result empty;
  K  (0.2.10) the lens (`GGG / GBG / GGG`) crafts from eight `#c:glass_blocks`
     members and one Black Quartz, all nine consumed, leaving one lens in the
     inventory for the slot leg; stone in the glass cells leaves the result empty.

`--negative` is the counterfactual: it asserts the *pre-0.2.4* state (the Coal
Generator's recipe is not unlocked) and therefore must fail on this package,
proving phase A can fail.

    python3 tools/craft_check.py SOCK CTL X Y Z [--negative]
"""
import json
import subprocess
import sys

# The crafting table's grid, row-major, and its result slot (`ctl screen`).
GRID = {
    "tl": 100, "tm": 101, "tr": 102,
    "ml": 103, "mm": 104, "mr": 105,
    "bl": 106, "bm": 107, "br": 108,
}
RESULT = 200

# The Coal Generator, `CIC / CAC / CIC`: casings in the four corners and the top
# and bottom middles, cobblestone in the four edge middles, coal in the centre.
C_CELLS = [GRID[c] for c in ("tl", "tr", "ml", "mr", "bl", "br")]
CASING_CELLS = [GRID[c] for c in ("tm", "bm")]
CENTRE = GRID["mm"]
# The Crusher, `RFC / BIB / CFR`.
CRUSHER_CELLS = {
    "r": [GRID["tl"], GRID["br"]],
    "f": [GRID["tm"], GRID["bm"]],
    "c": [GRID["tr"], GRID["bl"]],
    "b": [GRID["ml"], GRID["mr"]],
    "i": [GRID["mm"]],
}
# The Iron Casing (0.2.5), `WSW / SQS / WSW`: `W` = `#c:ingots/iron`,
# `S` = `#c:rods/wooden`, `Q` = `actuallyadditions:black_quartz`.
IRON_CELLS = [GRID["tl"], GRID["tr"], GRID["bl"], GRID["br"]]
ROD_CELLS = [GRID["tm"], GRID["ml"], GRID["mr"], GRID["bm"]]
# The Atomic Reconstructor (0.2.6), `IRI / RCR / IRI`: `I` = `#c:ingots/iron` in
# the corners, `R` = `#c:dusts/redstone` in the edge middles, `C` = the casing.
REDSTONE_CELLS = ROD_CELLS


def main() -> int:
    argv = sys.argv[1:]
    negative = "--negative" in argv
    argv = [a for a in argv if a != "--negative"]
    if len(argv) != 5:
        raise SystemExit(__doc__)
    sock, ctl, x, y, z = argv

    def run(*args: str):
        out = subprocess.run([ctl, "--socket", sock, *args], text=True, capture_output=True)
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            raise SystemExit(f"ctl {' '.join(args)}: {out.stdout}{out.stderr}")

    def wait(ticks: int = 4) -> None:
        run("wait", str(ticks))

    def slots() -> list:
        screen = run("screen")
        if "slots" not in screen:
            raise SystemExit(f"FAIL: no menu is open: {json.dumps(screen)[:300]}")
        return screen["slots"]

    def find(item: str) -> int:
        for slot in slots():
            if slot.get("item") == item:
                return slot["slot"]
        raise SystemExit(f"FAIL: the inventory holds no {item} for the grid")

    def result():
        for slot in slots():
            if slot["slot"] == RESULT and slot.get("item"):
                return slot
        return None

    def grid_empty() -> bool:
        return all(not s.get("item") for s in slots() if 100 <= s["slot"] <= 108)

    def count(item: str) -> int:
        return run("inventory").get("counts", {}).get(item, 0)

    def say(*lines: str) -> None:
        for line in lines:
            print(line)

    failures: list[str] = []

    # Phase A: the recipe book knows the recipe, or (under --negative) does not.
    def recipe_gate() -> None:
        reply = run("command", "recipe give @s actuallyadditions:coal_generator")
        text = " ".join(reply.get("chat", []))
        say(f"  recipe give actuallyadditions:coal_generator -> {json.dumps(reply)}")
        if negative:
            if "Unlocked 1 recipe" in text:
                raise SystemExit(
                    "FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour), so "
                    "the flipped assertion 'the recipe is not unlocked' fails — the real assertion "
                    "can fail"
                )
            raise SystemExit(
                "FAIL: NEGATIVE: the recipe did not unlock; the flipped assertion passed, so this "
                "counterfactual proves nothing"
            )
        if "Unlocked 1 recipe" not in text:
            failures.append(
                "`recipe give @s actuallyadditions:coal_generator` did not unlock one recipe "
                f"(the recipe is absent or invalid): {text}"
            )
        # The item the Crusher's recipe waits on (0.2.6): the Atomic Reconstructor's beam makes it,
        # so it must now exist — a refusal here means the crystal did not ship and the Crusher's
        # recipe would be back to `blocked(restonia_crystal_source)`.
        crusher_recipe = run("command", "recipe give @s actuallyadditions:crusher")
        say(f"  recipe give actuallyadditions:crusher -> {json.dumps(crusher_recipe)}")
        if "Unlocked 1 recipe" not in " ".join(crusher_recipe.get("chat", [])):
            failures.append(
                "`recipe give @s actuallyadditions:crusher` did not unlock one recipe — the "
                f"loader dropped it: {json.dumps(crusher_recipe)}"
            )
        # The Iron Casing's own recipe (0.2.5): it resolves only if both `c:` tags and the gem
        # are present. An empty tag file is dropped at load, which drops the recipe with it, so
        # this unlock is the in-game half of the "empty tag" trap.
        casing = run("command", "recipe give @s actuallyadditions:iron_casing")
        say(f"  recipe give actuallyadditions:iron_casing -> {json.dumps(casing)}")
        if "Unlocked 1 recipe" not in " ".join(casing.get("chat", [])):
            failures.append(
                "`recipe give @s actuallyadditions:iron_casing` did not unlock one recipe — the "
                "recipe is absent, or one of its two `c:` tags resolved to nothing and the "
                f"loader dropped it: {json.dumps(casing)}"
            )
        reconstructor = run("command", "recipe give @s actuallyadditions:atomic_reconstructor")
        say(f"  recipe give actuallyadditions:atomic_reconstructor -> {json.dumps(reconstructor)}")
        if "Unlocked 1 recipe" not in " ".join(reconstructor.get("chat", [])):
            failures.append(
                "`recipe give @s actuallyadditions:atomic_reconstructor` did not unlock one "
                f"recipe — `#c:dusts/redstone` did not resolve, or the recipe is absent: "
                f"{json.dumps(reconstructor)}"
            )
        given = run("give", "actuallyadditions:restonia_crystal", "1")
        say(f"  give actuallyadditions:restonia_crystal -> {json.dumps(given)}")
        if "unknown item" in json.dumps(given):
            failures.append(
                "actuallyadditions:restonia_crystal is refused, so the Crusher's recipe's last "
                f"key still cannot exist: {json.dumps(given)}"
            )

    # A fresh table (a replaced block entity, so the grid starts empty), the exact
    # ingredients and the open menu. The player stands ~2.5 blocks off and aims at the
    # table first: `ctl interact` refuses a face the eye cannot see, and standing right
    # beside a block puts the eye above it (the powah port measured both).
    def setup(ingredients: list[tuple[str, int]]) -> None:
        try:
            run("close")
        except SystemExit:
            pass
        wait(4)
        run("setblock", str(x), str(y), str(z), "minecraft:air")
        run("setblock", str(x), str(y), str(z), "minecraft:crafting_table")
        wait(2)
        run("command", f"tp @s {float(x) - 2.5} {float(y)} {float(z) + 0.5}")
        wait(3)
        run("command", "clear @s")
        for item, n in ingredients:
            run("give", item, str(n))
        wait(3)
        run("look-at-block", str(x), str(y), str(z), "up")
        wait(2)
        clicked = run("interact", str(x), str(y), str(z))
        say(f"  interact {x},{y},{z}: {json.dumps(clicked)}")
        wait(5)
        screen = run("screen")
        if screen.get("craft_size") != 3:
            raise SystemExit(
                "FAIL: the crafting table did not open a 3x3 grid "
                f"(screen {screen.get('screen')!r}): {json.dumps(screen)[:300]}"
            )

    # One pickup per target: a single held stack cannot fill several slots with
    # right-clicks while the count is what matters, and re-picking keeps the
    # remainder in the inventory slot it came from.
    def place(item: str, targets: list[int]) -> None:
        for target in targets:
            origin = find(item)
            run("click-slot", str(origin))
            wait(1)
            run("click-slot", str(target), "right")
            wait(1)
            run("click-slot", str(origin))
            wait(1)

    def craft(label, ingredients, placements, left: dict[str, int],
              result_item: str = "actuallyadditions:coal_generator") -> None:
        setup(ingredients)
        for item, cells in placements:
            place(item, cells)
        got = result()
        say(f"  {label}: result {json.dumps(got)}")
        if not got or got.get("item") != result_item or got.get("count") != 1:
            grid = [s for s in slots() if 100 <= s["slot"] <= 108]
            failures.append(f"{label}: expected 1 {result_item}, got {got} "
                            f"(grid {json.dumps(grid)})")
            return
        run("click-slot", str(RESULT), "shift")
        wait(5)
        say(f"  {label}: inventory after the craft "
            f"{json.dumps({k: count(k) for k in left})}")
        if not grid_empty():
            failures.append(f"{label}: the grid still holds ingredients after the craft")
        for item, want in left.items():
            got_count = count(item)
            if got_count != want:
                failures.append(f"{label}: {item} is {got_count} after the craft, expected {want} "
                                "(the ingredients must be consumed)")

    def empty_control(label: str, ingredients, placements) -> None:
        setup(ingredients)
        for item, cells in placements:
            place(item, cells)
        got = result()
        say(f"  {label}: result {json.dumps(got)}")
        if got is not None:
            failures.append(f"{label}: the control crafted {got.get('item')} x{got.get('count')}")

    recipe_gate()
    if negative:
        # `recipe_gate` answers with the flipped assertion; report and stop.
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    # A: the deliverable craft.
    craft(
        "coal generator (6 cobblestone + 2 iron casings + 1 coal)",
        [("minecraft:cobblestone", 8), ("actuallyadditions:iron_casing", 4), ("minecraft:coal", 2)],
        [
            ("minecraft:cobblestone", C_CELLS),
            ("actuallyadditions:iron_casing", CASING_CELLS),
            ("minecraft:coal", [CENTRE]),
        ],
        {
            "minecraft:cobblestone": 2,
            "actuallyadditions:iron_casing": 2,
            "minecraft:coal": 1,
            "actuallyadditions:coal_generator": 1,
        },
    )

    # B: the brief's differential — an iron ingot where a casing goes.
    empty_control(
        "control: iron ingots where the casings go",
        [("minecraft:cobblestone", 8), ("minecraft:iron_ingot", 4), ("minecraft:coal", 2)],
        [
            ("minecraft:cobblestone", C_CELLS),
            ("minecraft:iron_ingot", CASING_CELLS),
            ("minecraft:coal", [CENTRE]),
        ],
    )

    # C: a tag member that is not plain cobblestone.
    craft(
        "coal generator from mossy cobblestone (a c:cobblestones member)",
        [("minecraft:mossy_cobblestone", 8), ("actuallyadditions:iron_casing", 4),
         ("minecraft:coal", 2)],
        [
            ("minecraft:mossy_cobblestone", C_CELLS),
            ("actuallyadditions:iron_casing", CASING_CELLS),
            ("minecraft:coal", [CENTRE]),
        ],
        {
            "minecraft:mossy_cobblestone": 2,
            "actuallyadditions:iron_casing": 2,
            "minecraft:coal": 1,
            "actuallyadditions:coal_generator": 1,
        },
    )

    # D: a block the tag must not contain.
    empty_control(
        "control: stone in the cobblestone cells (not a c:cobblestones member)",
        [("minecraft:stone", 8), ("actuallyadditions:iron_casing", 4), ("minecraft:coal", 2)],
        [
            ("minecraft:stone", C_CELLS),
            ("actuallyadditions:iron_casing", CASING_CELLS),
            ("minecraft:coal", [CENTRE]),
        ],
    )

    # E: the Crusher's recipe, whose last key the Atomic Reconstructor's beam now makes (0.2.6).
    craft(
        "crusher (2 restonia + 2 flint + 2 cobblestone + 2 coils + 1 casing)",
        [("actuallyadditions:restonia_crystal", 4), ("minecraft:flint", 4),
         ("minecraft:cobblestone", 4), ("actuallyadditions:basic_coil", 4),
         ("actuallyadditions:iron_casing", 2)],
        [
            ("actuallyadditions:restonia_crystal", CRUSHER_CELLS["r"]),
            ("minecraft:flint", CRUSHER_CELLS["f"]),
            ("minecraft:cobblestone", CRUSHER_CELLS["c"]),
            ("actuallyadditions:basic_coil", CRUSHER_CELLS["b"]),
            ("actuallyadditions:iron_casing", CRUSHER_CELLS["i"]),
        ],
        {
            "actuallyadditions:restonia_crystal": 2,
            "minecraft:flint": 2,
            "minecraft:cobblestone": 2,
            "actuallyadditions:basic_coil": 2,
            "actuallyadditions:iron_casing": 1,
            "actuallyadditions:crusher": 1,
        },
        result_item="actuallyadditions:crusher",
    )

    # F: the Iron Casing's own recipe (0.2.5), from the two convention tags and the gem.
    craft(
        "iron casing (4 iron ingots + 4 sticks + 1 black quartz)",
        [("minecraft:iron_ingot", 6), ("minecraft:stick", 6),
         ("actuallyadditions:black_quartz", 3)],
        [
            ("minecraft:iron_ingot", IRON_CELLS),
            ("minecraft:stick", ROD_CELLS),
            ("actuallyadditions:black_quartz", [CENTRE]),
        ],
        {
            "minecraft:iron_ingot": 2,
            "minecraft:stick": 2,
            "actuallyadditions:black_quartz": 2,
            "actuallyadditions:iron_casing": 1,
        },
        result_item="actuallyadditions:iron_casing",
    )

    # G: `#c:ingots/iron` is a tag, not a wildcard — a gold ingot in its cells crafts nothing.
    empty_control(
        "control: gold ingots where #c:ingots/iron goes (not a member)",
        [("minecraft:gold_ingot", 6), ("minecraft:stick", 6),
         ("actuallyadditions:black_quartz", 3)],
        [
            ("minecraft:gold_ingot", IRON_CELLS),
            ("minecraft:stick", ROD_CELLS),
            ("actuallyadditions:black_quartz", [CENTRE]),
        ],
    )

    # H: likewise `#c:rods/wooden` — an iron ingot is not a rod.
    empty_control(
        "control: iron ingots where #c:rods/wooden goes (not a member)",
        [("minecraft:iron_ingot", 6), ("minecraft:coal", 4),
         ("actuallyadditions:black_quartz", 3)],
        [
            ("minecraft:iron_ingot", IRON_CELLS),
            ("minecraft:coal", ROD_CELLS),
            ("actuallyadditions:black_quartz", [CENTRE]),
        ],
    )

    # I: the Atomic Reconstructor's own recipe (0.2.6), `IRI / RCR / IRI`.
    craft(
        "atomic reconstructor (4 iron ingots + 4 redstone + 1 iron casing)",
        [("minecraft:iron_ingot", 6), ("minecraft:redstone", 6),
         ("actuallyadditions:iron_casing", 2)],
        [
            ("minecraft:iron_ingot", IRON_CELLS),
            ("minecraft:redstone", REDSTONE_CELLS),
            ("actuallyadditions:iron_casing", [CENTRE]),
        ],
        {
            "minecraft:iron_ingot": 2,
            "minecraft:redstone": 2,
            "actuallyadditions:iron_casing": 1,
            "actuallyadditions:atomic_reconstructor": 1,
        },
        result_item="actuallyadditions:atomic_reconstructor",
    )

    # J: its two tag keys are not wildcards — gold ingots where `#c:ingots/iron` goes …
    empty_control(
        "control: gold ingots where #c:ingots/iron goes (not a member)",
        [("minecraft:gold_ingot", 6), ("minecraft:redstone", 6),
         ("actuallyadditions:iron_casing", 2)],
        [
            ("minecraft:gold_ingot", IRON_CELLS),
            ("minecraft:redstone", REDSTONE_CELLS),
            ("actuallyadditions:iron_casing", [CENTRE]),
        ],
    )

    # … and glowstone dust where `#c:dusts/redstone` goes.
    empty_control(
        "control: glowstone dust where #c:dusts/redstone goes (not a member)",
        [("minecraft:iron_ingot", 6), ("minecraft:glowstone_dust", 6),
         ("actuallyadditions:iron_casing", 2)],
        [
            ("minecraft:iron_ingot", IRON_CELLS),
            ("minecraft:glowstone_dust", REDSTONE_CELLS),
            ("actuallyadditions:iron_casing", [CENTRE]),
        ],
    )

    # K (0.2.10): the lens's own recipe, `GGG/GBG/GGG`, eight `#c:glass_blocks` members and one
    # Black Quartz. One crafted lens is left in the inventory for the e2e's lens-slot phase.
    lens_unlock = run("command", "recipe give @s actuallyadditions:lens")
    say(f"  recipe give actuallyadditions:lens -> {json.dumps(lens_unlock)}")
    if "Unlocked 1 recipe" not in " ".join(lens_unlock.get("chat", [])):
        failures.append("actuallyadditions:lens is not in the recipe book")
    GLASS_CELLS = [GRID[c] for c in ("tl", "tm", "tr", "ml", "mr", "bl", "bm", "br")]
    # #c:glass_blocks is a tag, not a wildcard: stone in the eight cells crafts nothing. This
    # control runs *before* the craft, whose `setup` clears the inventory and leaves the lens.
    empty_control(
        "control: stone where #c:glass_blocks goes (not a member)",
        [("minecraft:stone", 8), ("actuallyadditions:black_quartz", 1)],
        [
            ("minecraft:stone", GLASS_CELLS),
            ("actuallyadditions:black_quartz", [CENTRE]),
        ],
    )
    craft(
        "lens (8 glass + 1 black quartz)",
        [("minecraft:glass", 8), ("actuallyadditions:black_quartz", 1)],
        [
            ("minecraft:glass", GLASS_CELLS),
            ("actuallyadditions:black_quartz", [CENTRE]),
        ],
        {
            "minecraft:glass": 0,
            "actuallyadditions:black_quartz": 0,
            "actuallyadditions:lens": 1,
        },
        result_item="actuallyadditions:lens",
    )

    try:
        run("close")
    except SystemExit:
        pass
    wait(3)

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    if failures:
        return 1
    print("recipe PASS: the Coal Generator's own recipe unlocks and crafts one machine from six "
          "cobblestone, two iron casings and a coal (all consumed, empty grid), also crafts from a "
          "mossy cobblestone tag member, and stays empty for iron ingots in the casing cells and "
          "for stone in the cobblestone cells; the Iron Casing's own recipe unlocks and crafts one "
          "casing from four iron ingots (#c:ingots/iron), four sticks (#c:rods/wooden) and one "
          "black quartz, all nine consumed, and stays empty for gold ingots in the ingot cells and "
          "coal in the rod cells; the Crusher's recipe — blocked on restonia_crystal until the "
          "0.2.6 beam could make one — now unlocks and crafts one machine from two restonia "
          "crystals, two flint, two cobblestone, two basic coils and one iron casing, all nine "
          "consumed; and the Atomic Reconstructor's own recipe unlocks and crafts one machine from "
          "four iron ingots, four redstone (#c:dusts/redstone) and one iron casing, all nine "
          "consumed, staying empty for gold ingots in the iron cells and glowstone dust in the "
          "redstone cells; and the lens (`GGG/GBG/GGG`) crafts from eight glass (a "
          "`c:glass_blocks` member) and one Black Quartz, all nine consumed, while stone in the "
          "glass cells stays empty")
    return 0


if __name__ == "__main__":
    sys.exit(main())
