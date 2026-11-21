# Actually Additions — upstream findings (slice 1)

Analysis for the clean-room Rust rewrite of **Actually Additions 1.3.26**
(`Ellpeck/ActuallyAdditions`, **MIT** → licence rank 0), Minecraft Java 1.21.1
NeoForge. The pack ships `actuallyadditions-1.3.26+mc1.21.1.jar`
(Crash Assistant `modlist.json`, Modrinth SHA-1
`bd1826f117065dc3d73f0a7197091a4c37829a06`, size 3,217,309 B).

Repo read: `https://github.com/Ellpeck/ActuallyAdditions` at
`cd9d9c63254f471f966ee51b078afdf47af5f852` (2026-06-19, "Increment version";
`gradle.properties`: `mod_version=1.3.26`, `game_version=1.21.1`,
`neo_version=21.1.233`). Files read (behaviour only, no code copied):

- `mod/tile/TileEntityCoalGenerator.java`, `mod/tile/TileEntityCrusher.java`,
  `mod/tile/CustomEnergyStorage.java`, `mod/tile/ISharingEnergyProvider.java`
- `mod/blocks/BlockCoalGenerator.java`, `mod/blocks/BlockCrusher.java`,
  `mod/blocks/ActuallyBlocks.java` (`defaultPickProps`)
- `mod/crafting/CrushingRecipe.java`
- `mod/inventory/ContainerCoalGenerator.java`, `mod/inventory/CrusherContainer.java`
- `src/generated/resources/data/actuallyadditions/recipe/{coal_generator,crusher}.json`
  and `recipe/crushing/*.json` (50 files)
- `src/generated/resources/assets/actuallyadditions/{blockstates,models}/…`,
  `lang/en_us.json`
- the jar: `META-INF/neoforge.mods.toml` (`license="MIT"`),
  `assets/actuallyadditions/**`, `data/actuallyadditions/**`

## Coal Generator (`actuallyadditions:coal_generator`)

| Item | Upstream | Notes |
|---|---|---|
| energy buffer | `CustomEnergyStorage(60000, 0, 80)` | 60,000 FE capacity, **takes nothing** by capability, **gives up to 80 FE per call/side** |
| production | `ENERGY_PER_TICK = 20` | 20 FE/t while a fuel item burns |
| burn time | `stack.getBurnTime(RecipeType.SMELTING)` | the vanilla smelting fuel value (coal/charcoal 1600, coal block 16000, …) |
| refuel | when not redstone-powered, `currentBurnTime <= 0`, and `energy < 60000`: take one item from slot 0 if its burn time is > 0 | one item consumed per burn |
| slots | 1 (slot 0, fuel); GUI slot at (87,43) | output-less |
| redstone | `isRedstonePowered` only blocks *refuelling*; production continues while burning | no redstone signal required |
| comparator | `floor(energy / 60000 * 15)` | 0 at empty |
| block | horizontal `facing`, metal sound, `strength(1.5, 10)`, random tick smoke particles | `getStateForPlacement` = horizontal opposite |
| NBT | `Energy` (storage) + `BurnTime`/`MaxBurnTime` | written on save and on sync |

Edge cases: energy is capped at capacity (a full buffer does not consume fuel);
a burning item keeps burning even when the buffer is full (energy is lost at the
cap); the fuel slot accepts only smelting fuels; automation may insert a fuel and
may remove a non-fuel item (`getRemover`).

## Crusher (`actuallyadditions:crusher`)

| Item | Upstream | Notes |
|---|---|---|
| energy buffer | `CustomEnergyStorage(60000, 100, 0)` | 60,000 FE, **takes up to 100 FE/call**, gives none |
| use | `ENERGY_USE = 40` **per tick while crushing** | not per operation; 100 ticks → 4,000 FE per operation |
| duration | 100 ticks (single), 150 ticks (double) | |
| slots (single) | 0 input, 1 output 1, 2 output 2 | GUI at (80,21), (66,69), (92,69) |
| recipe match | first crushing recipe whose ingredient matches the input | `ActuallyAdditionsAPI.CRUSHER_RECIPES` (registration order) |
| output room | output 1 empty or same item with room for the result; if a second result exists, output 2 empty or same item with room | otherwise progress resets to 0 |
| finish | add output 1, then `level.random.nextFloat() <= secondChance` adds output 2, then shrink the input by 1 | the bonus roll happens **once per finished operation** |
| lit state | `lit` = `energy >= 40` after the tick; light level **12**; random tick particles | redstone only forces `lit` on (no gating) |
| block | horizontal `facing` + `lit`, metal sound, `strength(1.5, 10)` | |
| NBT | `Energy`, `FirstCrushTime`, `SecondCrushTime`, `IsAutoSplit` | |

