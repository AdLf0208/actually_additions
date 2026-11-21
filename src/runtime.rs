// Pure machine logic for Actually Additions slice 2 (Coal Generator, Crusher, and the
// state a broken machine carries on its item).
//
// This file is both the standalone Cargo library and the injected
// `crate::game::actuallyadditions` module. It has no game types: the hook
// glue in `support.rs` converts block entities, item stacks and the engine's
// fuel values into the small values used here.

use serde_json::Value;

/// Upstream `CustomEnergyStorage(60000, 0, 80)`.
pub const GENERATOR_CAPACITY: i32 = 60_000;
/// The most one extract call/side moves (upstream `maxExtract`).
pub const GENERATOR_MAX_EXTRACT: i32 = 80;
/// Upstream `ENERGY_PER_TICK`.
pub const GENERATOR_ENERGY_PER_TICK: i32 = 20;
/// Upstream `CustomEnergyStorage(60000, 100, 0)`.
pub const CRUSHER_CAPACITY: i32 = 60_000;
/// The most one insert call/side moves (upstream `maxReceive`).
pub const CRUSHER_MAX_INSERT: i32 = 100;
/// Upstream `ENERGY_USE`, spent each tick while crushing.
pub const CRUSHER_ENERGY_PER_TICK: i32 = 40;
/// Upstream `getMaxCrushTime()` for the single Crusher.
pub const CRUSHER_TICKS: u32 = 100;

/// Energy clamped into a buffer.
#[must_use]
pub fn clamp_energy(energy: i32, capacity: i32) -> i32 {
    energy.clamp(0, capacity.max(0))
}

/// `floor(energy / capacity * 15)`, as upstream's `getComparatorStrength`.
#[must_use]
pub fn comparator_strength(energy: i32, capacity: i32) -> i32 {
    if capacity <= 0 {
        return 0;
    }
    let strength = (i64::from(energy.max(0)) * 15 / i64::from(capacity)) as i32;
    strength.clamp(0, 15)
}

/// The Coal Generator's saved state (`energy`, `burn`, `burn_max`).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Generator {
    pub energy: i32,
    pub burn: u32,
    pub burn_max: u32,
}

impl Generator {
    /// The empty generator.
    #[must_use]
    #[allow(dead_code, reason = "pure API; the glue fills the state from NBT")]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn burning(&self) -> bool {
        self.burn > 0
    }

    /// Upstream's refuel gate: not redstone-powered, no burn left, room in the
    /// buffer.
    #[must_use]
    pub fn wants_fuel(&self, powered: bool) -> bool {
        !powered && !self.burning() && self.energy < GENERATOR_CAPACITY
    }

    /// Take one fuel item's burn time. False when nothing was taken.
    pub fn load_fuel(&mut self, burn_time: u32) -> bool {
        if self.burning() || !is_fuel(burn_time) {
            return false;
        }
        self.burn = burn_time;
        self.burn_max = burn_time;
        true
    }

    /// One server tick: burn one tick of fuel and make 20 FE. Returns the FE
    /// actually stored (0 when not burning or full).
    pub fn tick(&mut self) -> i32 {
        if !self.burning() {
            return 0;
        }
        self.burn -= 1;
        let produced = GENERATOR_ENERGY_PER_TICK.min(GENERATOR_CAPACITY - self.energy);
        let produced = produced.max(0);
        self.energy += produced;
        produced
    }
}

/// One entry of a crushing recipe's `result` list.
#[derive(Clone, Debug, PartialEq)]
pub struct CrushResult {
    pub item: String,
    pub count: i32,
    /// 0.0..=1.0; the guaranteed (first) result is 1.0 unless the file says so.
    pub chance: f32,
}

/// A `actuallyadditions:crushing` recipe, read from the pin's custom-recipe
/// table.
#[derive(Clone, Debug, PartialEq)]
pub struct CrushingRecipe {
    pub id: String,
    pub results: Vec<CrushResult>,
}

/// Why a crushing recipe's JSON was refused.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RecipeError {
    MissingIngredient,
    MissingResult,
    TooManyResults,
    BadResult,
    BadChance,
}

impl std::fmt::Display for RecipeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = match self {
            RecipeError::MissingIngredient => "missing ingredient",
            RecipeError::MissingResult => "missing result",
            RecipeError::TooManyResults => "more than two results",
            RecipeError::BadResult => "a result without an item id or a positive count",
            RecipeError::BadChance => "a chance outside 0..=1",
        };
        f.write_str(text)
    }
}

