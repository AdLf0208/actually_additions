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
// Where the Black Quartz Ore generates (upstream's `add_black_quartz` biome modifier)
// ---------------------------------------------------------------------------

/// Vanilla's generation steps (`GenerationStep.Decoration`), by name, in order. The SDK
/// refuses a modifier whose step is not one of these.
pub const VANILLA_GENERATION_STEPS: [&str; 11] = [
    "raw_generation",
    "lakes",
    "local_modifications",
    "underground_structures",
    "surface_structures",
    "strongholds",
    "underground_ores",
    "underground_decoration",
    "fluid_springs",
    "vegetal_decoration",
    "top_layer_modification",
];

/// A biome modifier as this port declares it, in the platform's vocabulary: which placed
/// feature is added, to which generation step, on which biomes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OreGeneration {
    /// The modifier's own id in the mod's namespace.
    pub id: &'static str,
    /// Biome ids or `#tags`.
    pub biomes: &'static [&'static str],
    /// The placed feature to add.
    pub feature: &'static str,
    /// The generation step to append it to.
    pub step: &'static str,
}

/// Upstream 1.3.26's `add_black_quartz` (`ActuallyBiomeModifiers.ADD_BLACK_QUARTZ_ORE_MODIFIER`):
/// `#minecraft:is_overworld`, `underground_ores`, the `actuallyadditions:ore_black_quartz`
/// placed feature. Upstream puts it behind its own `bool_config_feature_modifier` type and the
/// `generateQuartz` flag; the pin reads neither, so the port declares the same addition with
/// the platform's `add_features` operation and the ore always generates (recorded deviation).
#[must_use]
pub fn black_quartz_ore_generation() -> OreGeneration {
    OreGeneration {
        id: "add_black_quartz",
        biomes: &["#minecraft:is_overworld"],
        feature: "actuallyadditions:ore_black_quartz",
        step: "underground_ores",
    }
}

/// Whether `id` is `namespace:path` with both halves non-empty, as NeoForge ids are. The SDK
/// refuses a modifier naming `mymod` or `:thing`, so the declaration is checked here instead.
#[must_use]
pub fn is_namespaced(id: &str) -> bool {
    match id.split_once(':') {
        Some((namespace, path)) => !namespace.is_empty() && !path.is_empty(),
        None => false,
    }
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

// ---------------------------------------------------------------------------
// The Atomic Reconstructor and its laser conversion (upstream
// `TileEntityAtomicReconstructor`, `MethodHandler.invokeReconstructor` /
// `invokeConversionLens`, `LensConversion`, `LaserRecipe`)
// ---------------------------------------------------------------------------

/// Upstream `CommonConfig.Machines.RECONSTRUCTOR_POWER`'s default: the CF buffer.
pub const RECONSTRUCTOR_CAPACITY: i32 = 300_000;
/// `Mth.ceil(power * 0.016666F)` — the most one insert call moves.
pub const RECONSTRUCTOR_MAX_INSERT: i32 = 5_000;
/// Upstream `TileEntityAtomicReconstructor.ENERGY_USE`: one shot's gate, paid before the
/// beam walks and on top of the converting recipe's own energy.
pub const RECONSTRUCTOR_ENERGY_USE: i32 = 1_000;
/// The `currentTime` reset: a shot is attempted about once every hundred ticks.
pub const RECONSTRUCTOR_TICKS: u32 = 100;
/// `LensConversion.getDistance()`: the default conversion lens reaches ten blocks.
pub const RECONSTRUCTOR_LENS_DISTANCE: i32 = 10;
/// `invokeConversionLens`'s `range`: a shot converts the 3x3 plane it hits.
pub const RECONSTRUCTOR_CONVERSION_RANGE: i32 = 1;
/// Upstream's comparator: `clamp(energy / 20000, 0, 15)`, not the buffer's fifteenths.
pub const RECONSTRUCTOR_COMPARATOR_STEP: i32 = 20_000;

/// One of the six block directions, in upstream's `Direction` vocabulary.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Facing {
    Down,
    Up,
    North,
    South,
    West,
    East,
}

