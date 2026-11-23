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
# Slice 4 (0.2.5): the Black Quartz Ore and the gem it drops. The ore is a block
# (`ActuallyBlocks.BLACK_QUARTZ_ORE`: `Blocks.STONE` copied, `strength(1.5f, 10f)`, so the
# same numbers as the machines); the gem is a plain item. The ore is worldgen: its
# configured/placed features and the biome modifier that attaches them are carried below.
ORE = "black_quartz_ore"
GEM = "black_quartz"
# Slice 5 (0.2.6): the Atomic Reconstructor and the crystal its beam makes. The machine is a
# full-directional block (`FullyDirectionalBlock.FACING`, six values) whose only state property is
# `facing`; the result of the redstone conversion is a plain item. The three `laser/` recipes are
# the ones whose terms this package resolves *for a block*: `#c:dusts/redstone` (a redstone wire's
# block item is `minecraft:redstone`), `#c:sands` and `minecraft:red_mushroom`. The jar's other
# laser recipes name items this package does not ship (the other crystals, lenses, relays, ethetic
# blocks) or turn an item into an item (`leather ← rotten flesh`, `prismarine_shard ← quartz`),
# which is the beam's item-entity half, not the block half this slice proves.
RECONSTRUCTOR = "atomic_reconstructor"
CRYSTAL = "restonia_crystal"
LASER_RECIPES = ("crystalize_restonia_crystal", "soul_sand", "nether_wart")
# NeoForge 1.21.x's `Tags.Items.DUSTS_REDSTONE` and `Tags.Items.SANDS` (26.3 ships no `c:`
# namespace, so the two tags the machine's recipe and its soul-sand conversion key on are
# declared here).
REDSTONE_DUST_TAG = ("minecraft:redstone",)
SANDS_TAG = ("minecraft:red_sand", "minecraft:sand", "minecraft:suspicious_sand")
# NeoForge's convention item tags the Iron Casing's recipe keys on (`#c:ingots/iron`,
# `#c:rods/wooden`). 26.3 ships no `c:` namespace, so the port declares the two tags; the
# members are NeoForge 1.21.x's generated lists (iron has one member, wooden rods the stick).
IRON_INGOT_TAG = ("minecraft:iron_ingot",)
WOODEN_ROD_TAG = ("minecraft:stick",)
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
    "atomic_reconstructor_front.png",
    "atomic_reconstructor_side.png",
    "base_texture_arrow.png",
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
        json.dumps(
            {
                "values": [
                    f"actuallyadditions:{b}" for b in (*BLOCKS, CASING, ORE, RECONSTRUCTOR)
                ]
            },
            indent=2,
        )
        + "\n",
    )
    # Upstream puts the ore in `minecraft:needs_stone_tool` (BlockTagsGenerator): a wooden
    # pickaxe does not drop it.
    write(
        OUT / "data/minecraft/tags/block/needs_stone_tool.json",
        json.dumps({"values": [f"actuallyadditions:{ORE}"]}, indent=2) + "\n",
    )

    # The item tag the mod's own recipes key on (`#c:cobblestones` in
    # `recipe/coal_generator.json` and `recipe/crusher.json`). Without it the
    # loader drops both recipes as an unresolved ingredient.
    write(
        OUT / "data/c/tags/item/cobblestones.json",
        json.dumps({"values": list(COBBLESTONE_TAG)}, indent=2) + "\n",
    )
    # The Iron Casing's recipe keys on these two; a missing tag drops the recipe at load.
    write(
        OUT / "data/c/tags/item/ingots/iron.json",
        json.dumps({"values": list(IRON_INGOT_TAG)}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/item/rods/wooden.json",
        json.dumps({"values": list(WOODEN_ROD_TAG)}, indent=2) + "\n",
    )

    # The Black Quartz Ore, the Black Quartz gem and their worldgen (slice 4, 0.2.5).
    for source in ("blockstates", "items"):
        copy(
            CARRY / f"assets/actuallyadditions/{source}/{ORE}.json",
            assets / f"{source}/{ORE}.json",
        )
    copy(
        CARRY / f"assets/actuallyadditions/models/block/{ORE}.json",
        assets / f"models/block/{ORE}.json",
    )
    for model in (f"models/item/{ORE}.json", f"models/item/{GEM}.json"):
        copy(CARRY / f"assets/actuallyadditions/{model}", assets / model)
    copy(
        CARRY / f"assets/actuallyadditions/items/{GEM}.json",
        assets / f"items/{GEM}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/textures/block/{ORE}.png",
        assets / f"textures/block/{ORE}.png",
    )
    copy(
        CARRY / f"assets/actuallyadditions/textures/item/{GEM}.png",
        assets / f"textures/item/{GEM}.png",
    )
    # `ActuallyBlocks.miscBlockProperties()`: `Blocks.STONE` copied, `strength(1.5f, 10f)`,
    # so stone's sound and a tool requirement, and the item is the block's own.
    write(
        data / f"horizon/block/{ORE}.json",
        json.dumps(
            {
                "template": "minecraft:stone",
                "properties": {
                    "hardness": 1.5,
                    "explosion_resistance": 10.0,
                    "requires_tool": True,
                },
                "item": True,
            },
            indent=2,
        )
        + "\n",
    )
    write(data / f"horizon/item/{GEM}.json", json.dumps({"template": "minecraft:stick"}, indent=2) + "\n")
    # The jar's loot table, already upgraded by the port pack to 26.3's shape: silk touch
    # drops the ore itself, otherwise one Black Quartz with fortune's `ore_drops` bonus and
    # explosion decay. This is the one carried table that is *not* the machine's shape.
    copy(
        CARRY / f"data/actuallyadditions/loot_table/blocks/{ORE}.json",
        data / f"loot_table/blocks/{ORE}.json",
    )
    # The ore's own recipes: a furnace, a blast furnace, and the crusher's (already carried
    # with the other 48 `crushing/*` files) all produce the gem.
    for recipe in ("black_quartz_ore_smelting", "black_quartz_ore_blasting", "iron_casing"):
        copy(
            CARRY / f"data/actuallyadditions/recipe/{recipe}.json",
            data / f"recipe/{recipe}.json",
        )
    # The convention tags a `c:ores` consumer reads, and the gem tag the quartz family
    # shares. Only ids this package declares are named: the storage block is another slice,
    # so `c:storage_blocks/black_quartz` is not carried (its lone member does not exist here).
    write(
        OUT / "data/c/tags/block/ores/black_quartz.json",
        json.dumps({"values": [f"actuallyadditions:{ORE}"]}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/block/ores.json",
        json.dumps({"values": ["#c:ores/black_quartz"]}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/block/ores_in_ground/stone.json",
        json.dumps({"values": [f"actuallyadditions:{ORE}"]}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/item/ores/black_quartz.json",
        json.dumps({"values": [f"actuallyadditions:{ORE}"]}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/item/ores.json",
        json.dumps({"values": ["#c:ores/black_quartz"]}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/item/ores_in_ground/stone.json",
        json.dumps({"values": [f"actuallyadditions:{ORE}"]}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/item/gems/black_quartz.json",
        json.dumps({"values": [f"actuallyadditions:{GEM}"]}, indent=2) + "\n",
    )
    # The worldgen: pure vanilla JSON (`minecraft:ore` + count/in_square/height_range/biome).
    # What attaches it to the Overworld is a biome modifier. Upstream's own
    # `neoforge/biome_modifier/add_black_quartz.json` names
    # `actuallyadditions:bool_config_feature_modifier`, a type the pin does not read (it would be
    # skipped), so the file is written with the platform's `neoforge:add_features` type instead —
    # the same addition, the `generateQuartz` flag dropped. `Mod::register` also declares it
    # through the SDK's `declare_biome_modifier`; at this pin the data file is the one the content
    # root reads (measured: the code declaration never reaches `biome-modifiers.json`).
    for feature in ("configured_feature", "placed_feature"):
        copy(
            CARRY / f"data/actuallyadditions/worldgen/{feature}/ore_black_quartz.json",
            data / f"worldgen/{feature}/ore_black_quartz.json",
        )
    write(
        OUT / "data/actuallyadditions/neoforge/biome_modifier/add_black_quartz.json",
        json.dumps(
            {
                "type": "neoforge:add_features",
                "biomes": "#minecraft:is_overworld",
                "features": f"actuallyadditions:ore_black_quartz",
                "step": "underground_ores",
            },
            indent=2,
        )
        + "\n",
    )

    # The Atomic Reconstructor and its crystal (slice 5, 0.2.6).
    for source in ("blockstates", "items"):
        copy(
            CARRY / f"assets/actuallyadditions/{source}/{RECONSTRUCTOR}.json",
            assets / f"{source}/{RECONSTRUCTOR}.json",
        )
    copy(
        CARRY / f"assets/actuallyadditions/models/block/{RECONSTRUCTOR}.json",
        assets / f"models/block/{RECONSTRUCTOR}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/models/item/{RECONSTRUCTOR}.json",
        assets / f"models/item/{RECONSTRUCTOR}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/items/{CRYSTAL}.json",
        assets / f"items/{CRYSTAL}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/models/item/{CRYSTAL}.json",
        assets / f"models/item/{CRYSTAL}.json",
    )
    copy(
        CARRY / f"assets/actuallyadditions/textures/item/{CRYSTAL}.png",
        assets / f"textures/item/{CRYSTAL}.png",
    )
    copy(
        CARRY / f"data/actuallyadditions/loot_table/blocks/{RECONSTRUCTOR}.json",
        data / f"loot_table/blocks/{RECONSTRUCTOR}.json",
    )
    # Its table names the unregistered `actuallyadditions:energy` and `pulse_mode` components, so
    # the same strip applies as for the two machines: the state rides
    # `minecraft:block_entity_data` instead (`support::on_block_drops`).
    reconstructor_table = data / f"loot_table/blocks/{RECONSTRUCTOR}.json"
    table = json.loads(reconstructor_table.read_text())
    for pool in table.get("pools", []):
        pool.pop("modifier", None)
    write(reconstructor_table, json.dumps(table, indent=2) + "\n")
    copy(
        CARRY / f"data/actuallyadditions/recipe/{RECONSTRUCTOR}.json",
        data / f"recipe/{RECONSTRUCTOR}.json",
    )
    copy(
        CARRY / f"data/actuallyadditions/advancement/craft_reconstructor.json",
        data / "advancement/craft_reconstructor.json",
    )
    # `ActuallyBlocks.defaultPickProps(10.0F, 80F)`: `Blocks.STONE` copied with that strength, so
    # stone's sound and a tool requirement. The jar's model is a whole block with a face on one
    # side, and the blockstate names only `facing` (six values), so the template is the one vanilla
    # block with exactly that state property; the shapes are a full cube on every facing.
    write(
        data / f"horizon/block/{RECONSTRUCTOR}.json",
        json.dumps(
            {
                "template": "minecraft:end_rod",
                "properties": {
                    "hardness": 10.0,
                    "explosion_resistance": 80.0,
                    "light": 0,
                    "requires_tool": True,
                    "sounds": "minecraft:stone",
                },
                "shapes": {
                    "property": "facing",
                    "values": {
                        facing: [[0, 0, 0, 1, 1, 1]]
                        for facing in ("down", "up", "north", "south", "west", "east")
                    },
                },
                "item": True,
            },
            indent=2,
        )
        + "\n",
    )
    write(
        data / f"horizon/item/{CRYSTAL}.json",
        json.dumps({"template": "minecraft:stick"}, indent=2) + "\n",
    )
    for recipe in LASER_RECIPES:
        copy(
            CARRY / f"data/actuallyadditions/recipe/laser/{recipe}.json",
            data / f"recipe/laser/{recipe}.json",
        )
    write(
        OUT / "data/c/tags/item/dusts/redstone.json",
        json.dumps({"values": list(REDSTONE_DUST_TAG)}, indent=2) + "\n",
    )
    write(
        OUT / "data/c/tags/item/sands.json",
        json.dumps({"values": list(SANDS_TAG)}, indent=2) + "\n",
    )

    # Upstream's creative tab is code; one tab for the slice, with the two
    # crafting-chain pieces the machine recipes are made of.
    write(
        data / "horizon/creative_tab/machines.json",
        json.dumps(
            {
                "title": "itemGroup.actuallyadditions.machines",
                "icon": "actuallyadditions:coal_generator",
                "items": [f"actuallyadditions:{b}" for b in BLOCKS + (CASING, ORE)] + [f"actuallyadditions:{GEM}"] + [f"actuallyadditions:{i}" for i in ITEMS] + [f"actuallyadditions:{RECONSTRUCTOR}", f"actuallyadditions:{CRYSTAL}"],
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
