# Actually Additions → Horizon (slices 1–10)

The **Coal Generator**, the **Crusher** and the **Atomic Reconstructor** of Actually Additions
1.3.26 (`Ellpeck/ActuallyAdditions`, **MIT**) as one flat SDK package (mod API `0.2`, version
`0.2.11`), built by the launcher against Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` and
mixins `e59da9094f0c2fdda6c627fe9eff22dec6a906f0` for Minecraft 26.3.

- [`FINDINGS.md`](FINDINGS.md) — upstream behaviour read from the source, the slice boundary and
  the mod's remaining machine list.
- [`notes.md`](notes.md) — scope, the retired-hook → SDK mapping, slices 2–5, verification,
  deviations, gaps and every migration/verification trap.
- [`VALIDATION.md`](VALIDATION.md) — the ladder and the in-game evidence for each version.
- `horizon-mod.toml` — the one manifest and identity (`capabilities = ["registries"]`, `[native]`
  pins); `Cargo.toml` + `src/lib.rs` — the one `impl mod_api::Hooks`; `src/support.rs` — the glue
  (the three block-entity Parts, the container and energy declarations, the clicks, the beam, the
  commands); `src/runtime.rs` — the pure, unit-tested machine logic.
- `assets/`, `data/` — the carried content, reproduced by `tools/assemble_content.py` from the raw
  carry of the ATM10 jar (`ports/_shared/carry-work/actuallyadditions/carry/`, Modrinth SHA-1
  `bd1826f117065dc3d73f0a7197091a4c37829a06`) and patched as [`notes.md`](notes.md) records;
  `tools/stamp_license.py` copies the licence and notice into `data/actuallyadditions/license/`;
  `tools/check_recipe_keys.py` fails a tree whose carried recipe key (or a `laser/` result) names an
  item or tag it cannot resolve; `tools/craft_check.py` drives the in-game crafting-table leg.

## What the slices do

| | Upstream | Here |
|---|---|---|
| Generator buffer | `CustomEnergyStorage(60000, 0, 80)` | a 60,000 FE block energy capability that takes no inserts and gives 80 FE a call, every face |
| Generator output | 20 FE/t while burning | the same; any fuel the game's cooking-fuel table knows |
| Crusher buffer | `CustomEnergyStorage(60000, 100, 0)` | a 60,000 FE capability that takes 100 FE a call and gives nothing |
| Crusher cost | 40 FE/t, 100 ticks | the same, reading the jar's own `actuallyadditions:crushing` recipes |
| Crusher outputs | first result + second at `chance` | the same, with `Level.random` |
| Energy link | Energy Laser Relays | a fuelled generator pushes its FE to the machines beside it (a relay is a later slice) |
| Interaction | a container GUI | a right click inserts fuel/a recipe input; a `/actuallyadditions info <pos>` readout for the harness |
| Break a machine | loot copies the `energy` component | the saved compound rides `minecraft:block_entity_data` (an allowlist: FE, burn, progress, cycle; never the inventory) and is clamped on placement |
| Craft a machine | `actuallyadditions:iron_casing` + `basic_coil` + `c:cobblestones` | the same: the Iron Casing block, the Basic Coil item and the `c:cobblestones` tag ship, and the Coal Generator's recipe crafts in a vanilla table |
| Black Quartz | an ore (worldgen) smelted/blasted/crushed into the gem | the ore block, the gem, the loot table (silk touch → the ore) and all three recipes ship; the ore does **not generate** at this pin (`blocked(configured-feature-not-registered)`, a platform gap the e2e asserts) |
| Iron Casing | `WSW / SQS / WSW` from `#c:ingots/iron`, `#c:rods/wooden`, black quartz | the recipe and both convention tags ship and craft |
| Atomic Reconstructor buffer | `CustomEnergyStorage(300000, ceil(300000·0.016666), 0)` | a 300,000 CF capability that takes 5,000 CF a call and gives nothing |
| Atomic Reconstructor shot | `ENERGY_USE = 1000` CF + the recipe's own energy, one attempt a 100-tick `currentTime` cycle, redstone stops it | the same |
| Atomic Reconstructor beam | the first block within the default lens's 10 blocks, converting the 3×3 plane it hits, then stopping | the same, plus a `/actuallyadditions info` line that names the block it sights and what it becomes |
| Atomic Reconstructor results | a `laser/` recipe's block result is placed, an item result is dropped | the same (redstone dust → Restonia Crystal, sands → soul sand, red mushroom → nether wart ship) |
| The crystal chain | `restonia_crystal` from the beam, then the Crusher's recipe | the crystal ships, the Crusher's own recipe now crafts, and `tools/recipe-blockers.json` is empty |
| The beam's item half | `invokeConversionLens` also converts the dropped items in the box from the machine to the block it hit, as many as the buffer pays for, marking each result `aa_cnv` | the same: a dropped redstone becomes a Restonia Crystal (count conserved), one entity per beam step, the remainder of a stack stays convertible, and all six facings work (upstream's box is inverted on three of them) |
| A conversion's order | the result is spawned first, then the source is removed with `removeBlock`'s answer ignored; the energy is charged anyway | the source goes first and its answer is checked, the result arrives only if it did (or the source is put back), and the recipe's energy is charged only when the conversion happened — in the block half and the item half |
| Redstone mode | `isPulseMode`: a rising edge of `getBestNeighborSignal` fires one shot, and the cycle never free-runs; a click with the config's `redstoneConfigurator` (default a redstone torch) toggles it, and the mode travels on the broken item | the same: a `pulse on/off` field in the `/actuallyadditions info` line, one shot per rising edge, the cycle frozen in pulse mode, the flag in the drop's payload |
| Lens slot | `getLens()` takes an `ILensItem` from the reconstructor's one slot; an occupied slot refuses a second lens, and the four lenses form a 5,000 CF laser ring | the four ring items, their recipe and the `c:glass_blocks` tag ship; a right click fills the slot (the `info` line names it), a non-lens and a second lens are refused, and a dropped lens converts to the next one |
| Miner lens | `LensMining.invoke` spends 60,000 CF to swap the sighted `stone_ore_replaceables` block for a weighted-random ore from `actuallyadditions:mining_lens`, then stops the beam | the miner item, the 20 top-level `mining_lens` recipes and their tags ship; with it installed a 61,000 CF shot replaces the sighted stone (the default lens keeps it and spends only the gate). Its own craft needs crystals this package lacks, so the in-game rig **gives** the item |