impl Facing {
    /// The state property's value (`facing=east`).
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Facing::Down => "down",
            Facing::Up => "up",
            Facing::North => "north",
            Facing::South => "south",
            Facing::West => "west",
            Facing::East => "east",
        }
    }

    /// The facing a state property names, `None` for anything else.
    #[must_use]
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "down" => Some(Facing::Down),
            "up" => Some(Facing::Up),
            "north" => Some(Facing::North),
            "south" => Some(Facing::South),
            "west" => Some(Facing::West),
            "east" => Some(Facing::East),
            _ => None,
        }
    }

    /// `Direction.getOpposite`.
    #[must_use]
    pub fn opposite(self) -> Self {
        match self {
            Facing::Down => Facing::Up,
            Facing::Up => Facing::Down,
            Facing::North => Facing::South,
            Facing::South => Facing::North,
            Facing::West => Facing::East,
            Facing::East => Facing::West,
        }
    }

    /// `BlockPos.relative`'s offset: north is -z, east +x, up +y.
    #[must_use]
    pub fn offset(self) -> [i32; 3] {
        match self {
            Facing::Down => [0, -1, 0],
            Facing::Up => [0, 1, 0],
            Facing::North => [0, 0, -1],
            Facing::South => [0, 0, 1],
            Facing::West => [-1, 0, 0],
            Facing::East => [1, 0, 0],
        }
    }

    /// The axis it lies on: 0 = x, 1 = y, 2 = z.
    #[must_use]
    pub fn axis(self) -> usize {
        match self {
            Facing::Down | Facing::Up => 1,
            Facing::North | Facing::South => 2,
            Facing::West | Facing::East => 0,
        }
    }
}

/// The blocks one shot converts around the block the beam hit: a 3x3 plane across the beam
/// (`invokeConversionLens`'s `range 1`, zero on the facing axis), in upstream's
/// `reachX` → `reachZ` → `reachY` order, the hit block at its centre.
#[must_use]
pub fn conversion_plane(hit: [i32; 3], facing: Facing) -> Vec<[i32; 3]> {
    let reach = |axis: usize| {
        if axis == facing.axis() {
            0
        } else {
            RECONSTRUCTOR_CONVERSION_RANGE
        }
    };
    let (range_x, range_y, range_z) = (reach(0), reach(1), reach(2));
    let mut plane = Vec::with_capacity(9);
    for dx in -range_x..=range_x {
        for dz in -range_z..=range_z {
            for dy in -range_y..=range_y {
                plane.push([hit[0] + dx, hit[1] + dy, hit[2] + dz]);
            }
        }
    }
    plane
}

/// `BlockAtomicReconstructor.getAnalogOutputSignal`: `clamp(energy / 20000, 0, 15)`.
#[must_use]
pub fn reconstructor_comparator(energy: i32) -> i32 {
    (energy.max(0) / RECONSTRUCTOR_COMPARATOR_STEP).clamp(0, 15)
}

/// The Atomic Reconstructor's saved state: its CF buffer and the position in its cycle
/// (`TileEntityAtomicReconstructor`'s `Energy` and `CurrentTime`).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Reconstructor {
    pub energy: i32,
    pub cycle: u32,
}

impl Reconstructor {
    /// The empty machine.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// One server tick. A redstone-powered machine does not advance and does not shoot.
    /// Returns true on the tick the cycle reaches zero, when upstream calls
    /// `invokeReconstructor`.
    pub fn tick(&mut self, powered: bool) -> bool {
        if powered {
            return false;
        }
        if self.cycle > 0 {
            self.cycle -= 1;
            return self.cycle == 0;
        }
        self.cycle = RECONSTRUCTOR_TICKS;
        false
    }

    /// The shot's gate: under 1000 CF nothing goes out; otherwise the gate is paid and the
    /// remaining buffer is the beam's budget (upstream extracts before walking it).
    pub fn fire(&mut self) -> Option<i32> {
        if self.energy < RECONSTRUCTOR_ENERGY_USE {
            return None;
        }
        self.energy -= RECONSTRUCTOR_ENERGY_USE;
        Some(self.energy)
    }

    /// Whether the buffer still covers one conversion's own energy.
    #[must_use]
    pub fn can_afford(&self, energy: i32) -> bool {
        self.energy >= energy
    }

    /// Pay one conversion's energy (`tile.extractEnergy(recipe.getEnergy())`).
    pub fn spend(&mut self, energy: i32) {
        self.energy = (self.energy - energy.max(0)).max(0);
    }
}

/// What a placed reconstructor comes back with: its buffer clamped and its cycle inside the
/// machine's own range (a stale item can name any int).
#[must_use]
pub fn restored_reconstructor(energy: i32, cycle: i32) -> Reconstructor {
    Reconstructor {
        energy: clamp_energy(energy, RECONSTRUCTOR_CAPACITY),
        cycle: (cycle.max(0) as u32).min(RECONSTRUCTOR_TICKS),
    }
}

