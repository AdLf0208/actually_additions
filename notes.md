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
| `Cargo.toml` | one crate, `edition = "2024"`; `horizon-mod-api` from `.horizon/sdk/` **only** — the `serde_json = "=1.0.151"` this row used to carry was removed in 0.2.9, when the registry's R9 refused it (see "The registry's R9") |
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
   **Superseded in 0.2.9, and the reversal is the point:** the registry refuses a package that
   declares *any* dependency but the SDK path dep (rule R9), so a package with a registry
   dependency cannot be published at all. The dependency is gone and `src/runtime.rs` reads the
   recipe JSON with its own reader (see "The registry's R9").
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
3. **~~`serde_json` is the package's one registry dependency~~ — removed in 0.2.9.** It was pinned
   by `Cargo.toml` rather than by a lock (trap 2); the registry's R9 then refused the package for
   it, and the reader now lives in `src/runtime.rs` (see "The registry's R9").
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

### 2. The registry `Cargo.lock` now ships — and 0.2.9 reverses it

**The rule this section stated is dead for the registry.** It read: *the crate declares
`serde_json = "=1.0.151"`, so the package must pack its lock (`verify-sdk-package.py` refuses an
unlocked package that declares a registry dependency; the launcher's clean build needs it)*. That
was true for the **launcher**, and 0.2.3–0.2.8 acted on it: 0.2.3 kept the tree's lock
(`sha256 4938025f0ffa737da852043f35a5b7a190fe071f0719af4f597279c7d06e35fd`, 8,850 B), the archive
became **91 entries instead of 90**, and every later version packed it (0.2.8: 152 entries).

The **registry** closed the door instead of opening it. Its `tools/native-subset/README.md`, rule
R9, verbatim:

> `Cargo.toml` has a dependency other than `horizon-mod-api = { path = ".horizon/sdk/api/crates/horizon-mod-api" }`, a build script, a proc-macro or a `lib.path` other than `src/lib.rs`, or a table other than `[package]`, `[dependencies]`, `[lib]` and `[lints]`.

and the automated check at `495701cf` refused 0.2.8 with **`rules R9`**. So a package with a
registry dependency **cannot be published at all** — the lock it forces is not a workaround, it is
the evidence of the violation. `Cargo.toml` now declares the SDK path dependency and nothing else,
`src/` uses no crate, and the archive carries **no `Cargo.lock`**
(`rm -f Cargo.lock` before `cargo horizon-mod build`; 0.2.2's shape, now for a different reason).
The 0.2.0 migration trap 2 stands only for the launcher's own clean build, which applies to no
package this campaign ships.

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

## Next slice after 0.2.4 (the list the 0.2.5 investigation came from)

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

## 0.2.5 investigation #1 (2026-11-23) — the water-growth premise is not in the artefact; **that** slice was blocked

> **What happened next:** the version number 0.2.5 was not spent on that dispatch (nothing artefact-true was
> left to ship). The next dispatch was the **Black Quartz Ore** — the slice the investigation's own
> "next slice, in artefact order" list ranked first — and it is what 0.2.5 is; see "Slice 4 (0.2.5)"
> at the end of this file.

The 0.2.5 brief asked for "the restonia crystal growth: a seed planted in water grows into the crystal
cluster". **1.3.26 has no such mechanic**, and the gap line that produced it was this port's own wrong
inference — the 0.2.4 note and `tools/recipe-blockers.json` both said "upstream grows rather than
crafts". This section records what the jar and the matching source actually say, retracts the claim, and
states why the chain cannot close with the crystal alone either. Everything below is reproducible:

```sh
ports/actuallyadditions/tools/audit_restonia_source.sh \
    > ports/_shared/evidence/actuallyadditions/restonia-source-audit.log   # 499 lines
```

### The growth rule as read — there is none

| Question the brief asked | What the artefact answers |
|---|---|
| `random_ticks`? | **No.** The only `randomTick`/`isRandomlyTicking` in the source are the Coal Generator, the Crusher, Greenhouse Glass, the Oil Generator and the Powered Furnace. No crystal block has one (`CrystalClusterBlock` extends `FullyDirectionalBlock`, whose base classes have none). |
| a growth state? | **No.** `restonia_crystal_cluster`'s only property is `facing` (the jar's blockstate has six variants, all one model). The constructor takes a `Crystals` argument and **never uses it** (`CrystalClusterBlock.java:48`); the enum itself carries only colours. |
| how many stages? | **Zero.** A cluster is one block with one shape per facing. |
| a seed? | **No.** Every registered id containing `seed` is a plant seed (`canola`, `coffee`, `flax`, `rice`, `crystallized/empowered_canola_seed`), and every jar entry containing `seed` is one of those or its texture. |
| where clusters come from | **A worldgen feature that no longer exists at 1.21.1.** The jar's whole `data/actuallyadditions/worldgen/` tree is 5 configured features (4 crops + `ore_black_quartz`), 5 placed features and one processor list — **no cluster feature**. `WorldGenLushCaves`, which once placed `CRYSTAL_CLUSTERS` on cave walls, is commented out **end to end (194 of 194 lines)**. |
| what makes a crystal, then | **The Atomic Reconstructor**, in the mod's own words: *"The Atomic Reconstructor is used to craft Crystals … Upon being supplied with power, it shoots out a Laser. It will convert all surrounding items and blocks along the beam's path"* (`booklet.actuallyadditions.chapter.crystals.text.1/2`). The recipe is `laser/crystalize_restonia_crystal`: `#c:dusts/redstone → restonia_crystal`, **40 CF** of a **1000 CF** shot; the shot fires once per **100 ticks** and the default lens reaches **10 blocks**. |

So the 0.2.4 next-slice's "water-placed seed that grows" is not upstream behaviour: crystals come out of
a machine, not out of water. The **lava** half of the proposed assertion has the same problem — no fluid
participates in this mechanic at all, so "lava does not grow it" cannot be made fail-capable.

### Why the crystal would not close the chain anyway (an independent blocker)

| Recipe | Keys | Gate |
|---|---|---|
| `actuallyadditions:iron_casing` | `W S W / S Q S / W S W`, W=`#c:ingots/iron`, S=`#c:rods/wooden`, **Q=`actuallyadditions:black_quartz`** | black_quartz |
| `actuallyadditions:basic_coil` | `_ R _ / R I R / _ R _`, R=`restonia_crystal`, **I=`black_quartz`** | black_quartz **and** the crystal |
| `actuallyadditions:crusher` | 2 `basic_coil` + 2 `iron_casing` + 2 `restonia_crystal` + 2 flint + 4 `#c:cobblestones` | both of the above |

`black_quartz` has exactly two sources in the jar and **both are worldgen**: the `ore_black_quartz`
configured/placed feature (`count 8`, trapezoid −25…45, `stone_ore_replaceables` +
`deepslate_ore_replaceables`) attached by the `add_black_quartz` biome modifier, and the **engineer
house's chest table** (a structure's loot, which also carries an `iron_casing`). The ore's smelting,
blasting and crushing recipes all take the ore. Nothing crafts `black_quartz`.

So the 0.2.4 gap line — *"with it, the two pieces become survival-reachable"* — is false: the crystal
alone leaves `iron_casing` and `basic_coil` uncraftable, exactly as the 0.2.4 next-slice's first bullet
had it ("starting with **`black_quartz`**, which gates both"). The chain is blocked on **`black_quartz`**,
and a slice that ships only the crystal would have been dead weight.

### What changed in this dispatch — record and tooling only, no version

- `tools/recipe-blockers.json`: the Crusher's blocker is now **`restonia_crystal_source`** (was
  `restonia_crystal_growth`) and its `why` states the source above; `tools/craft_check.py`'s phase-E
  docstring + PASS line and `tools/e2e.sh`'s header comment follow the new label and drop the growth
  claim.
- `tools/audit_restonia_source.sh` added — the reproducible audit behind every line above.
- **No package, no version bump, no packed file touched.** Nothing artefact-true was left for this
  slice to ship, and a version whose only change is a comment is not a version (ruling 2026-11-21).
  0.2.4's `actuallyadditions.hmod` is byte-identical and still **1/1** under
  `verify-sdk-package.py`, whose `package matches the tree` line proves no packed byte moved.
- Still stale **inside** the delivered 0.2.4 bytes, to fix at the next real build (editing them now
  would desync the tree from the published artifact): `horizon-mod.toml`'s description ("the Crusher's
  still waits on `restonia_crystal`, which upstream grows rather than crafts") and `README.md`'s
  `blocked(restonia_crystal_growth)` label.

### Verification of this dispatch

| Step | Command | Result |
|---|---|---|
| artefact audit | `tools/audit_restonia_source.sh` | 499 lines, exit 0 — `evidence/actuallyadditions/restonia-source-audit.log` |
| recipe keys (the blocker still resolves) | `tools/check_recipe_keys.py` | `blocked actuallyadditions:crusher: restonia_crystal_source — actuallyadditions:restonia_crystal` / `2 recipe(s), 1 craftable, 1 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys-blocker-rename.log` |
| tooling syntax | `python3 -m py_compile tools/craft_check.py`, `bash -n tools/e2e.sh` | both clean |
| delivered package unchanged | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1**, `110,156 B`, sha256 `f7767eba…dd1d67`, `package matches the tree`, `packed Cargo.lock … 103 entries` |

No ladder and no in-game leg ran: there is no code or content change to build, and `craft_check.py` /
`e2e.sh` only had comments and one printed label changed (their assertions are untouched). That is why
the 0.2.4 logs remain the current ones rather than being regenerated for a version that does not exist.

### The next slice, in artefact order

1. **`black_quartz` (the ore) — the only slice that closes the chain.** It is fully data-defined
   (configured + placed feature + `add_black_quartz` biome modifier, all in the jar), and
   `ARCHITECTURE.md` §8 (2026-11-18) records worldgen as **no longer a gap**: the SDK ships
   `BiomeModifiersRegistrar`/`WorldgenHost`. In-game assertion: enter a loaded chunk, find
   `actuallyadditions:black_quartz_ore`, `ctl break` it from 3.5 blocks and assert the break's own
   `drops` record names `actuallyadditions:black_quartz`; differential: a stone block at the same depth
   drops cobblestone, and the same chunk on the **control** game (no package) has no ore. Then
   `iron_casing` from the two tags + the ore crafts ×1, and the chain continues.
