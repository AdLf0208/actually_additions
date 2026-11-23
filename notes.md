# Actually Additions → Horizon — port notes

Ported from **Actually Additions 1.3.26** (`Ellpeck/ActuallyAdditions`, **MIT**),
Minecraft Java 1.21.1 NeoForge, from the ATM10 jar
`actuallyadditions-1.3.26+mc1.21.1.jar` (Modrinth SHA-1
`bd1826f117065dc3d73f0a7197091a4c37829a06`; provenance:
`ports/_shared/carry-work/actuallyadditions/SOURCE.md`). Upstream source read
for behaviour only (commit `cd9d9c63…`), this is a clean-room Rust rewrite.

**Licence:** MIT → **rank 0 (permissive)**. Local-only until the maintainer
approves publishing (ARCHITECTURE.md §8); MIT allows derivatives, approval is
still required. Ported now because it is the next P0 `content/machines` row
with no mod dependency and a permissive licence.

**Class + tier:** `content` · **machines** (`ports/ledger.csv`). Approach per the
pin's `docs/modpacks.md` ("What packs need and what runs today"): block entities
with ticks, containers, a capability (energy), a custom recipe type and a
command — not a data-only carry. Details: [`FINDINGS.md`](FINDINGS.md).

## Slice 1 scope

The **Coal Generator** and the **Crusher** only:

- their blocks/items, loot tables, names, models/textures (carried from the jar),
  the two machine crafting recipes, 49 `actuallyadditions:crushing` recipes and
  the two advancements;
- a block entity per machine (API 15/17), a container (API 16), an FE buffer
  (API 142), the generator's tick and the crusher's recipe/energy tick;
- the generator→adjacent-crusher energy link, a right-click insert/refusal
  surface (no GUI in this slice) and `/actuallyadditions info <x> <y> <z>`.

Everything else in the mod — Double Crusher, the other ~45 machines, the GUI,
redstone control, energy relays/cables, the crafting chain, worldgen, booklet —
is a recorded gap below, not a silent claim.

## Behaviour read from upstream

| Area | Upstream | This port |
|---|---|---|
| generator buffer | `CustomEnergyStorage(60000, 0, 80)` | API 142 buffer `energy`, capacity 60,000, insert 0, extract 80, all faces |
| generator output | 20 FE/t while burning | same |
| fuel | `stack.getBurnTime(RecipeType.SMELTING)` | the engine's `minecraft:cooking_fuel` via `Providers::burn_time` (so modded fuels work) |
| refuel gate | not powered, burn 0, buffer not full | same (`runtime::Generator::wants_fuel`) |
| fuel consumption | one item; containers return (lava bucket → bucket) | same (`ItemInfo::remainder`) |
| crusher buffer | `CustomEnergyStorage(60000, 100, 0)` | API 142 buffer, insert 100, extract 0 |
| crusher cost | 40 FE/t while crushing | same |
| duration | 100 ticks | same |
| outputs | first result + second at `roll <= chance` | same, `level.random.nextFloat()` |
| output room | same item with room in slot 1, and slot 2 when there is a bonus | same (`runtime::can_crush`) |
| slots | generator 1 (fuel); crusher 3 (input, out1, out2) | same; automation inputs `[0]`, crusher outputs `[1,2]` |
| comparator | `floor(energy / 60000 * 15)` | in the info line; **not** exposed to vanilla comparators (gap) |
| `lit` | crusher `lit` = energy ≥ 40, light 12 | not set (gap) |
| break | item carries the `actuallyadditions:energy` component | not carried (gap): a broken machine loses its FE |

## Hooks

| Hook (API) | Helper | What it does |
|---|---|---|
| `block_entity` (15) | `block_entity.rs` | Both machines get a block entity. |
| `block_entity_ticks` (15) | `ticks.rs` | Both tick on the server. |
| `block_entity_container` (16) | `container.rs` | 1 fuel slot / 3 crusher slots, all faces. |
| `block_entity_energy` (142) | `energy.rs` | FE buffers (`Capabilities.Energy.BLOCK`). |
| `block_entity_tick` (17) | `tick.rs` | Generator burn/FE, crusher recipe/energy/progress. |
| `level_tick_post` (23) | `level_tick_post.rs` | Move queued generator FE into adjacent crushers (`native_move_energy`). |
| `right_click_block` (21) | `right_click.rs` | Insert fuel/recipe input; claim the click (no GUI); refuse non-fuel/non-recipe. |
| `register_commands` (8) | `register.rs` | `/actuallyadditions info`. |
| `perform_command` (8) | `perform.rs` | The command body. |
| `world_lifecycle` (v1) | `world.rs` | Drop the parsed recipe cache and the push queue per world. |

**The pin has an FE hook.** The brief's "no FE hook exists" was true at older
pins; at `1d63e0a5` **API 142** declares a `Capabilities.Energy.BLOCK` buffer
whose amount is the int `energy` in the block entity's saved compound, with
`native_energy`, `native_energy_insert/extract` and `native_move_energy`
(`crates/horizon-client/src/game/machines/native_energy.rs`). Using it keeps the
energy in the BE's NBT as the brief says, while making the buffers real FE for
other mods. Cross-block exchange stays inside this mod (a generator→crusher
link), per ARCHITECTURE.md §3.

`native_energy_at` refuses a block entity that is ticking at that moment, so the
generator queues its adjacent crushers and the transfer runs at
`level_tick_post`, where both are in the world. There is no Energy Laser Relay in
slice 1: adjacency is the documented stand-in for a relay.

## Command (harness addition)

`/actuallyadditions info <x> <y> <z>` (no permission level) prints, for the
machine at that position:

```
Coal Generator at 0,100,0: 1940/60000 FE (comparator 0, burning 1503/1600 ticks, t=324)
Crusher at 1,100,0: 3600/60000 FE (comparator 0, progress 0/100, input empty, crushing into nothing, bonus none, t=607)
```

It is a **harness/observability addition**, not upstream gameplay: there is no
FE hook readout for players and no GUI in this slice; the thread needs a way to
see stored FE, burn and progress. It is recorded here so nobody mistakes it for
an upstream command. (`t=` is the world game time, added so the e2e can tell a
fresh reply from a stale one.)

## Verification

Pin **`1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9`**, mixins
**`5a64af938ec86b00d53d16a408aabc0038fb3e57`** (schema 6); checkouts
`ports/_shared/pins/horizon-1d63e0a` / `horizon-mixins-5a64af9`. Every build ran
through `ports/tools/build-slot.sh` with `CARGO_INCREMENTAL=0 HORIZON_MIXINS=…`,
never a bare cargo; the e2e ran with the pin-matched shared `horizon-ctl`
(`ports/_shared/bin/horizon-1d63e0a5/horizon-ctl`) and the port's fast game.

### Ladder

| Step | Command | Result |
|---|---|---|
| format | `cargo fmt --all` + `rustfmt` on the helpers | clean |
| lints | `cargo clippy --all-targets --locked --offline -- -D warnings` | exit 0, 0 warnings |
| runtime tests | `cargo test --locked --offline` | **15 passed**, 0 failed (TDD: 14 red first, then 15 green incl. the ingredient upgrade) |
| staged check | `python3 tools/horizon.py check --horizon …/pins/horizon-1d63e0a` | `cargo_exit: 0`, **0 warnings** (`target/horizon-check.log`) |
| embedded tests | `python3 tools/horizon.py test …` | `15 passed; 0 failed; 1240 filtered out` (`target/horizon-test.log`) |
| fast build | `python3 tools/horizon.py build …` | `cargo_exit: 0`, binary in the slot target |
| e2e | `build-slot.sh e2e … -- tools/e2e.sh` | **PASS**, `EXIT:0` |
| fail-capability | `SELFTEST=1 tools/e2e.sh` | **exit 1** at the generator assertion |
| content `.hmod` | `horizon-mod build` + `check` | **62,930 B**, SHA-256 `8435a3da…3ee7`, **80 files**, content only, API 0.2 |
| native `.hnmod` | `python3 tools/package.py` | **16,463 B**, SHA-256 `a7b7c9b8…dcb14` |
| load-check | `tools/hmod-load.sh` (shared 1d63e0a5 game) | **PASS** with `--dev-mod <hmod>`; the same ids are refused without it (block stays bedrock) |

Evidence: `ports/_shared/evidence/actuallyadditions/{e2e,e2e-selftest,hmod-load,horizon-check,horizon-test,horizon-build}.log`.

### In-game scenario (quoted from `e2e.log`)

```
  arena: y=100.0 floor(0,99,3)=minecraft:stone feet(0,100,3)=minecraft:air
  block(0,100,0) = actuallyadditions:coal_generator
  block(4,100,0) = actuallyadditions:crusher
  after 40 ticks: Coal Generator at 0,100,0: 0/60000 FE (comparator 0, burning 0/0 ticks, t=198)
  click: {"ok":true,"block":"actuallyadditions:coal_generator","inventory_change":{}}
  after the click: Coal Generator at 0,100,0: 920/60000 FE (comparator 0, burning 1554/1600 ticks, t=273)
  has(0,100,0) minecraft:coal x4: ok
  generator alone: 1940 FE, burn 1503
  far crusher: no output
  started: Crusher at 1,100,0: 1640/60000 FE (comparator 0, progress 9/100, input minecraft:coal_ore x1, crushing into minecraft:coal x3, bonus none, t=488)
  finished: Crusher at 1,100,0: 3600/60000 FE (comparator 0, progress 0/100, input empty, crushing into nothing, bonus none, t=607)
  has(1,100,0) minecraft:coal x3: ok
  stone refused by both machines (no item taken, no block placed)
  after relaunch: Coal Generator at 0,100,0: 0/60000 FE (comparator 0, burning 1072/1600 ticks, t=756)
  crusher after relaunch: Crusher at 1,100,0: 6740/60000 FE (comparator 1, progress 0/100, input empty, crushing into nothing, bonus none, t=765)
PASS: a fuelled generator made FE, the adjacent crusher took it and crushed coal ore into 3 coal, an unfuelled generator made nothing, a crusher without FE crushed nothing, stone was refused by both, and the machines survived a relaunch
EXIT:0
```