/// `Block.getStateForPlacement` for upstream's `FullyDirectionalBlock`:
/// `getNearestLookingDirection().getOpposite()`, i.e. the machine faces away from the player.
#[must_use]
pub fn facing_for_placement(yaw: f32, pitch: f32) -> Facing {
    nearest_looking_direction(yaw, pitch).opposite()
}

/// `Direction.orderedByNearest(yaw, pitch)[0]`: the direction the view points at most.
/// The branch structure is the engine's own (`horizon-world/src/level/place.rs`), so a
/// tie resolves the same way vanilla resolves it.
fn nearest_looking_direction(yaw: f32, pitch: f32) -> Facing {
    let pitch_rad = f64::from(pitch) * (std::f64::consts::PI / 180.0);
    let yaw_rad = -f64::from(yaw) * (std::f64::consts::PI / 180.0);
    let (pitch_sin, pitch_cos) = (pitch_rad.sin(), pitch_rad.cos());
    let (yaw_sin, yaw_cos) = (yaw_rad.sin(), yaw_rad.cos());
    let x_pos = yaw_sin > 0.0;
    let y_pos = pitch_sin < 0.0;
    let z_pos = yaw_cos > 0.0;
    let x_yaw = if x_pos { yaw_sin } else { -yaw_sin };
    let y_mag = if y_pos { -pitch_sin } else { pitch_sin };
    let z_yaw = if z_pos { yaw_cos } else { -yaw_cos };
    let x_mag = x_yaw * pitch_cos;
    let z_mag = z_yaw * pitch_cos;
    let ax = if x_pos { Facing::East } else { Facing::West };
    let ay = if y_pos { Facing::Up } else { Facing::Down };
    let az = if z_pos { Facing::South } else { Facing::North };
    // The engine's own branch structure, reduced to its first element: the two pairs of
    // branches that answered the same direction are one branch here.
    if x_yaw > z_yaw {
        if y_mag > x_mag { ay } else { ax }
    } else if y_mag > z_mag {
        ay
    } else {
        az
    }
}

/// Why a laser recipe's JSON was refused.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LaserError {
    MissingIngredient,
    MissingResult,
    MissingEnergy,
    BadEnergy,
}

impl std::fmt::Display for LaserError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = match self {
            LaserError::MissingIngredient => "missing ingredient",
            LaserError::MissingResult => "missing result",
            LaserError::MissingEnergy => "missing energy",
            LaserError::BadEnergy => "an energy that is not a non-negative integer",
        };
        f.write_str(text)
    }
}

impl std::error::Error for LaserError {}

/// One `actuallyadditions:laser` recipe (upstream `LaserRecipe`): an ingredient, the result
/// it becomes, and the CF one conversion costs on top of the shot's gate.
#[derive(Clone, Debug, PartialEq)]
pub struct LaserRecipe {
    pub id: String,
    pub energy: i32,
    /// The ingredient as the pin's `recipe_ingredient` names it (`"id"` / `"#tag"` / a list).
    pub ingredient: Value,
    /// The file's own `result` object, for the pin's `recipe_result`.
    pub result: Value,
}

impl LaserRecipe {
    /// Parse a recipe file. The JSON is the pin's custom-recipe JSON, unchanged from
    /// 1.21.1 (the custom table keeps it as written).
    pub fn parse(id: &str, json: &str) -> Result<Self, LaserError> {
        let value: Value = serde_json::from_str(json).map_err(|_| LaserError::MissingIngredient)?;
        let ingredient = value
            .get("ingredient")
            .ok_or(LaserError::MissingIngredient)?;
        if !matches!(
            ingredient,
            Value::Object(_) | Value::Array(_) | Value::String(_)
        ) {
            return Err(LaserError::MissingIngredient);
        }
        let result = value.get("result").ok_or(LaserError::MissingResult)?;
        if result.get("id").and_then(Value::as_str).is_none() {
            return Err(LaserError::MissingResult);
        }
        let energy = value
            .get("energy")
            .ok_or(LaserError::MissingEnergy)?
            .as_i64()
            .ok_or(LaserError::BadEnergy)?;
        if !(0..=i64::from(i32::MAX)).contains(&energy) {
            return Err(LaserError::BadEnergy);
        }
        Ok(Self {
            id: id.to_owned(),
            energy: energy as i32,
            ingredient: ingredient_json(ingredient),
            result: result.clone(),
        })
    }

    /// The item id the conversion produces.
    #[must_use]
    pub fn result_id(&self) -> Option<&str> {
        self.result.get("id").and_then(Value::as_str)
    }

    /// How many items the conversion produces (1 unless the file says otherwise).
    #[must_use]
    pub fn result_count(&self) -> i32 {
        self.result
            .get("count")
            .and_then(Value::as_i64)
            .unwrap_or(1)
            .clamp(1, 99) as i32
    }
}

#[cfg(test)]
mod reconstructor_tests {
    use super::*;

    #[test]
    fn the_shot_costs_a_thousand_and_the_recipe_its_own() {
        let mut reconstructor = Reconstructor {
            energy: 1_040,
            cycle: 1,
        };
        assert!(reconstructor.tick(false), "the cycle reaches 0 and fires");
        assert_eq!(
            reconstructor.fire(),
            Some(40),
            "the 1000 CF gate is paid first"
        );
        assert!(
            reconstructor.can_afford(40),
            "redstone dust's recipe costs 40 CF on top"
        );
        reconstructor.spend(40);
        assert_eq!(reconstructor.energy, 0);
        assert!(
            !reconstructor.can_afford(40),
            "an empty buffer converts nothing"
        );

        let mut short = Reconstructor {
            energy: 1_039,
            cycle: 1,
        };
        assert!(short.tick(false));
        assert_eq!(short.fire(), Some(39));
        assert!(
            !short.can_afford(40),
            "39 CF left after the shot is not enough for the 40 CF conversion"
        );

        let mut empty = Reconstructor {
            energy: 0,
            cycle: 1,
        };
        assert!(empty.tick(false));
        assert_eq!(empty.fire(), None, "under 1000 CF the shot does not go out");
    }

    #[test]
    fn the_cycle_is_about_a_hundred_ticks() {
        let mut reconstructor = Reconstructor::new();
        assert!(!reconstructor.tick(false));
        assert_eq!(reconstructor.cycle, RECONSTRUCTOR_TICKS);
        for _ in 1..RECONSTRUCTOR_TICKS {
            assert!(!reconstructor.tick(false));
        }
        assert_eq!(reconstructor.cycle, 1);
        assert!(reconstructor.tick(false), "the hundredth tick fires");
        assert_eq!(reconstructor.cycle, 0);
    }

    #[test]
    fn redstone_freezes_the_cycle() {
        let mut reconstructor = Reconstructor {
            energy: 5_000,
            cycle: 50,
        };
        for _ in 0..20 {
            assert!(!reconstructor.tick(true), "a powered machine does not fire");
        }
        assert_eq!(reconstructor.cycle, 50, "the cycle does not advance");
        assert_eq!(reconstructor.energy, 5_000);
    }

    #[test]
    fn the_comparator_steps_every_twenty_thousand() {
        assert_eq!(reconstructor_comparator(0), 0);
        assert_eq!(reconstructor_comparator(19_999), 0);
        assert_eq!(reconstructor_comparator(20_000), 1);
        assert_eq!(reconstructor_comparator(-5), 0);
        assert_eq!(reconstructor_comparator(RECONSTRUCTOR_CAPACITY), 15);
        assert_eq!(reconstructor_comparator(900_000), 15);
    }

    #[test]
    fn the_plane_is_three_by_three_across_the_beam() {
        let hit = [10, 100, 0];
        let east = conversion_plane(hit, Facing::East);
        assert_eq!(east.len(), 9);
        assert!(
            east.iter().all(|at| at[0] == 10),
            "a horizontal beam converts the plane one block deep along its axis"
        );
        assert_eq!(
            east.iter().map(|at| (at[2], at[1])).collect::<Vec<_>>(),
            vec![
                (-1, 99),
                (-1, 100),
                (-1, 101),
                (0, 99),
                (0, 100),
                (0, 101),
                (1, 99),
                (1, 100),
                (1, 101)
            ],
            "upstream's reachZ then reachY order, the centre block in the middle"
        );
        let up = conversion_plane(hit, Facing::Up);
        assert_eq!(up.len(), 9);
        assert!(
            up.iter().all(|at| at[1] == 100),
            "a vertical beam converts the horizontal plane"
        );
        let north = conversion_plane(hit, Facing::North);
        assert!(
            north.iter().all(|at| at[2] == 0),
            "a north beam converts the plane across x and y"
        );
    }

    #[test]
    fn a_placed_reconstructor_faces_away_from_the_player() {
        // `getNearestLookingDirection().getOpposite()`: yaw 0 is south, 90 west.
        assert_eq!(facing_for_placement(0.0, 0.0), Facing::North);
        assert_eq!(facing_for_placement(180.0, 0.0), Facing::South);
        assert_eq!(facing_for_placement(90.0, 0.0), Facing::East);
        assert_eq!(facing_for_placement(-90.0, 0.0), Facing::West);
        assert_eq!(facing_for_placement(0.0, -90.0), Facing::Down);
        assert_eq!(facing_for_placement(0.0, 90.0), Facing::Up);
        assert_eq!(
            facing_for_placement(0.0, -45.0),
            Facing::North,
            "a 45 degree look is still the horizontal axis first"
        );
    }

