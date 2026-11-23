# Actually Additions → Horizon (slices 1–4)

The **Coal Generator** and the **Crusher** of Actually Additions 1.3.26
(`Ellpeck/ActuallyAdditions`, **MIT**) as one flat SDK package (mod API `0.2`, version `0.2.5`),
built by the launcher against Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` and mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` for Minecraft 26.3.

- [`FINDINGS.md`](FINDINGS.md) — upstream behaviour read from the source, the slice boundary and
  the mod's remaining machine list.
- [`notes.md`](notes.md) — scope, the retired-hook → SDK mapping, slices 2–4, verification,
  deviations, gaps and every migration/verification trap.
- [`VALIDATION.md`](VALIDATION.md) — the ladder and the in-game evidence for each version.
- `horizon-mod.toml` — the one manifest and identity (`capabilities = ["registries"]`, `[native]`
  pins); `Cargo.toml` + `src/lib.rs` — the one `impl mod_api::Hooks`; `src/support.rs` — the glue
  (the two block-entity Parts, the container and energy declarations, the clicks, the command);
  `src/runtime.rs` — the pure, unit-tested machine logic.
- `assets/`, `data/` — the carried content, reproduced by `tools/assemble_content.py` from the raw
  carry of the ATM10 jar (`ports/_shared/carry-work/actuallyadditions/carry/`, Modrinth SHA-1
  `bd1826f117065dc3d73f0a7197091a4c37829a06`) and patched as [`notes.md`](notes.md) records;
  `tools/stamp_license.py` copies the licence and notice into `data/actuallyadditions/license/`;
  `tools/check_recipe_keys.py` fails a tree whose carried recipe key names an item or tag it cannot
  resolve; `tools/craft_check.py` drives the in-game crafting-table leg.

## What the slices do

| | Upstream | Here |
|---|---|---|
| Generator buffer | `CustomEnergyStorage(60000, 0, 80)` | a 60,000 FE block energy capability that takes no inserts and gives 80 FE a call, every face |
| Generator output | 20 FE/t while burning | the same; any fuel the game's cooking-fuel table knows |
| Crusher buffer | `CustomEnergyStorage(60000, 100, 0)` | a 60,000 FE capability that takes 100 FE a call and gives nothing |
| Crusher cost | 40 FE/t, 100 ticks | the same, reading the jar's own `actuallyadditions:crushing` recipes |
| Crusher outputs | first result + second at `chance` | the same, with `Level.random` |
| Energy link | Energy Laser Relays | a fuelled generator pushes its FE to the crushers beside it (a relay is a later slice) |
| Interaction | a container GUI | a right click inserts fuel/a recipe input; a `/actuallyadditions info <pos>` readout for the harness |
| Break a machine | loot copies the `energy` component | the saved compound rides `minecraft:block_entity_data` (an allowlist: FE, burn, progress; never the inventory) and is clamped on placement |
| Craft a machine | `actuallyadditions:iron_casing` + `basic_coil` + `c:cobblestones` | the same: the Iron Casing block, the Basic Coil item and the `c:cobblestones` tag ship, and the Coal Generator's recipe crafts in a vanilla table |
| Black Quartz | an ore (worldgen) smelted/blasted/crushed into the gem | the ore block, the gem, the loot table (silk touch → the ore) and all three recipes ship; the ore does **not generate** at this pin (`blocked(configured-feature-not-registered)`, a platform gap the e2e asserts) |
| Iron Casing | `WSW / SQS / WSW` from `#c:ingots/iron`, `#c:rods/wooden`, black quartz | the recipe and both convention tags ship and craft |

Not ported, and recorded as gaps in [`notes.md`](notes.md): the GUI
(`blocked(no-single-player-mod-screen)`), the Double Crusher and the other ~45 machines, redstone
control, relays/cables, the rest of the crafting chain (the Crusher's recipe waits on
`restonia_crystal`, which the Atomic Reconstructor's laser makes — `blocked(restonia_crystal_source)`),
the ore's generation (`blocked(configured-feature-not-registered)`: a content package's configured
features do not reach the feature registry at this pin), the booklet, `lit`/comparator/particles.

## Quick checks

```sh
cargo test --offline                                       # 34 tests: 20 runtime, 14 glue
cargo clippy --all-targets --offline -- -D warnings         # 0 warnings
cargo fmt --check                                          # not --all: that checks the fetched SDK
cargo horizon-mod build                                    # keep Cargo.lock in the tree (declares serde_json)
cargo horizon-mod check actuallyadditions.hmod              # the registry's package check
cargo horizon-mod fits actuallyadditions.hmod --build 0a875da
cargo horizon-mod fits actuallyadditions.hmod --build 0b14f8a   # a different build: not a tautology
python3 tools/check_recipe_keys.py                          # every recipe key resolves, or is a recorded blocker
ports/tools/launcher-game.sh build actuallyadditions        # the launcher compiles the package into a game
eval "$(ports/tools/launcher-game.sh env actuallyadditions)" && tools/e2e.sh
                                                            # SELFTEST=1, SELFTEST=drops, SELFTEST=ore and NEGATIVE=1 must fail
```

Local-only until the maintainer approves publishing (ARCHITECTURE.md §8); the artifact goes to a
release of the author's repository and a maintainer stages it (`notes.md`, "Publication route").