Controls in the run: an unfuelled generator stores 0 FE for 40 ticks; a crusher
with no source stays at 0 FE and crushes nothing (its coal ore is untouched); a
stone click is refused by both machines and places no block; the coal stack
shrinks by one when the burn starts. `SELFTEST=1` flips the generator's energy
expectation and the run fails at it (`FAIL: SELFTEST flipped: the generator made
1920 FE, not 0`, exit 1), so the scenario can fail.

## Deviations and gaps (slice 1)

1. **No GUI/screen.** Upstream opens a container screen; this slice inserts by
   right-click or automation and reads state through `/actuallyadditions info`.
   The GUI, its textures and shift-click routing are deferred.
2. **`lit` is never set.** Upstream sets the crusher's `lit` (light 12) and the
   generator's smoke/`CRIT` random-tick particles; this slice writes no block
   state (the carried `lit=false` model is what shows). The furnace template's
   `lit` light 13 would apply if it were set.
3. ~~**Breaking a machine loses its FE.**~~ **Closed by slice 2 (0.2.2)**: a broken machine's
   saved compound travels as vanilla `minecraft:block_entity_data` and is clamped back when the
   item is placed again (see "Slice 2" below).
4. **The two machine recipes ship but do not craft yet.** They need
   `black_quartz`, `restonia_crystal`, `iron_casing` and `basic_coil` (later
   slices); the `c:` tags those recipes use are not in 26.3 either.
5. **2 of the 49 crushing recipes are skipped**: `black_quartz_ore` and `rice`
   name Actually Additions items not in this slice (one debug log line per
   cache rebuild).
6. **The bonus roll is unit-tested, not asserted in-game**: the 50 % gravel
   bonus is random; the run proves the guaranteed output (coal ore → 3 coal).
7. **No comparator output.** `comparator_strength` is computed (and printed), but
   no `has_analog_output` hook is declared, so a vanilla comparator beside a
   machine reads its container fullness, not its FE.
8. **No client sync** of energy/progress (`block_entity_update_tag` is not
   used); there is no GUI to show them anyway.
9. **No sounds/particles/animations** beyond the carried block models'
   `.mcmeta` animations (`crusher_rotation_animation`, generator fire).
10. **The energy link is adjacency, not a relay.** Upstream machines move FE
    through Energy Laser Relays; slice 1 moves generator→crusher at
    `level_tick_post`, 80 FE/call from the generator, 100 FE/call into the
    crusher (the buffer limits).
11. **Fuel-slot automation is insert-only** (`outputs: []`); upstream lets
    automation take a non-fuel item back out.
12. **No Double Crusher, auto-split, redstone gating, config, JEI/booklet,
    worldgen, or any of the other machines** listed in `FINDINGS.md`.
13. `ctl container` reports mod containers and inserts into their `inputs`
    slots; on a block with no `inputs` (none here) it would refuse. A hopper path
    was not exercised in-game in this slice.

## Harness findings (for the next machine port)

- `ctl messages` lists chat **newest first**: the newest reply is `head -1`, not
  `tail -1` (a `tail -1` picked the previous reply for several runs).
- Chat command replies arrived ~2 s (≈40–60 ticks) after the send in this
  environment: poll for a *new, different* line (the `t=` field makes each reply
  unique) instead of waiting a fixed 4 ticks.
- The action-bar field (`messages.action_bar`) was `null` for the refusal
  messages in a headless run; the refusals are proven by state (no item taken, no
  block placed), not by the message.
- An **Overworld arena at y=100** (`ctl tp` + `fill`) is reliable; the earlier
  `execute in minecraft:the_end run tp @s` left the player in the void when the
  End chunk was not loaded yet.
- The shared build-slot target holds the **last port's** game binary: a `run`
  without a build can execute another port's game. Always run the e2e through
  `build-slot.sh e2e` (or build + e2e in one lease); the run above checked
  `strings <game> | grep 'actuallyadditions info'` = 1 before launching.
- `ctl container X Y Z` lists slots and inserts into the container's `inputs`;
  it needs the block to be a registered mod container at that state.
- `ctl chat "/actuallyadditions …"` is required (`ctl command` runs the console
  path and bypasses `perform_command`).

## Artifact rebuild at the campaign pin (2026-11-09)

**Mode B** — the pin was already the campaign pin (`1d63e0a5` / mixins
`5a64af93`); the delivered packages were older than the sources and the port
had no `.hnmod`, so a port with 10 injections had no valid native artifact.
Rebuilt both from the tree in one build-slot lease, then re-ran the ladder and
the e2e.

| Step | Command (through `ports/tools/build-slot.sh`) | Result |
|---|---|---|
| fmt | `cargo fmt --all -- --check` | exit 0 |
| clippy | `cargo clippy --all-targets --locked --offline -- -D warnings` | exit 0, **0 warnings** |
| runtime tests | `cargo test --locked --offline` | **15 passed**, 0 failed |
| stage | `python3 tools/horizon.py stage` | exit 0, `stage_changed: true`, revision `1d63e0a5a37a` |
| staged check | `python3 tools/horizon.py check` | `cargo_exit: 0`, **0 warnings** |
| embedded tests | `python3 tools/horizon.py test` | `cargo_exit: 0`, **15 passed / 0 failed / 1240 filtered** (`game::actuallyadditions::`) |
| package | `tools/package.sh` | both artifacts built (hashes below) |
| e2e default | `build-slot.sh e2e … -- tools/e2e.sh` | `PASS` + `EXIT:0` (see below) |
| e2e selftest | `SELFTEST=1` | `FAIL: SELFTEST flipped: the generator made 1920 FE, not 0` + `EXIT:1` |

Artifacts (delivered in the port, never `target/`):

| File | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `content/actuallyadditions.hmod` | 62,930 B | `8435a3da0638c1a5b8818f82dbe2dfef51bae3c185759aff332776753ee762e7` | 80 |
| `actuallyadditions.hnmod` | 16,463 B | `a7b7c9b815a0607a5fad6bfed02fbc36bb2822779296e41c73f618817e6dcb14` | 14 |

