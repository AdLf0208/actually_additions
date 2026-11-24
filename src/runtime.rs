// Pure machine logic for Actually Additions slice 2 (Coal Generator, Crusher, and the
// state a broken machine carries on its item).
//
// This file is both the standalone Cargo library and the injected
// `crate::game::actuallyadditions` module. It has no game types: the hook
// glue in `support.rs` converts block entities, item stacks and the engine's
// fuel values into the small values used here.

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

// ---------------------------------------------------------------------------
// The JSON reader the recipe files need
// ---------------------------------------------------------------------------

/// A JSON value, read here rather than by a crate: the recipe files are the only JSON this
/// package handles, and the registry refuses a package that declares a registry dependency
/// (rule R9 of its `tools/native-subset` checks), so the reader lives in this file.
///
/// A number keeps the digits it was written with, so a `count` stays an integer and a `chance`
/// keeps its exact text; the value is otherwise the usual tree. Key order is file order and a
/// repeated key is kept twice (the first one wins in [`Json::get`]).
#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    /// The literal as written: `3`, `-1`, `0.5`, `1e2`.
    Number(String),
    String(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    /// Read one JSON document; `None` for anything malformed.
    #[must_use]
    pub fn parse(text: &str) -> Option<Self> {
        let mut reader = JsonReader {
            bytes: text.as_bytes(),
            at: 0,
        };
        let value = reader.value(0)?;
        reader.skip_whitespace();
        (reader.at == reader.bytes.len()).then_some(value)
    }

    /// The value under `key`, when this is an object that carries it.
    #[must_use]
    pub fn get(&self, key: &str) -> Option<&Self> {
        match self {
            Json::Object(entries) => entries
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value),
            _ => None,
        }
    }

    /// The text, when this is a string.
    #[must_use]
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::String(text) => Some(text),
            _ => None,
        }
    }

    /// The entries, when this is an array.
    #[must_use]
    pub fn as_array(&self) -> Option<&[Self]> {
        match self {
            Json::Array(items) => Some(items),
            _ => None,
        }
    }

    /// The number as an integer, when it is written as one (serde_json's `as_i64`).
    #[must_use]
    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Json::Number(text) => text.parse().ok(),
            _ => None,
        }
    }

    /// The number as a float, when it is a number (serde_json's `as_f64`).
    #[must_use]
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Json::Number(text) => text.parse().ok(),
            _ => None,
        }
    }

    fn write(&self, out: &mut dyn std::fmt::Write) -> std::fmt::Result {
        match self {
            Json::Null => out.write_str("null"),
            Json::Bool(true) => out.write_str("true"),
            Json::Bool(false) => out.write_str("false"),
            Json::Number(text) => out.write_str(text),
            Json::String(text) => write_string(out, text),
            Json::Array(items) => {
                out.write_char('[')?;
                for (index, item) in items.iter().enumerate() {
                    if index > 0 {
                        out.write_char(',')?;
                    }
                    item.write(out)?;
                }
                out.write_char(']')
            }
            Json::Object(entries) => {
                out.write_char('{')?;
                for (index, (key, value)) in entries.iter().enumerate() {
                    if index > 0 {
                        out.write_char(',')?;
                    }
                    write_string(out, key)?;
                    out.write_char(':')?;
                    value.write(out)?;
                }
                out.write_char('}')
            }
        }
    }
}

/// A JSON value prints as the compact document it was read from (serde_json's `Display`).
impl std::fmt::Display for Json {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.write(f)
    }
}

/// The deepest nesting [`Json::parse`] accepts: serde_json's own default, and far more than a
/// recipe nested through `components` uses.
const JSON_DEPTH: u32 = 128;

/// One string's JSON form: the two mandatory escapes, the short control escapes, and `\u00XX`
/// for the rest.
fn write_string(out: &mut dyn std::fmt::Write, text: &str) -> std::fmt::Result {
    out.write_char('"')?;
    for character in text.chars() {
        match character {
            '"' => out.write_str("\\\"")?,
            '\\' => out.write_str("\\\\")?,
            '\n' => out.write_str("\\n")?,
            '\r' => out.write_str("\\r")?,
            '\t' => out.write_str("\\t")?,
            control if (control as u32) < 0x20 => write!(out, "\\u{:04x}", control as u32)?,
            other => out.write_char(other)?,
        }
    }
    out.write_char('"')
}

/// A byte cursor over one document. JSON's structure is ASCII, so a byte scan is enough; a
/// multi-byte character inside a string is copied whole.
struct JsonReader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl JsonReader<'_> {
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.at).copied()
    }

    fn bump(&mut self) -> Option<u8> {
        let byte = self.peek()?;
        self.at += 1;
        Some(byte)
    }

    fn skip_whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.at += 1;
        }
    }

    fn value(&mut self, depth: u32) -> Option<Json> {
        if depth > JSON_DEPTH {
            return None;
        }
        self.skip_whitespace();
        match self.peek()? {
            b'{' => self.object(depth),
            b'[' => self.array(depth),
            b'"' => self.string().map(Json::String),
            b't' => self.literal("true", Json::Bool(true)),
            b'f' => self.literal("false", Json::Bool(false)),
            b'n' => self.literal("null", Json::Null),
            b'-' | b'0'..=b'9' => self.number(),
            _ => None,
        }
    }

    fn literal(&mut self, word: &str, value: Json) -> Option<Json> {
        let end = self.at.checked_add(word.len())?;
        if self.bytes.get(self.at..end)? == word.as_bytes() {
            self.at = end;
            Some(value)
        } else {
            None
        }
    }

    /// A number keeps its source text; the scan takes every character a number may hold and
    /// `f64::parse` (which Rust writes to the JSON grammar) rejects a token that is not one.
    fn number(&mut self) -> Option<Json> {
        let start = self.at;
        while matches!(
            self.peek(),
            Some(b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9')
        ) {
            self.at += 1;
        }
        let text = std::str::from_utf8(self.bytes.get(start..self.at)?).ok()?;
        text.parse::<f64>().ok()?;
        Some(Json::Number(text.to_owned()))
    }

    fn string(&mut self) -> Option<String> {
        self.bump().filter(|byte| *byte == b'"')?;
        let mut out = String::new();
        loop {
            match self.bump()? {
                b'"' => return Some(out),
                b'\\' => self.escape(&mut out)?,
                0x00..=0x1f => return None,
                byte => self.push_byte(byte, &mut out)?,
            }
        }
    }

    /// One byte of a string body: ASCII as itself, a multi-byte sequence copied whole.
    fn push_byte(&mut self, byte: u8, out: &mut String) -> Option<()> {
        if byte < 0x80 {
            out.push(char::from(byte));
            return Some(());
        }
        let width = match byte {
            0xc0..=0xdf => 2,
            0xe0..=0xef => 3,
            0xf0..=0xf7 => 4,
            _ => return None,
        };
        let start = self.at - 1;
        let end = start.checked_add(width)?;
        out.push_str(std::str::from_utf8(self.bytes.get(start..end)?).ok()?);
        self.at = end;
        Some(())
    }

    fn escape(&mut self, out: &mut String) -> Option<()> {
        match self.bump()? {
            b'"' => out.push('"'),
            b'\\' => out.push('\\'),
            b'/' => out.push('/'),
            b'b' => out.push('\u{8}'),
            b'f' => out.push('\u{c}'),
            b'n' => out.push('\n'),
            b'r' => out.push('\r'),
            b't' => out.push('\t'),
            b'u' => {
                let first = self.hex4()?;
                let scalar = if (0xd800..=0xdbff).contains(&first) {
                    if self.bump()? != b'\\' || self.bump()? != b'u' {
                        return None;
                    }
                    let second = self.hex4()?;
                    if !(0xdc00..=0xdfff).contains(&second) {
                        return None;
                    }
                    0x1_0000 + ((u32::from(first) - 0xd800) << 10) + (u32::from(second) - 0xdc00)
                } else if (0xdc00..=0xdfff).contains(&first) {
                    return None;
                } else {
                    u32::from(first)
                };
                out.push(char::from_u32(scalar)?);
            }
            _ => return None,
        }
        Some(())
    }

    fn hex4(&mut self) -> Option<u16> {
        let mut value = 0u16;
        for _ in 0..4 {
            let nibble = match self.bump()? {
                digit @ b'0'..=b'9' => digit - b'0',
                digit @ b'a'..=b'f' => digit - b'a' + 10,
                digit @ b'A'..=b'F' => digit - b'A' + 10,
                _ => return None,
            };
            value = value * 16 + u16::from(nibble);
        }
        Some(value)
    }

    fn array(&mut self, depth: u32) -> Option<Json> {
        self.at += 1; // '['
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b']') {
            self.at += 1;
            return Some(Json::Array(items));
        }
        loop {
            items.push(self.value(depth + 1)?);
            self.skip_whitespace();
            match self.bump()? {
                b',' => self.skip_whitespace(),
                b']' => return Some(Json::Array(items)),
                _ => return None,
            }
        }
    }

    fn object(&mut self, depth: u32) -> Option<Json> {
        self.at += 1; // '{'
        let mut entries = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b'}') {
            self.at += 1;
            return Some(Json::Object(entries));
        }
        loop {
            self.skip_whitespace();
            let key = self.string()?;
            self.skip_whitespace();
            if self.bump()? != b':' {
                return None;
            }
            entries.push((key, self.value(depth + 1)?));
            self.skip_whitespace();
            match self.bump()? {
                b',' => {}
                b'}' => return Some(Json::Object(entries)),
                _ => return None,
            }
        }
    }
}

#[cfg(test)]
mod json_tests {
    use super::*;

    #[test]
    fn a_number_keeps_the_digits_it_was_written_with() {
        let value =
            Json::parse(r#"{"count": 3, "chance": 0.5, "scaled": 1e2}"#).expect("valid JSON");
        assert_eq!(value.get("count").and_then(Json::as_i64), Some(3));
        assert_eq!(
            value.get("count").and_then(Json::as_f64),
            Some(3.0),
            "an integer is also a float"
        );
        assert_eq!(value.get("chance").and_then(Json::as_f64), Some(0.5));
        assert_eq!(value.get("scaled").and_then(Json::as_f64), Some(100.0));
        assert_eq!(
            value.get("chance").and_then(Json::as_i64),
            None,
            "0.5 is not an integer, as serde_json's as_i64 has it"
        );
        assert_eq!(
            value.to_string(),
            r#"{"count":3,"chance":0.5,"scaled":1e2}"#,
            "the digits survive the round trip"
        );
    }

    #[test]
    fn a_string_reads_escapes_and_unicode_pairs() {
        let value = Json::parse(r#""a\"b\\c\u00e9\ud83d\ude00\n""#).expect("valid JSON");
        assert_eq!(value.as_str(), Some("a\"b\\cé😀\n"));
        assert_eq!(
            Json::parse(&value.to_string()),
            Some(value),
            "the text it writes reads back as the same value"
        );
    }

    #[test]
    fn a_broken_document_is_refused() {
        for text in [
            "",
            "{",
            "[1,]",
            r#"{"a":}"#,
            "tru",
            r#"{"a":1} x"#,
            r#""\ud800""#,
            "{'a':1}",
            "[1 2]",
        ] {
            assert_eq!(Json::parse(text), None, "{text:?} is not JSON");
        }
    }

    #[test]
    fn a_recipe_ingredient_becomes_the_pins_form() {
        let spec = |text: &str| ingredient_json(&Json::parse(text).expect("valid JSON"));
        assert_eq!(
            spec(r#"{"item": "minecraft:coal_ore"}"#),
            Json::String("minecraft:coal_ore".into())
        );
        assert_eq!(spec(r#"{"tag": "c:ores"}"#), Json::String("#c:ores".into()));
        assert_eq!(
            spec(r#"[{"item": "minecraft:gravel"}, {"tag": "minecraft:coals"}]"#),
            Json::Array(vec![
                Json::String("minecraft:gravel".into()),
                Json::String("#minecraft:coals".into())
            ])
        );
        assert_eq!(
            spec(r#""minecraft:stone""#),
            Json::String("minecraft:stone".into())
        );
    }
}

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
    /// The ingredient in the pin's own form (`"id"` / `"#tag"` / a list), which is what
    /// `Host::recipe_ingredient` reads.
    pub ingredient: Json,
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
        let value = Json::parse(json).ok_or(RecipeError::MissingIngredient)?;
        let ingredient = value
            .get("ingredient")
            .map(ingredient_json)
            .ok_or(RecipeError::MissingIngredient)?;
        let results = value
            .get("result")
            .and_then(Json::as_array)
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
                .and_then(Json::as_str)
                .ok_or(RecipeError::BadResult)?;
            let count = stack.get("count").and_then(Json::as_i64).unwrap_or(1);
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
            ingredient,
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
/// pin's `recipe_ingredient` names it (`"id"` / `"#tag"` / a list).
#[must_use]
pub fn ingredient_json(value: &Json) -> Json {
    match value {
        Json::Object(_) => {
            if let Some(item) = value.get("item").and_then(Json::as_str) {
                Json::String(item.to_owned())
            } else if let Some(tag) = value.get("tag").and_then(Json::as_str) {
                Json::String(format!("#{tag}"))
            } else {
                value.clone()
            }
        }
        Json::Array(entries) => Json::Array(entries.iter().map(ingredient_json).collect()),
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

/// Upstream `MethodHandler.invokeConversionLens`'s `aabb.inflate(0.02, 0.02, 0.02)`: the slack
/// the item box takes on every side.
const ITEM_BOX_INFLATE: f64 = 0.02;
/// Upstream's `aa_cnv` persistent-data flag, as a vanilla scoreboard tag (the pin has no entity
/// persistent-data surface; `Entity.getTags` is saved with the entity and readable in game). A
/// converted item carries it, so the beam never converts the same entity twice.
pub const CONVERTED_MARKER: &str = "aa_cnv";

/// The box a dropped item must be in to be converted by one beam step, from the machine's own
/// block to the block the beam hit plus one, inflated by 0.02 and carried one block further along
/// the facing (`new AABB(tile, hit + 1).inflate(0.02).expandTowards(dir)`).
///
/// Upstream passes the machine as the minimum and `hit + 1` as the maximum, which `AABB` does not
/// order: on a `north`, `west` or `down` beam that box is inverted and vanilla intersects nothing
/// with it, so those three facings convert no dropped item. This one is ordered and extends the
/// end away from the machine — upstream's own numbers for `east`/`south`/`up`, the mirrored,
/// working case for the other three (see `notes.md`, "Upstream defects fixed").
#[must_use]
pub fn item_scan_box(tile: [i32; 3], hit: [i32; 3], facing: Facing) -> ([f64; 3], [f64; 3]) {
    let mut min = [0.0; 3];
    let mut max = [0.0; 3];
    for axis in 0..3 {
        let machine = f64::from(tile[axis]);
        let hit_end = f64::from(hit[axis]) + 1.0;
        min[axis] = machine.min(hit_end) - ITEM_BOX_INFLATE;
        max[axis] = machine.max(hit_end) + ITEM_BOX_INFLATE;
    }
    // `expandTowards`: one more block on the beam's own side, i.e. the far end of the box.
    let step = facing.offset();
    for axis in 0..3 {
        if step[axis] > 0 {
            max[axis] += f64::from(step[axis]);
        } else if step[axis] < 0 {
            min[axis] += f64::from(step[axis]);
        }
    }
    (min, max)
}

/// How many items one beam step converts: `Math.min(tile.getEnergy() / recipe.getEnergy(),
/// stack.getCount())`, with `energy` the buffer left after the shot's gate. A recipe with no cost
/// converts the whole stack — upstream would divide by zero there, which is a defect, not a rule.
#[must_use]
pub fn items_possible(energy: i32, recipe_energy: i32, count: u32) -> u32 {
    let count = u64::from(count);
    let affordable = if recipe_energy <= 0 {
        count
    } else {
        u64::try_from(energy.max(0)).unwrap_or(0) / u64::try_from(recipe_energy).unwrap_or(u64::MAX)
    };
    u32::try_from(affordable.min(count)).unwrap_or(0)
}

/// Whether a scanned dropped stack may be converted: not empty, and not one the beam's own
/// conversion already marked (`!item.getPersistentData().getBoolean("aa_cnv")`).
#[must_use]
pub fn may_convert(tags: &[String], count: u32) -> bool {
    count > 0 && !tags.iter().any(|tag| tag == CONVERTED_MARKER)
}

/// `BlockAtomicReconstructor.getAnalogOutputSignal`: `clamp(energy / 20000, 0, 15)`.
#[must_use]
pub fn reconstructor_comparator(energy: i32) -> i32 {
    (energy.max(0) / RECONSTRUCTOR_COMPARATOR_STEP).clamp(0, 15)
}

/// The redstone level a machine sees this tick: `getBestNeighborSignal(pos) > 0`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Signal {
    /// No neighbour drives the machine.
    #[default]
    Off,
    /// A neighbour drives the machine.
    On,
}

impl Signal {
    /// The level of a `has_neighbor_signal` answer.
    #[must_use]
    pub fn of(powered: bool) -> Self {
        if powered { Self::On } else { Self::Off }
    }
}

/// The Atomic Reconstructor's saved state: its CF buffer, the position in its cycle
/// (`TileEntityAtomicReconstructor`'s `Energy` and `CurrentTime`), upstream's `isPulseMode` and the
/// signal its last tick saw (`TileEntityBase`'s `isRedstonePowered`, which is what makes an edge an
/// edge).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Reconstructor {
    pub energy: i32,
    pub cycle: u32,
    /// Upstream's `isPulseMode`: one shot per rising edge instead of a free-running cycle.
    pub pulse: bool,
    /// The level the previous tick read, so a rising edge can be told from a level.
    pub signal: Signal,
}

impl Reconstructor {
    /// The empty machine.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// One server tick. Returns true when the machine fires now.
    ///
    /// Upstream `TileEntityAtomicReconstructor.serverTick` runs the cycle only under
    /// `!isRedstonePowered && !isPulseMode`, so a powered machine freezes and a pulse-mode one
    /// never runs its cycle at all; `BlockContainerBase.updateRedstoneState` calls
    /// `activateOnPulse` on a rising edge while `respondsToPulses()`
    /// (`isRedstoneToggle() && isPulseMode`).
    pub fn tick(&mut self, signal: Signal) -> bool {
        let rose = signal == Signal::On && self.signal == Signal::Off;
        self.signal = signal;
        if self.pulse {
            return rose;
        }
        if signal == Signal::On {
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

/// The four items 1.3.26 declares as `ILensItem`s, in the order of the jar's laser ring:
/// `lens → lens_of_color → lens_of_detonation → lens_of_certain_death → lens`. The port carries
/// all four; the three non-plain lenses' own beam effects are a later slice (their acceptance here
/// is faithful to `getLens`, but the beam uses the default conversion rule for them).
pub const LENS_ITEMS: [&str; 5] = [
    "actuallyadditions:lens",
    "actuallyadditions:lens_of_color",
    "actuallyadditions:lens_of_detonation",
    "actuallyadditions:lens_of_certain_death",
    LENS_OF_THE_MINER,
];

/// Whether `item` is one of the mod's lens items (`instanceof ILensItem` upstream).
#[must_use]
pub fn is_lens(item: &str) -> bool {
    LENS_ITEMS.contains(&item)
}

/// Upstream `ILensItem`: a right click fills the reconstructor's empty lens slot only with one of
/// 1.3.26's lens items (`TileEntityAtomicReconstructor.getLens`); an occupied slot refuses a second
/// lens, and a non-lens is refused by an empty one.
#[must_use]
pub fn lens_slot_accepts(slot: Option<&str>, item: &str) -> bool {
    slot.is_none() && is_lens(item)
}

/// Upstream `CommonConfig.Machines.MINER_LENS_ENERGY`: the CF the miner lens spends per block it
/// swaps (`CommonConfig.java:56`, default 60,000, on top of the shot's 1,000 CF gate).
pub const MINING_LENS_ENERGY: i32 = 60_000;

/// `LensMining.getDistance` — the same ten blocks as the default conversion lens.
pub const MINING_LENS_DISTANCE: i32 = 10;

/// The behaviour lens whose `ItemLens.getLens()` is upstream's `LensMining` (`LensMining.java`).
/// Its crafting recipe names empowered crystals this package does not carry, so the in-game rig
/// gives the item; the item itself is in the jar and is an `ILensItem`, so the slot accepts it.
pub const LENS_OF_THE_MINER: &str = "actuallyadditions:lens_of_the_miner";

/// `LensDetonation.ENERGY_USE` (`LensDetonation.java:22`): the CF the blast costs **on top of**
/// the shot's 1,000 CF gate, so a shot needs 251,000 CF in the buffer.
pub const DETONATION_LENS_ENERGY: i32 = 250_000;

/// The radius passed to `explode(null, hit + 0.5, 10F, true, ExplosionInteraction.NONE)`
/// (`LensDetonation.java:28`). The beam's reach is separate: [`LensEffect::Detonation`] travels 30.
pub const DETONATION_BLAST_RADIUS: f32 = 10.0;

/// The behaviour lens whose `ItemLens.getLens()` is upstream's `LensDetonation`. Its own craft
/// keys on crystals this package does not carry, so the in-game rig gives it; the jar's item is
/// an `ILensItem` already carried by the package, so the slot accepts it.
pub const LENS_OF_DETONATION: &str = "actuallyadditions:lens_of_detonation";

/// `LensDetonation.invoke` returns `true` for any non-air sight (so the beam stops even if it
/// cannot pay) and `false` for air (so it keeps walking). Upstream's near-null case is the same
/// "keep walking" answer — the beam always calls `invoke` with a positioned block.
#[must_use]
pub fn detonation_stop(air: bool) -> bool {
    !air
}

/// Which `Lens.invoke` a held lens item selects (`TileEntityAtomicReconstructor.getLens` →
/// `MethodHandler.invokeReconstructor`). The miner, detonator, killer and disenchanting lenses are
/// distinct `invoke` paths; the first two are carried, the others recorded as gaps.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LensEffect {
    /// `LensConversion`: the default conversion of the plane and the beam's dropped items.
    Conversion,
    /// `LensMining`: replace the sighted ore-replaceable block with a weighted-random ore.
    Mining,
    /// `LensDetonation`: a sourceless, fiery radius-10 blast at the sighted block.
    Detonation,
}

impl LensEffect {
    /// The rule a held lens item selects; an empty slot (no id) is upstream's `lensDefaultConversion`.
    pub fn of(item: &str) -> Self {
        match item {
            LENS_OF_THE_MINER => Self::Mining,
            LENS_OF_DETONATION => Self::Detonation,
            _ => Self::Conversion,
        }
    }

    /// Upstream `Lens.getDistance`: the default conversion lens and the miner reach ten blocks;
    /// `LensDetonation.getDistance` returns thirty (three times as far).
    pub fn distance(self) -> i32 {
        match self {
            Self::Conversion => RECONSTRUCTOR_LENS_DISTANCE,
            Self::Mining => MINING_LENS_DISTANCE,
            Self::Detonation => DETONATION_LENS_DISTANCE,
        }
    }
}

/// `LensDetonation.getDistance` — three times the default conversion lens's ten blocks.
pub const DETONATION_LENS_DISTANCE: i32 = 30;

/// What a placed reconstructor comes back with: its buffer clamped and its cycle inside the
/// machine's own range (a stale item can name any int).
#[must_use]
pub fn restored_reconstructor(energy: i32, cycle: i32, pulse: bool) -> Reconstructor {
    Reconstructor {
        energy: clamp_energy(energy, RECONSTRUCTOR_CAPACITY),
        cycle: (cycle.max(0) as u32).min(RECONSTRUCTOR_TICKS),
        pulse,
        signal: Signal::Off,
    }
}

/// The world writes one conversion makes. The block half and the item half each implement it over
/// the level; the unit tests supply a fake that can refuse either write.
///
/// The order is the point: upstream's `invokeConversionLens` spawns the result **before** it removes
/// the source block and ignores `removeBlock`'s answer, so a host that refuses the removal leaves
/// both the input and its output in the world.
pub trait Conversion {
    /// Take the source out of the world: the block (replaced by a block result in the same write),
    /// or the item stack's converted copies. False when the host refused it, with the world as it was.
    fn remove_source(&mut self) -> bool;

    /// Put the result in the world. For a result `remove_source` already wrote (a block placed over
    /// the source, a whole stack rewritten in place) this is a no-op that reports success.
    fn emit_result(&mut self) -> bool;

    /// Put back what [`Conversion::remove_source`] removed, after a refused
    /// [`Conversion::emit_result`], so the world never holds neither. Does nothing when
    /// `remove_source` wrote the result itself.
    fn restore_source(&mut self);
}

/// One conversion: the source goes first, the result arrives only if it did, and the recipe's own
/// energy is owed only when both happened. Returns whether the conversion happened.
pub fn convert(source: &mut impl Conversion, energy: i32, state: &mut Reconstructor) -> bool {
    if !source.remove_source() {
        return false;
    }
    if !source.emit_result() {
        source.restore_source();
        return false;
    }
    state.spend(energy);
    true
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
    pub ingredient: Json,
    /// The file's own `result` object, for the pin's `recipe_result`.
    pub result: Json,
}

impl LaserRecipe {
    /// Parse a recipe file. The JSON is the pin's custom-recipe JSON, unchanged from
    /// 1.21.1 (the custom table keeps it as written).
    pub fn parse(id: &str, json: &str) -> Result<Self, LaserError> {
        let value = Json::parse(json).ok_or(LaserError::MissingIngredient)?;
        let ingredient = value
            .get("ingredient")
            .ok_or(LaserError::MissingIngredient)?;
        if !matches!(
            ingredient,
            Json::Object(_) | Json::Array(_) | Json::String(_)
        ) {
            return Err(LaserError::MissingIngredient);
        }
        let result = value.get("result").ok_or(LaserError::MissingResult)?;
        if result.get("id").and_then(Json::as_str).is_none() {
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
        self.result.get("id").and_then(Json::as_str)
    }

    /// How many items the conversion produces (1 unless the file says otherwise).
    #[must_use]
    pub fn result_count(&self) -> i32 {
        self.result
            .get("count")
            .and_then(Json::as_i64)
            .unwrap_or(1)
            .clamp(1, 99) as i32
    }
}

/// Why an `actuallyadditions:mining_lens` recipe file was refused.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MiningLensError {
    MissingIngredient,
    MissingResult,
    BadWeight,
}

impl std::fmt::Display for MiningLensError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = match self {
            MiningLensError::MissingIngredient => "missing ingredient",
            MiningLensError::MissingResult => "missing result",
            MiningLensError::BadWeight => "a weight that is not a non-negative integer",
        };
        f.write_str(text)
    }
}

impl std::error::Error for MiningLensError {}

/// One `actuallyadditions:mining_lens` recipe (upstream `MiningLensRecipe`): the ingredient the
/// sighted block's item must match, the block result placed over it, and its random-selection weight.
#[derive(Clone, Debug, PartialEq)]
pub struct MiningLensRecipe {
    pub id: String,
    pub ingredient: Json,
    pub result: Json,
    pub weight: u32,
}

impl MiningLensRecipe {
    /// Parse a recipe file. The custom table keeps 1.21.1's JSON as written.
    pub fn parse(id: &str, json: &str) -> Result<Self, MiningLensError> {
        let value = Json::parse(json).ok_or(MiningLensError::MissingIngredient)?;
        let ingredient = value
            .get("ingredient")
            .ok_or(MiningLensError::MissingIngredient)?;
        if !matches!(
            ingredient,
            Json::Object(_) | Json::Array(_) | Json::String(_)
        ) {
            return Err(MiningLensError::MissingIngredient);
        }
        let result = value.get("result").ok_or(MiningLensError::MissingResult)?;
        if result.get("id").and_then(Json::as_str).is_none() {
            return Err(MiningLensError::MissingResult);
        }
        let weight = value
            .get("weight")
            .and_then(Json::as_i64)
            .ok_or(MiningLensError::BadWeight)?;
        if !(0..=i64::from(u32::MAX)).contains(&weight) {
            return Err(MiningLensError::BadWeight);
        }
        Ok(Self {
            id: id.to_owned(),
            ingredient: ingredient_json(ingredient),
            result: result.clone(),
            weight: weight as u32,
        })
    }

    /// The item id the recipe places.
    pub fn result_id(&self) -> Option<&str> {
        self.result.get("id").and_then(Json::as_str)
    }
}

/// Upstream `WeightedRandom.getRandomItem`: `random.nextInt(totalWeight)` walks the matching recipes
/// in order, each owning a slice of the total. The pure rule takes the drawn `roll` so it is testable.
#[must_use]
pub fn pick_weighted(recipes: &[MiningLensRecipe], roll: i32) -> Option<&MiningLensRecipe> {
    let total: i64 = recipes.iter().map(|recipe| i64::from(recipe.weight)).sum();
    if total <= 0 || roll < 0 || i64::from(roll) >= total {
        return None;
    }
    let mut remaining = i64::from(roll);
    recipes.iter().find(|recipe| {
        if remaining < i64::from(recipe.weight) {
            true
        } else {
            remaining -= i64::from(recipe.weight);
            false
        }
    })
}

#[cfg(test)]
mod reconstructor_tests {
    use super::*;

    #[test]
    fn the_shot_costs_a_thousand_and_the_recipe_its_own() {
        let mut reconstructor = Reconstructor {
            energy: 1_040,
            cycle: 1,
            ..Reconstructor::new()
        };
        assert!(
            reconstructor.tick(Signal::Off),
            "the cycle reaches 0 and fires"
        );
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
            ..Reconstructor::new()
        };
        assert!(short.tick(Signal::Off));
        assert_eq!(short.fire(), Some(39));
        assert!(
            !short.can_afford(40),
            "39 CF left after the shot is not enough for the 40 CF conversion"
        );

        let mut empty = Reconstructor {
            energy: 0,
            cycle: 1,
            ..Reconstructor::new()
        };
        assert!(empty.tick(Signal::Off));
        assert_eq!(empty.fire(), None, "under 1000 CF the shot does not go out");
    }

    #[test]
    fn the_cycle_is_about_a_hundred_ticks() {
        let mut reconstructor = Reconstructor::new();
        assert!(!reconstructor.tick(Signal::Off));
        assert_eq!(reconstructor.cycle, RECONSTRUCTOR_TICKS);
        for _ in 1..RECONSTRUCTOR_TICKS {
            assert!(!reconstructor.tick(Signal::Off));
        }
        assert_eq!(reconstructor.cycle, 1);
        assert!(reconstructor.tick(Signal::Off), "the hundredth tick fires");
        assert_eq!(reconstructor.cycle, 0);
    }

    #[test]
    fn redstone_freezes_the_cycle() {
        let mut reconstructor = Reconstructor {
            energy: 5_000,
            cycle: 50,
            ..Reconstructor::new()
        };
        for _ in 0..20 {
            assert!(
                !reconstructor.tick(Signal::On),
                "a powered machine does not fire"
            );
        }
        assert_eq!(reconstructor.cycle, 50, "the cycle does not advance");
        assert_eq!(reconstructor.energy, 5_000);
    }

    /// Upstream's `isPulseMode`: `serverTick` only runs the cycle under
    /// `!isRedstonePowered && !isPulseMode`, so a toggle-mode machine never free-runs.
    #[test]
    fn a_pulse_mode_machine_never_runs_its_cycle() {
        let mut reconstructor = Reconstructor {
            energy: 5_000,
            cycle: 50,
            pulse: true,
            ..Reconstructor::new()
        };
        for _ in 0..20 {
            assert!(
                !reconstructor.tick(Signal::Off),
                "no cycle shot in pulse mode"
            );
        }
        assert_eq!(reconstructor.cycle, 50, "the cycle does not advance");
        assert_eq!(reconstructor.energy, 5_000);
    }

    /// `BlockContainerBase.updateRedstoneState` calls `activateOnPulse` on the rising edge of
    /// `getBestNeighborSignal(pos) > 0`, and only while `respondsToPulses()`.
    #[test]
    fn a_pulse_mode_machine_fires_once_for_each_rising_edge() {
        let mut reconstructor = Reconstructor {
            energy: 5_000,
            cycle: 50,
            pulse: true,
            ..Reconstructor::new()
        };
        assert!(!reconstructor.tick(Signal::Off), "a low signal is no edge");
        assert!(reconstructor.tick(Signal::On), "the rising edge fires");
        assert!(
            !reconstructor.tick(Signal::On),
            "the level does not fire again"
        );
        assert!(!reconstructor.tick(Signal::On));
        assert!(
            !reconstructor.tick(Signal::Off),
            "the falling edge fires nothing"
        );
        assert!(
            reconstructor.tick(Signal::On),
            "the second rising edge fires"
        );
        assert_eq!(
            reconstructor.cycle, 50,
            "pulse mode never touches the cycle"
        );
    }

    /// The control: without the toggle the same rising edge does nothing and the cycle freezes,
    /// which is upstream's `!isRedstonePowered` branch and this port's pre-0.2.8 behaviour.
    #[test]
    fn a_machine_without_pulse_mode_never_fires_on_an_edge() {
        let mut reconstructor = Reconstructor {
            energy: 5_000,
            cycle: 50,
            ..Reconstructor::new()
        };
        for _ in 0..20 {
            assert!(
                !reconstructor.tick(Signal::On),
                "a frozen machine never fires"
            );
        }
        assert_eq!(reconstructor.cycle, 50);
        assert!(!reconstructor.tick(Signal::Off));
        assert_eq!(
            reconstructor.cycle, 49,
            "the cycle resumes when the signal drops"
        );
    }

    /// The world writes one conversion makes, in the order [`convert`] requires.
    #[derive(Debug)]
    struct FakeConversion {
        source: bool,
        result: bool,
        refuse_removal: bool,
        refuse_result: bool,
        restores: usize,
    }

    impl FakeConversion {
        fn new() -> Self {
            Self {
                source: true,
                result: false,
                refuse_removal: false,
                refuse_result: false,
                restores: 0,
            }
        }
    }

    impl Conversion for FakeConversion {
        fn remove_source(&mut self) -> bool {
            if self.refuse_removal {
                return false;
            }
            self.source = false;
            true
        }

        fn emit_result(&mut self) -> bool {
            if self.refuse_result {
                return false;
            }
            self.result = true;
            true
        }

        fn restore_source(&mut self) {
            self.restores += 1;
            self.source = true;
        }
    }

    /// The review's refused-removal path: the host refuses to take the source, so no result may
    /// appear and the recipe's energy must stay in the buffer.
    #[test]
    fn a_refused_removal_leaves_no_result_and_charges_nothing() {
        let mut state = Reconstructor {
            energy: 1_040,
            cycle: 0,
            ..Reconstructor::new()
        };
        let mut world = FakeConversion {
            refuse_removal: true,
            ..FakeConversion::new()
        };
        assert!(!convert(&mut world, 40, &mut state));
        assert!(world.source, "the source is still in the world");
        assert!(
            !world.result,
            "a refused removal must not leave the output too"
        );
        assert_eq!(world.restores, 0, "nothing was taken, nothing to put back");
        assert_eq!(
            state.energy, 1_040,
            "a conversion that did not happen is free"
        );
    }

    /// The success path: both writes happened, so the recipe's energy is owed — once.
    #[test]
    fn a_conversion_charges_once_after_both_writes() {
        let mut state = Reconstructor {
            energy: 1_040,
            cycle: 0,
            ..Reconstructor::new()
        };
        let mut world = FakeConversion::new();
        assert!(convert(&mut world, 40, &mut state));
        assert!(!world.source, "the source went");
        assert!(world.result, "the result arrived");
        assert_eq!(state.energy, 1_000, "the recipe's 40 CF, charged once");
        assert_eq!(world.restores, 0);
    }

    /// The third hazard: the source went but the result could not be made. Put the source back and
    /// owe nothing, so the world never holds neither (or both).
    #[test]
    fn a_refused_result_puts_the_source_back_and_charges_nothing() {
        let mut state = Reconstructor {
            energy: 1_040,
            cycle: 0,
            ..Reconstructor::new()
        };
        let mut world = FakeConversion {
            refuse_result: true,
            ..FakeConversion::new()
        };
        assert!(!convert(&mut world, 40, &mut state));
        assert!(world.source, "the source is back");
        assert!(!world.result);
        assert_eq!(world.restores, 1, "the removal was undone exactly once");
        assert_eq!(
            state.energy, 1_040,
            "a conversion that did not finish is free"
        );
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

    /// Whether a box holds a point, as vanilla's `AABB.contains` does.
    fn holds(boxes: ([f64; 3], [f64; 3]), at: [f64; 3]) -> bool {
        let (min, max) = boxes;
        (0..3).all(|axis| min[axis] <= at[axis] && at[axis] <= max[axis])
    }

    #[test]
    fn the_item_box_runs_from_the_machine_to_a_block_past_the_hit_block() {
        // `new AABB(tile, hit + 1).inflate(0.02).expandTowards(facing)` plus the ordering fix:
        // the machine at 0, the hit block at 5, so the box spans 0..6 and one further to 7.
        let east = item_scan_box([0, 100, 0], [5, 100, 0], Facing::East);
        assert!(
            holds(east, [2.5, 100.0, 0.5]),
            "an item between the machine and the hit block is in the beam's box: {east:?}"
        );
        assert!(
            holds(east, [6.5, 100.5, 0.5]),
            "the box reaches one block past the hit block (upstream's expandTowards): {east:?}"
        );
        assert!(
            !holds(east, [7.5, 100.5, 0.5]),
            "and no further than that: {east:?}"
        );
        assert!(
            !holds(east, [2.5, 100.0, 2.5]),
            "the box is one block deep across the beam: {east:?}"
        );

        // The three negative facings are where upstream's AABB is inverted and matches nothing;
        // the port's box is ordered and mirrored, so a west beam converts its own items.
        let west = item_scan_box([10, 100, 0], [5, 100, 0], Facing::West);
        assert!(
            (0..3).all(|axis| west.0[axis] <= west.1[axis]),
            "a west beam's box is not inverted: {west:?}"
        );
        assert!(
            holds(west, [7.0, 100.0, 0.5]),
            "an item between a west-facing machine and its hit block: {west:?}"
        );
        assert!(
            holds(west, [5.5, 100.0, 0.5]),
            "a west beam's box reaches a block beyond its hit-side end: {west:?}"
        );
        assert!(!holds(west, [4.5, 100.0, 0.5]), "{west:?}");

        let north = item_scan_box([0, 100, 10], [0, 100, 5], Facing::North);
        assert!(
            (0..3).all(|axis| north.0[axis] <= north.1[axis]),
            "{north:?}"
        );
        assert!(holds(north, [0.5, 100.0, 7.0]), "{north:?}");

        let down = item_scan_box([0, 110, 0], [0, 105, 0], Facing::Down);
        assert!((0..3).all(|axis| down.0[axis] <= down.1[axis]), "{down:?}");
        assert!(holds(down, [0.5, 107.0, 0.5]), "{down:?}");
        let up = item_scan_box([0, 100, 0], [0, 105, 0], Facing::Up);
        assert!((0..3).all(|axis| up.0[axis] <= up.1[axis]), "{up:?}");
        assert!(holds(up, [0.5, 107.0, 0.5]), "{up:?}");
    }

    #[test]
    fn a_shot_converts_as_many_items_as_the_recipe_and_the_buffer_allow() {
        // `Math.min(energy / recipe.getEnergy(), stack.getCount())`, after the 1,000 CF gate.
        assert_eq!(items_possible(40, 40, 1), 1, "one redstone for 40 CF");
        assert_eq!(
            items_possible(40, 40, 3),
            1,
            "40 CF converts one item of a stack of three, not all three"
        );
        assert_eq!(items_possible(120, 40, 3), 3, "120 CF converts the stack");
        assert_eq!(items_possible(39, 40, 1), 0, "39 CF converts nothing");
        assert_eq!(
            items_possible(20_000, 20_000, 1),
            1,
            "rotten flesh at 20,000"
        );
        assert_eq!(
            items_possible(30_000, 30_000, 2),
            1,
            "30,000 CF converts one quartz of two"
        );
        assert_eq!(
            items_possible(1_000_000, 40, 64),
            64,
            "the stack's own count caps the conversion"
        );
        assert_eq!(
            items_possible(0, 0, 5),
            5,
            "a zero-cost recipe converts the stack (upstream would divide by zero)"
        );
        assert_eq!(
            items_possible(-10, 40, 1),
            0,
            "a negative buffer converts nothing"
        );
    }

    #[test]
    fn a_converted_item_carries_the_marker_and_is_not_converted_again() {
        assert_eq!(
            CONVERTED_MARKER, "aa_cnv",
            "upstream's own persistent-data key"
        );
        assert!(may_convert(&[], 1), "a fresh dropped item may convert");
        assert!(
            !may_convert(&["aa_cnv".to_owned()], 1),
            "an item the beam already converted is skipped"
        );
        assert!(
            may_convert(&["other".to_owned()], 1),
            "an unrelated tag does not skip it"
        );
        assert!(!may_convert(&[], 0), "an empty stack is skipped");
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
            Json::String("#c:dusts/redstone".into()),
            "the ingredient is the pin's own form, as the crusher's recipes use"
        );
        assert_eq!(
            recipe.ingredient.to_string(),
            r##""#c:dusts/redstone""##,
            "the text handed to recipe_ingredient is the spec, quoted"
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
    fn a_restored_reconstructor_is_clamped_into_its_buffer_cycle_and_mode() {
        assert_eq!(
            restored_reconstructor(5_000, 40, true),
            Reconstructor {
                energy: 5_000,
                cycle: 40,
                pulse: true,
                ..Reconstructor::new()
            }
        );
        assert_eq!(
            restored_reconstructor(400_000, 900, false),
            Reconstructor {
                energy: RECONSTRUCTOR_CAPACITY,
                cycle: RECONSTRUCTOR_TICKS,
                ..Reconstructor::new()
            }
        );
        // A stale item can name any int, but the buffer, the cycle and the mode come back in range.
        assert_eq!(restored_reconstructor(-1, -7, false), Reconstructor::new());
    }

    #[test]
    fn a_lens_fills_the_empty_slot_and_a_second_lens_is_refused() {
        assert!(
            lens_slot_accepts(None, "actuallyadditions:lens"),
            "a lens fills the empty slot"
        );
        assert!(
            !lens_slot_accepts(Some("actuallyadditions:lens"), "actuallyadditions:lens"),
            "an occupied slot refuses a second lens"
        );
        assert!(
            !lens_slot_accepts(None, "minecraft:stick"),
            "a non-lens is refused by the empty slot"
        );
    }

    #[test]
    fn a_miner_lens_is_accepted_by_the_slot_and_selects_the_mining_effect() {
        assert!(
            lens_slot_accepts(None, LENS_OF_THE_MINER),
            "the miner lens is an ILensItem, so the empty slot accepts it"
        );
        assert_eq!(
            LensEffect::of(LENS_OF_THE_MINER),
            LensEffect::Mining,
            "its getLens() is LensMining"
        );
        assert_eq!(
            LensEffect::of("actuallyadditions:lens"),
            LensEffect::Conversion,
            "the plain lens keeps the default conversion"
        );
        assert_eq!(
            LensEffect::of(""),
            LensEffect::Conversion,
            "an empty slot is the default conversion lens"
        );
    }

    #[test]
    fn the_mining_lens_costs_sixty_thousand_cf_and_reaches_ten_blocks() {
        assert_eq!(
            MINING_LENS_ENERGY, 60_000,
            "CommonConfig's minerLensEnergy default"
        );
        assert_eq!(LensEffect::Mining.distance(), 10, "LensMining.getDistance");
        let mut state = Reconstructor {
            energy: 61_000,
            ..Reconstructor::new()
        };
        assert_eq!(
            state.fire(),
            Some(60_000),
            "the 1,000 CF gate is paid first"
        );
        assert!(
            state.can_afford(MINING_LENS_ENERGY),
            "the gate leaves the miner's 60,000"
        );
        state.spend(MINING_LENS_ENERGY);
        assert_eq!(state.energy, 0, "the miner's own energy is charged on top");
        let mut short = Reconstructor {
            energy: 1_040,
            ..Reconstructor::new()
        };
        assert_eq!(short.fire(), Some(40));
        assert!(
            !short.can_afford(MINING_LENS_ENERGY),
            "a 1,040 CF shot cannot fire the miner lens"
        );
    }

    #[test]
    fn a_weighted_pick_walks_the_recipes_in_order_with_the_roll() {
        let recipes = [
            MiningLensRecipe {
                id: "a".into(),
                ingredient: Json::Null,
                result: Json::Null,
                weight: 2,
            },
            MiningLensRecipe {
                id: "b".into(),
                ingredient: Json::Null,
                result: Json::Null,
                weight: 3,
            },
            MiningLensRecipe {
                id: "c".into(),
                ingredient: Json::Null,
                result: Json::Null,
                weight: 5,
            },
        ];
        let picked = |roll| pick_weighted(&recipes, roll).map(|recipe| recipe.id.as_str());
        assert_eq!(picked(0), Some("a"));
        assert_eq!(picked(1), Some("a"), "a owns rolls 0 and 1");
        assert_eq!(picked(2), Some("b"), "b owns rolls 2, 3 and 4");
        assert_eq!(picked(4), Some("b"));
        assert_eq!(picked(5), Some("c"), "c owns rolls 5 through 9");
        assert_eq!(picked(9), Some("c"));
        assert_eq!(picked(10), None, "a roll past the total picks nothing");
        assert_eq!(
            pick_weighted(&[], 0),
            None,
            "no matching recipe picks nothing"
        );
    }

    #[test]
    fn a_mining_lens_recipe_is_read_from_the_jars_json() {
        let recipe = MiningLensRecipe::parse(
            "actuallyadditions:mining_lens/stone_coal_ore",
            r#"{"type":"actuallyadditions:mining_lens","ingredient":{"tag":"actuallyadditions:stone_ore_replaceables"},"result":{"count":1,"id":"minecraft:coal_ore"},"weight":5000}"#,
        )
        .expect("the jar's own recipe parses");
        assert_eq!(recipe.id, "actuallyadditions:mining_lens/stone_coal_ore");
        assert_eq!(recipe.weight, 5000);
        assert_eq!(recipe.result_id(), Some("minecraft:coal_ore"));
        assert_eq!(
            recipe.ingredient.to_string(),
            "\"#actuallyadditions:stone_ore_replaceables\"",
            "the tag ingredient is normalised to the pin's #tag form"
        );
        assert!(
            MiningLensRecipe::parse(
                "x:y",
                r#"{"ingredient":{"item":"a:b"},"result":{"id":"c:d"}}"#
            )
            .is_err(),
            "a recipe with no weight is refused"
        );
    }

    #[test]
    fn a_detonation_lens_is_accepted_by_the_slot_and_selects_the_detonation_effect() {
        assert!(
            lens_slot_accepts(None, LENS_OF_DETONATION),
            "the detonator lens is an ILensItem, so the empty slot accepts it"
        );
        assert_eq!(
            LensEffect::of(LENS_OF_DETONATION),
            LensEffect::Detonation,
            "its getLens() is LensDetonation, not the default conversion"
        );
        assert_eq!(
            LensEffect::of("actuallyadditions:lens"),
            LensEffect::Conversion,
            "the plain lens keeps the default conversion"
        );
    }

    #[test]
    fn the_detonation_costs_two_hundred_and_fifty_thousand_cf_and_reaches_thirty_blocks() {
        assert_eq!(
            DETONATION_LENS_ENERGY, 250_000,
            "LensDetonation.ENERGY_USE, on top of the shot's 1,000 CF gate"
        );
        assert_eq!(DETONATION_BLAST_RADIUS, 10.0, "explode's radius argument");
        assert_eq!(
            LensEffect::Detonation.distance(),
            30,
            "LensDetonation.getDistance, three times the default lens"
        );
        let mut state = Reconstructor {
            energy: 251_000,
            ..Reconstructor::new()
        };
        assert_eq!(
            state.fire(),
            Some(250_000),
            "the 1,000 CF shot gate is paid before the lens's invoke"
        );
        assert!(
            state.can_afford(DETONATION_LENS_ENERGY),
            "the gate leaves the detonator's own 250,000 CF"
        );
        state.spend(DETONATION_LENS_ENERGY);
        assert_eq!(state.energy, 0, "the blast's own energy is charged");
        let mut short = Reconstructor {
            energy: 250_999,
            ..Reconstructor::new()
        };
        assert_eq!(short.fire(), Some(249_999));
        assert!(
            !short.can_afford(DETONATION_LENS_ENERGY),
            "251,000 CF total is the exact price: one CF short cannot fire"
        );
    }

    #[test]
    fn the_detonation_stops_at_a_solid_sight_and_lets_air_pass() {
        assert!(
            detonation_stop(false),
            "invoke returns true for a non-air block, even when nothing matched"
        );
        assert!(
            !detonation_stop(true),
            "an air sight returns false, so the beam keeps walking"
        );
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
        assert_eq!(
            recipe.ingredient,
            Json::String("minecraft:coal_ore".into()),
            "the ingredient is read in the same pass as the results"
        );
        assert_eq!(recipe.ingredient.to_string(), r#""minecraft:coal_ore""#);
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
