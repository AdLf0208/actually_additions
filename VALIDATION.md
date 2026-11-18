# Validation

**0.2.0 (the SDK package, 2026-11-18)** is validated by the migration ladder in
[`notes.md`](notes.md) → "Migration to the SDK format": `cargo test` **26 passed / 0 failed**
(15 `runtime::`, 11 `support::`), `cargo clippy --all-targets -- -D warnings` **0 warnings**,
`cargo fmt --check` clean, `cargo horizon-mod build` twice with the same 95,503 B /
sha256 `2367bd09…c311`, `cargo horizon-mod check` and `fits --build nightly` exit 0, and
`unzip -p actuallyadditions.hmod src/runtime.rs | sha256sum` equal to the retired
`mixins/actuallyadditions/runtime.rs` (`df6c993a…c683`). Every log is under
`ports/_shared/evidence/actuallyadditions/sdk-*.log`.

**No 0.2.0 in-game run exists.** A native `.hmod` is built by `horizon-launcher native-build`,
which is not installed in this environment; `tools/e2e.sh` is updated for a launcher-built game
(`GAME=`, optional `CONTROL_GAME=`, `SELFTEST=1`) and unrun. The 0.1.0 runs below remain the
behaviour's evidence, for a `src/runtime.rs` that did not change.

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