impl std::error::Error for RecipeError {}

impl CrushingRecipe {
    /// Parse a recipe file. The JSON is the pin's custom-recipe JSON, unchanged
    /// from 1.21.1 (the custom table keeps it as written).
    pub fn parse(id: &str, json: &str) -> Result<Self, RecipeError> {
        let value: Value =
            serde_json::from_str(json).map_err(|_| RecipeError::MissingIngredient)?;
        if value.get("ingredient").is_none() {
            return Err(RecipeError::MissingIngredient);
        }
        let results = value
            .get("result")
            .and_then(Value::as_array)
            .ok_or(RecipeError::MissingResult)?;
        if results.is_empty() {
            return Err(RecipeError::MissingResult);
        }
        if results.len() > 2 {
            return Err(RecipeError::TooManyResults);
        }
        let mut parsed = Vec::with_capacity(results.len());
        for entry in results {
            let stack = entry.get("result").ok_or(RecipeError::BadResult)?;
            let item = stack
                .get("id")
                .and_then(Value::as_str)
                .ok_or(RecipeError::BadResult)?;
            let count = stack.get("count").and_then(Value::as_i64).unwrap_or(1);
            if item.is_empty() || !(1..=99).contains(&count) {
                return Err(RecipeError::BadResult);
            }
            let chance = entry.get("chance").map_or(Ok(1.0), |chance| {
                chance
                    .as_f64()
                    .map(|c| c as f32)
                    .ok_or(RecipeError::BadChance)
            })?;
            if !(0.0..=1.0).contains(&chance) {
                return Err(RecipeError::BadChance);
            }
            parsed.push(CrushResult {
                item: item.to_owned(),
                count: count as i32,
                chance,
            });
        }
        Ok(CrushingRecipe {
            id: id.to_owned(),
            results: parsed,
        })
    }

    /// The always-produced first result.
    #[must_use]
    pub fn guaranteed(&self) -> &CrushResult {
        &self.results[0]
    }

    /// The chance-gated second result, when the recipe has one.
    #[must_use]
    pub fn bonus(&self) -> Option<&CrushResult> {
        self.results.get(1)
    }
}

/// Whether `result` fits an output slot holding `slot` (item id and count).
#[must_use]
pub fn output_fits(slot: Option<(&str, i32)>, result: &CrushResult, max_stack: i32) -> bool {
    match slot {
        None => true,
        Some((item, count)) => item == result.item && count + result.count <= max_stack,
    }
}

/// Upstream `canCrushOn`: the guaranteed output must fit slot 1 and the bonus
/// output (when present) must fit slot 2.
#[must_use]
pub fn can_crush(
    recipe: &CrushingRecipe,
    output_one: Option<(&str, i32)>,
    output_two: Option<(&str, i32)>,
    max_stack: impl Fn(&str) -> i32,
) -> bool {
    output_fits(
        output_one,
        recipe.guaranteed(),
        max_stack(&recipe.guaranteed().item),
    ) && recipe
        .bonus()
        .is_none_or(|bonus| output_fits(output_two, bonus, max_stack(&bonus.item)))
}

/// What one tick of the Crusher did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Step {
    /// Nothing to crush (a missing recipe or a full output): progress resets.
    Idle,
    /// Out of FE: progress is kept, as upstream keeps the timer.
    Starved,
    /// One tick closer to the operation.
    Working,
    /// The operation finished this tick; progress is back to 0.
    Finished,
}

/// The Crusher's saved state (`energy`, `progress`).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Crusher {
    pub energy: i32,
    pub progress: u32,
}

impl Crusher {
    /// The empty crusher.
    #[must_use]
    #[allow(dead_code, reason = "pure API; the glue fills the state from NBT")]
    pub fn new() -> Self {
        Self::default()
    }

    /// One server tick. `has_work` is `can_crush` for this tick's input.
    pub fn tick(&mut self, has_work: bool) -> Step {
        if !has_work {
            self.progress = 0;
            return Step::Idle;
        }
        if self.energy < CRUSHER_ENERGY_PER_TICK {
            return Step::Starved;
        }
        self.energy -= CRUSHER_ENERGY_PER_TICK;
        self.progress += 1;
        if self.progress >= CRUSHER_TICKS {
            self.progress = 0;
            Step::Finished
        } else {
            Step::Working
        }
    }
}

