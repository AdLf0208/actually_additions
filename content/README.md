# Actually Additions — content (slice 1)

The `.hmod` for the Coal Generator and the Crusher. This folder **is** the mod
root (`horizon-mod.toml` + `assets/` + `data/`); `actuallyadditions.hmod` is the
built artifact.

Every file comes from the raw carry of the ATM10 jar
`actuallyadditions-1.3.26+mc1.21.1.jar` (Crash Assistant `modlist.json`;
Modrinth SHA-1 `bd1826f117065dc3d73f0a7197091a4c37829a06`, 3,217,309 B) in
`ports/_shared/carry-work/actuallyadditions/carry/`, produced by
`horizon-port-pack check` at the campaign pin. `patches/assemble.py` reproduces
this folder and applies the five patches below; no asset or model is invented.

| Path | What |
|---|---|
| `data/actuallyadditions/horizon/block/coal_generator.json` | **Patched** from the carry's `minecraft:carved_pumpkin` guess to `minecraft:furnace` (the machine is a container with a block entity and upstream's `lit` state is the crusher's; the generator keeps the template's `lit=false`). Hardness 1.5, resistance 10, `minecraft:iron_block` sounds, tool required (upstream `defaultPickProps().sound(METAL)`). |
| `data/actuallyadditions/horizon/block/crusher.json` | The carry's `minecraft:furnace` (facing + lit) — already right. |
| `data/actuallyadditions/horizon/creative_tab/machines.json` | Upstream's tab is code; one tab with the two items. |
| `data/actuallyadditions/loot_table/blocks/{coal_generator,crusher}.json` | **Patched**: the raw carry's `minecraft:copy_components` modifier names `actuallyadditions:energy`, a component type not registered in slice 1; an unknown component would drop the table (a machine would drop nothing). |
| `data/actuallyadditions/recipe/{coal_generator,crusher}.json` | Upstream's shaped recipes, as shipped. Their ingredients (`black_quartz`, `restonia_crystal`, `iron_casing`, `basic_coil`) are later slices, so they do not craft yet (recorded gap). |
| `data/actuallyadditions/recipe/crushing/*.json` | The 49 crushing recipes of the custom type `actuallyadditions:crushing`; the pin keeps a recipe of a type outside `minecraft:` as JSON in its custom-recipe table, which the native half reads. |
| `data/actuallyadditions/advancement/craft_{coal_generator,crusher}.json` | Upstream's two advancements for these recipes. |
| `data/minecraft/tags/block/mineable/pickaxe.json` | **Patched** to the two ids that exist (the carry names all 125 AA blocks). |
| `assets/actuallyadditions/blockstates/coal_generator.json` | **Patched**: the furnace template carries `lit`, so both values bind upstream's model (the carry only had `facing`). |
| `assets/actuallyadditions/blockstates/crusher.json` | Upstream's `facing` × `lit` (8 variants). |
| `assets/actuallyadditions/models/block/*`, `models/item/*`, `items/*` | Upstream's models, carried (the carry generated the 26.3 `items/` definitions). |
| `assets/actuallyadditions/textures/block/*` | Only the nine textures the two models reference, plus their `.mcmeta` animations. |
| `assets/actuallyadditions/lang/en_us.json` | Upstream's full `en_us.json` plus the port's tab title key. |

Built with (inside a build slot, from this folder):

```sh
CARGO_TARGET_DIR=<slot target>/cargo-horizon-mod cargo run --locked --offline \
  --manifest-path ../../../ports/_shared/pins/horizon-1d63e0a/crates/cargo-horizon-mod/Cargo.toml \
  -- horizon-mod build
```

then copied beside `carry/` as `content/actuallyadditions.hmod`.
