# Validation

**0.2.7 (2026-11-23, pin `0a875da`)** — slice 6: the beam's **item-entity half**. The Atomic
Reconstructor's `invokeConversionLens` also converts the **dropped items** in the box from the
machine to the block it hit (`new AABB(tile, hit + 1).inflate(0.02).expandTowards(facing)`), as many
of a stack as the buffer pays for, one entity per beam step, its result marked `aa_cnv` — plus the
two `laser/` recipes whose terms only ever match an item (`rotten_flesh` → leather at 20,000 CF,
`quartz` → prismarine shard at 30,000 CF). The rules as the artefact states them are in `notes.md` →
"Slice 6"; the one upstream defect (the box is inverted on `north`/`west`/`down`, so those three
facings converted no item) is recorded under "Upstream defects fixed" there and fixed here.

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline` before the implementation | `error[E0425]: cannot find function item_scan_box / items_possible / may_convert` + `cannot find value CONVERTED_MARKER`, 19 errors, exit 101 — `evidence/actuallyadditions/sdk-test-red-item-half.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)`, exit 0; both new `laser/` files `ok … every ingredient and its result resolve (laser)` — `check-recipe-keys.log` |
| content carry | `tools/assemble_content.py` + `tools/stamp_license.py` re-run | the two new `laser/` files are the only bytes that moved (140 files before, 142 after) |
| tests | `cargo test --offline` after `cargo clean -p actuallyadditions` | **50 passed / 0 failed** (20 runtime, 11 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.7` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| package | `cargo horizon-mod build` twice, **lock kept** | **145,399 B** both, `cmp` identical, sha256 `7d35fc805d9e49c05d2cc4e30a1a5f1cc261da0a6d0bf6d3b18b8a5d909bc5e4`, **152 entries with `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log`, `sdk-sha256.txt` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.7 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 145399 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** (packed lock, tree match, runtime hash, skills gate) |
| in-game | `tools/e2e.sh` (`--offscreen`, launcher build `native-0a875da-7ac0c4c42e48`) | `PASS` + `EXIT:0` — `actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=item` | `FAIL: SELFTEST item: the beam converted the dropped item (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-item.log` |
| counterfactual | `SELFTEST=laser` | `FAIL: SELFTEST laser: …` + `EXIT:1` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2540 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=ore` | `FAIL: SELFTEST ore: …` + `EXIT:1` |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked …` + `EXIT:1` |
| control | `GAME=$CONTROL_GAME` (same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=7 ok=7` |

In game the item half prints (from `e2e-launcher.log`): the dropped item settled at
`[2.5,100.0,20.5]`; after the shot `1 restonia crystal(s), 0 redstone left`; the converted entity's
`Tags` read `["aa_cnv"]`; the differential item two blocks across the beam stayed redstone with the
buffer at `40/300000 CF`; a stack of three gave `1 crystal(s), 2 redstone left`, the leftover
unmarked; a **west**-facing beam converted its item too (the fixed defect); rotten flesh → `1
leather` at 20,000 CF and quartz → `1 shard` at 30,000 CF. The launcher build is
`native-0a875da-7ac0c4c42e48`, exported to `~/.cache/horizon-e2e/0a875da/actuallyadditions/`, and the
leg's first line names the delivered sha256. The 0.2.6 block below is superseded.

**0.2.6 (2026-11-23, pin `0a875da`)** — slice 5: the Atomic Reconstructor (a facing block entity, a
300,000 CF buffer, a lens slot, a 100-tick cycle, a ten-block beam converting the 3×3 plane it hits)
and the three block-reachable `laser/` recipes it fires, the `restonia_crystal` item, the
`c:dusts/redstone` and `c:sands` tags and the machine's own recipe — which closes the chain: the
Crusher's recipe now crafts. `tools/recipe-blockers.json` is empty. The conversion rules as the
artefact states them (buffer 300,000 / shot gate 1,000 / recipe energy on top / distance 10 / cycle
100 / plane 3×3) are in `notes.md` → "Slice 5".

| Check | Command | Result |
|---|---|---|
| pure rules (red) | `cargo test --offline` before the implementation | `error[E0422]: cannot find struct … Reconstructor` + `E0425: … RECONSTRUCTOR_TICKS`, exit 101 — `evidence/actuallyadditions/sdk-test-red-laser.log` |
| content rule (red) | `python3 tools/check_recipe_keys.py` with the 0.2.5 blocker still in place | `FAIL actuallyadditions:crusher: blocked(restonia_crystal_source) is stale — the recipe resolves now`, `6 recipe(s), 9 craftable, 1 blocked, 1 failure(s)`, exit 1 — `check-recipe-keys-red-0.2.6.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `6 recipe(s), 9 craftable, 0 blocked, 0 failure(s)`, exit 0; the three `laser/` files `ok … every ingredient and its result resolve (laser)` — `check-recipe-keys.log` |
| tests | `cargo test --offline` | **47 passed / 0 failed** (20 runtime, 8 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.6` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| package | `cargo horizon-mod build` twice, **lock kept** | **140,841 B** both, `cmp` identical, sha256 `414c0ab9ad5da8795420261ecd04720d5cc030c76d001832d395d2c34693d52b`, **150 entries with `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.6 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 140,841 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** (packed lock, tree match, skills gate) |
| in-game | `tools/e2e.sh` (`--offscreen`) on the launcher build of this package | `PASS` + `EXIT:0` — `actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=laser` | `FAIL: SELFTEST laser: the beam made a crystal (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-laser.log` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| counterfactual | `SELFTEST=ore` | `FAIL: SELFTEST ore: the ore dropped Black Quartz (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-ore.log` |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour) …` + `EXIT:1` — `e2e-launcher-negative.log` |
| control | `GAME=$CONTROL_GAME` (same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=6 ok=6` |

The launcher build the leg used is `native-0a875da-226ec8d9c3ec` (its `native-mods.json` records
`actuallyadditions 0.2.6`), exported to `~/.cache/horizon-e2e/0a875da/actuallyadditions/`; the leg's
first line names the delivered sha256. The 0.2.5 block below is superseded.

**0.2.5 (2026-11-23, pin `0a875da`)** — slice 4: the Black Quartz Ore, the gem it drops, its loot
table and three recipes, the `c:ores`/`c:gems` tags, the `c:ingots/iron` + `c:rods/wooden` tags and
the Iron Casing's own recipe. The ore's **generation** is `blocked(configured-feature-not-registered)`
at this pin (measured; the same gap silentgems recorded) and the e2e asserts it.

| Check | Command | Result |
|---|---|---|
| generation rule (red) | `cargo test --offline` before the implementation | `error[E0425]: cannot find … black_quartz_ore_generation / is_namespaced / VANILLA_GENERATION_STEPS`, exit 101 — `evidence/actuallyadditions/sdk-test-red-generation.log` |
| content rule (red) | `python3 tools/check_recipe_keys.py --port <pre-slice tree + 3 new recipes>` | 3 failures, exit 1 — `check-recipe-keys-red-0.2.5.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `5 recipe(s), 4 craftable, 1 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys-0.2.5.log` |
| worldgen probe | `place feature` + the content root's bundles | `Can't find element … in registry 'minecraft:worldgen/feature'`; `features.json` a symlink, `placed_features.json` merged, `biome-modifiers.json` carries the data file — `worldgen-probe-0.2.5.md` |
| tests | `cargo test --offline` | **34 passed / 0 failed** (20 runtime, 14 glue), `Compiling actuallyadditions v0.2.5` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| package | `cargo horizon-mod build` twice, **lock kept** | **121,206 B** both, `cmp` identical, sha256 `de43f029…62486`, **130 entries with `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.5 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** (includes the packed lock) |
| in-game | `tools/e2e.sh` (`--offscreen`) on the launcher-built game | `PASS` + `EXIT:0` — `actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=ore tools/e2e.sh` | `FAIL: SELFTEST ore: the ore dropped Black Quartz (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-ore.log` |
| counterfactual | `SELFTEST=1 tools/e2e.sh` | `FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| counterfactual | `NEGATIVE=1 tools/e2e.sh` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour) …` + `EXIT:1` — `e2e-launcher-negative.log` |
| control | `GAME=$CONTROL_GAME tools/e2e.sh` (same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=5 ok=5` |

The launcher build the leg used is `native-0a875da-5b58559626c6`, exported to
`~/.cache/horizon-e2e/0a875da/actuallyadditions/`. The 0.2.4 block below is superseded; its
`SELFTEST=drops` log moved to `actuallyadditions-e2e/retired-0.2.4/`.

**0.2.5 investigation (2026-11-23, pin `0a875da`)** — historical: the brief's "restonia crystal
growth" was **not in the artefact**; that dispatch stopped **blocked** and produced no package. The
version number went to slice 4 above. The record is in `notes.md` → "0.2.5 investigation #1".

| Check | Command | Result |
|---|---|---|
| artefact audit | `tools/audit_restonia_source.sh` | 499 lines, exit 0: no growth tick, no seed item, no cluster worldgen feature, no cluster recipe; `restonia_crystal` = the Atomic Reconstructor's `#c:dusts/redstone` conversion; `black_quartz` = ore feature + engineer-house loot — `evidence/actuallyadditions/restonia-source-audit.log` |
| recipe keys | `python3 tools/check_recipe_keys.py` | `blocked actuallyadditions:crusher: restonia_crystal_source — actuallyadditions:restonia_crystal`; `2 recipe(s), 1 craftable, 1 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys-blocker-rename.log` |
| tooling | `python3 -m py_compile tools/craft_check.py`; `bash -n tools/e2e.sh` | both clean |
| package unchanged | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** — `110,156 B`, sha256 `f7767eba…dd1d67`, `package matches the tree`, packed `Cargo.lock`, 103 entries |

No ladder, no build and no in-game leg: nothing in `src/`, `assets/` or `data/` changed. The 0.2.4 block
below remains the current evidence for the delivered package.

**0.2.4 (2026-11-23, pin `0a875da`)** — slice 3: the Iron Casing block, the Basic Coil item and the
`c:cobblestones` item tag, so the Coal Generator's own recipe resolves and crafts. No Rust change
(`src/*.rs` byte-identical to 0.2.3).

| Check | Command | Result |
|---|---|---|
| content rule | `python3 tools/check_recipe_keys.py` | red on the pre-slice `data/` (`coal_generator: unresolved #c:cobblestones, actuallyadditions:iron_casing`, exit 1), green after (`2 recipe(s), 1 craftable, 1 blocked, 0 failure(s)`) — `evidence/actuallyadditions/check-recipe-keys-red.log`, `check-recipe-keys.log` |
| tests | `cargo test --offline` | **31 passed / 0 failed**, `Compiling actuallyadditions v0.2.4` — `evidence/actuallyadditions/sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| package | `cargo horizon-mod build` twice, **lock kept** | **110,156 B** both, `cmp` identical, sha256 `f7767eba…dd1d67`, **103 entries with `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log`, `sdk-sha256.txt` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | EXIT 0 (`actuallyadditions 0.2.4 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`) — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` (a tautology) |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** (includes the packed lock) |
| in-game | `tools/e2e.sh --offscreen` on the launcher-built game | `PASS` + `EXIT:0` — `evidence/actuallyadditions-e2e/e2e-launcher.log`; the crafting phase's own line is `recipe PASS: …` |
| counterfactual | `NEGATIVE=1 tools/e2e.sh` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour) …` + `EXIT:1` — `e2e-launcher-negative.log` |
| counterfactual | `SELFTEST=1 tools/e2e.sh` | `FAIL: SELFTEST flipped: the placed machine kept 2620 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| counterfactual | `SELFTEST=drops tools/e2e.sh` | `FAIL: SELFTEST drops: the payload carries no Items …` + `EXIT:1` — `e2e-launcher-selftest-drops.log` |
| control | the same script on the same Nightly **without** the package | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=5 ok=5` |

Every log prints the package's sha256 and size it was run against (and `sdk-test.log` the three
source hashes). The launcher build is `native-0a875da-f3eb138168ab`, exported to
`~/.cache/horizon-e2e/0a875da/actuallyadditions/`. The 0.2.3 logs are the ones this block
supersedes; 0.2.2 and 0.2.1 stay under `retired-0.2.2/` and `retired-0.2.1/`.

**0.2.3 (2026-11-23, pin `0a875da`)** — review fixes for `horizon-mods#1557` round 1: the drop
payload is an allowlist (no `Items`), the registry `Cargo.lock` ships, the upstream MIT notice is
verbatim.

| Check | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **31 passed / 0 failed** (`runtime::` 17, `support::` 14) — `evidence/actuallyadditions/sdk-test.log`; the new rule's red run is `sdk-test-red-payload.log` (30 passed, 1 failed) |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --manifest-path ports/actuallyadditions/Cargo.toml --check` | exit 0 — `sdk-fmt.log` |
| package | `cargo horizon-mod build` twice, **lock kept** | 105,538 B, `cmp` identical, sha256 `e0b1f95a…9600`, **91 entries with `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | EXIT 0 (`actuallyadditions 0.2.3 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`) — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` (a tautology) |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** (includes the packed lock) |
| in-game | `tools/e2e.sh` on the launcher-built game | `PASS` + `EXIT:0` — `evidence/actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=drops tools/e2e.sh` | `FAIL: SELFTEST drops: the payload carries no Items (the fixed behaviour) …` + `EXIT:1` — `e2e-launcher-selftest-drops.log` |
| counterfactual | `SELFTEST=1 tools/e2e.sh` | `FAIL: SELFTEST flipped: the placed machine kept 2820 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| control | the same script on the same Nightly **without** the package | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=4 ok=4` |

Every log prints the package's sha256 and size it was run against (and `sdk-test.log` the three
source hashes). The launcher build used for the in-game leg is a `native-0a875da-…` build exported
to `~/.cache/horizon-e2e/0a875da/actuallyadditions/`. The 0.2.2 logs are under
`evidence/actuallyadditions-e2e/retired-0.2.2/`.

**0.2.2 (2026-11-21, pin `0a875da`)** — slice 2: a broken machine keeps its saved state.

| Check | Command | Result |
|---|---|---|
| tests | `cargo test --offline` | **30 passed / 0 failed** (`runtime::` 17, `support::` 13) — `evidence/actuallyadditions/sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| package | `rm -f Cargo.lock && cargo horizon-mod build`, twice | 100,946 B, `cmp` identical, sha256 `483f4e11…e253ad`, **90 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | EXIT 0 (`actuallyadditions 0.2.2 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`) — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` (a tautology) |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** |
| in-game | `tools/e2e.sh` on the launcher-built game | `PASS` + `EXIT:0` — `evidence/actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=1 tools/e2e.sh` | `FAIL: SELFTEST flipped: the placed machine kept 2820 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| control | the same script on the same Nightly **without** the package | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=3 ok=3` |

Every log prints the package's sha256 and size it was run against (and `sdk-test.log` the three
source hashes). The launcher build used for the in-game leg is
`native-0a875da-ec01b0d091ee`, exported to `~/.cache/horizon-e2e/0a875da/actuallyadditions/`.

Historical: the 0.2.1 and 0.2.0 logs are under
`evidence/actuallyadditions/retired-0.2.1/` and `evidence/actuallyadditions-e2e/retired-0.2.1/`;
they were made at `0b14f8a` and describe the same code without slice 2. The 0.1.0 `.hnmod` runs
below remain the record of the retired container.

## 0.1.0 (the retired `.hnmod` bundle) — historical

Validated on Linux with Rust 1.95.0 on 2026-10-30 and again at the campaign pin
`1d63e0a5` on 2026-11-09, against the `.hnmod` container the mod-API merge has since retired. The
paths it names (`compatibility.json`, `tools/horizon.py`, `tools/test_template.py`,
`tools/test_stage.py`) are in `ports/_shared/evidence/actuallyadditions/retired-hnmod-0.1.0/` and
do not exist in this package.

| Check | Result |
|---|---|
| `cargo fmt --all --check` | Pass |
| `cargo clippy --workspace --all-targets --locked --offline -- -D warnings` | Pass |
| `cargo test --workspace --locked --offline` | 15 runtime tests pass |
| `python3 tools/test_template.py` | The bundle compiled in the fixture; AST audit, shared runtime, unchanged bytes and revision refusal passed |
| `python3 tools/test_stage.py` | The pinned Horizon export staged deterministically; the checkout was unchanged |
| `python3 tools/horizon.py check` / `test` | The game checked with 0 warnings; the 15 embedded tests passed |
| `tools/e2e.sh` + `SELFTEST=1` | `PASS` + `EXIT:0`; the flipped assertion `FAIL` + `EXIT:1` |