/// The bonus result for a `[0.0, 1.0)` roll: upstream's `roll <= chance`.
#[must_use]
pub fn bonus_for(recipe: &CrushingRecipe, roll: f32) -> Option<&CrushResult> {
    recipe.bonus().filter(|result| roll <= result.chance)
}

/// A 1.21.1 ingredient (`{"item": ...}` / `{"tag": ...}` / a list) as the
/// pin's `native_recipe_ingredient` names it (`"id"` / `"#tag"` / a list).
#[must_use]
pub fn ingredient_json(value: &Value) -> Value {
    match value {
        Value::Object(object) => {
            if let Some(item) = object.get("item").and_then(Value::as_str) {
                Value::String(item.to_owned())
            } else if let Some(tag) = object.get("tag").and_then(Value::as_str) {
                Value::String(format!("#{tag}"))
            } else {
                value.clone()
            }
        }
        Value::Array(entries) => Value::Array(entries.iter().map(ingredient_json).collect()),
        _ => value.clone(),
    }
}

/// A fuel item's burn time, from the engine's item table (upstream
/// `getBurnTime(RecipeType.SMELTING)`); 0 is "not a fuel".
#[must_use]
pub fn is_fuel(burn_time: u32) -> bool {
    burn_time > 0
}

// ---------------------------------------------------------------------------
// The state a broken machine carries on its item (upstream's `actuallyadditions:energy`)
// ---------------------------------------------------------------------------

/// What a generator comes back with when its item is placed again. A broken machine's item
/// carries the block entity's saved compound and vanilla applies it whole, so a stale or edited
/// item can name any int: this clamps it into the buffer and the burn the machine declares.
#[must_use]
pub fn restored_generator(energy: i32, burn: i32, burn_max: i32) -> Generator {
    let burn_max = burn_max.max(0) as u32;
    Generator {
        energy: clamp_energy(energy, GENERATOR_CAPACITY),
        burn: (burn.max(0) as u32).min(burn_max),
        burn_max,
    }
}

