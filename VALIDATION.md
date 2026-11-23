# Validation

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