Not ported, and recorded as gaps in [`notes.md`](notes.md): the GUI
(`blocked(no-single-player-mod-screen)`), the Double Crusher and the other ~44 machines, the rest of
redstone control (only the reconstructor toggles; the generator and the crusher do not), a
relay/cable, the Empowerer and the empowered crystals, the killer/detonator/disenchanting lenses'
own beam effects (distinct `invoke` rule paths — damage, explosion and item-enchantment edits — each
needs its own slice; their surfaces exist at this pin), the ore's generation
(`blocked(configured-feature-not-registered)`), the booklet,
`lit`/particles.

## Quick checks

```sh
cargo test --offline                                       # 64 tests: 45 runtime (19 + 4 json + 22 reconstructor incl. the miner lens), 19 glue
cargo clippy --all-targets --offline -- -D warnings         # 0 warnings
cargo fmt --check                                          # not --all: that checks the fetched SDK
rm -f Cargo.lock && cargo horizon-mod build                # no lock in the tree: the registry packs none (R9)
cargo horizon-mod check actuallyadditions.hmod              # the registry's package check
cargo horizon-mod fits actuallyadditions.hmod --build 0a875da
cargo horizon-mod fits actuallyadditions.hmod --build 0b14f8a   # a different build: not a tautology
python3 tools/check_recipe_keys.py                          # every recipe key resolves, or is a recorded blocker
ports/tools/launcher-game.sh build actuallyadditions        # the launcher compiles the package into a game
eval "$(ports/tools/launcher-game.sh env actuallyadditions)" && tools/e2e.sh
                # SELFTEST=1, drops, ore, laser, item, pulse, lens, lens-effect and NEGATIVE=1 must fail
```

Local-only until the maintainer approves publishing (ARCHITECTURE.md §8); the artifact goes to a
release of the author's repository and a maintainer stages it (`notes.md`, "Publication route").