/// What a crusher comes back with: its buffer clamped, and its progress never at or past the
/// tick that would finish the operation (`Crusher::tick` resets progress at `CRUSHER_TICKS`).
#[must_use]
pub fn restored_crusher(energy: i32, progress: i32) -> Crusher {
    Crusher {
        energy: clamp_energy(energy, CRUSHER_CAPACITY),
        progress: (progress.max(0) as u32).min(CRUSHER_TICKS - 1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn recipe(json: &str) -> CrushingRecipe {
        CrushingRecipe::parse("actuallyadditions:crushing/test", json).unwrap()
    }

    const COAL_ORE: &str = r#"{
        "type": "actuallyadditions:crushing",
        "ingredient": { "item": "minecraft:coal_ore" },
        "result": [ { "result": { "count": 3, "id": "minecraft:coal" } } ]
    }"#;

    const GRAVEL: &str = r#"{
        "type": "actuallyadditions:crushing",
        "ingredient": { "item": "minecraft:gravel" },
        "result": [
            { "result": { "count": 1, "id": "minecraft:flint" } },
            { "chance": 0.5, "result": { "count": 1, "id": "minecraft:flint" } }
        ]
    }"#;

    #[test]
    fn a_parsed_recipe_keeps_its_id_and_results_in_file_order() {
        let recipe = recipe(COAL_ORE);
        assert_eq!(recipe.id, "actuallyadditions:crushing/test");
        assert_eq!(
            recipe.results,
            vec![CrushResult {
                item: "minecraft:coal".into(),
                count: 3,
                chance: 1.0
            }]
        );
        assert!(recipe.bonus().is_none());
    }

    #[test]
    fn a_missing_chance_defaults_to_certain_and_the_second_is_the_chance_one() {
        let recipe = recipe(GRAVEL);
        assert_eq!(recipe.guaranteed().chance, 1.0);
        let bonus = recipe.bonus().expect("gravel has a second result");
        assert_eq!(bonus.item, "minecraft:flint");
        assert_eq!(bonus.chance, 0.5);
    }

    #[test]
    fn a_broken_recipe_is_refused_with_the_reason() {
        assert_eq!(
            CrushingRecipe::parse("x:y", r#"{"result": []}"#),
            Err(RecipeError::MissingIngredient)
        );
        assert_eq!(
            CrushingRecipe::parse("x:y", r#"{"ingredient": {"item": "minecraft:stone"}}"#),
            Err(RecipeError::MissingResult)
        );
        assert_eq!(
            CrushingRecipe::parse(
                "x:y",
                r#"{"ingredient": {"item": "minecraft:stone"},
                    "result": [{"result": {"id": "minecraft:sand", "count": 1}},
                               {"result": {"id": "minecraft:sand", "count": 1}},
                               {"result": {"id": "minecraft:sand", "count": 1}}]}"#
            ),
            Err(RecipeError::TooManyResults)
        );
        assert_eq!(
            CrushingRecipe::parse(
                "x:y",
                r#"{"ingredient": {"item": "minecraft:stone"},
                    "result": [{"result": {"count": 1}}]}"#
            ),
            Err(RecipeError::BadResult)
        );
        assert_eq!(
            CrushingRecipe::parse(
                "x:y",
                r#"{"ingredient": {"item": "minecraft:stone"},
                    "result": [{"result": {"id": "minecraft:sand", "count": 1},
                                "chance": 1.5}]}"#
            ),
            Err(RecipeError::BadChance)
        );
    }

    #[test]
    fn the_generator_makes_twenty_a_tick_while_burning() {
        let mut generator = Generator::new();
        assert_eq!(generator.tick(), 0, "no fuel, no energy");
        assert!(generator.load_fuel(1600));
        assert_eq!(generator.tick(), 20);
        assert_eq!(generator.energy, 20);
        assert_eq!(generator.burn, 1599);
    }

    #[test]
    fn the_generator_stops_fueling_while_it_burns_is_powered_or_full() {
        let mut generator = Generator::new();
        assert!(generator.wants_fuel(false));
        assert!(!generator.wants_fuel(true), "redstone stops refuelling");
        assert!(generator.load_fuel(1600));
        assert!(!generator.wants_fuel(false), "still burning");
        assert!(!generator.load_fuel(1600), "no second item while burning");

        let full = Generator {
            energy: GENERATOR_CAPACITY,
            ..Generator::new()
        };
        assert!(!full.wants_fuel(false), "a full buffer takes no fuel");
    }

    #[test]
    fn a_full_generator_burns_without_storing_more() {
        let mut generator = Generator {
            energy: GENERATOR_CAPACITY - 5,
            burn: 2,
            burn_max: 2,
        };
        assert_eq!(generator.tick(), 5);
        assert_eq!(generator.energy, GENERATOR_CAPACITY);
        assert_eq!(generator.burn, 1);
        assert_eq!(generator.tick(), 0, "the cap eats the production");
        assert_eq!(generator.energy, GENERATOR_CAPACITY);
    }

    #[test]
    fn a_non_fuel_item_has_no_burn_time_and_loads_nothing() {
        assert!(!is_fuel(0));
        assert!(is_fuel(1600));
        let mut generator = Generator::new();
        assert!(!generator.load_fuel(0));
        assert_eq!(generator, Generator::new());
    }

    #[test]
    fn the_comparator_follows_the_buffer_in_fifteen_steps() {
        assert_eq!(comparator_strength(0, GENERATOR_CAPACITY), 0);
        assert_eq!(
            comparator_strength(GENERATOR_CAPACITY, GENERATOR_CAPACITY),
            15
        );
        assert_eq!(comparator_strength(30_000, GENERATOR_CAPACITY), 7);
        assert_eq!(
            comparator_strength(GENERATOR_CAPACITY * 2, GENERATOR_CAPACITY),
            15,
            "a stale over-capacity read still answers 15"
        );
    }

    #[test]
    fn energy_clamps_to_the_buffer() {
        assert_eq!(clamp_energy(-1, 100), 0);
        assert_eq!(clamp_energy(40, 100), 40);
        assert_eq!(clamp_energy(140, 100), 100);
    }

    #[test]
    fn an_output_fits_only_an_empty_slot_or_the_same_item_with_room() {
        let result = CrushResult {
            item: "minecraft:coal".into(),
            count: 3,
            chance: 1.0,
        };
        assert!(output_fits(None, &result, 64));
        assert!(output_fits(Some(("minecraft:coal", 61)), &result, 64));
        assert!(!output_fits(Some(("minecraft:coal", 62)), &result, 64));
        assert!(!output_fits(Some(("minecraft:stone", 0)), &result, 64));
    }

    #[test]
    fn a_second_result_needs_room_in_the_other_slot() {
        let recipe = recipe(GRAVEL);
        let fits = |slot| output_fits(slot, recipe.guaranteed(), 64);
        assert!(can_crush(&recipe, None, None, |_| 64));
        assert!(
            can_crush(&recipe, Some(("minecraft:flint", 0)), None, |_| 64),
            "slot one holds flint with room"
        );
        assert!(
            !can_crush(&recipe, None, Some(("minecraft:stone", 0)), |_| 64),
            "a stone in the bonus slot stops the operation"
        );
        assert!(!fits(Some(("minecraft:stone", 0))));
    }

    #[test]
    fn one_operation_costs_four_thousand_and_takes_a_hundred_ticks() {
        let mut crusher = Crusher {
            energy: 4_000,
            progress: 0,
        };
        for tick in 1..=CRUSHER_TICKS {
            let step = crusher.tick(true);
            if tick < CRUSHER_TICKS {
                assert_eq!(step, Step::Working, "tick {tick}");
            } else {
                assert_eq!(step, Step::Finished, "tick {tick}");
            }
        }
        assert_eq!(crusher.energy, 0);
        assert_eq!(crusher.progress, 0);
    }

    #[test]
    fn a_starved_crusher_keeps_its_progress_and_an_idle_one_resets() {
        let mut crusher = Crusher {
            energy: CRUSHER_ENERGY_PER_TICK,
            progress: 0,
        };
        assert_eq!(crusher.tick(true), Step::Working);
        assert_eq!(crusher.progress, 1);
        assert_eq!(crusher.tick(true), Step::Starved);
        assert_eq!(crusher.progress, 1, "upstream keeps the timer while short");
        crusher.energy = CRUSHER_ENERGY_PER_TICK;
        assert_eq!(crusher.tick(false), Step::Idle);
        assert_eq!(crusher.progress, 0, "no work resets the timer");
    }

    #[test]
    fn an_upstream_ingredient_becomes_the_pins_json() {
        assert_eq!(
            ingredient_json(&serde_json::json!({"item": "minecraft:coal_ore"})),
            serde_json::json!("minecraft:coal_ore")
        );
        assert_eq!(
            ingredient_json(&serde_json::json!({"tag": "c:ores"})),
            serde_json::json!("#c:ores")
        );
        assert_eq!(
            ingredient_json(&serde_json::json!([
                {"item": "minecraft:gravel"},
                {"tag": "minecraft:coals"}
            ])),
            serde_json::json!(["minecraft:gravel", "#minecraft:coals"])
        );
        assert_eq!(
            ingredient_json(&serde_json::json!("minecraft:stone")),
            serde_json::json!("minecraft:stone")
        );
    }

    #[test]
    fn the_bonus_roll_is_inclusive_like_upstream() {
        let gravel = recipe(GRAVEL);
        assert_eq!(
            bonus_for(&gravel, 0.5).map(|r| r.item.as_str()),
            Some("minecraft:flint")
        );
        assert!(bonus_for(&gravel, 0.500_1).is_none());
        assert!(bonus_for(&gravel, 0.0).is_some());
        assert!(
            bonus_for(&recipe(COAL_ORE), 0.0).is_none(),
            "a single-result recipe never rolls"
        );
    }

    #[test]
    fn a_restored_generator_is_clamped_into_its_buffer_and_burn() {
        assert_eq!(
            restored_generator(1_940, 1_503, 1_600),
            Generator {
                energy: 1_940,
                burn: 1_503,
                burn_max: 1_600
            },
            "a machine broken mid-burn comes back exactly as it was"
        );
        assert_eq!(
            restored_generator(70_000, -5, 1_600),
            Generator {
                energy: GENERATOR_CAPACITY,
                burn: 0,
                burn_max: 1_600
            },
            "a stale buffer clamps to capacity and a negative burn is empty"
        );
        assert_eq!(
            restored_generator(100, 2_000, 1_600),
            Generator {
                energy: 100,
                burn: 1_600,
                burn_max: 1_600
            },
            "a burn past its own maximum would burn longer than its fuel allows"
        );
        assert_eq!(
            restored_generator(0, 5, 0),
            Generator::new(),
            "burn without a maximum is no burn"
        );
    }

    #[test]
    fn a_restored_crusher_cannot_start_at_the_end_of_an_operation() {
        assert_eq!(
            restored_crusher(3_600, 50),
            Crusher {
                energy: 3_600,
                progress: 50
            }
        );
        assert_eq!(
            restored_crusher(70_000, 120),
            Crusher {
                energy: CRUSHER_CAPACITY,
                progress: CRUSHER_TICKS - 1
            },
            "progress starts before the tick that would finish, never at or past it"
        );
        assert_eq!(restored_crusher(-1, -3), Crusher::new());
    }
}