2. **The Atomic Reconstructor + the crystal conversion** (the artefact's real "make a crystal" slice):
   a block entity with a 1000 CF buffer (insert `Mth.ceil(power*0.016666F)` per tick), a lens slot, a
   100-tick cycle, a 10-block beam that converts the first convertible block, and the jar's `laser/*`
   recipes. In-game assertion: place it facing a redstone-dust block, fill 1000 CF, tick 100, assert a
   `restonia_crystal` drop and the dust block gone; differential: the same shot at stone emits nothing
   and spends no CF. **Caveat:** its own recipe needs an `iron_casing`, so it is not survival-reachable
   before (1).
3. **Nothing else in the chain** — every remaining piece (`iron_casing`, `basic_coil`, the Crusher, the
   Atomic Reconstructor) keys on `black_quartz`; the GUI is `blocked(no-single-player-mod-screen)`, and
   the Double Crusher is a second machine, not a chain piece.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Slice 4 (0.2.5, 2026-11-23) — the Black Quartz Ore, the gem it drops, and the two recipes that need it

**Family:** `actuallyadditions:black_quartz_ore` (a block), `actuallyadditions:black_quartz` (the gem
it drops), the ore's loot table, its smelting/blasting/crushing recipes, the convention tags
(`c:ores/black_quartz`, `c:ores`, `c:ores_in_ground/stone`, `c:gems/black_quartz`,
`c:ingots/iron`, `c:rods/wooden`) and the `iron_casing` recipe — the chain piece the 0.2.4 gap line
named and the 0.2.5 investigation proved was gated on this one item.

- **Gap line** (`0.2.4`, "Deviations and gaps this slice adds", item 1): *"A player cannot yet obtain
  an Iron Casing or a Basic Coil in survival. Both are only craftable from `black_quartz` (worldgen)
  and `restonia_crystal` (grown)…"* — the investigation then proved the first half: `black_quartz`
  has exactly two sources, the ore and a structure chest, and nothing crafts it.
- **Why it fits `machines`:** carried content on a machines-tier port (one block, one item, one loot
  table, three recipes, the tags they key on), proven through blocks and the machine the port
  already ships — no GUI, no renderer, no new hook beyond the biome-modifier declaration.
- **Pin:** `0a875da` + mixins `e59da909`.

### Behaviour (from the jar and the source)

| Item | Upstream | This port |
|---|---|---|
| `black_quartz_ore` | `ActuallyBlocks.BLACK_QUARTZ_ORE`, `miscBlockProperties()` = `Blocks.STONE` copied, `strength(1.5f, 10f)` (`ActuallyBlocks.java:218, 275`); `mineable/pickaxe` + `needs_stone_tool` (`BlockTagsGenerator:80, 175`) | `horizon/block/black_quartz_ore.json`: template `minecraft:stone`, hardness 1.5, explosion resistance 10.0, `requires_tool`, `item: true`; the jar's blockstate/model/texture; both vanilla tags declared |
| `black_quartz` | a plain item, stack 64 | `horizon/item/black_quartz.json`: template `minecraft:stick`; the jar's model and texture |
| loot | the jar's table: silk touch → the ore, otherwise one gem with fortune's `ore_drops` and explosion decay | carried byte-identical (the port pack had already upgraded it to 26.3's `condition`/`modifier` shape and `minecraft:tool/can_silk_touch`) |
| smelting / blasting | `SimpleCookingRecipeBuilder` 0.7 xp, 200 / 100 ticks | carried byte-identical (26.3 shape: the ingredient is a plain id string) |
| crushing | `new CrushingBuilder(ore, 2 x black_quartz, 1.0f)` | already carried with the other 48 `crushing/*.json`; it could not run before because its input did not exist |
| `iron_casing` recipe | `WSW / SQS / WSW`, `W`=`#c:ingots/iron`, `S`=`#c:rods/wooden`, `Q`=black quartz | carried; the two conventions tags declared (`minecraft:iron_ingot`, `minecraft:stick` — NeoForge 1.21.x's lists, the same ones `mekanismtools`, `constructionstick` and `bibliocraft` carry) |
| worldgen | `configured_feature/ore_black_quartz` (`minecraft:ore`, size 6, `stone_ore_replaceables` + `deepslate_ore_replaceables`), `placed_feature` (count 8, `in_square`, trapezoid −25…45, `biome`), and `neoforge/biome_modifier/add_black_quartz.json` of type **`actuallyadditions:bool_config_feature_modifier`** | the two features carried byte-identical; the modifier **re-typed** — see below |

`tools/assemble_content.py` carries all of it and rewrites nothing else: the tree went from 93 to 119
files, and the only pre-existing files whose bytes moved are the creative tab (two ids added) and
`minecraft:mineable/pickaxe` (the ore added).

### The trap: the jar's biome-modifier type is inert here, and the supported route is half-implemented

Upstream attaches the placed feature with `BoolConfigFeatureBiomeModifier`
(`mod/gen/modifier/BoolConfigFeatureBiomeModifier.java`), a serializer of its own, gated on
`generateQuartz`. At this pin a data file of that type is skipped with a line
("biome modifier type … skipped: only add_features, remove_features and none are read"), so shipping
the jar's file as-is would have produced a package whose ore never generates and whose log said why —
the exact failure mode the brief named.

Two supported shapes exist, and both were measured:

| Route | Result at `0a875da` |
|---|---|
| **data file**, `"type": "neoforge:add_features"`, `biomes "#minecraft:is_overworld"`, `features "actuallyadditions:ore_black_quartz"`, `step "underground_ores"` | **read**: the content root's `biome-modifiers.json` carries it (`["actuallyadditions", "data/actuallyadditions/neoforge/biome_modifier/add_black_quartz.json", …]`) |
| **code**, `Registrar::declare_biome_modifier("add_black_quartz", BiomeModifier { … AddFeatures { … } })` in `Mod::register` | **accepted, not consumed**: with the data file absent the same file read `"modifiers":[]`; the game has no host for the declaration table at this pin (`grep declare_biome_modifier horizon/crates` finds only the SDK) |

Both are in the package: the data file is what this pin reads, the code declaration is the SDK's
documented route (so a repin that wires it needs no port change). A feature already in a step is not
added twice, so the pair is idempotent. **The `generateQuartz` flag has no equivalent here** — no
config surface exists for a content port at this pin, so the ore always generates once generation
works (recorded below).

### The generation is `blocked(configured-feature-not-registered)` — measured, not assumed

The features do not reach the registry at this pin, exactly as `silentgems` measured on 2026-11-21
(`ports/_shared/evidence/silentgems-e2e/worldgen-gap.md`). Reproduced for this package in a fresh
scratch home (full data in `evidence/actuallyadditions/worldgen-probe-0.2.5.md`):

```text
place feature actuallyadditions:ore_black_quartz 8 30 8
  -> Can't find element 'actuallyadditions:ore_black_quartz' in registry 'minecraft:worldgen/feature'
content root: worldgen/features.json       symlink to vanilla's bundle (no merged copy)
              worldgen/placed_features.json real, 212,432 B, carries actuallyadditions:ore_black_quartz
              biome-modifiers.json          carries the data-file modifier (one entry)
log: Horizon: 1 placed features cannot run and will be skipped
     Horizon:   actuallyadditions:ore_black_quartz: unknown feature reference actuallyadditions:ore_black_quartz
```

So `worldgen_entry()` classifies the placed files and not the configured ones: the content loader
merges `placed_feature/` into its bundle and leaves `configured_feature/` out, and the worldgen
loader then skips the placed feature it cannot resolve. It is the pin, not this package (the same
minimal-probe result is recorded in the silentgems evidence). The e2e therefore **asserts the gap**:
`find-block` answers 0, `place feature` answers "Can't find element", and the loader's warning is
required in the log — the phase fails the day the pin merges the features, which is the signal to
restore the generation assertion (`ctl break` a generated ore and read its `drops`).

### TDD

Two rules, each red first.

1. **The generation declaration** (`src/runtime.rs`, pure): the modifier is a namespaced id, a
   namespaced feature, a vanilla step and a biome id-or-tag. Red
   (`evidence/actuallyadditions/sdk-test-red-generation.log`, `cargo test --offline`, exit 101):

   ```text
   error[E0425]: cannot find value `VANILLA_GENERATION_STEPS` in this scope
   error[E0425]: cannot find function `black_quartz_ore_generation` in this scope
   error[E0425]: cannot find function `is_namespaced` in this scope
   ```

   Green: 34 tests (20 runtime, 14 glue), the three new ones
   `the_black_quartz_ore_generates_in_the_overworlds_underground_ores_step`,
   `the_modifier_names_namespaced_ids_and_a_vanilla_generation_step`,
   `a_name_without_a_namespace_is_refused`.
2. **The carried recipes resolve** (`tools/check_recipe_keys.py`, extended to read a cooking recipe's
   singular `ingredient`, so the two new cooking recipes are checked and not skipped). Red against
   the pre-slice tree plus the three new recipe files
   (`evidence/actuallyadditions/check-recipe-keys-red-0.2.5.log`, exit 1):

   ```text
   FAIL actuallyadditions:black_quartz_ore_blasting: unresolved actuallyadditions:black_quartz_ore
   FAIL actuallyadditions:black_quartz_ore_smelting: unresolved actuallyadditions:black_quartz_ore
   FAIL actuallyadditions:iron_casing: unresolved actuallyadditions:black_quartz, #c:rods/wooden, #c:ingots/iron
   5 recipe(s), 1 craftable, 1 blocked, 3 failure(s)
   ```

   Green (`check-recipe-keys-0.2.5.log`): `5 recipe(s), 4 craftable, 1 blocked, 0 failure(s)` — the
   Crusher stays `blocked(restonia_crystal_source)`.

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.5)

The worldgen gap (asserted):

```text
  find-block around spawn: {"block":"actuallyadditions:black_quartz_ore","count":0}
  place feature: {"chat":["Can't find element 'actuallyadditions:ore_black_quartz' in registry 'minecraft:worldgen/feature'", …]}
  blocked(configured-feature-not-registered): the placed feature is merged and skipped,
```

The data path:

```text
  block(10,100,-4) = actuallyadditions:black_quartz_ore
  at [10.5,100.0,0.0]                       # 3.5 blocks from the block's centre
  break: {"drops":{"actuallyadditions:black_quartz":1},"picked_up":{},"items_left_on_ground":1}
  break: {"drops":{"minecraft:cobblestone":1},"picked_up":{},"items_left_on_ground":1}      # stone, same stance
  held: {… "minecraft:enchantments":{"minecraft:silk_touch":1} …}
  break: {"drops":{"actuallyadditions:black_quartz_ore":1},"picked_up":{},"items_left_on_ground":1}
  furnace after 240 ticks: [null,null,{"count":1,"item":"actuallyadditions:black_quartz"}]
  blast furnace after 240 ticks: [null,null,{"count":1,"item":"actuallyadditions:black_quartz"}]
  fresh crusher: Crusher at 0,100,-1: 4440/60000 FE …
  crusher: Crusher at 0,100,-1: 3280/60000 FE …, out0 actuallyadditions:black_quartz x2, …
```

and the Iron Casing's own recipe, from `tools/craft_check.py` (same run):

```text
  recipe give actuallyadditions:iron_casing -> {"chat": ["Unlocked 1 recipe(s) for Player27983"], "ok": true}
  iron casing (4 iron ingots + 4 sticks + 1 black quartz): result {"count": 1, "item": "actuallyadditions:iron_casing", "slot": 200}
  iron casing …: inventory after the craft {"minecraft:iron_ingot": 2, "minecraft:stick": 2, "actuallyadditions:black_quartz": 2, "actuallyadditions:iron_casing": 1}
  control: gold ingots where #c:ingots/iron goes (not a member): result null
  control: iron ingots where #c:rods/wooden goes (not a member): result null
```

Every assertion can fail and was made to: `SELFTEST=ore` flips the ore's drop assertion
(`FAIL: SELFTEST ore: the ore dropped Black Quartz (the real assertion); …` + `EXIT:1`),
`SELFTEST=1` flips the machine's FE (`FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0`),
`NEGATIVE=1` flips the recipe unlock, and the same script on the unmodded game fails at its first
machine (`FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'`). The
control leg inside the run also proves the ore's ids are the package's: without it `setblock` answers
`Unknown block type 'actuallyadditions:black_quartz_ore'`.

### Ladder (0.2.5, slot `W1*/W1121-aa`, `CARGO_INCREMENTAL=0`, `BUILD_LOCAL=1`)

| Step | Result |
|---|---|
| tests | **34 passed** (20 runtime, 14 glue), `Compiling actuallyadditions v0.2.5` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings`, exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check`, exit 0 — `sdk-fmt.log` |
| package ×2 | `cargo horizon-mod build`, twice, **lock kept** — **121,206 B** both, `cmp` identical, sha256 `de43f029…62486`, **130 entries** — `sdk-build.log`, `sdk-build-second.log` |
| check | `actuallyadditions 0.2.5 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, EXIT 0 — `sdk-check.log` |
| fits, the pin | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` → **1/1** |
| in-game | `tools/e2e.sh` (`--offscreen`, launcher-built `native-0a875da-5b58559626c6`) → `PASS` + `EXIT:0` — `e2e-launcher.log` |
| counterfactual | `SELFTEST=ore` → `FAIL: SELFTEST ore: …` + `EXIT:1` — `e2e-launcher-selftest-ore.log` |
| counterfactual | `SELFTEST=1` → `FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| counterfactual | `NEGATIVE=1` → `FAIL: NEGATIVE: the Coal Generator's recipe unlocked …` + `EXIT:1` — `e2e-launcher-negative.log` |
| control | `GAME=$CONTROL_GAME` (the same Nightly, no package) → `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` → `logs=5 ok=5` |

Artifact: `actuallyadditions.hmod`, **121,206 B**, sha256
`de43f029a98fa818f59dfb7ce6cbbb777d3436497ab67195ee1bbb1805662486`, **130 entries** (0.2.4: 103;
the 26 new files + the re-typed modifier), `Cargo.lock` **packed** (8,850 B,
`a41aa744…b636fd`, its own version line moved to 0.2.5). The launcher build the leg used is
`native-0a875da-5b58559626c6`, exported to `~/.cache/horizon-e2e/0a875da/actuallyadditions/`.

### Coverage (slice 4)

| Family | State |
|---|---|
| `actuallyadditions:black_quartz_ore` block | **tested** — placed and read back; an unknown id is refused; the control game refuses `setblock` |
| the ore's loot table | **tested** — mined in survival from 3.5 blocks, the break's own `drops` names `actuallyadditions:black_quartz`; stone mined the same way drops cobblestone (differential); silk touch (a pickaxe given with the component) drops the ore and no gem |
| the ore's smelting recipe | **tested** — a furnace turns one ore into one `black_quartz`, the ore slot empties |
| the ore's blasting recipe | **tested** — a blast furnace, same assertion |
| the ore's crushing recipe | **tested** — a crusher with FE yields `black_quartz x2` and consumes the input |
| `c:ores/black_quartz`, `c:ores`, `c:ores_in_ground/stone`, `c:gems/black_quartz` | **declared**; the in-game proof of the tag files themselves is positional (a `c:` tag has no command readout), and `check_recipe_keys.py` refuses an empty tag — the ids are the ones the Crushing recipe and the quark consumers name |
| `c:ingots/iron`, `c:rods/wooden` | **tested** — the `iron_casing` recipe unlocks and crafts from tag members; gold ingots in the iron cells and coal in the rod cells stay empty |
| `actuallyadditions:iron_casing` recipe | **tested** — crafts one casing from 4 ingots + 4 sticks + 1 gem, all nine consumed, grid empty |
| the ore's worldgen (configured + placed feature + biome modifier) | **blocked(configured-feature-not-registered)** — the placed feature is merged and skipped, `place feature` answers "Can't find element … in registry 'minecraft:worldgen/feature'", the data-file modifier is read; asserted in the leg |
| the `generateQuartz` config flag | **not ported** — no config surface for a content port at this pin; the ore is always on |

### Deviations and gaps this slice adds

1. **The ore does not generate at this pin**, `blocked(configured-feature-not-registered)` (the pin,
   not the package; silentgems measured the same on 2026-11-21). The features and the modifier stay
   in the package — they are the mod's data and the modifier is already the shape this loader reads —
   and the e2e asserts the gap so a merge is noticed.
2. **`generateQuartz` has no equivalent.** Upstream's flag lives in its own config; a content port has
   no settings surface here, so the ore always generates.
3. **The jar's `bool_config_feature_modifier` is re-typed** to `neoforge:add_features` (same biomes,
   feature and step). Shipping the jar's type would have been silently inert.
4. **`c:storage_blocks/black_quartz` is not carried**: its only member is the Black Quartz Block,
   which is another slice; a tag naming an id this package does not declare is dropped, and
   `check_recipe_keys.py` refuses a tag with no values.
5. **`c:ingots/iron` = `minecraft:iron_ingot`, `c:rods/wooden` = `minecraft:stick`** — NeoForge
   1.21.x's generated lists, which is what the campaign's other ports carry; a 1.21.1 pack's tags
   would also hold modded metals/rods, and 26.3 has none to name.

### Harness facts measured while getting there

1. **`ctl enchant` does not reach the break's tool on this pin.** The enchantment shows in
   `ctl inventory`'s `held` immediately after the command, but the `held` record inside `ctl break`'s
   reply carries only `minecraft:damage`, and the loot table's silk-touch branch does not fire —
   measured twice, at 3.5 and 2.5 blocks. A pickaxe *given* with the component
   (`give @s minecraft:iron_pickaxe[minecraft:enchantments={"minecraft:silk_touch":1}]`) keeps it
   through the same break and drops the ore block. The silk-touch leg uses the `give` form.
2. **A generator feeding adjacent crushers reads 0 FE.** Its buffer is emptied every tick into its
   neighbours, so "wait for the generator to charge the new crusher" must watch the *crusher*
   (`info 0 100 -1`), not the generator — the first version of the leg failed on `0/60000 FE` while
   the machine was burning normally.
3. **The content root's `biome-modifiers.json` is the readout of which modifier route works**:
   the data file appears there, the `declare_biome_modifier` call does not (0.2.5 measured both).
4. **A content package's configured features are the half that is missing** (`worldgen/features.json`
   stays a symlink while `placed_features.json` is a real merged file). The probe that produced this
   is `evidence/actuallyadditions/worldgen-probe-0.2.5.md`.