    #[test]
    fn a_laser_recipe_is_read_from_the_jars_json() {
        let recipe = LaserRecipe::parse(
            "actuallyadditions:laser/crystalize_restonia_crystal",
            r#"{"type": "actuallyadditions:laser", "energy": 40,
                "ingredient": {"tag": "c:dusts/redstone"},
                "result": {"id": "actuallyadditions:restonia_crystal"}}"#,
        )
        .expect("the carried recipe parses");
        assert_eq!(recipe.energy, 40);
        assert_eq!(
            recipe.ingredient,
            Value::String("#c:dusts/redstone".into()),
            "the ingredient is the pin's own form, as the crusher's recipes use"
        );
        assert_eq!(
            recipe.result_id(),
            Some("actuallyadditions:restonia_crystal")
        );
        assert_eq!(recipe.result_count(), 1);

        assert_eq!(
            LaserRecipe::parse("x:y", r#"{"energy": 40, "ingredient": {"item": "a:b"}}"#),
            Err(LaserError::MissingResult)
        );
        assert_eq!(
            LaserRecipe::parse(
                "x:y",
                r#"{"ingredient": {"item": "a:b"}, "result": {"id": "a:c"}}"#
            ),
            Err(LaserError::MissingEnergy)
        );
        assert_eq!(
            LaserRecipe::parse(
                "x:y",
                r#"{"energy": -1, "ingredient": {"item": "a:b"}, "result": {"id": "a:c"}}"#
            ),
            Err(LaserError::BadEnergy)
        );
        assert_eq!(
            LaserRecipe::parse("x:y", r#"{"energy": 1, "result": {"id": "a:c"}}"#),
            Err(LaserError::MissingIngredient)
        );
    }

    #[test]
    fn a_restored_reconstructor_is_clamped_into_its_buffer_and_cycle() {
        assert_eq!(
            restored_reconstructor(5_000, 40),
            Reconstructor {
                energy: 5_000,
                cycle: 40
            }
        );
        assert_eq!(
            restored_reconstructor(400_000, 900),
            Reconstructor {
                energy: RECONSTRUCTOR_CAPACITY,
                cycle: RECONSTRUCTOR_TICKS
            }
        );
        assert_eq!(restored_reconstructor(-1, -7), Reconstructor::new());
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

    // The ore's generation (0.2.5). The carried `worldgen/configured_feature` and
    // `placed_feature` only generate when a biome modifier attaches them, and 1.3.26's own
    // `add_black_quartz.json` names `actuallyadditions:bool_config_feature_modifier`, a type the
    // pin does not read. The port declares the same addition itself, so these pin the fields the
    // SDK's `declare_biome_modifier` refuses when they are wrong (an id outside the mod's
    // namespace, a name that is not namespaced, a step vanilla does not have, an empty list).
    #[test]
    fn the_black_quartz_ore_generates_in_the_overworlds_underground_ores_step() {
        let generation = black_quartz_ore_generation();
        assert_eq!(generation.id, "add_black_quartz");
        assert_eq!(generation.feature, "actuallyadditions:ore_black_quartz");
        assert_eq!(generation.step, "underground_ores");
        assert_eq!(generation.biomes, &["#minecraft:is_overworld"]);
    }

    #[test]
    fn the_modifier_names_namespaced_ids_and_a_vanilla_generation_step() {
        let generation = black_quartz_ore_generation();
        assert!(
            is_namespaced(generation.feature),
            "feature {:?} is not namespaced",
            generation.feature
        );
        assert!(
            VANILLA_GENERATION_STEPS.contains(&generation.step),
            "step {:?} is not one of vanilla's",
            generation.step
        );
        for biome in generation.biomes {
            let id = biome.strip_prefix('#').unwrap_or(biome);
            assert!(
                is_namespaced(id),
                "biome {biome:?} is neither an id nor a #tag"
            );
        }
    }

    #[test]
    fn a_name_without_a_namespace_is_refused() {
        assert!(is_namespaced("actuallyadditions:black_quartz_ore"));
        assert!(is_namespaced(
            "#minecraft:is_overworld".trim_start_matches('#')
        ));
        assert!(!is_namespaced("black_quartz_ore"));
        assert!(!is_namespaced(":black_quartz_ore"));
        assert!(!is_namespaced("actuallyadditions:"));
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