The e2e (Overworld arena, y=100, `--dev-mod content`, shared `1d63e0a5`
`horizon-ctl`, the port's own fast game) printed: an unfuelled generator stays
`0/60000 FE`; a coal right-click starts the burn (`1555/1600` ticks) and FE
reaches `1920`; an adjacent crusher takes the FE and turns `coal_ore ×1` into
`coal ×3`; a crusher with no source stays at `0 FE` and crushes nothing; stone
is refused by both machines without taking an item or placing a block; the
generator's burn and the crusher's FE/output survive `save` + quit + relaunch.
The selftest asserts the false `0 FE` expectation and exits 1, so the scenario
can fail.

`python3 ports/tools/check-e2e-logs.py actuallyadditions --strict` →
`ok e2e-selftest.log FAIL + EXIT:1`, `ok e2e.log PASS + EXIT:0`, rc 0.

Skills: superpowers/using-superpowers, brainstorming, writing-plans, test-driven-development, systematic-debugging, verification-before-completion; BeautifulRust/rust-best-practices

## Content embedded in the bundle; re-verified in game (2026-11-10)

**Beat: one file per project.** The registry takes one `file` per version, so a
port that ships a `.hmod` *and* a `.hnmod` cannot be listed faithfully. This port
now follows the AE2 pattern proved on `charginggadgets` (PR #526): the built
content mod travels **inside** the bundle at
`mixins/actuallyadditions/data/actuallyadditions-content.hmod`, and `mixins/actuallyadditions/embedded_content.rs`
compiles it in with `horizon_client::native_data!` and injects it at
`content_root` (`target = "horizon_client::game::mods::content_root"`,
`kind = "HEAD"`, `cancellable = true`). The helper writes the file to
`.horizon-cache/actuallyadditions-embedded-content.hmod` once, appends it to the dev-mod list
and returns the merged root; the recursive call stops at its own
`dev.contains(&file)` guard, so the vanilla body runs once. The `.hmod` stays in
`content/` as the build input; `tools/package.py` refuses a stale copy in `data/`.

**Proved with no `--dev-mod`:** the e2e launches the game *without* passing the
content folder, so every content id and every behaviour it asserts comes from the
bundle. `EMBEDDED=1` is the flag; the launch line passes an empty dev-mod list.

| Artifact | Size | SHA-256 | Entries |
|---|---:|---|---:|
| `content/actuallyadditions.hmod` (input) | 62,930 B | `8435a3da0638c1a5b8818f82dbe2dfef51bae3c185759aff332776753ee762e7` | 80 |
| `actuallyadditions.hnmod` (deliverable, embeds it) | 67,354 B | `5556eb05a06e27ad5770bc6464c5424536d6da0da5cd147fedaf2a5177e215d8` | 16 |

E2E (one lease each, `CARGO_INCREMENTAL=0`, shared `1d63e0a5` `horizon-ctl`, the
port's own fast game): default `PASS` + `EXIT:0`; `SELFTEST=1` `FAIL` + `EXIT:1`.

`python3 ports/tools/check-e2e-logs.py actuallyadditions --strict` → every log carries its
own `PASS`/`FAIL` + `EXIT:` pair. `python3 ports/tools/upstream_ready.py actuallyadditions` →
**READY (exit 0)**.

## Reviewer repairs (2026-11-11) — PR review items and what changed


Each item below is quoted from `ports/_shared/horizon-mods/reviews/pr-*-actuallyadditions.md` (the review is the specification), with what this repair did about it.

- **Reviewer:** registry artifact delivery
  **Repair:** **Staging (orchestrator, not ours)**: the artifact is not in registry release/staging as `<sha256>.<ext>`; the orchestrator answers it with `horizon-mods#686` (no write access to the registry's releases). Every repackaged artifact below has a fresh sha256 for that re-push, and the author release must be re-uploaded from the port repository.
- **Reviewer:** licence notice
  **Repair:** `LICENSE` + `LICENSE-NOTICE.md` in the `.hnmod`, `data/actuallyadditions/license/` in the carried `.hmod`.

Skills: superpowers/using-superpowers,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Migration to the SDK format (0.2.0, 2026-11-18)

Horizon's mod-API merge (#16941, launcher ≥ 0.2.70; PR #17992 cleans up the old files) retired
`.hnmod`: the registry closed this port's former submission **#790** (`actuallyadditions` 0.1.0)
on 2026-11-18 with the format purge. **0.2.0** is the same behaviour republished as one flat SDK
`.hmod`; `src/runtime.rs` and its 15 tests are **byte-identical**. The reference recipes were
`ports/enderstorage/notes.md` and `ports/naturesaura/notes.md` → "Migration to the SDK format"
(block entities, containers, commands) and `ports/mekanismgenerators/src/{lib,heat_generator}.rs`
for a *generator* with a fuel slot, an output-only FE buffer and a `/… info` command at this SDK.

Pins: SDK nightly **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** (2026-11-18, `package_format` 6,
`content_api` "0.2", rust 1.99.1), mixins **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**,
`cargo-horizon-mod` from `horizon-rust/horizon@main`. The pinned SDK is cached in-tree at
`../_shared/sdk/0b14f8a/` and copied into `.horizon/sdk/` (gitignored) for offline builds.

### What moved, and where the retired tree is

The retired layout was **moved** (never copied) into
`ports/_shared/evidence/actuallyadditions/retired-hnmod-0.1.0/` **before the first
`cargo horizon-mod build`** — the tool refuses any root that holds a non-package path
(`unexpected package path: tools/audit/src/main.rs` was the last such refusal in this campaign).
Nothing was deleted: `mixins/`, `actuallyadditions.hnmod`, `compatibility.json`,
`rust-toolchain.toml`, `Cargo.lock`, the repo `AGENTS.md`, `.github/`, the retired `tools/`
(`horizon.py`, `package.py`, `package.sh`, `test_stage.py`, `test_template.py`,
`stamp_license.py`, `hmod-load.sh`, `audit/`), and the old `content/` (with its own
`horizon-mod.toml`, `README.md`, built `actuallyadditions.hmod` and `patches/`) are all there.

| 0.1.0 path | Now | Evidence |
|---|---|---|
| `mixins/actuallyadditions/runtime.rs` | `src/runtime.rs`, **copied with `cp`, `cmp`-checked** | `retired-hnmod-0.1.0/mixins/actuallyadditions/runtime.rs` |
| `mixins/actuallyadditions/support.rs` (664 lines) + 11 hook helpers | `src/support.rs` (glue, 2 Parts) + `src/lib.rs` (the one `Hooks`) | `retired-hnmod-0.1.0/mixins/actuallyadditions/` |
| `mixins/actuallyadditions/horizon-mixin.toml` (11 `[[injection]]`, 2 `[[module]]`) | no plan: `Registrar` declarations + typed `Hooks`/Part methods | `retired-hnmod-0.1.0/mixins/` |
| `mixins/actuallyadditions/data/actuallyadditions-content.hmod` + `embedded_content.rs` (AE2 pattern) | **gone**: the package carries `assets/` and `data/` itself | `retired-hnmod-0.1.0/mixins/` |
| `content/assets/`, `content/data/` | the package root: `assets/`, `data/` (79 files, diffed byte for byte) | `retired-hnmod-0.1.0/content/` |
| `content/horizon-mod.toml` (id 1.3.26, content only) | merged into the root `horizon-mod.toml` (`version = "0.2.0"`, `[native]`) | `retired-hnmod-0.1.0/content-manifest/` |
| `content/actuallyadditions.hmod` (62,930 B, content carry) | not needed: content and code are one package | `retired-hnmod-0.1.0/content-manifest/` |
| `content/patches/assemble.py` | `tools/assemble_content.py`, writing `assets/` + `data/` at the root | re-run: 79 files unchanged |
| `actuallyadditions.hnmod` (67,354 B, 16 entries, embeds the content) | `actuallyadditions.hmod` (95,503 B, 90 entries, native + content) | `retired-hnmod-0.1.0/` |
| `compatibility.json`, `rust-toolchain.toml` | `[native]` in `horizon-mod.toml`; the launcher's toolchain builds | `retired-hnmod-0.1.0/` |
| `tools/stamp_license.py` (wrote `content/data/…/license/`) | `tools/stamp_license.py`, now writing `data/actuallyadditions/license/` at the root | retained |

**Kept and updated:** `tools/e2e.sh` (now drives a launcher-built game), `tools/assemble_content.py`,
`tools/stamp_license.py`, `FINDINGS.md`, `VALIDATION.md`, `README.md` (rewritten),
`LICENSE`, `LICENSE-NOTICE.md`. **Not kept:** `Cargo.lock` (trap 2).

### File map (0.2.0)

| Path | What it is |
|---|---|
| `horizon-mod.toml` | the only manifest and identity: `id = "actuallyadditions"`, `version = "0.2.0"`, `api = "0.2"`, `side = "both"`, `capabilities = ["registries"]`, `[native]` pinned to `0b14f8a`/`e59da90` |
| `Cargo.toml` | one crate, `edition = "2024"`; `horizon-mod-api` from `.horizon/sdk/` plus `serde_json = "=1.0.151"` (the version the SDK's own lock pins) |
| `src/lib.rs` | the one `#[mod_api::horizon_mod] impl Hooks`: `register`, `register_commands`, `run_mod_command`, `level_tick_post`, `world_lifecycle` — five methods, each one line into `support` |
| `src/support.rs` | all the game glue: the two block-entity Parts (click + tick), the container/energy declarations, the recipe cache, the energy push, the command body. 11 unit tests |
| `src/runtime.rs` | the pure truth (generator, crusher, recipe parser), **byte-identical**, 15 tests |
| `assets/`, `data/` | the carried content (20 + 61 files): blocks, items, models, textures, lang, loot, the two machine recipes, 49 crushing recipes, advancements, the pickaxe tag, the licence copies |
| `tools/` | `assemble_content.py` (the carry and its five patches), `stamp_license.py`, `e2e.sh` |
| `actuallyadditions.hmod` | the deliverable (95,503 B, sha256 `2367bd09…c311`) |

### Helper → hook table

Each former `[[injection]]` helper is now one typed method, a Part method or a `Registrar`
declaration; the helper file itself is gone. A hook with no home is a gap, not a silent deletion.

| 0.1.0 injection (hook, API) | 0.2.0 | Mapping notes |
|---|---|---|
| `embedded-content` (`content_root` HEAD, cancellable) | **none** | one flat `.hmod` carries the content: nothing to write out or append to the dev list |
| `block-entity` (15) | the two **block entity types** in `Hooks::register` (`block_entity_type("coal_generator"/"crusher").blocks(…)`) | the declaration owns the type id; `BlockEntityPart::block_entity` answers the empty starting compound |
| `block-entity-ticks` (15) | `BlockEntityPart::block_entity_ticks` → `event.ticks = true` | asked per block state when a world opens |
| `block-entity-container` (16) | `Registrar::block_container` with `support::generator_container()` / `crusher_container()` | a declaration keyed by the block, not a hook with a shared output: the PR #674 review's hazard cannot recur |
| `block-entity-energy` (142) | `Registrar::block_energy` with `support::generator_battery()` / `crusher_battery()` | the amount is still the int `energy` in the saved compound; the buffers are upstream's `CustomEnergyStorage(60000, 0, 80)` / `(60000, 100, 0)` |
| `block-entity-tick` (17) | `BlockEntityPart::block_entity_tick` on `GeneratorPart` / `CrusherPart` | two Parts, so neither has to check its own id; `event.entity.nbt` (a checked view) and `event.entity.items` are the payload |
| `level-tick-post` (23) | `Hooks::level_tick_post` → `support::on_level_tick_post` | the queue holds `(LevelRef, pos)` instead of `(dimension, pos)`; the move is `fn:move_energy` over `level.capability(&ENERGY, …)`, the counterpart of `native_move_energy` |
| `right-click-block` (21) | `BlockPart::use_item_on` + `use_without_item` on both Parts | the SDK splits the two hands into two methods; `Some(Success)` replaces the 0.1.0 `*canceled = true`. `use_item_on` is the block's own method, i.e. after the engine's sneak/place checks (recorded difference) |
| `register-commands` (8) | `Hooks::register_commands` → `support::declare_commands` | `NativeCommand::new` → `Command::new`, same usage string (`<pos:block_pos>` parses the 0.1.0's three words) |
| `perform-command` (8) | `Hooks::run_mod_command` → `support::run_command` | typed `CommandInvocation` (`BlockPos([i32; 3])`), not a split line; the printed text is byte-identical |
| `world-lifecycle` (v1) | `Hooks::world_lifecycle` → `reset_recipes()` + `clear_push_queue()` | the SDK's `WorldPhase` has only close/fail variants; the 0.1.0 code also reset on every phase, so nothing is lost |
| `[[module]] runtime` / `[[module]] state` | `pub mod runtime;` / `pub mod support;` | same two roles, now ordinary modules of the package crate |

### Behaviour that changed with the format (deliberate, and why)

- **The click is the block's `useItemOn`, not a pre-block `RightClickBlock`.** A sneaking player
  holding a placeable stack now places it instead of having the click claimed by the machine
  (vanilla skips block use for that case); a normal click, a refusal (stone) and the empty-hand
  status are unchanged, and the item is still never placed on the machine.
- **No log line for an unreadable crushing recipe.** The SDK exports no logger and a mod may not
  add a crate, so the one `log::debug!` ("N crushing recipes of M were unreadable") is gone; the
  recipe is still skipped, and the `/actuallyadditions info` line still names what the input slot
  crushes into, so a missing recipe is visible in the readout.
- **The chunk is marked changed only when something moved.** 0.1.0 called `mark_modified`
  unconditionally after `store_*`; the Part answers `BlockEntityTickReply::Unchanged` when the
  state and the fuel slot came out the same, so an idle machine no longer dirties its chunk
  (a performance difference only).
- **The creative hand is the SDK's own rule.** `ItemPlace::extract` gives from a creative player's
  hand without losing any, so the explicit `game.creative` check is gone; the behaviour is the same.
- **`/actuallyadditions info` keeps its exact bytes** (the 0.1.0 e2e assertions still match): the
  generator and crusher lines, the `t=` field and "No Actually Additions machine there." are pinned
  by tests in `src/support.rs`.

### The ladder (all inside one build slot, `CARGO_INCREMENTAL=0`, no `--target-dir`)

`build-slot.sh` speaks the retired staging tool, so the SDK ladder runs **directly in the port**
inside the lease (the slot is the guard, not the driver; `BUILD_LOCAL=1`, since the far box is not
the one holding the SDK copy).

| Step | Command | Result |
|---|---|---|
| runtime only, before any glue | `cargo test --offline` | **15 passed**, 0 failed (`evidence/actuallyadditions/sdk-test-runtime-only.log`) |
| glue first red | `cargo test --offline` with the glue's bodies at `todo!()` | **15 passed, 11 failed** — every glue test panicked at `not yet implemented` (`sdk-test-glue-red.log`) |
| tests | `cargo test --offline` | **26 passed**, 0 failed (15 `runtime::`, 11 `support::`) — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check` (**not** `--all`: that checks the fetched SDK) | exit 0, empty diff — `sdk-fmt.log` |
| package | `rm -f Cargo.lock && cargo horizon-mod build` | `SDK 0b14f8a … in ./.horizon/sdk`, `Built ./target/horizon-mod/actuallyadditions.hmod` — `sdk-build.log` |
| same package twice | the same build again | 95,503 B, `2367bd09…c311` both times — `sdk-build-second.log`, `sdk-sha256.txt` |
| registry check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.0 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3)`, **95,503 bytes**, sha256 `2367bd09…`, **EXIT 0** — `sdk-check.log` |
| machine form | `… check … --json` | `sdk-check-json.log` |
| fits the pinned build | `cargo horizon-mod fits actuallyadditions.hmod --build nightly` | `Actually Additions:` / `0b14f8a  made for`, **EXIT 0** — `sdk-fits.log` |
| runtime untouched | `unzip -p actuallyadditions.hmod src/runtime.rs \| sha256sum` | `df6c993a…c683` = `src/runtime.rs` = the retired file, byte for byte — `sdk-runtime-sha256.txt` |
| content carry unchanged | re-ran `tools/assemble_content.py` + `tools/stamp_license.py` | 79 carried files identical (`sha256sum` diff empty); the two licence copies added under `data/actuallyadditions/license/` |

`check` output:

```
actuallyadditions 0.2.0 (native-mod, format native-1/0b14f8acfd97fa2c750e42795249dcc981178ca4/e59da9094f0c2fdda6c627fe9eff22dec6a906f0, for 26.3)
  95503 bytes, SHA-256 2367bd09250116d2f57496b99212276f70399610965cc60feae52256fbb3c311, unsigned
  native source: unsandboxed; not executed by the registry check. Compile and test against the exact pinned Horizon and Mixins revisions before review.
```

`fits` output:

```
Actually Additions:
0b14f8a  made for
```

The archive is **90 entries**: `horizon-mod.toml`, `Cargo.toml`, `README.md`, `LICENSE`,
`LICENSE-NOTICE.md`, `uses.json`, `src/{lib,runtime,support}.rs`, `assets/actuallyadditions/**`
(20), `data/actuallyadditions/**` (60), `data/minecraft/tags/block/mineable/pickaxe.json` (1).
**No `Cargo.lock`** (`sdk-entries.txt`).

### `uses.json` (from the package)

`sdk-uses-summary.txt`: **397 surface entries** for `made_for 0b14f8a` — **9 hooks**
(`block_entity`, `block_entity_ticks`, `block_entity_tick`, `use_item_on`, `use_without_item`,
`level_tick_post`, `register_commands`, `run_mod_command`, `world_lifecycle`), 5 part kinds,
**42 methods** (`Register`'s `block_key`/`block_container`/`block_energy`/`block_entity_type`/
`block_entity_part`/`block_part`, `LevelRef::capability`/`block`/`game_time`/`with_random`/
`has_neighbor_signal`/`in_place`, `BlockEntityRef::{data,item_slot,set_item_slot,set_changed}`,
`ItemPlace::extract`, `HostTransaction::transaction`, `RecipesHost::{recipes_of_type,
recipe_ingredient}`, `ItemsHost::{item_key,max_stack_size,item_burn_time}`,
`Commands::feedback`, `RandomSource::next_float`, …), the **`horizon:energy`** and **`registries`**
capabilities, `fn:move_energy`, and the `horizon_mod` / `horizon_part` macros. Types 190, handles
92, traits 28 — the full list is `evidence/actuallyadditions/sdk-uses-from-package.json`.

### Traps this migration hit (the next port must know)

1. **Move the retired paths before the first build, and move `content/` last.** `mixins/`,
   `content/`, `compatibility.json`, `rust-toolchain.toml`, the repo `AGENTS.md`, `.github/` and
   the old `tools/` are non-package paths; `cargo horizon-mod build` refuses a root that holds
   them. Copy `content/` into the evidence folder **first**, then move `content/assets` and
   `content/data` to the package root — that leaves the retired copy intact to diff against (79
   files, identical).
2. **`src/runtime.rs` parses JSON, so the package needs `serde_json` — and then the lock question
   flips.** The carried file's `use serde_json::Value;` cannot change, so `Cargo.toml` gained one
   registry dependency, pinned `=1.0.151` (the version in the SDK's own `Cargo.lock`; a plain
   `"1"` resolved to 1.0.154). `cargo horizon-mod build` packs **no** `Cargo.lock` even though
   `cargo test` wrote one, so the delivered archive is the same 95,503 B either way — but the
   launcher-side pin the SDK documents (`horizon-launcher native-lock .`) is **not installed
   here** and could not run: the exact `=` pin in `Cargo.toml` is what carries the version. Verify
   this at the first real launcher build.
3. **`Compound` and `Tag` are two different `get`s.** `Compound` *is* the `BTreeMap<JavaString,
   Tag>`, so `nbt.get("energy")` does not compile (`expected &JavaString`). Keep the codec on
   `Tag` (`Tag::get(&str)`, as `mekanismgenerators` does) and wrap at the boundary:
   `Tag::Compound(std::mem::take(&mut event.entity.nbt))` and back out again.
4. **`host.levels()` is on `ServerHost`, not on `Host`.** `in_place_level` takes
   `&dyn ServerHost`; a helper that only needs `&dyn Host` cannot find the level a tick is in.
5. **`transaction` needs `use mod_api::HostTransaction`.** Without it rustc reports "no method
   named `transaction` … there is a method `transaction_open`".
6. **A status read borrows the host twice.** `player.action_bar(host, Text::literal(status_line(host,
   pos)))` is E0499; compute the line first, then hand it to the player.
7. **`fn:move_energy` wants the capability handles from *inside* the transaction.** Reading
   `level.capability(…)` outside and moving inside is stale; re-read both handles inside the
   `host.transaction` closure (this is what `bigreactors` learned the same way).
8. **A tick is not told its level, so the roll needs it too.** `LevelRef::with_random(host,
   RandomSource::next_float)` gives upstream's `Level.random.nextFloat()`; without a level the
   crusher uses `1.0` (no chance result) rather than `0.0` (always), because `bonus_for` is
   `roll <= chance`.
9. **A `BlockEntityPart` still needs an empty `impl BlockPart`** beside it — the click Part is the
   same struct attached twice (`Registrar::block_part` on the block, `block_entity_part` on the
   type), and `#[horizon_part]` derives subscriptions rather than implementing the supertrait.
10. **`cargo fmt --check`, never `--all`**, and check afterwards that `runtime.rs` did not move:
    `cmp` against the retired file and `unzip -p … src/runtime.rs | sha256sum` are the proof.
11. **A root `*.hmod` is not packed into the next build.** The deliverable can live beside the
    sources (as the campaign requires) and the second build still hashes identically — verified,
    not assumed.
12. **The e2e cannot run here.** A native `.hmod` needs a game built by `horizon-launcher
    native-build`, and the launcher is not installed; `tools/e2e.sh` now takes `GAME=` (and an
    optional `CONTROL_GAME=` for the unmodded negative control), drops `--dev-mod`, and is kept
    for the next slice. The 0.1.0 logs are **historical**: they prove the behaviour of a
    `runtime.rs` that did not change, and no 0.2.0 in-game claim is made.

### Gaps after the migration

Everything in the 0.1.0 gap list above still stands (no GUI, `lit`, comparator, particles, client
sync, the FE lost on break, the relay, the remaining machines). Added by this format:

1. **No 0.2.0 in-game run.** See trap 12. The scenario, its controls and its `SELFTEST=1`
   fail-capability are unchanged and ready for a launcher-built game.
2. **The unreadable-recipe log line is gone** (no logger in the SDK); the skip itself and the
   readout are unchanged.
3. **`serde_json` is the package's one registry dependency**, pinned by `Cargo.toml` rather than by
   a lock (trap 2); `horizon-launcher native-lock` is the documented tool and is not installed.
4. **The click is the block's `useItemOn`** (deliberate; see "Behaviour that changed").

### Changelog (0.2.0)

> **0.2.0 — republished as an SDK `.hmod`.** Supersedes **#790**, closed on 2026-11-18 because
> Horizon retired the `.hnmod` container (#16941; PR #17992 cleans up the old files). 0.2.0 is one
> flat package: `api = "0.2"`, `[native]` pinned to nightly
> `0b14f8acfd97fa2c750e42795249dcc981178ca4` and mixins
> `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, for 26.3. The eleven old injections became nine typed
> hooks (`block_entity`, `block_entity_ticks`, `block_entity_tick`, `use_item_on`,
> `use_without_item`, `level_tick_post`, `register_commands`, `run_mod_command`, `world_lifecycle`)
> plus two block-entity types, two containers and two energy buffers declared through `Registrar`;
> the content half now travels in the same package instead of an embedded `.hmod`; `src/runtime.rs`
> and its 15 tests are unchanged, byte for byte. Package: 90 entries, **95,503 B**, sha256
> `2367bd09250116d2f57496b99212276f70399610965cc60feae52256fbb3c311`; `check` and `fits` exit 0,
> two builds hash identically. No 0.2.0 in-game run: the launcher is not installed here.

### Publication route (campaign ruling 2026-11-18)

The submission form is gone; publishing is `horizon-rust/horizon-mods#1147` — the artifact is
attached to a release of the author's own repository under the entry's exact `file` name, a PR adds
the `[[versions]]` record and links the file, and a **maintainer** runs `scripts/stage.sh` (a red
`check` before that is the expected `fetch.sh` failure). The orchestrator's
`python3 ports/tools/publish-ready.py actuallyadditions` does the bookkeeping; this job owns no
submission. The port stays local-only until the maintainer approves publishing (ARCHITECTURE.md §8).

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices,rust-port

## Review fixes (2026-11-18) — registry source review #1230

Skills: superpowers/using-superpowers,systematic-debugging,test-driven-development,verification-before-completion; BeautifulRust/rust-best-practices

File: `var/review-all/1230-actuallyadditions.md`. Package **0.2.1**, `actuallyadditions.hmod`
97,276 B, sha256 `0ce6483c0e7fbcbfac4bb3c8c74ff9f0fbb2aacfddd5ac52e78834aa43110854`.

1. **`src/support.rs:655` the public coordinate readout revealed a crusher's input id/count and
   its recipe anywhere in the level.** `info` is declared `Command::op(…, 2)` (the level
   `/data get block` needs) and its body re-checks `may_read(permission)`; a non-machine still
   gets the generic `No Actually Additions machine there.` Pinned by
   `the_readout_needs_an_operator`, the updated `the_command_is_the_readout_at_the_operator_level`,
   the in-game de-op phase, and the non-machine control (the command test now asserts the level).
2. **`src/support.rs:620` input insertion rebuilt the stack from its item id and count (stripping
   components), merged on id alone, and committed without checking the hand supplied the full
   amount.** The slot now keeps the caller's own stack (`held.clone()` with the new count), only
   merges with a stack that `is_stackable_with` (same item **and** component patch), extracts
   from the hand **first** and aborts the transaction unless the full amount came out (the slot
   never gains items the player did not pay). Pinned in game by the new phase: a named coal must
   not merge into the plain coal in the fuel slot (the slot stays at four, the hand keeps the
   named one). `cargo test`: **27 passed**.

**Found by the in-game leg (fixed here, not in the reviewer's list).**

1. **The package could not load.** `declare` registered each Part twice (`block_part` *and*
   `block_entity_part`, which already expands to the type's blocks), and the game refused it
   (*"GeneratorPart is attached to actuallyadditions:coal_generator twice"*); and the carried
   `data/actuallyadditions/recipe/crushing/*.json` had no serializer (*"unregistered recipe
   serializer actuallyadditions:crushing"*). The Part is now attached once (through its type) and
   `declare` registers the recipe type with an object-preserving raw serializer.
2. **The harness's container path does not reach a mod block entity** (`ctl container` reads the
   engine's vanilla container map, which these machines do not use). The e2e now feeds by the
   player's right click and reads the `/actuallyadditions info` line; that line gained the slot
   counts it needed (`fuel …` on the generator, `out0`/`out1` on the crusher) so every assertion is
   still on real contents.

In-game: `PASS` + `E2E EXIT:0` (`ports/_shared/evidence/actuallyadditions-e2e/e2e-launcher.log`),
control `EXIT:1`. The component test is the phase after the fuel click (a named coal stays in the
hand, the four plain coal stay in the slot) and the de-op phase is the readout gate.

## Slice 2 (0.2.2, 2026-11-21) — a broken machine keeps its FE, burn and progress

**Pin:** Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a` (Nightly 2026-11-20) + mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, SDK `package_format` 6 / `content_api` 0.2. The
previous package (0.2.1) was built at `0b14f8a`; 0.2.2 is the same behaviour **repinned** plus
this slice. `src/runtime.rs` gained the restored-state rules and is otherwise unchanged.

**The gap line** (`## Deviations and gaps (slice 1)` item 3): *"Breaking a machine loses its FE.
Upstream's loot copies the `actuallyadditions:energy` component; the component type is not
registered in this slice, and the loot tables were patched to drop the block (an unknown
component would have dropped nothing)."* Upstream `TileEntityCoalGenerator`/`TileEntityCrusher`
save `Energy`/`BurnTime`/`MaxBurnTime`/`FirstCrushTime`, and the mod's loot copies them onto the
dropped item, so a player who picks a machine up and places it again finds it as it was. This
slice restores that with the carrier the pin documents, not a bespoke component: the block
entity's saved compound travels as vanilla **`minecraft:block_entity_data`** (the route proved in
game by `rftoolsutility` and recorded in `ARCHITECTURE.md` §3).

### Why this family, and what was tried first

The scoreboard said the #1 gap was the **GUI/screen** (`machines` tier lists menus/screens), so
that was built first: two content menu types (`data/actuallyadditions/horizon/menu/`), the
containers naming them, `menu_slot_rules` for the fuel/input filters, a `screen` layout at
upstream's `Slot` coordinates and a `screen_draw` over the carried `gui_coal_generator` /
`gui_grinder` / `gui_inventory` textures. It **cannot work at this pin in single player**, and the
measurement is worth keeping for the campaign:

- a right click *does* open the content menu (`ctl interact` answers `"screen":"container"`), but
  the client has no mod screen: `BlockEntity::Mod` then contributes **zero** container slots
  (`game.rs::slots`/`slot_count` fall back to the player's 36), so `ctl menu` lists no slot 300
  and the machine cannot be fed through it;
- the reason is in the engine: `open_native_screen` (which asks the mod's `screen` hook) is called
  only from the **remote client's** container-open path (`game/remote.rs`, `handleOpenScreen`); the
  single-player use path (`game.rs::open_menu` → `open_mod_menu`) sets `self.container` and
  `Screen::Inventory` without it, and `self.remote` is `None` in single player. The docs agree:
  *"a Horizon client shows it through the mod's own screen; without one it closes again."*
- `ctl screen` **hangs** (no reply, killed by the e2e guard) with a mod container open in
  `--headless`, so the screen also cannot be read through the harness.

The GUI code was reverted rather than shipped: a single-player machine whose right click opens a
container with no machine slots is worse than the slice-1 right-click insert. Recorded as
`blocked(no-single-player-mod-screen)` for the campaign — every `machines`-tier port that wants a
content menu hits it. The next slice below keeps the right-click insert and closes the
state-persistence gap.

### Behaviour (read from upstream, implemented in Rust)

| Item | Upstream | This port |
|---|---|---|
| generator saved state | `Energy`, `BurnTime`, `MaxBurnTime` | the same ints in the BE's saved compound (`energy`, `burn`, `burn_max`) |
| crusher saved state | `Energy`, `FirstCrushTime` | `energy`, `progress` |
| carry on break | loot copies the `actuallyadditions:energy` component | `Hooks::block_drops` writes the saved compound as `minecraft:block_entity_data`, tagged with the BE type id |
| restore on place | `BlockItem.updateCustomBlockEntityTag` applies it | vanilla applies the component when the item is placed; the item's Part clamps it |
| clamp | upstream trusts the component | `runtime::restored_generator` / `restored_crusher`: buffer clamped to 60,000, burn to `0..=burn_max`, progress to `0..=99` (never at the tick that would finish) |

The clamp is not cosmetic: a stale or edited item can name any int, and a progress of `100` would
finish an operation on its next tick without the input the operation needs.

### TDD

The two rules were written as failing tests first (`todo!()` bodies), then implemented:

```
---- runtime::tests::a_restored_crusher_cannot_start_at_the_end_of_an_operation stdout ----
thread 'runtime::tests::a_restored_crusher_cannot_start_at_the_end_of_an_operation' (105755) panicked at src/runtime.rs:323:5:
not yet implemented: a restored progress must not begin at the operation's end

---- runtime::tests::a_restored_generator_is_clamped_into_its_buffer_and_burn stdout ----
thread 'runtime::tests::a_restored_generator_is_clamped_into_its_buffer_and_burn' (105756) panicked at src/runtime.rs:316:5:
not yet implemented: the saved burn and buffer need clamping on placement

test result: FAILED. 0 passed; 2 failed; 0 ignored; 0 measured; 28 filtered out
```

Green afterwards: **30 passed, 0 failed** (`runtime::` 17, `support::` 13).

### Ladder (slot `W1-actuallyadditions`, `CARGO_INCREMENTAL=0`)

| Step | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **30 passed**, 0 failed — `evidence/actuallyadditions/sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | **100,946 B** both, `cmp` identical, `sha256 483f4e11…e253ad` — `sdk-build.log`, `sdk-build-second.log` |
| registry check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.2 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, **100,946 bytes**, EXIT 0 — `sdk-check.log` |
| fits, the pin | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 (a tautology) — `sdk-fits.log` |
| fits, a different build | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` | **1/1** |

Every log above prints the package's sha256 and size, and the source hashes in `sdk-test.log`.
The archive is **90 entries** with **no `Cargo.lock`** (the lock stays in the source tree because
`launcher native-build` reads it; `cargo horizon-mod build` packs it only when present, so the
delivered build is made with it removed and the tree's lock restored afterwards).

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.2)

```
package: …/actuallyadditions.hmod, 100946 bytes, sha256 483f4e112a6277cdb7e49026a01e6bb4faeb69811614eeff64c6cde32fe253ad
  before the break: Coal Generator at 10,100,-2: 1800/60000 FE (comparator 0, burning 1510/1600 ticks, fuel empty, t=972)
  dropped: [{"count":1,"item":"actuallyadditions:coal_generator"}]
  held after the walk: actuallyadditions:coal_generator
  after placing it again: Coal Generator at 6,100,-2: 2840/60000 FE (comparator 0, burning 1458/1600 ticks, fuel empty, t=1138)
  FE 1800 -> 2840, burn 1509/1600 -> 1458/1600
  the broken machine kept its FE and its burn
  a harness-given machine: Coal Generator at 8,100,-2: 0/60000 FE (comparator 0, burning 0/0 ticks, fuel empty, t=1157)
PASS: …
EXIT:0
```

The FE rises after placement because the machine resumes burning (1800 → 2840 over the ten seconds
between the two reads); the differential is the fresh machine beside it at `0/0`, so the value is
the broken machine's own state and not a default.

Legs (all `check-e2e-logs.py actuallyadditions-e2e --strict` → **logs=3 ok=3**):

| Leg | Verdict |
|---|---|
| `e2e-launcher.log` | `PASS` + `EXIT:0` |
| `e2e-launcher-selftest.log` | `FAIL: SELFTEST flipped: the placed machine kept 2820 FE, not 0` + `EXIT:1` |
| `e2e-launcher-control.log` | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` (the same Nightly without the package) |

Harness facts measured while getting there:

- `ctl entities`/`ctl inventory` print a stack's components through `encode_components`, which
  **omits `minecraft:block_entity_data`**; a probe that looked for it there read "no component"
  while placement proved the component was there. Assert the behaviour (place it again), not the
  JSON patch.
- `ctl screen` does not answer with a mod container open in `--headless` (the e2e guard killed the
  run after 900 s); `ctl menu` is the working readout.
- `ctl look-at-block` refuses a position that holds air, so the restore step places at the target
  coordinates without looking at them first; and the drop is picked up by walking to the block's
  *centre* (`x+0.5, z+0.5`), not to the block coordinate.
- A survival break needs a real tool (`iron_pickaxe`) and the player within reach; the scenario
  returns to creative before the pickup so a wandering mob cannot decide the run.
- **The operator readout phase was vacuous and is fixed.** It used `deop` + a grep, and both
  `op`/`deop` are dedicated-server commands an integrated server refuses, so the grep matched the
  failed `deop`'s own refusal (HANDOVER §9d 6). It is now a LAN guest at permission level 0 with a
  differential: the same guest runs `/help` and `/list` (so its command path is alive) and only
  then asks `/actuallyadditions info`, which is refused with no readout in its window. From the
  delivered run: `the level-0 guest runs /help: /trigger <objective> [add|set]`,
  `the level-0 guest runs /list: There are 2 of a max of 8 players online: …`, `as a level-0
  guest: … Unknown or incomplete command …` — and the owner reads the crusher again afterwards.

### Coverage (slice 2)

| Family | State |
|---|---|
| generator tick, burn, FE, fuel consumption, refusal | tested (slice 1 phases, unchanged) |
| crusher recipe/progress/FE/outputs, bonus roll unit-tested | tested (slice 1 phases; bonus roll remains unit-only) |
| generator→crusher FE move at `level_tick_post` | tested (adjacent pair, slice 1) |
| `/actuallyadditions info` (parsed reply, level-2 gate) | **tested** — owner reads the line, a level-0 LAN guest is refused after `/help` and `/list` answer the same guest |
| break carries a machine's saved state (generator) | **tested** — break → drop → pick up → place → `info` keeps FE and burn, fresh machine at 0 |
| break carries a machine's saved state (crusher, loaded) | **tested (0.2.3)** — a survival break of a crusher with 7,300 FE, progress 36 and a coal ore inside drops an item whose `Item` tag is `{energy: 5180, progress: 89, id: …}` with **no `Items`**; the ore spills as its own plain drop; placing it again reads 5,180 FE with an empty container; an empty crusher's payload is only `{id}` and comes back at 0 — `SELFTEST=drops` flips it to `EXIT:1` |
| clamp on placement (corrupt `burn`, `progress`, buffer) | unit-tested (`restored_generator`, `restored_crusher`); not reachable from `ctl` |
| GUI / menu / screen | **blocked(no-single-player-mod-screen)** — see above, code reverted |
| machine recipes | **the Coal Generator's crafts (0.2.4)** — see slice 3; the Crusher's is `blocked(restonia_crystal_growth)`. In 0.2.2/0.2.3 both were dropped: `recipes: invalid ingredient (unresolved tag or malformed input): "#c:cobblestones"` |

### Gaps after slice 2

Everything in the 0.1.0/0.2.0 lists still stands except item 3 of the slice-1 deviation list
(**breaking a machine loses its FE — closed**). Added/changed here:

1. **No GUI** — now `blocked(no-single-player-mod-screen)` rather than "deferred": the pin cannot
   show a content menu's slots on the single-player host, so the right-click insert stays.
2. **The crusher's own break/place leg** was unit-tested only after slice 2; **closed by the
   review fix below (0.2.3)**: the leg now breaks a loaded crusher in game and asserts its payload,
   its spill and its restore.
3. ~~**The two machine recipes still do not craft**, and the load log names the unresolved
   `#c:cobblestones`~~ — **closed for the Coal Generator by slice 3 (0.2.4)**: the tag, the Iron
   Casing and the Basic Coil ship and its recipe crafts in game. The Crusher's recipe is still
   `blocked(restonia_crystal_growth)` (it registers and never crafts — measured; see slice 3).
4. `minecraft:block_entity_data` carried the **whole** saved compound in 0.2.2, including any
   future keys — **closed by the review fix below (0.2.3)**: the payload is an allowlist of the
   values the port reads back, so a later key cannot ride along unnoticed.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices,rust-port

## Review fixes (2026-11-22/23) — `horizon-mods#1557` round 1 (`NikitaMGrimm`) → 0.2.3

**Package 0.2.3**, `actuallyadditions.hmod` **105,538 B**, sha256
`e0b1f95ad260a2a8fc81ab0906cf902a42a11a07db3aae3161b8b21a88369600`, **91 entries** (0.2.2: 90, the
lock is the new one). Three items, each answered with what changed and where.

### 1. BLOCKER — the drop hook duplicated the container's inventory (`src/support.rs`)

Quoted: *the drop hook duplicates inventory … `let mut payload = saved.clone()` … the crusher's
saved `Items` ride on the dropped item, on top of what the engine already spills.* That was true:
`event.block_entity` is the **pre-removal** snapshot (`HANDOVER.md` §9m), so the payload carried
`Items` on every drop the loot table made.

**Red first** (`evidence/actuallyadditions/sdk-test-red-payload.log`; the function was given its
`keys` parameter with the old body so the failure is the assertion, not a compile error):

```
---- support::tests::a_broken_machines_payload_carries_its_state_and_never_its_stacks stdout ----

thread 'support::tests::a_broken_machines_payload_carries_its_state_and_never_its_stacks' (6175) panicked at src/support.rs:1322:9:
assertion `left == right` failed: the container's stacks are the engine's to spill, never the payload's
  left: Some(List([Compound({JavaString([99, 111, 117, 110, 116]): Byte(1), JavaString([105, 100]): String(JavaString([109, 105, 110, 101, 99, 114, 97, 102, 116, 58, 99, 111, 97, 108, 95, 111, 114, 101]))})]))
 right: None
test result: FAILED. 30 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out
```

**What changed.** `entity_data_patch(saved, type_id, keys)` no longer clones the compound: it
copies **only** the allowlist (`GENERATOR_STATE_KEYS = ["energy", "burn", "burn_max"]`,
`CRUSHER_STATE_KEYS = ["energy", "progress"]` — exactly what `read_generator`/`read_crusher` read
back) plus the `id`, and nothing else can travel. `on_block_drops` resolves the machine's own
`ItemKey` **once at registration** (`GENERATOR_ITEM`/`CRUSHER_ITEM` `OnceLock`s — `block_drops`
gets a read-only `LevelHost`, which cannot name an item) and applies the patch **only** to the
drop whose `stack.item()` is that key, not to every drop the table made. Green: **31 passed**.

**In game** (`evidence/actuallyadditions-e2e/e2e-launcher.log`), a loaded crusher broken in
survival:

```
  before breaking the loaded crusher: Crusher at 12,100,5: 7300/60000 FE (comparator 1, progress 36/100, input minecraft:coal_ore x1, …)
  items near the break: [{"item":"actuallyadditions:crusher","count":1}, {"item":"minecraft:coal_ore","count":1}]
  the crusher drop's Item tag: {"chat":["Crusher has the following entity data: {components: {\"minecraft:block_entity_data\": {progress: 89, id: \"actuallyadditions:crusher_block_entity\", energy: 5180}}, count: 1, id: \"actuallyadditions:crusher\"}"],"ok":true}
  payload: energy 5180 (machine 7300), progress 89 (machine 36)
  the drop carries energy and progress and no Items
  the spilled input's Item tag: {"chat":["Coal Ore has the following entity data: {count: 1, id: \"minecraft:coal_ore\"}"],"ok":true}
  held after the walk: actuallyadditions:crusher
  after placing it again: Crusher at 14,100,5: 5180/60000 FE (comparator 1, progress 0/100, input empty, out0 empty, out1 empty, …)
  crusher FE 7300 -> 5180
  the placed crusher kept its FE and came back with an empty container
  a harness-given crusher: Crusher at 16,100,5: 0/60000 FE (comparator 0, progress 0/100, …)
  items near the empty break: ["actuallyadditions:crusher"]
  the empty crusher's Item tag: {"chat":["Crusher has the following entity data: {components: {\"minecraft:block_entity_data\": {id: \"actuallyadditions:crusher_block_entity\"}}, count: 1, id: \"actuallyadditions:crusher\"}"],"ok":true}
  the empty crusher placed again: Crusher at 18,100,5: 0/60000 FE (comparator 0, progress 0/100, input empty, …)
```

The payload's numbers are the machine's own **at the moment of the break** (the machine keeps
ticking while the pickaxe swings: 36 → 89), which is why the assertion is "the charged machine's
own" plus the empty-machine differential rather than an equality against the earlier read. Two
further facts the leg measured:

- `data get entity @e[type=minecraft:item,…] Item` **does** show `minecraft:block_entity_data`
  (unlike `ctl entities`, whose `encode_components` omits it, the slice-2 trap), so the carrier is
  asserted directly. The nbt-filtered selector was flaky in one run; the leg now clears item
  entities and reads the nearest one (`distance=..8`).
- An **idle** machine answers `BlockEntityTickReply::Unchanged`, so its saved compound holds **no**
  `energy`/`progress` keys at all: an empty machine's payload is `{id}` only, and both values read
  back as 0. That is what the differential asserts (no non-zero state), not a literal `energy: 0`.

**Fail-capability.** `SELFTEST=drops` flips the payload assertion ("the container's `Items`
travel"), which passes only on the defect:
`FAIL: SELFTEST drops: the payload carries no Items (the fixed behaviour); …` + `EXIT:1`
(`e2e-launcher-selftest-drops.log`).

### 2. The registry `Cargo.lock` now ships

The crate declares `serde_json = "=1.0.151"`, so the package must pack its lock
(`verify-sdk-package.py` refuses an unlocked package that declares a registry dependency; the
launcher's clean build needs it). The 0.2.2 build removed the lock before building — that is why
it was absent. 0.2.3 keeps the tree's lock (`sha256 4938025f0ffa737da852043f35a5b7a190fe071f0719af4f597279c7d06e35fd`,
8,850 B) and the pass packs it: the archive is **91 entries instead of 90**, `Cargo.lock` is the
91st, and its bytes in the package equal the tree's. The 0.2.0 migration trap 2 ("`cargo
horizon-mod build` packs no `Cargo.lock`") is superseded: it packs it **when it is present**, and
it should be present.

### 3. The upstream MIT notice is verbatim

`LICENSE` is now the upstream file byte for byte — 1,063 B, sha256
`82ea451b20be461c2bbf279262d4a28c34bed3edc3197b90ae902b77fb22c560`, including
`Copyright (c) 2019 Mrbysco`, from
<https://github.com/Ellpeck/ActuallyAdditions/blob/v1.3.26/LICENSE>. Our provenance (the jar's
SHA-1, the "clean-room Rust" statement) and our own copyright moved to `LICENSE-NOTICE.md`,
separate from the notice; `tools/stamp_license.py` re-stamped
`data/actuallyadditions/license/{license.txt,notice.txt}`, and `license.txt`'s hash equals the
upstream file's. The previous `LICENSE` had rewritten the copyright lines and named the wrong
project.

### Ladder (0.2.3, slot `W2-actuallyadditions`, `CARGO_INCREMENTAL=0`)

| Step | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **31 passed**, 0 failed (`Compiling actuallyadditions v0.2.3`, not a cached artefact) — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --manifest-path … --check` | exit 0 — `sdk-fmt.log` |
| package ×2 | `cargo horizon-mod build`, twice, **lock kept** | **105,538 B** both, `cmp` identical — `sdk-build.log`, `sdk-build-second.log` |
| registry check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.3 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 105,538 bytes, EXIT 0 — `sdk-check.log` |
| fits, the pin | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` | **1/1** (includes `packed Cargo.lock (declares a dependency) 91 entries`) |
| in-game | `tools/e2e.sh` on the launcher-built game | `PASS` + `EXIT:0` — `actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=drops` | `FAIL: SELFTEST drops: the payload carries no Items …` + `EXIT:1` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2820 FE, not 0` + `EXIT:1` |
| control | the same script on the same Nightly **without** the package | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=4 ok=4` |

The launcher build is `native-0a875da-…` and the leg's first line names the sha256 above, so the
game ran the delivered archive.

## Slice 3 (0.2.4, 2026-11-23) — the crafting chain's first two pieces, and the tag its recipes need

**Family:** the crafting chain's first two pieces — `actuallyadditions:iron_casing` (a block
upstream, `Blocks.IRON_CASING`, `ActuallyBlocks.java:42`) and `actuallyadditions:basic_coil` (a
plain item) — plus the **`c:cobblestones` item tag**, so the **Coal Generator's own recipe crafts
in game**. The Crusher's recipe still cannot: it needs `restonia_crystal`, which upstream grows
from a seed in water rather than crafts.

- **Gap line** (`Gaps after slice 2`, item 3): *"The two machine recipes still do not craft, and
  the load log names the unresolved `#c:cobblestones`. The crafting chain (`iron_casing`,
  `basic_coil`, `restonia_crystal`, `black_quartz`) is the next family; `black_quartz` needs the
  ore, which is worldgen."*
- **Why it fits `machines`:** carried content (one block, one item, one loot table, one tag) on a
  machines-tier port, proven through the machine the port already ships — no GUI, no new hook, no
  renderer, no Rust change.

**Pin:** Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`. `src/runtime.rs`, `src/support.rs` and `src/lib.rs`
are **byte-identical** to 0.2.3 (`215aa1be…`, `60e809d1…`, `e18ecd36…`).

### Behaviour (from the jar and the platform)

| Item | Upstream | This port |
|---|---|---|
| `actuallyadditions:iron_casing` | a block: `Blocks.STONE` copied, `strength(1.5f, 10f)`, `SoundType.METAL`; in `minecraft:mineable/pickaxe`; drops itself (loot table) | `horizon/block/iron_casing.json`: template `minecraft:stone`, `hardness 1.5`, `explosion_resistance 10.0`, `sounds minecraft:iron_block`, `requires_tool`, `item: true`; the jar's blockstate/model/loot table, and the id joins the port's subset pickaxe tag |
| `actuallyadditions:basic_coil` | a plain item, stack 64 | `horizon/item/basic_coil.json`: template `minecraft:stick`, the jar's model and texture; joins the machines creative tab |
| `c:cobblestones` | a NeoForge convention tag (not a jar file) | `data/c/tags/item/cobblestones.json` with NeoForge 1.21.x's four members — `minecraft:cobblestone`, `mossy_cobblestone`, `cobbled_deepslate`, `infested_cobblestone` (the same list `ports/theurgy/tools/tag_members.json` records); all four exist in 26.3, and 26.3 ships no `c:` namespace, so the tag has to be declared |

`tools/assemble_content.py` carries the two pieces and writes the tag, the pickaxe subset and the
tab; re-running it changes no other carried byte (checked with a before/after `sha256sum` of every
file under `assets/` and `data/`: 81 files before, 93 after, the other 81 identical).

### The loader's two failure shapes — measured, not assumed

The 0.2.3 note said both recipes were "dropped". 0.2.4 measured what actually happens, and the two
cases differ:

- **a missing `#tag` is fatal to the file.** 0.2.3's load log: `recipes: invalid ingredient
  (unresolved tag or malformed input): "#c:cobblestones"`, and `recipe give @s
  actuallyadditions:coal_generator` would have answered `Unknown`. That is why **neither** machine
  recipe existed in 0.2.2/0.2.3.
- **an unknown item id leaves the recipe registered but unsatisfiable.** With the tag in place,
  `recipe give @s actuallyadditions:crusher` answers `Unlocked 1 recipe(s)` even though
  `give actuallyadditions:restonia_crystal` answers `unknown item`, and the crusher's grid stays
  empty with its two crystal cells unfilled. So the Crusher's recipe is in the book and can never
  craft — the record is `blocked(restonia_crystal_growth)`, and the in-game leg asserts exactly
  that (not "the recipe is absent", which would be wrong).

### TDD (content slice): the rule first, red, then the in-game assertion

The family's rule is "every carried crafting recipe's ingredients resolve, or the recipe is a
recorded blocker". It is machine-checked by the new `tools/check_recipe_keys.py` (vanilla
`items.json` + the package's own item/block declarations + its `tags/item` files, and
`tools/recipe-blockers.json`); it reads the 26.3 item registry, so a tag or item that only *looks*
right fails.

**Red** (`evidence/actuallyadditions/check-recipe-keys-red.log`, run against a copy of the
pre-slice `data/` — the real 0.2.3 tree — with the blocker file present):

```
FAIL     actuallyadditions:coal_generator: unresolved #c:cobblestones, actuallyadditions:iron_casing (a missing tag drops the recipe at load, an unknown item leaves it uncraftable; declare the item/tag or add a blocker)
blocked  actuallyadditions:crusher: restonia_crystal_growth — actuallyadditions:basic_coil, #c:cobblestones, actuallyadditions:iron_casing, actuallyadditions:restonia_crystal
2 recipe(s), 0 craftable, 1 blocked, 1 failure(s)
exit=1
```

**Green** (`check-recipe-keys.log`):

```
ok       actuallyadditions:coal_generator: every ingredient resolves
blocked  actuallyadditions:crusher: restonia_crystal_growth — actuallyadditions:restonia_crystal
2 recipe(s), 1 craftable, 1 blocked, 0 failure(s)
exit=0
```

The tool also refuses an **empty** `tags/item` file (the loader drops a tag with no values) and a
**stale** blocker whose recipe now resolves, so the record cannot rot.

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.4)

`tools/craft_check.py` (the same shape as `bigreactors/tools/craft_check.py`) drives a real crafting
table (grid slots 100-108, result 200; `ctl screen` reports `craft_size` 3):

```
  recipe give actuallyadditions:coal_generator -> {"chat": ["Unlocked 1 recipe(s) for Player73342"], "ok": true}
  (recorded, not asserted) crusher recipe in the book: {"chat": ["Unlocked 1 recipe(s) for Player73342"], "ok": true}
  give actuallyadditions:restonia_crystal -> {"error": "unknown item actuallyadditions:restonia_crystal"}
  coal generator (6 cobblestone + 2 iron casings + 1 coal): result {"count": 1, "item": "actuallyadditions:coal_generator", "slot": 200}
  coal generator (6 cobblestone + 2 iron casings + 1 coal): inventory after the craft {"minecraft:cobblestone": 2, "actuallyadditions:iron_casing": 2, "minecraft:coal": 1, "actuallyadditions:coal_generator": 1}
  control: iron ingots where the casings go: result null
  coal generator from mossy cobblestone (a c:cobblestones member): result {"count": 1, "item": "actuallyadditions:coal_generator", "slot": 200}
  coal generator from mossy cobblestone (a c:cobblestones member): inventory after the craft {"minecraft:mossy_cobblestone": 2, "actuallyadditions:iron_casing": 2, "minecraft:coal": 1, "actuallyadditions:coal_generator": 1}
  control: stone in the cobblestone cells (not a c:cobblestones member): result null
  control: the Crusher's own recipe without restonia_crystal (blocked): result null
recipe PASS: the Coal Generator's own recipe unlocks, crafts one machine from six cobblestone, two iron casings and a coal (all consumed, empty grid), also crafts from a mossy cobblestone tag member, stays empty for iron ingots in the casing cells and for stone in the cobblestone cells, and the Crusher's recipe stays uncraftable (blocked(restonia_crystal_growth))
```

Every assertion can fail: the recipe unlock is the pre-0.2.4 red state (`NEGATIVE=1` flips it and
the run fails at it — `e2e-launcher-negative.log`); the iron-ingot differential is the brief's own;
mossy cobblestone proves the key is a **tag** and not the plain block; stone proves it is not a
wildcard.

The new block leg (also in the same log):

```
  block(22,100,-6) = actuallyadditions:iron_casing
  given: {"actuallyadditions:iron_casing":1}
  give an unknown id: {"error":"unknown item actuallyadditions:does_not_exist"}
  at [22.5,100.0,-3.5]
  break: {"drops":{"actuallyadditions:iron_casing":1},"picked_up":{},"items_left_on_ground":1}
  the Iron Casing dropped itself (asserted from the break's own drop record)
```

### Ladder (0.2.4, slot `W3-actuallyadditions`, `CARGO_INCREMENTAL=0`, `BUILD_LOCAL=1`)

| Step | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **31 passed**, 0 failed — `Compiling actuallyadditions v0.2.4` (not a cached artefact) — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `tools/check_recipe_keys.py` | red then green (above) — `check-recipe-keys{,-red}.log` |
| package ×2 | `cargo horizon-mod build`, twice, **lock kept** | **110,156 B** both, `cmp` identical — `sdk-build.log`, `sdk-build-second.log` |
| registry check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.4 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 110,156 bytes, `f7767eba…dd1d67`, EXIT 0 — `sdk-check.log` |
| fits, the pin | `cargo horizon-mod fits … --build 0a875da` | `Actually Additions:` / `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` | **1/1** |
| in-game | `tools/e2e.sh` on the launcher-built game (`--offscreen`) | `PASS` + `EXIT:0` — `actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour) …` + `EXIT:1` — `e2e-launcher-negative.log` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2620 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=drops` | `FAIL: SELFTEST drops: the payload carries no Items …` + `EXIT:1` |
| control | the same script on the same Nightly **without** the package | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=5 ok=5` |

Artifact: `actuallyadditions.hmod`, **110,156 B**, sha256
`f7767ebadf65127b0f0d5b38d0152296051a49243d9b0c98251e54fbaadd1d67`, **103 entries** (0.2.3: 91; the
12 new data/asset files), `Cargo.lock` packed and equal to the tree's (8,850 B,
`ef8de232…78e4` — the lock's own `actuallyadditions` version line moved to 0.2.4). The launcher build
is `native-0a875da-b89ef4c3ade8` (the exported package's README is byte-identical to the tree's), exported to `~/.cache/horizon-e2e/0a875da/actuallyadditions/`, and
the leg's first line names the sha256 above.

### Coverage (slice 3)

| Family | State |
|---|---|
| `actuallyadditions:coal_generator` recipe (`CIC/CAC/CIC`) | **tested** — `recipe give` unlocks 1; the grid crafts 1 machine and consumes all nine items (six cobblestone, two casings, one coal); the grid is empty afterwards |
| `c:cobblestones` tag | **tested** — its `mossy_cobblestone` member crafts the machine; `stone` (not a member) leaves the result empty; the tool refuses an empty tag file |
| `actuallyadditions:iron_casing` block + item | **tested** — places and reads back, is give-able, drops itself from its carried loot table (`ctl break`'s own `drops` record), and an undeclared id is refused (`unknown item`) |
| `actuallyadditions:basic_coil` item | **tested** — give-able and used as a key in the Crusher's blocked recipe; it has no other behaviour |
| `actuallyadditions:crusher` recipe | **blocked(restonia_crystal_growth)** — registers, `recipe give` unlocks it, and it never crafts (the grid with its crystal cells unfilled stays empty; `give restonia_crystal` is refused) |
| `iron_casing` / `basic_coil` own recipes | **not carried** — `iron_casing` needs `black_quartz` (the ore is worldgen) and `basic_coil` needs `black_quartz` + `restonia_crystal` (grown, not crafted); a recipe that cannot craft is not shipped as dead data. Added to `tools/recipe-blockers.json`'s rationale in this section, not as files |
| everything slice 1/2 shipped | unchanged and re-proved in the same run (machines, FE link, break state, operator readout) |

### Deviations and gaps this slice adds

1. **A player cannot yet obtain an Iron Casing or a Basic Coil in survival.** Both are only
   craftable from `black_quartz` (worldgen) and `restonia_crystal` (grown); the in-game proof
   supplies them with `give`. The Coal Generator recipe is therefore *correct and craftable* but not
   yet *reachable* from raw materials — the next two chain pieces close that.
2. **The Iron Casing is a block, so it has a blockstate/model/loot table**, not just an item; the
   jar's model is `cube_all` on its own texture and its item model parents the block model.
3. **`c:cobblestones` carries vanilla's four vanilla members only.** A 1.21.1 pack's tag would also
   have modded cobblestones; 26.3 has none to name, and `Known::keeps` drops an id a content root
   does not have, so naming one would only log a removal.
4. **The block-leg's aim refuses an obstructed line of sight** (`no face of block … is visible from
   here: … is in the way`) — the casing is placed at `z=-6`, clear of the crafting table at
   `(20, 100, 8)`.

### Harness facts measured while getting there (worth keeping)

1. **`click-slot` needs a renderer**: the whole leg now launches `--offscreen` (a crafting-table
   slot click under `--headless` answers "no renderer yet"). The machines and loot legs are
   unaffected.
2. **`ctl break` is the drop record**: its reply carries `drops` (counts of the item entities the
   break made, watched for 20 ticks), `picked_up` (the inventory delta) and `items_left_on_ground`.
   Reading the ground with `data get entity @e[…]` afterwards races the player's pickup and cost this
   wave three red runs; the legs now assert the break's own record.
3. **A player within ~1 block picks an item up after its 10-tick delay** (`getBoundingBox()
   .inflate(1.0, 0.5, 1.0)`), and a drop drifts: standing two blocks off a machine sometimes put its
   drop in the inventory before the reads (the drop's advancement fired mid-leg). Break from 3.5
   blocks.
4. **`ctl interact` on a vanilla crafting table opens the ordinary inventory screen with
   `craft_size` 3** — the grid is 100-108 and the result 200, and `ctl screen` lists them.
5. **`recipe give @s <id>` is a presence test for a recipe**, but it says nothing about whether the
   recipe can craft: an unknown *item* key leaves it registered and unlockable (the Crusher), while
   an unknown *tag* had dropped it entirely.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

**Changelog (0.2.4):**

> **0.2.4 — the crafting chain's first two pieces, and the tag the machine recipes need.** Adds the
> Iron Casing block and the Basic Coil item (the jar's blockstate, models, textures, loot table and
> declarations) and the `c:cobblestones` item tag 26.3 does not ship, so the Coal Generator's own
> recipe resolves and crafts in a vanilla crafting table: six cobblestone (any tag member), two
> iron casings and a coal make one machine, all consumed. The Crusher's recipe still cannot craft —
> it waits on `restonia_crystal`, which upstream grows rather than crafts
> (`blocked(restonia_crystal_growth)`; it registers and the grid stays empty). No Rust change
> (`src/*.rs` byte-identical); `tools/check_recipe_keys.py` now fails a build whose recipe key names
> an item or tag the package cannot resolve; the e2e runs `--offscreen` and gains the crafting and
> block legs. 103 entries, 110,156 B, sha256 `f7767eba…dd1d67`.

## Next slice (0.2.5)

**Family:** the rest of the crafting chain that is *craftable* — the `c:ingots/iron` and
`c:rods/wooden` item tags, wherever they are needed — starting with **`black_quartz`**, which gates
both `iron_casing` and `basic_coil`: with it, the two pieces become survival-reachable and their own
recipes can ship and be crafted.

- **Gap line** (`Deviations and gaps this slice adds`, item 1): *"A player cannot yet obtain an Iron
  Casing or a Basic Coil in survival. Both are only craftable from `black_quartz` (worldgen) and
  `restonia_crystal` (grown)…"*
- **Blocker to check first:** `black_quartz` comes from **Black Quartz Ore**, which is worldgen
  (`data/actuallyadditions/...` ore + `c:ores/black_quartz`). This pin has a worldgen API
  (`ARCHITECTURE.md` §8, 2026-11-18: the worldgen-last ruling is lifted), so the question is whether
  this port's tier (`machines`) should grow an ore: if yes, the `worldgen` slice; if not, a
  **`black_quartz` item via the crusher's `black_quartz_ore` recipe** stays blocked and the next
  craftable piece is `restonia_crystal`'s growth (a block/seed mechanic, `machines`-shaped: a
  water-placed seed that grows — a `random_ticks` block with a growth state, proved by ticking one
  in game).
- **In-game assertion that can fail:** for `restonia_crystal` growth: place the seed block in water,
  tick it, assert the cluster appears and a wrong fluid (lava) does not; for `black_quartz`: mine a
  generated ore in a loaded chunk and assert the drop, or `give` the item and craft `iron_casing`
  with `c:rods/wooden` + `c:ingots/iron` (which this slice must then declare).
- **Out of scope:** the remaining chain (`empowered_*` crystals, the Empowerer), the Double
  Crusher, the GUI (`blocked(no-single-player-mod-screen)`).

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices
