# Validation

**0.2.13 (2026-11-24, pin `0a875da`)** — slice 12: the **killer lens's own beam effect**. Every
cargo step was forwarded to the remote runner (`REMOTE_HOST` defaults to `deepseek@192.168.1.115`,
whose hostname is `AdLf-PC`; no `BUILD_LOCAL=1` for the cargo steps); the launcher build ran in a
**local** slot because the far box lacks `libxkbcommon-x11.so.0`. The artefact is `LensKiller extends
LensDeath` (`cd9d9c63`): 2,500 CF per entity after the 1,000 CF gate, 20 damage through
`playerAttack(FakePlayerFactory.getMinecraft)`, the hit cell's `AABB` queried before the air check,
reach 15, stop on non-air. The **lens item is `actuallyadditions:lens_of_the_killer`** —
`lens_of_certain_death` is plain `LensDeath` (350 CF). First gate: `EntityRef::hurt` and the
fake-player factory both exist; the pin has no `DamageSource` object, so the source is the
`minecraft:player_attack` type string with a connectionless fake as its `causing` handle.

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline`, the killer rules undefined | **12 errors**, `cannot find value LENS_OF_THE_KILLER`, `cannot find value KILLER_LENS_ENERGY`, `cannot find value KILLER_DAMAGE`, `no variant … named Killer`, `cannot find function killer_stop` — `evidence/actuallyadditions/sdk-test-red-killer.log` |
| tests | `cargo test --offline` | **70 passed / 0 failed** (51 runtime incl. 4 json and 28 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.13` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `7 recipe(s), 36 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | **181,126 B** both, `cmp` identical, sha256 `5812fce939c1a12b45975812e134c459f42d6cc19c76f43fd8d306af68f2c39c`, **205 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.13 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 181,126 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1**, `package matches the tree`, R9 rows green — `verify-gate-0.2.13.log` |
| launcher build | stale 0.2.13 `native-*` tags moved aside, `native-0a875da-ebec6a089275` | `Compiling actuallyadditions (1 of 1)` — `launcher-build-0.2.13.log` |
| in-game | `tools/e2e.sh` (`--offscreen`, the final package's launcher build) | `PASS` + `EXIT:0` — `e2e-launcher.log` (first line names the delivered sha) |
| counterfactual | `SELFTEST=killer` | `FAIL:` + `EXIT:1` — `e2e-launcher-selftest-killer.log` |
| counterfactual | `SELFTEST={detonation,lens-effect,lens,1,drops,ore,laser,item,pulse}` | each `FAIL:` + `EXIT:1` — the nine earlier selftest logs |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour)` + `EXIT:1` — `e2e-launcher-negative.log` |
| control | `CONTROL=1` (the same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=13 ok=13 missing-exit=0 bad-exit=0`, exit 0 — `e2e-audit-0.2.13.log` |

The killer phase's own lines (`e2e-launcher.log`): the harness-given lens fills the slot and the
readout names `minecraft:stone -> killer @ 2500 CF`; a 3,500 CF shot hurts a NoAI cow in the sighted
**air** cell (the cell box is queried before the air check) — the cow's parsed health goes to 0 and
the buffer reads 0; the differential default-lens machine keeps its cow at health 10 and 2,500 CF.
A dead cow stays in `ctl entities` for a while at this pin, so the assertion is on parsed
`health > 0`, not on the list being empty. `SELFTEST=killer` flips it to "the cow survives and
2,500 CF is left", which this package makes false. The 12 earlier legs are unchanged and re-proved.

**0.2.12 (2026-11-24, pin `0a875da`)** — slice 11: the **detonator lens's own beam effect**. Every
cargo step was forwarded to the remote runner (`REMOTE_HOST=AdLf-PC`, no `BUILD_LOCAL=1` for the
cargo steps); the launcher build ran in a **local** slot because the far box lacks
`libxkbcommon-x11.so.0`. `LensDetonation.invoke` (`cd9d9c63`) spends 250,000 CF after the shot's
1,000 CF gate on a sourceless radius-10 blast with `fire=true` and `ExplosionInteraction.NONE`.
The artefact wins over the brief's proposed crater: at this pin `NONE` **keeps blocks**, so the
in-game leg proves the blast by its energy spend and its fire, and asserts the stone stays.

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline`, the three detonator rules undefined | **10 errors**, `cannot find value LENS_OF_DETONATION`, `cannot find value DETONATION_LENS_ENERGY`, `no variant Detonation`, `cannot find function detonation_stop` — `evidence/actuallyadditions/sdk-test-red-detonation.log` |
| tests | `cargo test --offline` | **67 passed / 0 failed** (48 runtime incl. 4 json and the detonator rules, 19 glue), `Compiling actuallyadditions v0.2.12` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `7 recipe(s), 36 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | **177,060 B** both, `cmp` identical, sha256 `abafd0075c23eeb80a7f1b25b3fdea0b0587719171a591d5774a8eecd6249a57`, **201 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.12 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 177,060 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1**, `package matches the tree`, R9 rows green — `verify-gate-0.2.12.log` |
| launcher build | `native-0a875da-301e07058952` | `Compiling actuallyadditions (1 of 1)` — `launcher-build-0.2.12.log` |
| in-game | `tools/e2e.sh` (`--offscreen`, the launcher build of this package) | `PASS` + `EXIT:0` — `e2e-launcher.log` (first line names the delivered sha) |
| counterfactual | `SELFTEST=detonation` | `FAIL: SELFTEST detonation: the shot spent 250000 CF and lit 50 fire block(s) (the real assertion)` + `EXIT:1` — `e2e-launcher-selftest-detonation.log` |
| counterfactual | `SELFTEST={lens-effect,lens,1,drops,ore,laser,item,pulse}` | each `FAIL:` + `EXIT:1` — the eight earlier selftest logs |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour)` + `EXIT:1` — `e2e-launcher-negative.log` |
| control | `CONTROL=1` (the same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=12 ok=12 missing-exit=0 bad-exit=0`, exit 0 — `e2e-audit-0.2.12.log` |

The detonator phase's own lines (`e2e-launcher.log`): the harness-given lens fills the slot and the
readout names `sight minecraft:stone -> detonation @ 250000 CF`; a 251,000 CF shot spends the gate
and the lens's 250,000 CF (buffer 0) and lights **53** fire blocks in the blast box, while the
sighted stone **stays** (the artefact's `NONE`), and the differential default-lens machine keeps
250,000 CF, starts no fire and keeps its stone. `SELFTEST=detonation` flips the assertion to
"nothing spent, no fire", which fails on this package.

**0.2.11 (2026-11-24, pin `0a875da`)** — slice 10: the **miner lens's own beam effect**. Every cargo
step was forwarded to the remote runner (`REMOTE_HOST=AdLf-PC`, no `BUILD_LOCAL=1`). The launcher
game was built locally (`Compiling actuallyadditions (1 of 1)`, `native-0a875da-f6e610072fc5`).
The jar's 20 top-level `mining_lens` recipes, the two `*_ore_replaceables` tags, the
`c:ore_bearing_ground/netherrack` tag and the miner lens item ship; with it installed a 61,000 CF
shot swaps the sighted stone for a weighted ore, while the plain lens keeps its stone.

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline`, the four miner rules at `todo!()` | **60 passed / 4 failed**, four named `not yet implemented`/assertion failures — `evidence/actuallyadditions/sdk-test-red-lens-effect.log` |
| tests | `cargo test --offline` | **64 passed / 0 failed** (45 runtime incl. 4 json, 19 glue), `Compiling actuallyadditions v0.2.11` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `7 recipe(s), 36 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | **174,980 B** both, `cmp` identical, sha256 `b360583de142d0bea5e0036396e4d9149efb9977b0216f1c95d1039c3a069838`, **201 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.11 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 174,980 bytes, EXIT 0 — `check-run-0.2.11.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1**, `package matches the tree`, R9 rows green — `verify-gate-0.2.11.log` |
| launcher build | stale `native-0a875da-e321921d7f83` removed, `native-0a875da-f6e610072fc5` | `Compiling actuallyadditions (1 of 1)` — `launcher-build-0.2.11.log` |
| in-game | `tools/e2e.sh` (`--offscreen`, the launcher build of this package) | `PASS` + `EXIT:0` — `e2e-launcher.log` (first line names the delivered sha) |
| counterfactual | `SELFTEST=lens-effect` | `FAIL: SELFTEST lens-effect: the stone was replaced (the real assertion); the flipped assertion 'the stone stays' fails, so the real one can fail` + `EXIT:1` — `e2e-launcher-selftest-lens-effect.log` |
| counterfactual | `SELFTEST={lens,1,drops,ore,laser,item,pulse}` | each `FAIL:` + `EXIT:1` — the seven earlier selftest logs |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour)` + `EXIT:1` — `e2e-launcher-negative.log` |
| control | `CONTROL=1` (the same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=11 ok=11 missing-exit=0 bad-exit=0`, exit 0 — `e2e-audit-0.2.11.log` |

The miner phase's own lines: the harness-given miner lens (its craft needs crystals this package
lacks) fills the slot; a 61,000 CF shot (1,000 gate + 60,000 miner) replaces `minecraft:stone` with
`minecraft:iron_ore` in the delivered run, read back with `ctl block`; the differential's plain lens
keeps its stone and spends exactly the gate (60,000 CF left). Three legs first exited 3 when a
concurrent port's game exhausted memory; re-run one at a time with ≥4 GB free, all green.