### Upstream defects fixed

None found in this slice: the loot table, the three recipes, the tags and the block properties all
match what the mod's own code says.

**Changelog (0.2.5):**

> **0.2.5 — the Black Quartz Ore, the gem it drops, and the chain it unlocks.** Adds the ore block
> (the jar's blockstate, model, texture, `minecraft:stone`-copied properties), the `black_quartz`
> gem, the ore's loot table (silk touch → the ore, otherwise one gem with fortune's `ore_drops`),
> its smelting, blasting and crushing recipes, the `c:ores`/`c:gems` tags, the `c:ingots/iron` and
> `c:rods/wooden` tags and the Iron Casing's own recipe, so a casing now crafts from four iron
> ingots, four sticks and one gem where 0.2.4 could not craft one at all. The worldgen is carried
> (configured + placed feature) with the jar's custom `bool_config_feature_modifier` re-typed to
> the platform's `neoforge:add_features`, and `Mod::register` also declares it through the SDK's
> `declare_biome_modifier`; the ore's *generation* is `blocked(configured-feature-not-registered)`
> at this pin (a content package's configured features do not reach the feature registry — the
> same gap silentgems measured), and the e2e asserts the gap. 130 entries, 121,206 B, sha256
> `de43f029…62486`.

## Slice 5 (0.2.6, 2026-11-23) — the Atomic Reconstructor and its laser conversion

**Family:** the **Atomic Reconstructor** — a facing block entity with a 300,000 CF buffer, a lens
slot, a 100-tick cycle and a ten-block beam that converts the 3×3 plane it hits — plus the jar's
block-reachable `laser/` recipes (`crystalize_restonia_crystal`, `soul_sand`, `nether_wart`), the
`restonia_crystal` item, the `c:dusts/redstone` and `c:sands` tags and the machine's own crafting
recipe. This is the 0.2.5 next-slice, whose precondition (an `iron_casing`, hence `black_quartz`)
0.2.5 met.

- **Gap line** (`Next slice (0.2.6)`): *"the Atomic Reconstructor and its laser conversion — the
  artefact's real 'make a crystal' mechanic — because it is the only remaining route to
  `restonia_crystal`, which the Crusher's recipe and `basic_coil` still wait on"*.
- **Why it fits `machines`:** a block entity, an energy capability, a container and a custom recipe
  type — no GUI (still `blocked(no-single-player-mod-screen)`), no renderer, no new kind of hook.
- **Pin:** Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`, mixins `e59da909`.

### The conversion rules as the artefact states them

The brief's "1,000 CF buffer / charge 1,000 / tick 100" is the **shot**, not the buffer. Read from
`TileEntityAtomicReconstructor`, `MethodHandler.invokeReconstructor` / `invokeConversionLens`,
`LensConversion`, `LaserRecipe` and `CommonConfig` (upstream `cd9d9c6`):

| Rule | Value | Source |
|---|---|---|
| buffer | `new CustomEnergyStorage(power, Mth.ceil(power·0.016666F), 0)`, `RECONSTRUCTOR_POWER` default **300 000**; insert **5 000** a call, extract 0 | `TileEntityAtomicReconstructor.java:50-55`, `CommonConfig.java:54` |
| shot gate | `ENERGY_USE = **1 000**` CF, paid **before** the beam walks | `TileEntityAtomicReconstructor.java:43`, `MethodHandler.java:283-289` |
| conversion cost | the recipe's own `energy` (40 for `#c:dusts/redstone`), paid **again** per converted block | `MethodHandler.java:231` |
| cycle | `currentTime` 0 → 100, one decrement a tick, shot at 0: one attempt per **100** ticks; a starved attempt still waits the 100 | `TileEntityAtomicReconstructor.java:129-138` |
| redstone | `isRedstonePowered` freezes the cycle (no decrement, no shot); `isPulseMode` is the mod's own mode | same |
| lens | slot 0, an `ILensItem`; empty → `lensDefaultConversion` | `getLens` |
| distance | the default conversion lens reaches **10** blocks | `LensConversion.getDistance` |
| beam | `i` in 1..=10: convert the **3×3 plane** around `pos + facing·i` (range 1, zero on the facing axis), then stop if that block is not air (`invoke` returns `!isAir`), else continue | `MethodHandler.java:281-303`, `:177-275` |
| which blocks convert | **every** non-air block of the plane, in `x` → `z` → `y` order, while the remaining CF covers its recipe (the `break` leaves only the innermost loop) | `MethodHandler.java:203-237` |
| which recipe wins | the first recipe of the type whose ingredient matches the **block's item** (`new ItemStack(state.getBlock())`): `CONVERSION_LASER_RECIPES.stream().findFirst()`; the pin lists a type's recipes in file order | `LaserRecipe.java:94` |
| result | a `BlockItem` result is **placed**; any other result is spawned as an item at the block's centre and the block becomes air | `MethodHandler.java:234-240` |
| comparator | `clamp(energy / 20 000, 0, 15)` | `BlockAtomicReconstructor.getAnalogOutputSignal` |
| saved state | `Energy` in the block save; `CurrentTime` is sync-only (a reload restarts the cycle) | `writeSyncableNBT` |

Consequences the leg asserts: a shot at **1 040** CF (1 000 gate + 40 conversion) converts one
redstone wire and leaves 0; at **1 039** it pays the gate (39 left) and converts nothing; at stone
it pays 1 000, converts nothing and leaves 40; at **1 120** it converts *two* wires in the plane
(40 left) and at 1 040 only the first; the beam converts a block **ten** away and not one eleven
away.

### What is carried, and why only three `laser/` files

The jar has 22 `laser/` recipes. Only three can fire through the **block** half of the beam with
this package: `crystalize_restonia_crystal` (`#c:dusts/redstone` → the crystal, 40), `soul_sand`
(`#c:sands` → soul sand, 20 000) and `nether_wart` (`minecraft:red_mushroom` → nether wart,
150 000). The others name items or blocks this package does not ship (the other crystals, the
lenses, the relays, the ethetic blocks) or turn an **item** into an item (`leather ← rotten flesh`,
`prismarine_shard ← quartz`), which is the beam's item-entity half — a next slice, not this one
(the pin *can* enumerate entities, `LevelRef::entities_in`).

Both carried vanilla results are `BlockItem`s, so upstream's block branch **places** them: the sand
becomes soul sand in place, and the red mushroom becomes a `minecraft:nether_wart[age=0]` crop (the
leg gives that cell soul sand below, or the crop would pop and drop).

### TDD

Two reds, each quoted.

1. **The pure rules** (`src/runtime.rs`, tests first):
   `evidence/actuallyadditions/sdk-test-red-laser.log`, `cargo test --offline` exit 101:

   ```text
   error[E0422]: cannot find struct, variant or union type `Reconstructor` in this scope
      --> src/runtime.rs:405:33
   error[E0425]: cannot find value `RECONSTRUCTOR_TICKS` in this scope
      --> src/runtime.rs:439:41
   ```

   Green: **47 tests** (20 runtime, 8 reconstructor, 19 glue), including
   `the_shot_costs_a_thousand_and_the_recipe_its_own`, `the_cycle_is_about_a_hundred_ticks`,
   `redstone_freezes_the_cycle`, `the_comparator_steps_every_twenty_thousand`,
   `the_plane_is_three_by_three_across_the_beam`,
   `a_placed_reconstructor_faces_away_from_the_player`, `a_laser_recipe_is_read_from_the_jars_json`
   and `a_restored_reconstructor_is_clamped_into_its_buffer_and_cycle`.
2. **The carried recipes resolve** (`tools/check_recipe_keys.py`, which now also reads
   `recipe/laser/*.json` and checks each result id): red against the tree with the old blocker still
   in place (`evidence/actuallyadditions/check-recipe-keys-red-0.2.6.log`, exit 1):

   ```text
   FAIL     actuallyadditions:crusher: blocked(restonia_crystal_source) is stale — the recipe resolves now; remove the blocker and prove it in game
   6 recipe(s), 9 craftable, 1 blocked, 1 failure(s)
   exit=1
   ```

   Green (`check-recipe-keys.log`): `6 recipe(s), 9 craftable, 0 blocked, 0 failure(s)`, with the
   three laser recipes `ok … every ingredient and its result resolve (laser)`.

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.6)

```
  placed at 2,100,14 from the north looking south: actuallyadditions:atomic_reconstructor[facing=north]
  Atomic Reconstructor at 2,100,14: 0/300000 CF (comparator 0, facing north, cycle 92/100, lens default, sight nothing, t=4080)
  generator-charged: Atomic Reconstructor at 0,100,16: 540/300000 CF (comparator 0, facing east, … t=4145)
  block(3,100,18) = minecraft:redstone_wire[east=none,north=none,power=0,south=none,west=none]
  charged actuallyadditions:atomic_reconstructor at 2,100,18: 0 -> 1040 CF (inserted 1040)
  charged: Atomic Reconstructor at 2,100,18: 1040/300000 CF (… sight minecraft:redstone_wire -> actuallyadditions:restonia_crystal @ 40 CF, t=4174)
  block(3,100,18) = air
  restonia crystals on the ground: 1
  after the shot: Atomic Reconstructor at 2,100,18: 0/300000 CF (… t=4303)
  stone: Atomic Reconstructor at 6,100,18: 1040/300000 CF (… sight minecraft:stone -> nothing, t=4328)
  block(7,100,18) = minecraft:stone
  after the shot: Atomic Reconstructor at 6,100,18: 40/300000 CF (…)
  1,039 CF after the shot: Atomic Reconstructor at 10,100,18: 39/300000 CF (… sight minecraft:redstone_wire -> … @ 40 CF)
  block(10,100,22) = air
  a block ten away in the beam converted
  block(11,100,23) = minecraft:redstone_wire[…]
  eleven away, after the shot: Atomic Reconstructor at 0,100,23: 40/300000 CF (…)
  block(15,100,13) = air
  block(15,100,15) = air
  both plane blocks converted: 2 crystal(s)
  block(15,100,13) = air
  block(15,100,15) = minecraft:redstone_wire[…]
  cycle without redstone: 93 -> 66
  cycle beside a redstone block: 58 -> 58
  cycle after the redstone was removed: 58 -> 29
  before the break: Atomic Reconstructor at 22,100,14: 5000/300000 CF (…)
  break: {"drops":{"actuallyadditions:atomic_reconstructor":1},"picked_up":{},"items_left_on_ground":1}
  the drop's Item tag: {… "minecraft:block_entity_data": {id: "actuallyadditions:atomic_reconstructor_block_entity", energy: 5000} …}
  payload: 5000 CF
  placed again: Atomic Reconstructor at 20,100,14: 5000/300000 CF (…)
  sand: minecraft:sand -> minecraft:soul_sand @ 20000 CF
  block(3,100,10) = minecraft:soul_sand
  block(7,100,10) = minecraft:red_mushroom
  red mushroom: minecraft:red_mushroom -> minecraft:nether_wart @ 150000 CF
  block(7,100,10) = minecraft:nether_wart[age=0]
```

The crafting leg (`tools/craft_check.py`, same run) records the chain closing:

```
  recipe give actuallyadditions:atomic_reconstructor -> {"chat": ["Unlocked 1 recipe(s) …"], "ok": true}
  give actuallyadditions:restonia_crystal -> {"given": 1, "ok": true}
  atomic reconstructor (4 iron ingots + 4 redstone + 1 iron casing): result {"count": 1, "item": "actuallyadditions:atomic_reconstructor", "slot": 200}
  atomic reconstructor …: inventory after the craft {"minecraft:iron_ingot": 2, "minecraft:redstone": 2, "actuallyadditions:iron_casing": 1, "actuallyadditions:atomic_reconstructor": 1}
  control: gold ingots where #c:ingots/iron goes (not a member): result null
  control: glowstone dust where #c:dusts/redstone goes (not a member): result null
  crusher (2 restonia + 2 flint + 2 cobblestone + 2 coils + 1 casing): result {"count": 1, "item": "actuallyadditions:crusher", "slot": 200}
  crusher …: inventory after the craft {"actuallyadditions:restonia_crystal": 2, "minecraft:flint": 2, "minecraft:cobblestone": 2, "actuallyadditions:basic_coil": 2, "actuallyadditions:iron_casing": 1, "actuallyadditions:crusher": 1}
```

### Ladder (0.2.6, slot `W1121-aa`, `CARGO_INCREMENTAL=0`, `BUILD_LOCAL=1`)

| Step | Result |
|---|---|
| tests | **47 passed** (20 runtime, 8 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.6` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings`, exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check`, exit 0 — `sdk-fmt.log` |
| package ×2 | `cargo horizon-mod build`, twice, **lock kept** — **140,841 B** both, `cmp` identical, sha256 `414c0ab9…d52b`, **150 entries** — `sdk-build.log`, `sdk-build-second.log` |
| check | `actuallyadditions 0.2.6 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, EXIT 0 — `sdk-check.log` |
| fits, the pin | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` → **1/1** |
| in-game | `tools/e2e.sh` (`--offscreen`, the launcher build of this package) → `PASS` + `EXIT:0` — `e2e-launcher.log` |
| counterfactual | `SELFTEST=laser` → `FAIL: SELFTEST laser: the beam made a crystal (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-laser.log` |
| counterfactual | `SELFTEST=1` → `FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=ore` → `FAIL: SELFTEST ore: …` + `EXIT:1` |
| counterfactual | `NEGATIVE=1` → `FAIL: NEGATIVE: the Coal Generator's recipe unlocked …` + `EXIT:1` |
| control | `GAME=$CONTROL_GAME` (the same Nightly, no package) → `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` → `logs=6 ok=6` |

Artifact: `actuallyadditions.hmod`, **140,841 B**, sha256
`414c0ab9ad5da8795420261ecd04720d5cc030c76d001832d395d2c34693d52b`, **150 entries** (0.2.5: 130),
`Cargo.lock` **packed** (8,850 B; its own version line moved to 0.2.6). The launcher build is
`native-0a875da-226ec8d9c3ec` (its `native-mods.json` names `actuallyadditions 0.2.6`) and the leg's
first line names the sha above, so the game ran the delivered archive.

### Coverage (slice 5)

| Family | State |
|---|---|
| the reconstructor block (placement, state, drop) | **tested** — `ctl place` from a known yaw gives `facing=north` (upstream's `getNearestLookingDirection().getOpposite()`); `setblock` reads back each facing; a survival break drops the machine itself |
| its 300,000 CF buffer + the energy push | **tested** — a coal generator beside it charges it (`0 → 540 CF` and climbing); the buffer is a real block energy capability (the harness charger fills it through it) |
| the 100-tick cycle and the redstone stop | **tested** — `cycle 92 → 65` unpowered, `59 → 59` beside a redstone block, `59 → 32` after removing it |
| a 1,000 CF shot + the recipe's own energy | **tested** — 1,040 converts and leaves 0; 1,039 leaves 39 and converts nothing; stone leaves 40 |
| the 10-block beam | **tested** — a wire ten away converts, one eleven away stays |
| the 3×3 plane, in order | **tested** — two wires both convert at 1,120 (40 left), only the first at 1,040 |
| the result rule (block placed, item dropped) | **tested** — the crystal is an item drop (`restonia crystals on the ground: 1`); soul sand and nether wart are placed (`soul_sand`, `nether_wart[age=0]`) |
| `laser/crystalize_restonia_crystal` (40) | **tested** — the shot above, plus the readout's `sight … -> …restonia_crystal @ 40 CF` |
| `laser/soul_sand` (20,000) | **tested** — a sand block becomes soul sand, the buffer empties |
| `laser/nether_wart` (150,000) | **tested** — a red mushroom becomes a nether wart crop, the buffer empties |
| the machine's own recipe (`IRI / RCR / IRI`) | **tested** — crafts one from 4 `#c:ingots/iron`, 4 `#c:dusts/redstone` and a casing, all nine consumed; gold ingots and glowstone dust in those cells stay empty |
| `c:dusts/redstone`, `c:sands` | **tested via their consumers** — the reconstructor's recipe and the soul-sand conversion use them; a non-member (glowstone dust) fails the craft |
| `restonia_crystal` item | **tested** — give-able, dropped by the beam, and the Crusher's recipe's last key |
| the Crusher's recipe (chain closed) | **tested** — crafts one machine from 2 crystals + 2 flint + 2 cobblestone + 2 coils + 1 casing, all consumed |
| break keeps the buffer | **tested** — the drop's payload is `{id, energy: 5000}`, placing it again reads 5,000 |
| the lens slot | **not ported** — no item in this package is an `ILensItem` (1.3.26's only lens source is the reconstructor's own four-recipe lens cycle, which needs a lens to start); the slot is declared, nothing can fill it, and the click refuses every item |
| the beam's item-entity half | **closed by slice 6 (0.2.7)** — upstream also converts dropped items in the box between the machine and the hit block; the pin enumerates them (`LevelRef::entities_in`). See "Slice 6" below |
| comparator output | **not ported** — the strength is computed and printed; no `has_analog_output` hook is declared |
| the beam's visual + the block-break level event | **not ported** — no packet, no `levelEvent(2001)`; the conversion is state-only |
| the `reset/` recipe type and pulse mode | **not carried** — AA's own `actuallyadditions:reset` recipe type and the pulse-mode component are another slice (a wrench/redstone-control family) |

### Deviations and gaps this slice adds

1. **The cycle is persisted; upstream's is sync-only.** `currentTime` rides the block entity's saved
   compound, so a reload resumes the cycle where upstream restarts it at 0. A 100-tick timer; the
   item payload still carries the buffer only (upstream's loot copies the energy component).
2. **No pulse mode, no wrench, no side configuration.** A redstone signal freezes the cycle (as
   upstream), but the mod's own pulse mode and its `tryToggleRedstone` click are not ported.
3. **The lens slot is inert** (see coverage): nothing in the package is a lens.
4. **The beam converts blocks only** (the item half is the next slice).
5. **The comparator is printed, not wired** (same gap as the other two machines).
6. **The `c:` tag members are NeoForge 1.21.x's lists**, as for the earlier tags: `c:dusts/redstone`
   = `minecraft:redstone`; `c:sands` = sand, red sand, suspicious sand.
7. **`/actuallyadditions charge <pos> <amount>` is a harness addition** (the same shape as
   `/refinedstorage charge`): it brings a machine's buffer to `amount` through its energy
   capability, because a single-player world has no charger and a generator moves only 80 FE a tick.
   Level 2, like the readout.

### Harness facts measured while getting there

1. **`give` lands on the next tick.** `ctl command "give …"` followed immediately by `ctl select
   <item>` answers `no <item> in the inventory`; four ticks between them fixes it (this cost the
   first 0.2.6 run, at the silk-touch leg).
2. **An assignment from a `grep` that finds nothing is fatal under `set -euo pipefail`.** A helper
   that looks for an earlier chat reply must end `|| true`.
3. **A laser result that is a `BlockItem` is placed, not dropped** — `minecraft:soul_sand` and
   `minecraft:nether_wart` both are, and a nether wart crop needs soul sand below or it pops.
4. **`redstone_wire` is the block whose item is `minecraft:redstone`** — that is what makes
   `#c:dusts/redstone` convertible at all (`new ItemStack(state.getBlock())`).
5. **The `e2e` instance's recorded version had been pruned** (`native-0a875da-8a31482892f4` was gone),
   so `launcher native-build` died at "Installing the build" with `os error 2`. A dedicated instance
   (`HORIZON_E2E_INSTANCE=actuallyadditions-e2e`) builds and installs cleanly.

The two throwaway probes behind facts 1 and 3 are kept as evidence
(`ports/_shared/evidence/actuallyadditions/probe-ctl-exit.sh`, `probe-give-select.sh`): they launch the
package's game on a scratch home and print each `ctl` call's exit code and reply.

### Upstream defects fixed

None found in this slice: the cycle, the gate, the conversion and the plane order are what the code
says they are. The brief's "1,000 CF buffer" was a misreading of `ENERGY_USE`, recorded above.

**Changelog (0.2.6):**

> **0.2.6 — the Atomic Reconstructor and its laser conversion.** Adds the facing machine (the jar's
> blockstate, model, texture, loot table and `IRI/RCR/IRI` recipe), a 300,000 CF buffer (5,000 a
> call in, nothing out), a 100-tick cycle a redstone signal freezes, and a ten-block beam that pays
> 1,000 CF per shot plus the converting recipe's own energy and converts the 3×3 plane it hits,
> placing a block result or dropping an item one. Three of the jar's `laser/` recipes can fire
> through that block half and ship: `#c:dusts/redstone` → Restonia Crystal (40 CF), `#c:sands` → soul
> sand (20,000) and red mushroom → nether wart (150,000), with the `c:dusts/redstone` and `c:sands`
> tags. The crystal closes the chain: the Crusher's own recipe now crafts, and
> `tools/recipe-blockers.json` is empty. A `/actuallyadditions info` line reads the buffer, facing,
> cycle and the block the beam sights; a `/actuallyadditions charge <pos> <amount>` harness command
> brings a buffer to a level through its energy capability. 150 entries, 140,841 B, sha256
> `414c0ab9…d52b`.

## Next slice (0.2.7)

**Family:** the **beam's item-entity half** — the other thing `invokeConversionLens` converts — plus
the two `laser/` recipes that can only work on items (`minecraft:rotten_flesh` → leather 20,000,
`minecraft:quartz` → prismarine shard 30,000).

- **Gap line** (this slice's coverage table): *"the beam's item-entity half — not ported (next
  slice): upstream also converts dropped items in the box between the machine and the hit block; the
  pin can enumerate them (`LevelRef::entities_in`)"*.
- **Shape:** no new block or item; `LevelRef::entities_in` over upstream's AABB (`tile.pos` to
  `hitBlock + 1`, expanded along the facing), `host.item_entity` to read a dropped stack, the same
  `find_laser_recipe`, `item_entity_set_stack` (or a discard + `spawn_item`) to replace it, and
  upstream's `aa_cnv` marker so a converted item is not converted again.
- **In-game assertion that can fail:** drop a redstone *item* (not a wire block) in the beam,
  charge 1,040, tick 100, assert the item entity becomes a `restonia_crystal` and the count is
  conserved; differential: the same item outside the box stays redstone.
- **Out of scope:** the GUI, the Empowerer, the Double Crusher, lens items, the ore's generation
  (`blocked(configured-feature-not-registered)`), pulse mode/wrench.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices


## Slice 6 (0.2.7, 2026-11-23) — the beam's item-entity half

**Family:** the **dropped items the Atomic Reconstructor's beam converts** — the other thing
`MethodHandler.invokeConversionLens` does — plus the two `laser/` recipes whose terms only ever
match an item (`minecraft:rotten_flesh` → `minecraft:leather` at 20,000 CF, `minecraft:quartz` →
`minecraft:prismarine_shard` at 30,000 CF).

- **Gap line** (the slice-5 coverage table, `notes.md:1645`): *"the beam's item-entity half — not
  ported (next slice): upstream also converts dropped items in the box between the machine and the
  hit block; the pin can enumerate them (`LevelRef::entities_in`), but this slice is the block half"*.
  The 0.2.6 plan had recorded it as `blocked(no-entity-box-query)`; `LevelRef::entities_in` is that
  query, so the blocker is gone.
- **Why it fits `machines`:** no new block, item, model, texture or hook — a rule inside the machine
  this port already ships (its beam), proven through it.
- **Pin:** Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`, mixins
  `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`.

### The item-half rules as the artefact states them (`MethodHandler.invokeConversionLens`)

| Rule | Value | Source |
|---|---|---|
| **order** | the **block loop runs first**, then the **item loop**, both inside one `invoke` call — and `invoke` is called once per beam step, so the item half runs at *every* step with a box that grows as the beam walks | `MethodHandler.java:177-275` (blocks), `:277-314` (items), `:281-303` (the walk) |
| box | `new AABB(tile.x, tile.y, tile.z, hit.x + 1, hit.y + 1, hit.z + 1)`, then `.inflate(0.02, 0.02, 0.02)` and `.expandTowards(dir)` with the facing's normal — from the machine's own block corner to the hit block's far corner, 0.02 of slack, plus **one block further along the beam** | `:277-280` |
| which entities | `getEntitiesOfClass(ItemEntity.class, aabb)` — dropped items only, in the level's entity-list order | `:281` |
| skip | `!item.isAlive() \|\| stack.isEmpty() \|\| item.getPersistentData().getBoolean("aa_cnv")` | `:283` |
| recipe | the same `LaserRecipe.getRecipeForStack(stack)` the block half uses — first match, engine order | `:285`, `LaserRecipe.java:94` |
| how many | `Math.min(tile.getEnergy() / recipe.getEnergy(), stack.getCount())` — the buffer is the one left after the shot's 1,000 CF gate | `:290` |
| the conversion | `item.discard()`; a leftover is re-spawned as a new input entity at the item's own x/y/z; the result is spawned there with `setCount(itemsPossible)` and marked `aa_cnv`; `extractEnergy(recipe.energy × itemsPossible)` | `:291-308` |
| how many entities | `break` after the first entity that converts — **one item entity per `invoke`**, i.e. per beam step (up to 10 a shot) | `:310` |
| result count | `outputCopy.setCount(itemsPossible)` **overwrites** the recipe result's own count (all five carried results declare 1, so nothing observable changes) | `:302` |
| return | `!hitState.isAir()` — the block half's stop condition; the item half is not gated on the beam hitting air | `:314` |

Consequences the leg asserts: at 1,040 CF the buffer pays the gate and leaves 40, which is one 40 CF
conversion — one dropped redstone becomes one Restonia Crystal and the buffer is empty; a stack of
three converts **one** and leaves two; an item outside the box is untouched while the shot still
spends its 1,000 CF gate (40 left).

### The marker: upstream's `aa_cnv` as a vanilla scoreboard tag

Upstream stores a boolean in the entity's NeoForge **persistent data**. The pin has no
entity-persistent-data surface, so the port uses the closest exact analogue: the entity's **vanilla
scoreboard tags** (`Entity.addTag`/`getTags`, API 386 — saved with the entity and readable in game as
`/data get entity … Tags`), under upstream's own key, `aa_cnv`. The marker goes on the **output**
entity only, so a converted item is never converted again by a later beam step (whose box has grown)
or a later shot, while the leftover of a partially converted stack stays convertible — which is what
upstream's flag does too.

### TDD

The three rules were written as failing tests first (functions absent, so the red is the compile
error — the 0.2.5/0.2.6 precedent), `evidence/actuallyadditions/sdk-test-red-item-half.log`:

```text
error[E0425]: cannot find function `item_scan_box` in this scope
error[E0425]: cannot find function `items_possible` in this scope
error[E0425]: cannot find function `may_convert` in this scope
error[E0425]: cannot find value `CONVERTED_MARKER` in this scope
error: could not compile `actuallyadditions` (lib test) due to 19 previous errors
```

Green: **50 passed** (20 runtime, 11 reconstructor — three new: `the_item_box_runs_from_the_machine_to_a_block_past_the_hit_block`,
`a_shot_converts_as_many_items_as_the_recipe_and_the_buffer_allow`,
`a_converted_item_carries_the_marker_and_is_not_converted_again`).

The content half's rule is `tools/check_recipe_keys.py`, which now reads both new `laser/` files:
`6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)` (`check-recipe-keys.log`). It cannot be red for
two vanilla terms — the in-game leg is this family's red (below).

### Upstream defects fixed

**1. The item box is inverted on three of the six facings.** `AABB(x1, y1, z1, x2, y2, z2)` does not
order its corners and vanilla's `Level.getEntitiesOfClass` only matches an entity whose box
`intersects` it — and `AABB.intersects` is false for a box whose minimum is above its maximum.
Upstream passes the machine's position as the **minimum** and `hitBlock + 1` as the **maximum**
(`MethodHandler.java:278`), so on a `north`, `west` or `down` beam (`hit.x + 1 < tile.x`) the box is
inverted and **nothing** matches: those three facings convert no dropped item at all, while `east`,
`south` and `up` do. `expandTowards` moves a *raw* face afterwards and cannot rescue it.

- **Proved from the artefact:** the constructor takes the two corners in that order and `AABB`
  performs no normalisation; `Level.getEntitiesOfClass` filters with `aabb.intersects`.
- **What the port does instead:** `runtime::item_scan_box` orders the two corners and extends the
  face **away from the machine** by one block — byte-for-byte upstream's own numbers for
  `east`/`south`/`up`, and the mirrored, working case for the other three. The pin's `entities_in`
  documents a minimum above its maximum as the same box with the two swapped, so the port also
  passes an ordered box on purpose.
- **What a user notices:** a dropped item in a north-, west- or down-facing beam converts, instead
  of the machine quietly doing nothing to items on three sides.
- Worth an upstream report: yes (a three-line fix in `invokeConversionLens`); not filed — the
  orchestrator decides that.

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.7)

```
package: …/actuallyadditions.hmod, 145399 bytes, sha256 7d35fc805d9e49c05d2cc4e30a1a5f1cc261da0a6d0bf6d3b18b8a5d909bc5e4
== the beam's item half: dropped items convert, one entity per step (0.2.7) ==
  the dropped item settled: [{"item":"minecraft:redstone","count":1,"pos":[2.5,100.0,20.5],"distance":4.0}]
  after the shot: 1 restonia crystal(s), 0 redstone left
  the converted item's tags: {"chat":["Restonia Crystal has the following entity data: [\"aa_cnv\"]"],"ok":true}
  after the item shot: Atomic Reconstructor at 0,100,20: 0/300000 CF (comparator 0, facing east, cycle 55/100, lens default, sight nothing, t=6097)
  the differential's item (two blocks across the beam): [{"item":"minecraft:redstone","count":1,"pos":[8.5,100.0,22.5],"distance":4.47213595499958}]
  the differential after its shot: Atomic Reconstructor at 6,100,20: 40/300000 CF (comparator 0, facing east, cycle 57/100, lens default, sight nothing, t=6248)
  three redstone at 1,040 CF: 1 crystal(s), 2 redstone left
  the leftover input's tags: {"chat":["Found no elements matching Tags"],"ok":true}
  a west-facing beam's dropped item: 1 crystal(s), 0 redstone left
  rotten flesh -> leather at 20,000 CF: 1 leather, 0 rotten flesh left
  quartz -> prismarine shard at 30,000 CF: 1 shard(s), 0 quartz left
```

Every assertion can fail and was made to: `SELFTEST=item` flips the first one ("the beam converts no
dropped item"), which passes only on a machine without the item half —
`FAIL: SELFTEST item: the beam converted the dropped item (the real assertion); the flipped
assertion 'it converts none' fails, so the real one can fail` + `EXIT:1`
(`e2e-launcher-selftest-item.log`). The differential inside the run is the same redstone two blocks
across the beam (untouched, and the shot spends only its gate), and the west leg is the defect fix's
own assertion.

### Ladder (0.2.7, slot `W1121-aa`, `CARGO_INCREMENTAL=0`, `BUILD_LOCAL=1`)

| Step | Result |
|---|---|
| tests | **50 passed**, 0 failed (20 runtime, 11 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.7` from `cargo clean -p actuallyadditions` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings`, exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check`, exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` — `6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| content carry | re-ran `tools/assemble_content.py` + `tools/stamp_license.py`: the two new `laser/` files are the only bytes that moved (140 files before, 142 after; `sha256sum` diff) |
| package ×2 | `cargo horizon-mod build`, twice, **lock kept** — **145,399 B** both, `cmp` identical, sha256 `7d35fc80…bc5e4`, **152 entries** — `sdk-build.log`, `sdk-build-second.log` |
| check | `actuallyadditions 0.2.7 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 145399 bytes, EXIT 0 — `sdk-check.log` |
| fits, the pin | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` → **1/1** (packed lock, tree match, runtime hash, skills gate) |
| in-game | `tools/e2e.sh` (`--offscreen`, launcher build `native-0a875da-7ac0c4c42e48`) → `PASS` + `EXIT:0` — `e2e-launcher.log` |
| counterfactual | `SELFTEST=item` → `FAIL: SELFTEST item: …` + `EXIT:1` — `e2e-launcher-selftest-item.log` |
| counterfactual | `SELFTEST=laser` → `FAIL: SELFTEST laser: …` + `EXIT:1` |
| counterfactual | `SELFTEST=1` → `FAIL: SELFTEST flipped: the placed machine kept 2540 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=ore` → `FAIL: SELFTEST ore: …` + `EXIT:1` |
| counterfactual | `NEGATIVE=1` → `FAIL: NEGATIVE: the Coal Generator's recipe unlocked …` + `EXIT:1` |
| control | `GAME=$CONTROL_GAME` (the same Nightly, no package) → `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` → `logs=7 ok=7` |

Artifact: `actuallyadditions.hmod`, **145,399 B**, sha256
`7d35fc805d9e49c05d2cc4e30a1a5f1cc261da0a6d0bf6d3b18b8a5d909bc5e4`, **152 entries** (0.2.6: 150; the
two new recipes), `Cargo.lock` **packed** (8,850 B, `57fd9355…f998b`, its own version line moved to
0.2.7, and the copy in the archive equals the tree's). `src/runtime.rs` gained the three item-half
rules and `src/support.rs` the conversion; `src/lib.rs` is unchanged.

### Coverage (slice 6)

| Family | State |
|---|---|
| the beam's item half (a dropped item in the box converts) | **tested** — one dropped redstone becomes one Restonia Crystal, count conserved, buffer 1,040 → 0 |
| the marker (`aa_cnv`) | **tested** — the output entity's `Tags` read `["aa_cnv"]`; the leftover of a converted stack has none |
| one entity per beam step, one stack per entity | **tested** — a stack of three at 1,040 CF converts exactly one (40 CF leaves nothing for a second) and two stay |
| the box's extent (the differential) | **tested** — the same item two blocks across the beam stays redstone and the shot spends only its gate |
| all six facings | **tested for `east` and `west`** — a west-facing beam converts its item (upstream's inverted-box defect fixed); `north`/`south`/`up`/`down` are the same code path, unit-tested for the box |
| `laser/leather` (rotten flesh → leather, 20,000 CF) | **tested** — 21,000 CF converts one and leaves an empty buffer |
| `laser/prismarine_shard` (quartz → prismarine shard, 30,000 CF) | **tested** — 31,000 CF converts one and leaves an empty buffer |
| `laser/crystalize_restonia_crystal`, `laser/soul_sand`, `laser/nether_wart` on items | **not asserted** — the same code path as the three above; their block half is the 0.2.6 evidence. A sand item would become a soul-sand *item* (upstream's item branch never places) |
| everything slice 1–5 shipped | unchanged and re-proved in the same run |

### Deviations and gaps this slice adds

1. **The marker is a scoreboard tag, not NeoForge persistent data.** No entity-persistent-data
   surface at this pin; the tag is saved with the entity, readable in game, and uses upstream's key.
2. **A whole-stack conversion rewrites the entity in place** (upstream discards it and spawns a new
   one). Same stack, same position, same pickup delay for the entity that stays; a *partial*
   conversion leaves the remainder on the entity and spawns the result beside it, exactly upstream's
   shape. One entity fewer per conversion, and no rollback hazard: an item removal inside a
   block-entity tick is staged with the snapshot while a spawn is immediate, so discarding an input
   and spawning two entities could duplicate an item if the tick were rejected.
3. **A zero-cost `laser/` recipe converts the whole stack**; upstream divides by zero there. No
   carried recipe has energy 0.
4. **The lens slot stays inert** and the beam's visual/`levelEvent(2001)` stays unported (as in
   0.2.6).

### Harness facts measured while getting here

1. **`ctl entities` names an entity's position `pos`**, not `position` (`game/agent.rs`
   `entities_value`): a `jq` that reads `.position` silently prints `null` and the "settled" line
   reads like a stale reply. `pos` + `distance` is the pair to print.
2. **A summoned item stays where it lands and is never picked up with `PickupDelay:32767s`**: the
   item half only sees entities inside the box, so the leg summons it at `machine + 2.5` (inside the
   step-2 box) and stands four blocks off.
3. **`/data get entity … Tags` answers `Found no elements matching Tags`** for an entity with no
   tags — an absent key, not an empty list, so the "leftover is unmarked" assertion has to accept
   the error reply and just refuse `aa_cnv` in it.
4. **The item half needs no hit block**: `invoke` runs at every beam step, so a dropped item in an
   all-air beam converts at the step whose box first reaches it.

Skills: superpowers/using-superpowers,test-driven-development,verification-before-completion (loaded) + brainstorming (the slice chosen from this file's gap list), writing-plans (`evidence/actuallyadditions/plan-0.2.7.md`), systematic-debugging (the harness facts below); BeautifulRust/rust-best-practices (no rust-port: a clean-room rewrite, not a translation)

**Changelog (0.2.7):**

> **0.2.7 — the beam converts dropped items too.** `MethodHandler.invokeConversionLens` has two
> halves, and 0.2.6 shipped the block one: after converting the 3×3 plane around the block it hits,
> the beam converts the **dropped items** in the box from the machine to that block
> (`new AABB(tile, hit + 1).inflate(0.02).expandTowards(facing)`), as many of a stack as the buffer
> pays for (`min(energy / recipe energy, count)`), one entity per beam step, marking each result
> `aa_cnv` so it is never converted twice — and that is how the jar's two item-only `laser/` recipes
> work: rotten flesh into leather at 20,000 CF and quartz into a prismarine shard at 30,000 CF, both
> now carried. Upstream's box is inverted whenever the beam points north, west or down (an `AABB`
> is not ordered), so those three facings converted no item at all; the port builds the ordered box
> and converts on all six. The marker is a vanilla scoreboard tag (`aa_cnv`) because the pin has no
> entity persistent data. 152 entries, 145,399 B, sha256 `7d35fc80…bc5e4`.

## Next slice (0.2.8)

**Family:** **pulse mode + the wrench** — the last piece of the reconstructor's own interaction
surface that the artefact defines and the port does not ship: `TileEntityAtomicReconstructor`'s
`isPulseMode` / `tryToggleRedstone` (a click with a wrench toggles between "redstone off" and
"one shot per pulse"), which is the mod's `actuallyadditions:reset` component and its wrench item.

- **Gap line** (slice 5, "Deviations and gaps this slice adds", item 2): *"No pulse mode, no wrench,
  no side configuration. A redstone signal freezes the cycle (as upstream), but the mod's own pulse
  mode and its `tryToggleRedstone` click are not ported."*
- **Why it fits `machines`:** a saved-state flag, a click on a block the port already ships and one
  carried item (the wrench), no renderer and no new kind of hook.
- **Blocker to check first:** the wrench is `actuallyadditions:wrench` in the jar, and the pulse flag
  upstream saves in the `pulse_mode` **data component** on the dropped item — decide whether the
  flag rides the existing state allowlist (as `energy`/`cycle` do) or the component, and grep the
  pin's `ItemPart`/component surface before promising either.
- **In-game assertion that can fail:** place a reconstructor, click it with the wrench, and assert
  `/actuallyadditions info` reports `pulse` (a new field); then a redstone block beside it must make
  it fire **once** per pulse instead of freezing — count two shots across two pulses, and the
  differential: the same machine without a pulse keeps freezing.
- **Out of scope:** the GUI (`blocked(no-single-player-mod-screen)`), lens items, the Empowerer, the
  Double Crusher, the ore's generation (`blocked(configured-feature-not-registered)`).

## Slice 7 (0.2.8, 2026-11-23) — the redstone mode, the click that sets it, and the conversion's order

**Family:** the Atomic Reconstructor's **redstone mode** — upstream's `isPulseMode`, the
`tryToggleRedstone` click and the mode's own item — plus the review finding on the conversion
(`NikitaMGrimm`, `src/support.rs:815-824`: the result was spawned before its source was removed and
the removal's answer was ignored, and the price was charged on a path that may not have converted).

- **Gap line** (`notes.md`, slice 5 "Deviations and gaps this slice adds", item 2): *"No pulse mode, no
  wrench, no side configuration. A redstone signal freezes the cycle (as upstream), but the mod's own
  pulse mode and its `tryToggleRedstone` click are not ported."*
- **Why it fits `machines`:** a saved-state flag, a branch in a click on a block the port already
  ships, and no renderer, no new kind of hook and no new item (see check 1).
- **Pin:** Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`, mixins
  `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`.

### The two checks the brief asked for, answered from the artefacts

1. **Is there an `ItemPart` route for the wrench?** The route exists (`Registrar::item_part`, used by
   this port's own `MachineItemPart`), but there is **no `actuallyadditions:wrench`** in the jar: the
   mod's wrench is `actuallyadditions:laser_wrench` (`ActuallyItems.java:123`), whose own `useOn`
   links laser relays (`ItemLaserWrench.java:36`) — a family this package does not ship. The redstone
   toggle is `CommonConfig.Other.redstoneConfigureItem`, a **config value** whose default is
   `minecraft:redstone_torch` (`.define("redstoneConfigurator", "minecraft:redstone_torch")`,
   `CommonConfig.java:169`, resolved in `ActuallyAdditions.java:138`). So the slice adds **no item**
   and no ItemPart: the toggle is a branch in the reconstructor's existing `BlockPart::use_item_on`,
   which is exactly where upstream's `tryToggleRedstone` sits (`BlockAtomicReconstructor.java:59`).
   The port has no config surface, so it accepts the default.
2. **Does the flag ride the state allowlist or need the `pulse_mode` component?** The allowlist:
   `RECONSTRUCTOR_STATE_KEYS` is now `["energy", "pulse"]` and the flag travels inside
   `minecraft:block_entity_data`, the carrier this port has used for machine state since 0.2.2 and the
   pin's documented route (ARCHITECTURE.md §3). The component route *does* work at this pin —
   `Hooks::component_types` takes a list of type names and `impl mod_api::Component` gives the typed
   value, as `enderstorage`'s `enderstorage:frequency` proves (`support.rs` there: `Component::id` /
   `decode` / `encode` + `stack.set`/`stack.get`) — but it is **not** needed: upstream uses a
   component only because 1.21.1 removed block-entity data from items, and carrying the same flag in
   two homes (the BE compound *and* an item component) would put the mode's restore on a second path.

### The rules as the artefact states them (`cd9d9c6`)

| Rule | Value | Source |
|---|---|---|
| which machines toggle | `isRedstoneToggle()` is **true for the reconstructor only** (the base returns false) | `TileEntityAtomicReconstructor.java:216`, `TileEntityBase.java:250` |
| the free cycle | `serverTick` runs it only `if (!isRedstonePowered && !isPulseMode)`, so a pulse-mode machine never free-runs | `TileEntityAtomicReconstructor.java:132` |
| a pulse | `respondsToPulses() = isRedstoneToggle() && isPulseMode`; `updateRedstoneState` calls `activateOnPulse()` on the **rising edge** of `getBestNeighborSignal(pos) > 0` (and once at placement, through `onPlace`) | `TileEntityBase.java:258`, `BlockContainerBase.java:105-114`, `:158-172` |
| what a pulse does | `activateOnPulse()` → `invokeReconstructor`, i.e. a whole shot: the 1,000 CF gate plus the beam | `TileEntityAtomicReconstructor.java:224` |
| the toggle | main-hand item `== redstoneConfigureItem` → `isPulseMode = !isPulseMode`, `setChanged()`, `sendUpdate()`, click claimed | `BlockContainerBase.java:98-113` |
| the mode's words | "Redstone Mode", `Pulse`, `Deactivation` | `assets/actuallyadditions/lang/en_us.json:512-515` |
| the flag on the item | `collectImplicitComponents` sets `ActuallyComponents.PULSE_MODE`; `applyImplicitComponents` reads it | `TileEntityAtomicReconstructor.java:231-245` |
| the signal in the save | `isRedstonePowered` is written in `SAVE_TILE` (`"Redstone"`), so an edge is not re-seen after a reload | `TileEntityBase.java:107,121` |

The port's shape: `Reconstructor` gains `pulse: bool` and `signal: Signal` (the level the last tick
saw, `Signal::{Off, On}`); `tick(signal)` computes the rising edge, stores the level, and returns
"fire now" — on the edge in pulse mode, on the cycle's zero otherwise. `signal` is **persisted** (the
port's `redstone` key) because the level the previous tick saw is what makes an edge an edge.

### Upstream defect fixed (the review's finding)

**The conversion spawned its result before removing its source, and ignored the removal's answer.**
Upstream's item branch (`MethodHandler.java:225-231`) is `addFreshEntity(item)` then
`setBlockAndUpdate(pos, AIR)` with the result discarded; 0.2.6 copied that shape, so a host that
refused the removal left **both** the input block and its output in the world, and 0.2.6/0.2.7 charged
the recipe's energy on that path anyway. The reviewer measured the same class in the 0.2.7 item half,
where the input was consumed first and the spawned result could fail.

- **What the port does instead:** `runtime::convert(source, energy, state)` owns the order — the
  source goes first and its answer is checked; the result is emitted only then; a refused emission
  puts the source back (`Conversion::restore_source`); and the energy is charged only when both
  writes happened. Both halves implement `Conversion`: the block half's `remove_source` replaces the
  source with a **block** result in one write (as upstream's `BlockItem` branch already did) and
  otherwise removes it, restoring the block state it read first if the drop fails; the item half's
  `remove_source` writes the stack the entity keeps, and restores the whole stack if the output
  cannot be spawned.
- **What a user notices:** a machine no longer duplicates a block into both a block and an item when
  the world refuses the removal, and a refused spawn no longer eats the stack it was converting.
- Worth an upstream report: yes (a reordering of two calls in `invokeConversionLens`, both halves);
  not filed — the orchestrator decides that.

### TDD

The pulse rules, the restored mode and the transaction rules were written first, with the new
functions at `todo!()` so the red is a named test, not a compile error
(`evidence/actuallyadditions/sdk-test-red-pulse.log`, `cargo test` exit 101):

```text
---- runtime::reconstructor_tests::a_pulse_mode_machine_fires_once_for_each_rising_edge stdout ----
thread '…' panicked at src/runtime.rs:628:9:
not yet implemented: the pulse rule: an edge fires in pulse mode, and pulse mode never runs the cycle

---- runtime::reconstructor_tests::a_refused_removal_leaves_no_result_and_charges_nothing stdout ----
thread '…' panicked at src/runtime.rs:684:5:
not yet implemented: the conversion's order: source, result, then the charge

---- support::tests::the_reconstructor_line_is_the_one_the_e2e_asserts stdout ----
assertion `left == right` failed
  left: "… facing east, cycle 63/100, …"
 right: "… facing east, pulse off, cycle 63/100, …"

test result: FAILED. 44 passed; 12 failed
```

Green: **56 passed**, 0 failed (21 `runtime::tests`, 8 `reconstructor_tests`, 3 conversion rules, 24
`support::tests`).

### Coverage (slice 7)

| Family | State |
|---|---|
| the redstone mode's flip (`isPulseMode`) | **tested** — a fresh machine reads `pulse off`; a stick click leaves it off; a redstone-torch click switches it to `pulse on` and the torch's cell above the machine stays air (the click is claimed) |
| pulse mode does not free-run | **tested** — 60 ticks with no signal leave the cycle and the buffer exactly where they were |
| one shot per rising edge | **tested** — a redstone block beside the machine fires one 1,040 CF shot and converts the wire (buffer 2,080 → 1,040); the falling edge fires nothing; a second rising edge fires again (1,040 → 0, two crystals), and the cycle never moves |
| the differential (no toggle) | **tested** — the same arrangement with `pulse off` keeps its cycle frozen on the same signal, spends nothing and converts nothing |
| a conversion's order (block half) | **unit-tested** — refused removal: no result, no charge; refused result: the source is put back, no charge; success: both writes, one charge |
| a conversion's order (item half) | **unit-tested** through the same rule; the game leg re-proves the success path (the 0.2.7 item-half phases, unchanged) |
| the mode on a broken item | **unit-tested** (`the_reconstructors_drop_carries_its_buffer_and_its_mode_and_not_its_cycle`): the payload carries `energy` and `pulse`, never `cycle` or `redstone` |
| the generator's and the crusher's clicks | unchanged — they are not redstone-toggle machines upstream either |
| side configuration | **not ported** — `isRedstoneToggle` is the whole of AA 1.3.26's redstone control for these machines; there is no per-side setting in the jar for them |

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.8)

```
package: …/actuallyadditions.hmod, 150252 bytes, sha256 5440228fe6a14f9fa35fedd6efe924c1c099a1d5832f466fb6d2438daf123097
== pulse mode and the wrench click (0.2.8) ==
  the machine as placed: … facing east, pulse off, cycle 76/100, lens default, sight minecraft:redstone_wire -> actuallyadditions:restonia_crystal @ 40 CF, t=6497
  after a stick click:   … facing east, pulse off, cycle 23/100, …, t=6550
  after a redstone-torch click: … facing east, pulse on, cycle 97/100, …, t=6603
  the torch's own cell above the machine: minecraft:air
  140 ticks of pulse mode with no signal: … 2080/300000 CF …, pulse on, cycle 97/100, …, t=6765
  after the first rising edge:  … 1040/300000 CF (…, pulse on, cycle 97/100, …, sight nothing, t=6814); 1 crystal(s)
  after the falling edge:       … 1040/300000 CF,…, t=6844
  the wire is back in the beam: … 1040/300000 CF, sight minecraft:redstone_wire -> actuallyadditions:restonia_crystal @ 40 CF, t=6852
  items before the second edge: [{"item":"actuallyadditions:restonia_crystal","count":1,"pos":[1.58,100.0,30.07]}]
  after the second rising edge: … 0/300000 CF (…, pulse on, cycle 97/100, …, t=6901); 2 crystal(s)
  items after the second edge:  [{"item":"actuallyadditions:restonia_crystal","count":2,"pos":[1.01,100.0,29.52]}]
  the same machine without the toggle: … 10,100,30: 2080/300000 CF (…, pulse off, cycle 56/100, … t=7016) -> … 2080/300000 CF (…, cycle 56/100, … t=7163)
```

What the numbers say: the mode starts `off` and a stick leaves it there; the redstone torch switches it to `on`
and is **not** placed (the cell above the machine is air); with pulse mode on and no signal the machine
neither runs its cycle (97 → 97 over 140 ticks, more than a whole 100-tick cycle) nor spends anything; the
first rising edge converts the wire for exactly 1,040 CF (gate 1,000 + dust 40) and the falling edge does
nothing; a second rising edge with a fresh wire converts again, emptying a 2,080 CF buffer to 0, and the
cycle is still 97. The differential — the same machine, no toggle — keeps its cycle at 56 across 147 ticks
of the same signal, keeps 2,080 CF and converts nothing. The two crystals merged into one stack of two
between the reads, which is why `ground` (a count *sum*) is the helper the leg asserts on.

Every assertion can fail. `SELFTEST=pulse` flips the first one ("a rising edge fires nothing"), which
passes only on a machine without the mode — `FAIL: SELFTEST pulse: the rising edge fired a shot (the real
assertion); the flipped assertion 'it fires none' fails, so the real one can fail` + `EXIT:1`
(`e2e-launcher-selftest-pulse.log`). The differential inside the run is the untoggled machine beside it.

### Ladder (0.2.8, slot `W1121-aa`, `CARGO_INCREMENTAL=0`, `BUILD_LOCAL=1`)

| Step | Result |
|---|---|
| tests (red first) | 12 failed / 44 passed, the new rules at `todo!()` — `sdk-test-red-pulse.log` |
| tests | **56 passed**, 0 failed (20 `runtime::tests`, 17 `reconstructor_tests` — 8 rules + 3 pulse + 3 conversion + the restored-mode one, 19 `support::tests`), `Compiling actuallyadditions v0.2.8` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings`, exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check`, exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` — `6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)` — `check-recipe-keys.log` |
| package ×2 | `cargo horizon-mod build`, twice, **lock kept** — **150,252 B** both, `cmp` identical, sha256 `5440228f…3097`, **152 entries** — `sdk-build.log`, `sdk-build-second.log` |
| check | `actuallyadditions 0.2.8 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 150252 bytes, EXIT 0 — `sdk-check.log` |
| fits, the pin | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` (the first attempt died on a network reset, `os error 104`; retried, green) |
| gate | `verify-sdk-package.py actuallyadditions` → **1/1** (packed lock, tree match, runtime hash, skills gate) |
| launcher build | `native-0a875da-f04bebbba937`, `native-mods.json` names `actuallyadditions 0.2.8` |
| in-game | `tools/e2e.sh` (`--offscreen`, the launcher build of this package) → `PASS` + `EXIT:0` — `e2e-launcher.log` |
| counterfactual | `SELFTEST=pulse` → `FAIL: SELFTEST pulse: …` + `EXIT:1` — `e2e-launcher-selftest-pulse.log` |
| counterfactual | `SELFTEST=1` → `FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=drops` → `FAIL: SELFTEST drops: the payload carries no Items …` + `EXIT:1` |
| counterfactual | `SELFTEST=ore` → `FAIL: SELFTEST ore: the ore dropped Black Quartz (the real assertion); …` + `EXIT:1` |
| counterfactual | `SELFTEST=laser` → `FAIL: SELFTEST laser: the beam made a crystal (the real assertion); …` + `EXIT:1` |
| counterfactual | `SELFTEST=item` → `FAIL: SELFTEST item: the beam converted the dropped item (the real assertion); …` + `EXIT:1` |
| counterfactual | `NEGATIVE=1` → `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour), …` + `EXIT:1` |
| control | `GAME=$CONTROL_GAME` (the same Nightly, no package) → `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` → `logs=9 ok=9` |

Artifact: `actuallyadditions.hmod`, **150,252 B**, sha256
`5440228fe6a14f9fa35fedd6efe924c1c099a1d5832f466fb6d2438daf123097`, **152 entries**,
`Cargo.lock` **packed** (8,850 B, `13d40f9d…` — its own version line moved to 0.2.8) and byte-equal to
the tree's. `src/lib.rs` is unchanged; `src/runtime.rs` gained `Signal`, the mode and the conversion rule;
`src/support.rs` the toggle, the `pulse`/`redstone` keys and the two `Conversion` implementations. Every
in-game log names the sha above.

### Deviations and gaps this slice adds

1. **The toggle item is the config's default, not a carried wrench.** Upstream reads
   `CommonConfig.Other.redstoneConfigurator` (default `minecraft:redstone_torch`); the port has no config
   surface, so it accepts exactly that default. `actuallyadditions:laser_wrench` is *not* carried: its
   own job is laser-relay linking, which this package does not ship, and a wrench that only toggles would
   be an inert item for a family that is not here. When a config surface is ported, this constant becomes
   the setting's value.
2. **The flag rides `minecraft:block_entity_data`, not a registered component** (check 2 above): one
   carrier for all of a machine's state beats two, and upstream's component exists only because 1.21.1
   dropped block-entity data from items.
3. **The edge is sampled once per tick.** Upstream hears `neighborChanged` and fires inside it, so a
   signal that rises and falls within one tick would fire there and not here. Redstone at this pin
   cannot produce a sub-tick pulse from a block, so nothing observable differs; recorded for honesty.
4. **`redstone` (the last-seen level) is saved but never travels on the dropped item** — it belongs to
   the world the machine stands in, as upstream's `SAVE_TILE`/loot split has it.
5. The rest of the 0.2.6/0.2.7 gap list stands: no GUI (`blocked(no-single-player-mod-screen)`), no lens
   items, no comparator hook, no beam visual, the ore's generation `blocked(configured-feature-not-registered)`.

### Harness facts measured while getting here

1. **A crystal that lands at the beam's block is inside the player's pickup reach** if the player still
   stands where the click left them (two blocks away). One run read `1 crystal(s)` after two shots for
   exactly this reason; the phase now teleports the player eight blocks clear before the pulses.
2. **Two beam drops of the same item can merge into one stack**, so the shot count must be a count *sum*
   (`ground`), never an entity count: the delivered run shows one entity with `count: 2`.
3. **A chat-based read is stale by ~40 ticks**, so a "before" sample taken before a `setblock` describes
   the world from before the write. The differential now places the signal first, waits, and only then
   takes its baseline (the first attempt compared 149-ticks-apart values and failed on 59 → 53).
4. **Three concurrent e2e legs OOM-killed two games on this box** (7 GB available, the wave's own e2e runs
   in flight): every leg prints `cannot connect … is the game running with --control?` and exits 3. Run
   the legs one at a time.
5. **`CONTROL=1` is a command-line argument, not an environment variable** in `run-leg-0.2.8.sh`: passing
   it through `env "$@"` left the script's own `GAME` modded, and the control leg "passed" against the
   modded game until the script read it from `$@`.
6. **The launcher reuses cargo's fingerprint.** Its wording is "Checking 1 mod / Compiling the mods
   against the prebuilt game / Your mods are built", not cargo's `Compiling … (1 of 1)`. The 0.2.8 build
   that compiled took 8 s (`native-0a875da-f04bebbba937`, the export the legs ran); rebuilding after the
   README-only correction took 1 s and `native-0a875da-9166d4121218`, and `native-mods.json` names
   `actuallyadditions 0.2.8` in both — proof that the doc change touched nothing the mod compiles
   (`evidence/actuallyadditions/launcher-build.log`).

**Changelog (0.2.8):**

> **0.2.8 — the reconstructor's redstone mode, and the conversion's order.** A redstone signal freezes
> the Atomic Reconstructor's cycle (0.2.6); a click holding upstream's redstone configurator (the config's
> default, a redstone torch) now switches it to **pulse mode**: one shot per rising edge of the neighbour
> signal, the cycle never running, the click claimed so the torch is not placed. The mode is saved, is in
> `/actuallyadditions info` (`pulse on|off`), and travels on the machine's broken item beside its buffer
> (`minecraft:block_entity_data`), so a picked-up machine comes back in the mode it was in. The
> conversion itself now does its two writes in the order that keeps the world consistent — the source
> first and its answer checked, the result only if it went, the source put back if not, and the recipe's
> energy charged only when the conversion happened — in the block half and the item half; upstream spawns
> the result before removing the source and ignores the removal's answer, which can leave both the input
> and its output in the world (the review's finding on 0.2.6/0.2.7). 56 unit tests, 9 in-game legs,
> 152 entries, 150,252 B, sha256 `5440228f…3097`.

## Slice 8 (0.2.9, 2026-11-23) — the registry's R9: no crate dependency, no lock

**This is a packaging slice, not a family slice.** 0.2.8 was published and then refused by the
registry's automated check, so 0.2.9 ships the same gameplay in a package the checks accept. No
family was added, none was dropped; every coverage row of 0.2.8 stands.

### The red, verbatim

The registry's automated check at `495701cf` refused the 0.2.8 update:

> This native mod update waits for a reviewer: the automatic checks at `495701cf` refused **rules R9**.

Rule R9, from the registry's `tools/native-subset/README.md`:

> `Cargo.toml` has a dependency other than `horizon-mod-api = { path = ".horizon/sdk/api/crates/horizon-mod-api" }`, a build script, a proc-macro or a `lib.path` other than `src/lib.rs`, or a table other than `[package]`, `[dependencies]`, `[lib]` and `[lints]`.

0.2.8 declared `serde_json = "=1.0.151"` and packed the `Cargo.lock` that dependency forces — which
is the same violation twice over: the dependency is refused, and the lock it "requires" is the
evidence of it. **The rule this campaign wrote ("declare a dependency, pack its lock") is dead for
the registry**; it was right for the launcher and is recorded as historical in "The registry
`Cargo.lock` now ships — and 0.2.9 reverses it".

### The choice: the reader moves into `src/`, not into a build-time tool

The brief allowed either a dependency-free reader or a content-generation tool that resolves the
table so `src/` only reads it. **A tool cannot do this one**, because the table is not this
package's own data: `find_recipe` asks the world with
`host.recipes_of_type("actuallyadditions:crushing")`, so a data pack's override, another pack's
added recipe and a `/reload` all change it at run time (the cache is rebuilt every 40 ticks for
exactly that reason). A table frozen at package-build time would ignore all three. So the parse
stays on the recipe path and the crate dependency is replaced by a reader in the pure module:

- `Json` — `Null` / `Bool` / `Number(String)` / `String` / `Array` / `Object(Vec<(String, Json)>)`.
  A number keeps the digits it was written with, so `count: 3` is an integer for `as_i64`, `chance:
  0.5` is `0.5` for `as_f64`, and `1e2` survives the round trip — the same answers `serde_json`'s
  `as_i64`/`as_f64` give.
- `Json::parse` — a byte cursor (JSON's structure is ASCII), strings copied whole including
  `\uD83D\uDE00` surrogate pairs, nesting capped at 128, which is serde_json's own default.
- `impl Display for Json` — the compact document, so `.to_string()` still hands the host the text
  `recipe_ingredient` / `recipe_result` read. The host's own `Value` is only ever *printed* in
  `support.rs`, never named, which is what removes the second parser as well.
- `CrushingRecipe` and `LaserRecipe` now carry the normalised `ingredient: Json` from the same pass,
  so the glue no longer parses each recipe file twice (once for the results, once for the
  ingredient).

Same rules, same refusals: `MissingIngredient`, `MissingResult`, `TooManyResults`, `BadResult`,
`BadChance`, `MissingEnergy` and `BadEnergy` keep their triggers, and the test that pins them
(`a_broken_recipe_is_refused_with_the_reason`) is unchanged.

### TDD

`json_tests` was written first with `Json::parse` at `todo!()`: **12 failed / 47 passed**, every
failure the reader's own `not yet implemented` panic — `sdk-test-red-json.log`. Then the reader,
then **59 passed / 0 failed** (19 `runtime::tests`, 4 `json_tests`, 17 `reconstructor_tests`, 19
`support::tests`). The old `an_upstream_ingredient_becomes_the_pins_json` test became
`a_recipe_ingredient_becomes_the_pins_form` in `json_tests`, now over parsed documents instead of
`serde_json::json!` literals.

### Ladder (0.2.9, slot `W1/aa`, `CARGO_INCREMENTAL=0`, `BUILD_LOCAL=1`)

| Step | Result |
|---|---|
| rules (red) | 12 failed / 47 passed, `Json::parse` at `todo!()` — `sdk-test-red-json.log` |
| tests | **59 passed**, 0 failed (19 runtime, 4 json, 17 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.9` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings`, exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check`, exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` — `6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)` — `check-recipe-keys.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice — **151,085 B** both, `cmp` identical, sha256 `964b0a83…9911`, **151 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `actuallyadditions 0.2.9 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 151085 bytes, EXIT 0 — `sdk-check.log` |
| fits, the pin | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` → **1/1**, including the R9 checks (`Cargo.toml tables R9 allows`, `SDK-only dependencies (R9)`, `no build script (R9)`, `[lib] is src/lib.rs and no proc-macro (R9)`, `no packed Cargo.lock`) |
| launcher build | `native-0a875da-90007b61b7ec`, `Compiling actuallyadditions (1 of 1)`, `native-mods.json` names `actuallyadditions 0.2.9` — `launcher-build.log` |
| in-game | `tools/e2e.sh` (`--offscreen`, the launcher build of this package) → `PASS` + `EXIT:0` — `e2e-launcher.log` |
| counterfactual | `NEGATIVE=1`, `SELFTEST=1`, `drops`, `ore`, `laser`, `item`, `pulse` → each `FAIL:` + `EXIT:1` |
| control | `CONTROL=1` (the same Nightly, no package) → `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` → `logs=9 ok=9` |

Artifact: `actuallyadditions.hmod`, **151,085 B**, sha256
`964b0a83c110f3eabb00a763b338246dc7860eb241c2727705a94bcf8ccd9911`, **151 entries** (0.2.8's 152
less the lock), no `Cargo.lock`. Every in-game log names that sha.

### Harness facts measured while getting here

1. **`fits` matches a local type by name, so `Reader` false-failed the different build.** A private
   `struct Reader` in `runtime.rs` made `fits --build 0b14f8a` answer
   `does not fit: 1 item changed — the type wire::Reader can no longer be built with a literal, and
   src/runtime.rs:50 builds it`: the analyser resolved the literal against the SDK's own
   `type:wire::Reader`, which this port never names. Renamed `JsonReader` and the same build
   answers `0b14f8a  fits`. This is the `Block`/`Item` trap in another costume: **pick a local type
   name the SDK's surface does not carry** (`python3` over `ports/_shared/sdk/0a875da/surface.json`).
2. **`verify-sdk-package.py` gained explicit R9 rows** (the tables, the dependency set, the build
   script, the `lib.path`, the absent lock), so the gate now answers the registry's rule rather than
   inferring it from whether a lock is packed.

**Changelog (0.2.9):**

> **0.2.9 — the package meets the registry's R9.** The `serde_json` dependency and the `Cargo.lock`
> it forced are gone: the registry refuses any dependency but the SDK path dep (rule R9), and a
> package that declares one cannot be published at all. `src/runtime.rs` reads the
> `actuallyadditions:crushing` and `actuallyadditions:laser` files with its own reader (`Json`), so
> a data pack's recipes, its overrides and a `/reload` are read exactly as before; the glue no
> longer parses each file twice. Same behaviour, same 59 unit tests (4 new for the reader), same 9
> in-game legs, 151 entries, 151,085 B, sha256 `964b0a83…9911`.

## Next slice (0.2.10)

**Family:** the **lens items and the lens slot** — the one part of the reconstructor upstream still has
and this port cannot use. Checked against the jar while writing this, because the 0.2.6 note guessed at a
blocker that is not there:

(0.2.9 took the number this section was written for, with the registry's R9 packaging fix; the proposal
stands unchanged for 0.2.10.)

- `actuallyadditions:lens` **is craftable in a crafting table** (`GGG / GBG / GGG` = eight
  `#c:glass_blocks` + one `black_quartz`, `data/…/recipe/lens.json`), and `black_quartz` ships — so a lens
  *can* be had in survival once the `c:glass_blocks` tag is declared. `lens_of_the_killer`,
  `lens_of_the_miner` and `lens_of_disenchanting` are crafting recipes too.
- the jar's `laser/` folder also holds five **lens → lens** conversions (`lens` → `lens_of_color` →
  … → `lens_of_certain_death` → `lens`, 5,000 CF each). Those are matched by the **item half the port
  already ships**: a *dropped* lens converts today, as soon as the item exists.
- what is genuinely missing is the slot's behaviour: `getLens()` turns the held `ILensItem` into the
  beam's `Lens`, whose `getDistance` and `canInvoke`/`invoke` decide what the beam reaches and what it
  does (the miner's lens breaks blocks, the killer's damages entities, the detonator's explodes).

- **Gap line** (0.2.6 coverage table, "the lens slot"): *"not ported — no item in this package is an
  `ILensItem`; the slot is declared, nothing can fill it, and the click refuses every item"*.
- **Why it fits `machines`:** items, a slot the machine already has and a rule inside it — no new block,
  no renderer, no new hook kind.
- **In-game assertion that can fail:** craft the lens from eight glass and a Black Quartz (all consumed),
  right-click it into the slot (the click accepts it instead of refusing), assert the `info` line's
  `lens actuallyadditions:lens x1`; then a dropped lens in the beam converts to `lens_of_color` for
  5,040 CF (the item half plus the gate); differential: a dropped non-lens stays, and a *second* lens is
  refused by an occupied slot.
- **Out of scope:** the four behaviour lenses' own effects (a following slice; each needs a different
  beam action), the GUI (`blocked(no-single-player-mod-screen)`), the Double Crusher, the ore's
  generation (`blocked(configured-feature-not-registered)`), the beam's visual.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

## Slice 9 (0.2.10, 2026-11-24) — the lens items and the lens slot

**Family:** the four lens items of the jar's laser ring, the `lens` crafting recipe, the
`c:glass_blocks` tag it keys on, and — the actual missing behaviour — the Atomic Reconstructor's
**lens slot acceptance**: a right click with an `ILensItem` now fills the slot the machine already
has, `info` names it, an occupied slot refuses a second lens, and a *dropped* lens in the beam is
converted by the item half this port already ships.

- **Gap line** (0.2.6 coverage table, `notes.md:1660`): *"the lens slot — not ported — no item in
  this package is an `ILensItem`; the slot is declared, nothing can fill it, and the click refuses
  every item"*.
- **Why it fits `machines`:** items, a slot the machine already declares and the `getLens()` rule
  inside it — no new block, renderer or hook kind. The four behaviour lenses' own beam effects are
  a later slice; their acceptance here is faithful to `getLens`, and the beam uses the default
  conversion rule for them (recorded deviation below).
- **Pin:** Horizon `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`, mixins
  `e59da9094f0c2fdda6c627fe9eff22dec6a906f0`.

### The artefact: the lens recipe and the conversion rows, as read

`data/actuallyadditions/recipe/lens.json` (verbatim):

```json
{
  "category": "misc",
  "key": {"B": "actuallyadditions:black_quartz", "G": "#c:glass_blocks"},
  "pattern": ["GGG", "GBG", "GGG"],
  "result": {"count": 1, "id": "actuallyadditions:lens"},
  "type": "minecraft:crafting_shaped"
}
```

The jar's `recipe/laser/lens*.json` holds **four** conversions, each `"energy": 5000`, a ring —
`lens → lens_of_color → lens_of_detonation → lens_of_certain_death → lens`:

| file | ingredient | result | CF |
|---|---|---|---:|
| `laser/lens_of_color.json` | `actuallyadditions:lens` | `actuallyadditions:lens_of_color` | 5,000 |
| `laser/lens_of_detonation.json` | `actuallyadditions:lens_of_color` | `actuallyadditions:lens_of_detonation` | 5,000 |
| `laser/lens_of_certain_death.json` | `actuallyadditions:lens_of_detonation` | `actuallyadditions:lens_of_certain_death` | 5,000 |
| `laser/lens.json` | `actuallyadditions:lens_of_certain_death` | `actuallyadditions:lens` | 5,000 |

The brief said "five"; the jar has four (counted from `unzip -Z1 … | grep recipe/laser/`). The
artefact wins. All four are carried; the four *behaviour* lenses' own crafting recipes
(`lens_of_disenchanting`, `lens_of_the_killer`, `lens_of_the_miner`) key on empowered crystals and
an enchanted book this package does not carry, so they stay out of scope. `c:glass_blocks` is
declared with glass, tinted glass and the 16 stained glass blocks (panes belong to
`c:glass_panes`), all present in 26.3.

### TDD — the red, verbatim

`runtime::lens_slot_accepts` was written at `todo!()` first; `evidence/actuallyadditions/sdk-test-red-lens.log`
(`cargo test --offline`, exit 101):

```text
---- runtime::reconstructor_tests::a_lens_fills_the_empty_slot_and_a_second_lens_is_refused stdout ----

thread 'runtime::reconstructor_tests::a_lens_fills_the_empty_slot_and_a_second_lens_is_refused' (27499) panicked at src/runtime.rs:1086:5:
not yet implemented: the lens slot's acceptance rule

test result: FAILED. 59 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s
```

Green: **60 passed**, 0 failed (19 `runtime::tests`, 4 `json_tests`, 18 `reconstructor_tests`,
19 `support::tests`); `Compiling actuallyadditions v0.2.10` in `sdk-test.log`.

### Glue

`support::reconstructor_click` now runs `lens_slot_accepts(slot, item)` (pure, in `runtime.rs`)
before claiming the click: `insert_lens` takes one from the hand through `HostTransaction` and then
writes slot 0, so a refused write cannot leave a free lens; an occupied slot refuses a second lens
and a non-lens is refused. The `info` line already rendered the slot (`lens <id> x<count>`), so no
new readout code was needed. The container still declares no `inputs`: the pin's input list cannot
say "only a lens", so a hopper must not put an arbitrary item in a slot upstream protects.

### Ladder — the remote job

Every cargo step was forwarded (no `BUILD_LOCAL=1`):

```text
build-slot: forwarding test for ports/actuallyadditions to the remote runner
REMOTE_HOST=AdLf-PC
```

| Step | Result |
|---|---|
| tests (red first) | 59 passed / 1 failed, `todo!()` — `sdk-test-red-lens.log` |
| tests | **60 passed**, 0 failed, `Compiling actuallyadditions v0.2.10` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings`, exit 0, **0 warnings** — `sdk-clippy.log` |
| format | `cargo fmt --check`, exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` — `7 recipe(s), 16 craftable, 0 blocked, 0 failure(s)` — `check-recipe-keys.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice — **162,102 B** both, `cmp` identical, sha256 `63f263561061eede2b60fcd2886917004a998cc0321c302b32bfc02e6ca7b54b`, **174 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `actuallyadditions 0.2.10 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 162102 bytes, EXIT 0 — `sdk-check.log` |
| fits, the pin | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits, a different build | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `verify-sdk-package.py actuallyadditions` → **1/1** (`package matches the tree`, R9 rows) |
| launcher build | `native-0a875da-b7cae93da59c`, `Compiling actuallyadditions (1 of 1)` — `launcher-build.log` |

The dependency-free `Json` reader from 0.2.9 is unchanged; R9 still passes (`SDK-only dependencies`,
`no packed Cargo.lock`). No local type collided with the SDK surface this time, so both `fits`
runs were green on the first attempt.

### In-game transcript (`evidence/actuallyadditions-e2e/e2e-launcher.log`, 0.2.10)

```text
  recipe give actuallyadditions:lens -> {"chat": ["Unlocked 1 recipe(s) for Player52181"], "ok": true}
  lens (8 glass + 1 black quartz): result {"count": 1, "item": "actuallyadditions:lens", "slot": 200}
  lens (8 glass + 1 black quartz): inventory after the craft {"minecraft:glass": 0, "actuallyadditions:black_quartz": 0, "actuallyadditions:lens": 1}
  the machine as placed: Atomic Reconstructor at 0,100,40: … lens default, … t=3286
  after the lens click: Atomic Reconstructor at 0,100,40: … lens actuallyadditions:lens x1, … t=3334
  after a stick click: Atomic Reconstructor at 0,100,40: … lens actuallyadditions:lens x1, … t=3382
  after a second lens click: Atomic Reconstructor at 0,100,40: … lens actuallyadditions:lens x1, … t=3440
  the refused lens is still in hand: actuallyadditions:lens
  a dropped lens in the beam: 1 lens_of_color, 0 lens left; Atomic Reconstructor at 0,100,40: 40/300000 CF (… t=3595)
  the differential after its shot: Atomic Reconstructor at 8,100,40: 40/300000 CF (… lens default, … t=3743)
```

6,040 CF pays the 1,000 CF gate (5,040 left) and the 5,000 CF lens conversion, leaving 40 — the
item half already shipped, now with a recipe whose input exists. `check-e2e-logs.py
actuallyadditions-e2e --strict` → `logs=10 ok=10`; the default leg is `PASS` + `EXIT:0` and each of
`SELFTEST={lens,1,drops,ore,laser,item,pulse}`, `NEGATIVE=1` and the unmodded control is `FAIL` +
`EXIT:1`. `SELFTEST=lens` flips the first assertion to "the slot stays empty", which is false on
this package:
`FAIL: SELFTEST lens: the slot accepted the lens (the real assertion); the flipped assertion 'it stays empty' fails, so the real one can fail` + `EXIT:1`.
A dropped non-lens stays a stick and its shot spends only the gate.

### Coverage (slice 9)

| Family | State |
|---|---|
| `actuallyadditions:lens` recipe (`GGG/GBG/GGG`) | **tested** — `recipe give` unlocks one; the grid crafts one lens from eight glass and one black quartz, all nine consumed; stone in the glass cells stays empty |
| `c:glass_blocks` | **tested** through its consumer; the tool refuses an empty tag |
| the four lens items and their models/textures | **tested** — `lens` is crafted, `lens_of_color` is produced by the beam, all four are give-able declarations with `max_stack_size: 1` |
| the lens slot's acceptance | **tested** — the crafted lens fills it (`info` reads `lens actuallyadditions:lens x1`); a stick and a second lens are refused, the second still in hand |
| the four `laser/lens*` conversions (5,000 CF each) | **tested for `laser/lens_of_color`** — a dropped lens in the beam converts for gate + 5,000; the other three are the same code path, unit-tested and checked by `check_recipe_keys.py` |
| the four behaviour lenses' own beam effects | **out of scope** — each needs a different beam action (break/damage/explode/disenchant); they are accepted as lenses but use the default conversion rule |
| the GUI, ore generation, comparator, beam visual | unchanged: `blocked(no-single-player-mod-screen)`, `blocked(configured-feature-not-registered)`, printed-not-wired, no packet |

### Deviations and gaps this slice adds

1. **The three non-plain ring items are accepted but use the default beam rule.** Upstream's
   `lens_of_color`/`lens_of_detonation`/`lens_of_certain_death` each change what the beam does; the
   port only implements `getLens`'s *acceptance* (an `ILensItem` fills the slot) and the default
   conversion effect. Their own effects are the next family.
2. **The automation input list is still empty.** A hopper cannot insert a lens; upstream's handler
   accepts only an `ILensItem`, which the pin's container input list cannot express, so the right
   click is the supported route.
3. **The craft of the ring's other three lenses is not carried** — their recipes name crystals
   this package does not ship; the items exist because the beam makes them.

### Harness facts measured while getting here

1. **The e2e's dropped-item helper clears all item entities first**, so an earlier conversion's
   output is gone by the time a differential shot runs; assert the differential's own count (0),
   not the earlier one's.
2. **Restore the player's stance after a phase at positive z.** The later block-break legs aim at
   negative-z blocks from the arena centre; leaving the player 46 blocks away makes `ctl break`
   answer "out of reach (4.5)" even though `ctl tp` was issued. A console `tp @s 0.5 100 3.5` at
   the phase's end fixes it.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices

**Changelog (0.2.10):**

> **0.2.10 — the lens items and the lens slot.** The four items of the jar's 5,000 CF lens ring,
> their models/textures, the `lens` crafting recipe (`GGG/GBG/GGG`, eight `#c:glass_blocks` members
> and one Black Quartz) and the four `laser/lens*` conversions ship, and the reconstructor's lens
> slot is no longer inert: a right click with a lens fills it (the `info` line reads
> `lens actuallyadditions:lens x1`), a non-lens and a second lens are refused, and a dropped lens in
> the beam becomes `lens_of_color` for the 1,000 CF gate plus 5,000 CF. The behaviour lenses' own
> beam effects remain out of scope. 60 unit tests, 174 entries, 162,102 B, sha256 `63f26356…7b54b`.

## Next slice (0.2.11)

**Family:** the **behaviour lenses' own beam effects** — the four lens items whose `Lens` action
differs from the default conversion: the miner lens breaks the blocks it sights, the killer lens
damages entities in the beam, the detonator explodes at the hit block, and the disenchanting lens
strips enchantments from items.

- **Gap line** (this slice's deviations, item 1): *"The three non-plain ring items are accepted but
  use the default beam rule … their own effects are the next family."*
- **Why it fits `machines`:** a branch in the beam the port already ships, driven by the lens id in
  the slot it now accepts — no new block, renderer or hook kind. The behaviour lenses' *items* are
  not carried yet (their crafting recipes key on crystals this package lacks); the next slice must
  either carry those items with a reachable recipe or add the effect to the ring items already here.
- **In-game assertion that can fail:** with a lens that changes the beam installed, aim at a
  `minecraft:stone` block (not convertible by any carried `laser/` recipe) and tick a 1,040 CF shot:
  the miner variant must break it while the default lens leaves it; the differential is the same
  block with the plain lens in the slot.
- **Out of scope:** the GUI (`blocked(no-single-player-mod-screen)`), the Double Crusher, the ore's
  generation (`blocked(configured-feature-not-registered)`), the beam's visual.
