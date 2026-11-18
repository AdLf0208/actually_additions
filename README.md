# Actually Additions → Horizon (slice 1)

The **Coal Generator** and the **Crusher** of Actually Additions 1.3.26
(`Ellpeck/ActuallyAdditions`, **MIT**) as one flat SDK package (mod API `0.2`, version `0.2.0`),
built by the launcher against Horizon `0b14f8acfd97fa2c750e42795249dcc981178ca4` and mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` for Minecraft 26.3.

- [`FINDINGS.md`](FINDINGS.md) — upstream behaviour read from the source, the slice boundary and
  the mod's remaining machine list.
- [`notes.md`](notes.md) — scope, the retired-hook → SDK mapping, verification, deviations, gaps
  and every migration trap.
- `horizon-mod.toml` — the one manifest and identity (`capabilities = ["registries"]`, `[native]`
  pins); `Cargo.toml` + `src/lib.rs` — the one `impl mod_api::Hooks`; `src/support.rs` — the glue
  (the two block-entity Parts, the container and energy declarations, the clicks, the command);
  `src/runtime.rs` — the pure, unit-tested machine logic, byte-identical to the retired bundle's.
- `assets/`, `data/` — the carried content, reproduced by `tools/assemble_content.py` from the raw
  carry of the ATM10 jar (`ports/_shared/carry-work/actuallyadditions/carry/`, Modrinth SHA-1
  `bd1826f117065dc3d73f0a7197091a4c37829a06`) and patched as [`notes.md`](notes.md) records;
  `tools/stamp_license.py` copies the licence and notice into `data/actuallyadditions/license/`.

## What the slice does

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

## Quick checks

```sh
cargo test --all-targets                                   # 26 tests: 15 runtime, 11 glue
cargo clippy --all-targets -- -D warnings                   # 0 warnings
cargo fmt --check                                           # not --all: that checks the fetched SDK
rm -f Cargo.lock && cargo horizon-mod build                 # target/horizon-mod/actuallyadditions.hmod
cargo horizon-mod check actuallyadditions.hmod              # the registry's package check
cargo horizon-mod fits actuallyadditions.hmod --build nightly
GAME=<launcher-built horizon-client> tools/e2e.sh           # SELFTEST=1 must fail
```

`GAME` comes from `horizon-launcher native-build .`, which is **not installed here**, so no 0.2.0
in-game run exists; the 0.1.0 runs in `ports/_shared/evidence/actuallyadditions/` are the
behaviour's evidence for a `src/runtime.rs` that did not change. Local-only until the maintainer
approves publishing (ARCHITECTURE.md §8).
