#!/usr/bin/env python3
"""Assemble the slice-1 content of the SDK package from the raw carry of the ATM10 jar.

Source of every file: the raw `horizon-port-pack check` output in
`ports/_shared/carry-work/actuallyadditions/carry/` (jar
`actuallyadditions-1.3.26+mc1.21.1.jar`, Modrinth SHA-1
`bd1826f117065dc3d73f0a7197091a4c37829a06`). Nothing is invented: this script
copies the two machines' files and applies only the patches listed in
`README.md`'s content table:

1. `data/actuallyadditions/horizon/block/coal_generator.json`: the raw carry
   guessed `minecraft:carved_pumpkin` (the blockstate's only property is
   `facing`); the block is a container machine and needs a block entity, so it
   is declared on `minecraft:furnace` (facing + lit + BE), with upstream's
   `strength(1.5, 10)`, metal sound and tool requirement.
2. `assets/actuallyadditions/blockstates/coal_generator.json`: the furnace
   template carries `lit`, so both `lit` values are bound to upstream's model
   (the raw carry only had `facing`).
3. The two loot tables lose the `minecraft:copy_components` modifier naming
   `actuallyadditions:energy`: the component type is not registered in slice 1,
   and an unknown component would drop the table (a machine would drop nothing).
   Consequence: breaking a machine does not keep its FE (recorded gap).
4. `data/minecraft/tags/block/mineable/pickaxe.json` keeps only the two ids that
   exist in this slice (the raw carry's tag names all 125 AA blocks).
5. A creative tab (`data/actuallyadditions/horizon/creative_tab/machines.json`)
   because upstream's tab is code, and a subset `lang/en_us.json`.
6. `data/c/tags/item/cobblestones.json` (slice 3): NeoForge's `c:cobblestones`
   convention tag, which 26.3 does not ship and both machine recipes key on.

Run from the campaign root; it writes `assets/` and `data/` at the package root (the SDK
layout — there is no `content/` folder any more, and the root `horizon-mod.toml` is the only
manifest):

    python3 ports/actuallyadditions/tools/assemble_content.py
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CARRY = ROOT / "ports/_shared/carry-work/actuallyadditions/carry"
OUT = ROOT / "ports/actuallyadditions"

BLOCKS = ("coal_generator", "crusher")
# The crafting chain's first two pieces (slice 3, 0.2.4): the Iron Casing is a
# block upstream (`Blocks.IRON_CASING`, `ActuallyBlocks.java:42`), so it carries
# a blockstate, a block model, an item model and a loot table like any block;
# the Basic Coil is a plain item. Both are ingredients of the Coal Generator's
# recipe, which could not resolve before they existed.
CASING = "iron_casing"
ITEMS = ("basic_coil",)
# `c:cobblestones` is a NeoForge convention tag, not a jar file: 26.3 ships no
# `c:` namespace, so the port declares the tag the mod's own recipes use. The
# four members are NeoForge 1.21.x's generated list (the same values the
# theurgy port records in `tools/tag_members.json`), all present in 26.3.
COBBLESTONE_TAG = (
    "minecraft:cobbled_deepslate",
    "minecraft:cobblestone",
    "minecraft:infested_cobblestone",
    "minecraft:mossy_cobblestone",
)
TEXTURES = (
    "base_texture.png",
    "base_texture_back.png",
    "base_texture_large.png",
    "base_texture_small.png",
    "coal_generator_fire_animated.png",
    "coal_generator_fire_animated.png.mcmeta",
    "coal_generator_front.png",
    "generator_top.png",
    "crusher_front.png",
    "crusher_rotation_animation.png",
    "crusher_rotation_animation.png.mcmeta",
)


def copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def write(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data)


def main() -> None:
    assets = OUT / "assets/actuallyadditions"
    data = OUT / "data/actuallyadditions"

    for block in BLOCKS:
        copy(
            CARRY / f"assets/actuallyadditions/blockstates/{block}.json",
            assets / f"blockstates/{block}.json",
        )
        copy(
            CARRY / f"assets/actuallyadditions/items/{block}.json",
            assets / f"items/{block}.json",
        )
        copy(
            CARRY / f"assets/actuallyadditions/models/block/{block}.json",
            assets / f"models/block/{block}.json",
        )
        copy(
            CARRY / f"assets/actuallyadditions/models/item/{block}.json",
            assets / f"models/item/{block}.json",
        )
        copy(
            CARRY / f"data/actuallyadditions/loot_table/blocks/{block}.json",
            data / f"loot_table/blocks/{block}.json",
        )
        copy(
            CARRY / f"data/actuallyadditions/recipe/{block}.json",
            data / f"recipe/{block}.json",
        )
        copy(
            CARRY / f"data/actuallyadditions/advancement/craft_{block}.json",
            data / f"advancement/craft_{block}.json",
        )
        declaration = json.loads(
            (CARRY / f"data/actuallyadditions/horizon/block/{block}.json").read_text()
        )
        if block == "coal_generator":
            declaration = {
                "template": "minecraft:furnace",
                "properties": {
                    "hardness": 1.5,
                    "explosion_resistance": 10.0,
                    "sounds": "minecraft:iron_block",
                    "requires_tool": True,
                },
                "item": True,
            }
        write(data / f"horizon/block/{block}.json", json.dumps(declaration, indent=2) + "\n")

    # The crafting chain's first two pieces.
    copy(
        CARRY / f"assets/actuallyadditions/blockstates/{CASING}.json",
        assets / f"blockstates/{CASING}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/items/{CASING}.json",
        assets / f"items/{CASING}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/models/block/{CASING}.json",
        assets / f"models/block/{CASING}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/models/item/{CASING}.json",
        assets / f"models/item/{CASING}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/textures/block/{CASING}.png",
        assets / f"textures/block/{CASING}.png",
    )
    copy(
        CARRY / f"data/actuallyadditions/loot_table/blocks/{CASING}.json",
        data / f"loot_table/blocks/{CASING}.json",
    )
    for item in ITEMS:
        copy(
            CARRY / f"assets/actuallyadditions/items/{item}.json",
            assets / f"items/{item}.json",
        )
        copy(
            CARRY / f"assets/actuallyadditions/models/item/{item}.json",
            assets / f"models/item/{item}.json",
        )
        copy(
            CARRY / f"assets/actuallyadditions/textures/item/{item}.png",
            assets / f"textures/item/{item}.png",
        )
        write(
            data / f"horizon/item/{item}.json",
            json.dumps(
                json.loads((CARRY / f"data/actuallyadditions/horizon/item/{item}.json").read_text()),
                indent=2,
            )
            + "\n",
        )
    # Upstream: `Blocks.STONE` copied, `strength(1.5f, 10f)` and a metal sound
    # (`ActuallyBlocks.miscBlockProperties`), so the same numbers as the machines.
    write(
        data / f"horizon/block/{CASING}.json",
        json.dumps(
            {
                "template": "minecraft:stone",
                "properties": {
                    "hardness": 1.5,
                    "explosion_resistance": 10.0,
                    "sounds": "minecraft:iron_block",
                    "requires_tool": True,
                },
                "item": True,
            },
            indent=2,
        )
        + "\n",
    )

    for texture in TEXTURES:
        copy(
            CARRY / f"assets/actuallyadditions/textures/block/{texture}",
            assets / f"textures/block/{texture}",
        )

    # The coal generator's blockstate also binds the furnace template's `lit`.
    blockstate = json.loads((assets / "blockstates/coal_generator.json").read_text())
    variants = blockstate["variants"]
    for facing, model in list(variants.items()):
        name = facing.split("=", 1)[1]
        variants[f"{facing},lit=false"] = model
        variants[f"{facing},lit=true"] = model
        del variants[facing]
    write(assets / "blockstates/coal_generator.json", json.dumps(blockstate, indent=2) + "\n")

    # The crushing recipes are the port's custom recipe type (the pin keeps a
    # recipe of a type outside `minecraft:` as its JSON in the custom table).
    crushing = CARRY / "data/actuallyadditions/recipe/crushing"
    for recipe in sorted(crushing.glob("*.json")):
        copy(recipe, data / f"recipe/crushing/{recipe.name}")

    # The energy component is not registered in slice 1: drop the modifier so
    # the loot tables parse and the machines drop themselves.
    for block in BLOCKS:
        path = data / f"loot_table/blocks/{block}.json"
        table = json.loads(path.read_text())
        for pool in table.get("pools", []):
            pool.pop("modifier", None)
        write(path, json.dumps(table, indent=2) + "\n")

    # Every block the tag names must exist; a subset keeps the tag honest.
    write(
        OUT / "data/minecraft/tags/block/mineable/pickaxe.json",
        json.dumps({"values": [f"actuallyadditions:{b}" for b in BLOCKS + (CASING,)]}, indent=2)
        + "\n",
    )

    # The item tag the mod's own recipes key on (`#c:cobblestones` in
    # `recipe/coal_generator.json` and `recipe/crusher.json`). Without it the
    # loader drops both recipes as an unresolved ingredient.
    write(
        OUT / "data/c/tags/item/cobblestones.json",
        json.dumps({"values": list(COBBLESTONE_TAG)}, indent=2) + "\n",
    )

    # Upstream's creative tab is code; one tab for the slice, with the two
    # crafting-chain pieces the machine recipes are made of.
    write(
        data / "horizon/creative_tab/machines.json",
        json.dumps(
            {
                "title": "itemGroup.actuallyadditions.machines",
                "icon": "actuallyadditions:coal_generator",
                "items": [f"actuallyadditions:{b}" for b in BLOCKS + (CASING,) + ITEMS],
            },
            indent=2,
        )
        + "\n",
    )

    # The full upstream language file, plus the tab title and the tooltip key.
    lang = json.loads((CARRY / "assets/actuallyadditions/lang/en_us.json").read_text())
    lang["itemGroup.actuallyadditions.machines"] = "Actually Additions: Machines"
    write(assets / "lang/en_us.json", json.dumps(lang, indent=2, sort_keys=True) + "\n")

    print(f"assembled {OUT}")


if __name__ == "__main__":
    main()