**0.2.10 (2026-11-24, pin `0a875da`)** — the **lens items and the lens slot**. Every cargo step
was forwarded to the second box (`build-slot: forwarding … to the remote runner`,
`REMOTE_HOST=AdLf-PC`); no `BUILD_LOCAL=1`. The launcher game was built locally so the
`--offscreen` e2e had its binary — `Compiling actuallyadditions (1 of 1)`,
`native-0a875da-b7cae93da59c`. The four lens ring items, the `lens` recipe and the four 5,000 CF
conversions are carried; a right click fills the slot, a non-lens and a second lens are refused,
and a dropped lens converts for gate + 5,000 CF.

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline`, `lens_slot_accepts` at `todo!()` | **59 passed / 1 failed**, `not yet implemented: the lens slot's acceptance rule` — `evidence/actuallyadditions/sdk-test-red-lens.log` |
| tests | `cargo test --offline` | **60 passed / 0 failed** (19 runtime, 4 json, 18 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.10` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `7 recipe(s), 16 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| package ×2 | `rm -f Cargo.lock && cargo horizon-mod build`, twice | **162,102 B** both, `cmp` identical, sha256 `63f263561061eede2b60fcd2886917004a998cc0321c302b32bfc02e6ca7b54b`, **174 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.10 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 162102 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1**, `package matches the tree`, R9 rows green |

| in-game | `tools/e2e.sh` (`--offscreen`, launcher build `native-0a875da-b7cae93da59c`) | `PASS` + `EXIT:0` — `e2e-launcher.log` (first line names the delivered sha, 162102 bytes) |
| counterfactual | `SELFTEST=lens` | `FAIL: SELFTEST lens: the slot accepted the lens (the real assertion); the flipped assertion 'it stays empty' fails, so the real one can fail` + `EXIT:1` — `e2e-launcher-selftest-lens.log` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2560 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=drops` | `FAIL: SELFTEST drops: the payload carries no Items (the fixed behaviour)` + `EXIT:1` |
| counterfactual | `SELFTEST=ore` | `FAIL: SELFTEST ore: the ore dropped Black Quartz (the real assertion)` + `EXIT:1` |
| counterfactual | `SELFTEST=laser` | `FAIL: SELFTEST laser: the beam made a crystal (the real assertion)` + `EXIT:1` |
| counterfactual | `SELFTEST=item` | `FAIL: SELFTEST item: the beam converted the dropped item (the real assertion)` + `EXIT:1` |
| counterfactual | `SELFTEST=pulse` | `FAIL: SELFTEST pulse: the rising edge fired a shot (the real assertion)` + `EXIT:1` |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour)` + `EXIT:1` |
| control | `CONTROL=1` (the same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=10  ok=10  missing-exit=0  bad-exit=0`, exit 0 |

All e2e legs stayed local: the brief's `build-slot.sh run … --step e2e` path (the workaround for
launcher-migrated ports) does not take the e2e forwarder's remote branch, and the script is
`--offscreen` (the far box has no renderer). Every cargo step was forwarded to `AdLf-PC`.
The 0.2.9 section follows.

**0.2.9 (2026-11-23, pin `0a875da`)** — packaging: the **registry's R9**. The automated check at
`495701cf` refused 0.2.8 (*"refused rules R9"*), because `Cargo.toml` declared
`serde_json = "=1.0.151"` and the package packed the lock that dependency forces; the registry
refuses any dependency but the SDK path dep, so a package with a registry dependency cannot be
published at all. The dependency is removed and `src/runtime.rs` reads the recipe JSON with its own
reader (`Json`: parse, `Display`, the accessors serde_json's `as_i64`/`as_f64` had), which is the
path the world's data packs feed — a table resolved at build time would freeze what a pack can
override. No family changed. The reversal of this campaign's old "pack the lock" rule, the choice
and the traps are in `notes.md` → "Slice 8" and "The registry `Cargo.lock` now ships — and 0.2.9
reverses it".

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline`, `Json::parse` at `todo!()` | **12 failed / 47 passed**, every failure the reader's own `not yet implemented` panic — `evidence/actuallyadditions/sdk-test-red-json.log` |
| tests | `cargo test --offline` after `cargo clean -p actuallyadditions` | **59 passed / 0 failed** (19 runtime, 4 json, 17 reconstructor, 19 glue), `Compiling actuallyadditions v0.2.9` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| package | `rm -f Cargo.lock && cargo horizon-mod build`, twice | **151,085 B** both, `cmp` identical, sha256 `964b0a83c110f3eabb00a763b338246dc7860eb241c2727705a94bcf8ccd9911`, **151 entries, no `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log`, `sdk-sha256.txt` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.9 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 151085 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` (the first attempt, with the local type named `Reader`, answered `does not fit — the type wire::Reader can no longer be built with a literal`; the name collided with the SDK's own surface, see `notes.md` trap 1) |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1**, R9 rows included (tables, SDK-only dependency, no build script, `[lib]` is `src/lib.rs`, no packed lock) |
| launcher build | `ports/tools/launcher-game.sh build actuallyadditions --rebuild` | `native-0a875da-90007b61b7ec`, `Compiling actuallyadditions (1 of 1)`, `native-mods.json` names `actuallyadditions 0.2.9` — `evidence/actuallyadditions/launcher-build.log` |
| in-game | `tools/e2e.sh` on the launcher build of this package | `PASS` + `EXIT:0` — `evidence/actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour), …` + `EXIT:1` — `e2e-launcher-negative.log` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2500 FE, not 0` + `EXIT:1` — `e2e-launcher-selftest.log` |
| counterfactual | `SELFTEST=drops` | `FAIL: SELFTEST drops: the payload carries no Items (the fixed behaviour); …` + `EXIT:1` — `e2e-launcher-selftest-drops.log` |
| counterfactual | `SELFTEST=ore` | `FAIL: SELFTEST ore: the ore dropped Black Quartz (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-ore.log` |
| counterfactual | `SELFTEST=laser` | `FAIL: SELFTEST laser: the beam made a crystal (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-laser.log` |
| counterfactual | `SELFTEST=item` | `FAIL: SELFTEST item: the beam converted the dropped item (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-item.log` |
| counterfactual | `SELFTEST=pulse` | `FAIL: SELFTEST pulse: the rising edge fired a shot (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-pulse.log` |
| control | `CONTROL=1` (the same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` — `e2e-launcher-control.log` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=9 ok=9` |

Every log prints the package's sha256 and size it was run against. The 0.2.9 scripts are
`evidence/actuallyadditions/{ladder,build,check}-0.2.9.sh` and
`evidence/actuallyadditions-e2e/run-leg-0.2.9.sh`; the 0.2.8 logs they replace stay in place as the
record of that version.

**0.2.8 (2026-11-23, pin `0a875da`)** — slice 7: the Atomic Reconstructor's **redstone mode** and the
**conversion's order**. `isPulseMode` is upstream's second mode: `serverTick` runs the 100-tick cycle only
under `!isRedstonePowered && !isPulseMode`, and a rising edge of `getBestNeighborSignal` fires one whole
shot (`activateOnPulse` → `invokeReconstructor`, the 1,000 CF gate included); a click holding
`CommonConfig.Other.redstoneConfigurator` — a config value whose default is `minecraft:redstone_torch` —
flips it and claims the click. The mode is saved, printed by `/actuallyadditions info` (`pulse on|off`)
and carried on the broken machine's item. The reviewer's finding on 0.2.6/0.2.7 is fixed in both
halves: the source goes first and its answer is checked, the result only then, the source is put back if
the result cannot be made, and the recipe's energy is charged only when the conversion happened
(`runtime::convert`). The rules, the artefact lines and the two pre-code checks are in `notes.md` →
"Slice 7"; the upstream defect is under "Upstream defects fixed" there.

| Check | Command | Result |
|---|---|---|
| rules (red) | `cargo test --offline` before the implementation | **12 failed / 44 passed**: six named `not yet implemented` panics (pulse ×3, restored mode, conversion ×3 at `src/runtime.rs:628/657/684`) and two `support` assertion failures (the `pulse off` field, the `pulse` payload key) — `evidence/actuallyadditions/sdk-test-red-pulse.log` |
| tests | `cargo test --offline` after `cargo clean -p actuallyadditions` | **56 passed / 0 failed** (20 runtime, 17 reconstructor — 8 rules + 3 pulse + 3 conversion + the restored-mode one, 19 glue), `Compiling actuallyadditions v0.2.8` — `sdk-test.log` |
| lints | `cargo clippy --all-targets --offline -- -D warnings` | exit 0, 0 warnings — `sdk-clippy.log` |
| format | `cargo fmt --check` | exit 0 — `sdk-fmt.log` |
| content rule | `python3 tools/check_recipe_keys.py` | `6 recipe(s), 11 craftable, 0 blocked, 0 failure(s)`, exit 0 — `check-recipe-keys.log` |
| package | `cargo horizon-mod build` twice, **lock kept** | **150,252 B** both, `cmp` identical, sha256 `5440228fe6a14f9fa35fedd6efe924c1c099a1d5832f466fb6d2438daf123097`, **152 entries with `Cargo.lock`** — `sdk-build.log`, `sdk-build-second.log`, `sdk-sha256.txt` |
| check | `cargo horizon-mod check actuallyadditions.hmod` | `actuallyadditions 0.2.8 (native-mod, format native-1/0a875da…/e59da90…, for 26.3)`, 150252 bytes, EXIT 0 — `sdk-check.log` |
| fits (pin) | `cargo horizon-mod fits … --build 0a875da` | `0a875da  made for`, EXIT 0 — `sdk-fits.log` |
| fits (different build) | `cargo horizon-mod fits … --build 0b14f8a` | `0b14f8a  fits`, EXIT 0 — `sdk-fits-other.log` |
| gate | `python3 ports/tools/verify-sdk-package.py actuallyadditions` | **1/1** (packed lock, tree match, runtime hash, skills gate) |
| in-game | `tools/e2e.sh` (`--offscreen`, launcher build `native-0a875da-f04bebbba937`) | `PASS` + `EXIT:0` — `actuallyadditions-e2e/e2e-launcher.log` |
| counterfactual | `SELFTEST=pulse` | `FAIL: SELFTEST pulse: the rising edge fired a shot (the real assertion); …` + `EXIT:1` — `e2e-launcher-selftest-pulse.log` |
| counterfactual | `SELFTEST=1` | `FAIL: SELFTEST flipped: the placed machine kept 2520 FE, not 0` + `EXIT:1` |
| counterfactual | `SELFTEST=drops` | `FAIL: SELFTEST drops: the payload carries no Items …` + `EXIT:1` |
| counterfactual | `SELFTEST=ore` | `FAIL: SELFTEST ore: …` + `EXIT:1` |
| counterfactual | `SELFTEST=laser` | `FAIL: SELFTEST laser: …` + `EXIT:1` |
| counterfactual | `SELFTEST=item` | `FAIL: SELFTEST item: …` + `EXIT:1` |
| counterfactual | `NEGATIVE=1` | `FAIL: NEGATIVE: the Coal Generator's recipe unlocked (0.2.4's behaviour), …` + `EXIT:1` |
| control | `GAME=$CONTROL_GAME` (same Nightly, no package) | `FAIL: expected actuallyadditions:coal_generator at 0,100,0, got 'minecraft:air'` + `EXIT:1` |
| log audit | `python3 ports/tools/check-e2e-logs.py actuallyadditions-e2e --strict` | `logs=9 ok=9` |

The pulse phase prints (from `e2e-launcher.log`): the machine placed reads `pulse off`; a stick click
leaves it off; a redstone-torch click reads `pulse on` and the cell above the machine is still air; 140
ticks with no signal leave `2080/300000 CF` and `cycle 97/100` untouched; the first rising edge gives
`1040/300000 CF` and one crystal, the falling edge nothing, a second rising edge `0/300000 CF` and two
crystals, the cycle still 97; and the same machine without the toggle stays at `2080/300000 CF` and
`cycle 56/100` across 147 ticks of the same signal. `src/runtime.rs` gained `Signal`, the mode and
`Conversion`/`convert`; `src/support.rs` the toggle click and the two `Conversion` implementations;
`src/lib.rs` is unchanged. Every log names the sha above.

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
