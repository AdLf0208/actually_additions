# Actually Additions — a Horizon port

**Actually Additions** is a Minecraft mod. A Minecraft Mod about lots of useful gadgets and things!. This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [Ellpeck/ActuallyAdditions](https://github.com/Ellpeck/ActuallyAdditions) — licence **MIT**.

| | |
|---|---|
| Upstream mod | Actually Additions ([source](https://github.com/Ellpeck/ActuallyAdditions)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `actuallyadditions.hmod` (install it with the Horizon launcher) |
| Licence | **MIT** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

### What the slice does

| | Upstream | Here |
|---|---|---|
| Generator buffer | `CustomEnergyStorage(60000, 0, 80)` | a 60,000 FE block energy capability that takes no inserts and gives 80 FE a call, every face |
| Generator output | 20 FE/t while burning | the same; any fuel the game's cooking-fuel table knows |
| Crusher buffer | `CustomEnergyStorage(60000, 100, 0)` | a 60,000 FE capability that takes 100 FE a call and gives nothing |
| Crusher cost | 40 FE/t, 100 ticks | the same, reading the jar's own `actuallyadditions:crushing` recipes |
| Crusher outputs | first result + second at `chance` | the same, with `Level.random` |
| Energy link | Energy Laser Relays | a fuelled generator pushes its FE to the crushers beside it (a relay is a later slice) |
| Interaction | a container GUI | a right click inserts fuel/a recipe input; a `/actuallyadditions info <pos>` readout for the harness |

Not ported, and recorded as gaps in [`notes.md`](notes.md): the GUI, the Double Crusher and the
other ~45 machines, redstone control, relays/cables, the crafting chain, worldgen, the booklet,
`lit`/comparator/particles, and keeping the FE on a broken machine.

## Not yet ported

- **No GUI/screen.** Upstream opens a container screen; this slice inserts by
- **`lit` is never set.** Upstream sets the crusher's `lit` (light 12) and the
- **Breaking a machine loses its FE.** Upstream's loot copies the
- **The two machine recipes ship but do not craft yet.** They need
- **2 of the 49 crushing recipes are skipped**: `black_quartz_ore` and `rice`
- **The bonus roll is unit-tested, not asserted in-game**: the 50 % gravel
- **No comparator output.** `comparator_strength` is computed (and printed), but
- **No client sync** of energy/progress (`block_entity_update_tag` is not

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `actuallyadditions.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Actually Additions was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **MIT**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/Ellpeck/ActuallyAdditions

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run actuallyadditions` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/actuallyadditions/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).