Crushing recipe JSON (1.21.1, kept as-is by the pin's custom-recipe table):

```json
{
  "type": "actuallyadditions:crushing",
  "ingredient": { "item": "minecraft:coal_ore" },
  "result": [ { "result": { "count": 3, "id": "minecraft:coal" } } ]
}
```

`result` is a list of **1 or 2** entries of
`{ "result": { "id": …, "count": … }, "chance": <float, default 1.0> }`.
The port reads the first entry as the guaranteed output and the second (if any)
as the bonus. Two-result examples: `gravel → 1 flint + 1 flint @ 0.5`,
`iron_ore → 2 raw_iron + 1 raw_gold @ 0.2`.

Edge cases: a full output stops progress and resets the timer; a missing recipe
resets the timer; energy below 40 pauses (the timer keeps its value upstream, but
`canCrushOn` is still true, so the timer holds); the input is consumed only on a
completed operation; the bonus item is added only if the output slot has room and
the roll passes.

## Energy as FE (the pin has an energy hook)

The brief for this slice assumed "no FE hook exists". That was true at older
pins: at `1d63e0a5` **API 142** (`native_block_entity_energy`,
`native_energy`, `native_energy_insert/extract`, `native_move_energy`) declares
a `Capabilities.Energy.BLOCK` buffer per mod block, kept as the int `energy` in
the block entity's saved compound, and ships the `EnergyHandlerUtil.move` helper
(`crates/horizon-client/src/game/machines/native_energy.rs`). The port uses it
for both machines, so the buffers are real FE and the generator's 80 FE/call
extract / crusher's 100 FE/call insert are enforced by the engine, exactly as
upstream's `CustomEnergyStorage`. The energy is still "in the BE's NBT" as the
brief says (`energy` int in the saved compound).

`native_energy_at` returns nothing for a block entity that is ticking at that
moment, so a generator→crusher transfer cannot run inside either machine's own
tick: the generator queues an adjacent-crusher push and the transfer runs at
`level_tick_post` (the level is in place and no block entity is out of the
world).

## The rest of the mod (next slices, from `mod/tile/`)

Machines seen upstream, for planning — **not** in slice 1 or 2:

- **Generation/energy**: Coal Generator (this slice), Oil Generator, Leaf
  Generator, Heat Collector, Furnace Solar, Bio Reactor, Firework Box,
  Solar/Furnace.
- **Energy storage/transfer**: Battery Box, Energizer, Enervator, Energy Laser
  Relay / Advanced / Extreme, Phantom Energyface, Shock Suppressor.
- **Processing**: Crusher (this slice), Double Crusher, Powered Furnace,
  Canola Press, Fermenting Barrel, Coffee Machine, Atomic Reconstructor,
  Empowerer, Lava Factory Controller, XPSolidifier.
- **Automation/transport**: Placer, Breaker, Dropper, Farmer, Feeder, Fluid
  Placer, Fluid Collector, Item Interface (+ Hopping), Player Interface,
  Phantom Face / Itemface / Liquiface / Redstoneface / Breaker / Placer,
  Ranged Collector, Long-Range Breaker, Vertical Digger.
- **Storage/display**: Giant Chest (3 sizes), Crate, Display Stand.
- **Fluid**: Canola Press, Fermenting Barrel, Oil Generator, Fluid Collector /
  Placer, Phantom Liquiface, Laser Relay Fluids.
- Also: booklet/Patchouli guide, lenses, drills/weapons/armour, crystal ore
  worldgen, `Atomic Reconstructor` conversions, config, JEI integration.

## Class + tier and slice boundary

- **Class**: `content` · **tier**: `machines` (`ports/ledger.csv`), approach
  per the pin's `docs/modpacks.md` §"What packs need and what runs today": a
  block entity with ticks, a container, a menu (deferred), a capability
  (energy) and a custom recipe type — not a data-only carry.
- **Slice 1 (this job)**: the Coal Generator and the Crusher, their blocks,
  items, loot tables, names, models/textures, the two crafting recipes as
  shipped, the 50 `crushing` recipes, the `actuallyadditions:crushing` recipe
  type read from the pin's custom-recipe table, FE buffers through API 142,
  containers, the generator→crusher energy link, and an `/actuallyadditions
  info` readout.
- **Slice 2 (0.2.2)**: the saved-state carry — a broken machine's `Energy`/`BurnTime`/
  `MaxBurnTime` (and the crusher's `FirstCrushTime`) travel on its own item as vanilla
  `minecraft:block_entity_data` and are clamped back on placement, upstream's
  `actuallyadditions:energy` behaviour. The GUI was attempted and reverted: the pin cannot show a
  content menu's slots on the single-player host (`blocked(no-single-player-mod-screen)`, see
  `notes.md`).
- **Not in slice 1/2**: the GUI/screen (upstream `GuiCoalGenerator`,
  `CrusherScreen`), the Double Crusher, redstone control, item/fluid pipes,
  energy relays/cables (the adjacency link stands in), sounds/particles, the
  crafting chain that makes the two machines craftable
  (`black_quartz`, `restonia_crystal`, `iron_casing`, `basic_coil` are later
  slices), config, JEI/booklet, ores/worldgen, the rest of the machine list
  above.
