//! The Coal Generator's and the Crusher's glue: the two block-entity Parts, the blocks'
//! container and energy declarations, the saved state, the energy push, the click and the
//! `/actuallyadditions info` command.
//!
//! Every rule lives in [`crate::runtime`] (the retired bundle's `runtime.rs`, byte-identical);
//! this file reads the game, calls it and writes the result back. Its tests pin what it
//! *declares* (one insert-only fuel slot, three crusher slots, an output-only and an input-only
//! buffer), that the state written to the saved compound reads back, and the exact lines
//! `/actuallyadditions info` prints.
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use mod_api::{
    self, BlockClick, BlockEntityEvent, BlockEntityPart, BlockEntityTickEvent,
    BlockEntityTickReply, BlockEntityTicksEvent, BlockPart, Command, CommandArgumentValue,
    Compound, ENERGY, Flow, Host, HostTransaction, Identifier, Ingredient, InteractionResult,
    ItemKey, ItemPlace, ItemResource, ItemStack, LevelRef, LevelSide, ModContainer,
    ModEnergyBuffer, RandomSource, Registrar, RegistrationContext, RunModCommandEvent, ServerHost,
    Tag, Text, move_energy,
};

use crate::runtime::{
    CRUSHER_CAPACITY, CRUSHER_MAX_INSERT, CRUSHER_TICKS, CrushResult, Crusher, CrushingRecipe,
    GENERATOR_CAPACITY, GENERATOR_MAX_EXTRACT, Generator, Step, bonus_for, can_crush, clamp_energy,
    comparator_strength, ingredient_json, is_fuel,
};

/// The generator block; its block entity type carries the same path.
pub(crate) const GENERATOR: &str = "actuallyadditions:coal_generator";
/// The crusher block; its block entity type carries the same path.
pub(crate) const CRUSHER: &str = "actuallyadditions:crusher";
/// The custom recipe type the crusher reads (upstream `ActuallyAdditionsAPI.RECIPE_CRUSHING`).
const CRUSHING: &str = "actuallyadditions:crushing";
/// Rebuild the parsed recipe cache this often (ticks): a `/reload` lands within two seconds and
/// the pure parser cost is paid once, as the retired bundle did.
const RECIPE_CACHE_TICKS: u64 = 40;
/// The generator's one slot: fuel.
const GENERATOR_SLOTS: usize = 1;
/// The crusher's slots: input, guaranteed output, chance output.
const CRUSHER_SLOTS: usize = 3;
/// The slot a click fills: fuel for the generator, the input for the crusher.
const INPUT_SLOT: usize = 0;
/// The crusher's guaranteed-output slot.
const OUTPUT_ONE: usize = 1;
/// The crusher's chance-output slot.
const OUTPUT_TWO: usize = 2;
/// Vanilla's stack limit, for an item this world does not know.
const DEFAULT_STACK: u32 = 64;
/// The response of a status read where no machine stands.
const NO_MACHINE: &str = "No Actually Additions machine there.";

// ---------------------------------------------------------------------------
// What the mod declares for its two blocks
// ---------------------------------------------------------------------------

/// Declare both machines: a block entity type each, its Part (tick and click), the container and
/// the energy buffer (upstream's `RegisterCapabilitiesEvent`).
pub(crate) fn declare(r: &mut dyn Registrar, context: &RegistrationContext) {
    let generator = r.block_key(GENERATOR);
    let crusher = r.block_key(CRUSHER);
    r.block_container(&generator, generator_container());
    r.block_container(&crusher, crusher_container());
    r.block_energy(&generator, generator_battery());
    r.block_energy(&crusher, crusher_battery());
    let generator_kind = r
        .block_entity_type("coal_generator")
        .blocks(&["coal_generator"])
        .build();
    let crusher_kind = r.block_entity_type("crusher").blocks(&["crusher"]).build();
    r.block_part(generator, GeneratorPart);
    r.block_part(crusher, CrusherPart);
    if let Err(error) = r.block_entity_part(&generator_kind, GeneratorPart) {
        context.refuse(&error.to_string());
    }
    if let Err(error) = r.block_entity_part(&crusher_kind, CrusherPart) {
        context.refuse(&error.to_string());
    }
}

/// The generator's container: one fuel slot every face reaches, insert-only for automation
/// (`native_block_entity_container`'s `ModContainer` at the retired pin).
pub(crate) fn generator_container() -> ModContainer {
    ModContainer {
        slots: GENERATOR_SLOTS,
        faces: std::array::from_fn(|_| vec![INPUT_SLOT]),
        inputs: vec![INPUT_SLOT],
        outputs: vec![],
        menu: None,
    }
}

/// The crusher's container: its input and its two outputs, every face reaching each, so a hopper
/// can feed it and take from it.
pub(crate) fn crusher_container() -> ModContainer {
    let all: Vec<usize> = (0..CRUSHER_SLOTS).collect();
    ModContainer {
        slots: CRUSHER_SLOTS,
        faces: std::array::from_fn(|_| all.clone()),
        inputs: vec![INPUT_SLOT],
        outputs: vec![OUTPUT_ONE, OUTPUT_TWO],
        menu: None,
    }
}

/// The generator's buffer: upstream's `CustomEnergyStorage(60000, 0, 80)` — it stores, takes
/// nothing in and gives 80 FE a call.
pub(crate) fn generator_battery() -> ModEnergyBuffer {
    ModEnergyBuffer {
        capacity: GENERATOR_CAPACITY,
        max_insert: 0,
        max_extract: GENERATOR_MAX_EXTRACT,
        insert_faces: [false; 6],
        extract_faces: [true; 6],
    }
}

/// The crusher's buffer: upstream's `CustomEnergyStorage(60000, 100, 0)` — it takes 100 FE a call
/// and gives nothing out.
pub(crate) fn crusher_battery() -> ModEnergyBuffer {
    ModEnergyBuffer {
        capacity: CRUSHER_CAPACITY,
        max_insert: CRUSHER_MAX_INSERT,
        max_extract: 0,
        insert_faces: [true; 6],
        extract_faces: [false; 6],
    }
}

// ---------------------------------------------------------------------------
// The saved state
// ---------------------------------------------------------------------------

/// A saved int, 0 when absent or of another type.
fn int(saved: &Tag, key: &str) -> i32 {
    match saved.get(key) {
        Some(Tag::Int(value)) => *value,
        _ => 0,
    }
}

/// Write one int into a saved compound, as the energy capability and the tick read it.
fn set_int(saved: &mut Tag, key: &str, value: i32) {
    if let Tag::Compound(nbt) = saved {
        nbt.insert(key.into(), Tag::Int(value));
    }
}

/// The generator a saved compound holds (`energy`, `burn`, `burn_max`).
pub(crate) fn read_generator(saved: &Tag) -> Generator {
    Generator {
        energy: clamp_energy(int(saved, "energy"), GENERATOR_CAPACITY),
        burn: int(saved, "burn").max(0) as u32,
        burn_max: int(saved, "burn_max").max(0) as u32,
    }
}

/// Write the generator back into a saved compound.
pub(crate) fn write_generator(saved: &mut Tag, state: &Generator) {
    set_int(saved, "energy", state.energy);
    set_int(saved, "burn", state.burn as i32);
    set_int(saved, "burn_max", state.burn_max as i32);
}

/// The crusher a saved compound holds (`energy`, `progress`).
pub(crate) fn read_crusher(saved: &Tag) -> Crusher {
    Crusher {
        energy: clamp_energy(int(saved, "energy"), CRUSHER_CAPACITY),
        progress: int(saved, "progress").max(0) as u32,
    }
}

/// Write the crusher back into a saved compound.
pub(crate) fn write_crusher(saved: &mut Tag, state: &Crusher) {
    set_int(saved, "energy", state.energy);
    set_int(saved, "progress", state.progress as i32);
}

// ---------------------------------------------------------------------------
// The report line `/actuallyadditions info` prints
// ---------------------------------------------------------------------------

/// The generator's report line as `/actuallyadditions info` prints it, `t` being the world time
/// (the in-game check uses it to prove a reply is fresh).
pub(crate) fn generator_line(pos: [i32; 3], state: &Generator, t: i64) -> String {
    format!(
        "Coal Generator at {},{},{}: {}/{} FE (comparator {}, burning {}/{} ticks, t={t})",
        pos[0],
        pos[1],
        pos[2],
        state.energy,
        GENERATOR_CAPACITY,
        comparator_strength(state.energy, GENERATOR_CAPACITY),
        state.burn,
        state.burn_max,
    )
}

/// The crusher's report line: its buffer, progress, what its input slot holds, what that crushes
/// into and the chance result, then the world time.
pub(crate) fn crusher_line(
    pos: [i32; 3],
    state: &Crusher,
    input: Option<(&str, u32)>,
    recipe: Option<&CrushingRecipe>,
    t: i64,
) -> String {
    let input = match input {
        Some((item, count)) => format!("{item} x{count}"),
        None => "empty".to_owned(),
    };
    let crushing = recipe.map_or("nothing".to_owned(), |recipe| {
        format!(
            "{} x{}",
            recipe.guaranteed().item,
            recipe.guaranteed().count
        )
    });
    let bonus = recipe
        .and_then(CrushingRecipe::bonus)
        .map_or("none".to_owned(), |bonus| {
            format!(
                "{} x{} @ {:.0}%",
                bonus.item,
                bonus.count,
                bonus.chance * 100.0
            )
        });
    format!(
        "Crusher at {},{},{}: {}/{} FE (comparator {}, progress {}/{}, input {}, crushing into {}, \
         bonus {}, t={t})",
        pos[0],
        pos[1],
        pos[2],
        state.energy,
        CRUSHER_CAPACITY,
        comparator_strength(state.energy, CRUSHER_CAPACITY),
        state.progress,
        CRUSHER_TICKS,
        input,
        crushing,
        bonus,
    )
}

// ---------------------------------------------------------------------------
// The parsed recipe table
// ---------------------------------------------------------------------------

/// A crushing recipe with its engine-resolved ingredient.
struct Resolved {
    ingredient: Ingredient,
    recipe: CrushingRecipe,
}

/// The recipe table, rebuilt when a world loads and every [`RECIPE_CACHE_TICKS`] reads.
static RECIPES: Mutex<Option<Vec<Resolved>>> = Mutex::new(None);
/// Calls since the last rebuild; the counter is read outside the lock so a hot tick does not
/// contend on it.
static RECIPE_TICKS: AtomicU64 = AtomicU64::new(0);

/// The crushing recipe whose ingredient the stack matches, if any.
pub(crate) fn find_recipe(host: &dyn Host, input: &ItemStack) -> Option<CrushingRecipe> {
    let due = RECIPE_TICKS
        .fetch_add(1, Ordering::Relaxed)
        .is_multiple_of(RECIPE_CACHE_TICKS);
    let mut cache = RECIPES.lock().expect("the recipe cache lock is held");
    if cache.is_none() || due {
        let mut resolved = Vec::new();
        for recipe in host.recipes_of_type(CRUSHING).iter() {
            let Ok(parsed) = CrushingRecipe::parse(&recipe.id, &recipe.json.to_string()) else {
                continue;
            };
            let ingredient =
                recipe
                    .json
                    .get("ingredient")
                    .map(ingredient_json)
                    .and_then(|ingredient| {
                        host.recipe_ingredient(&ingredient.to_string())
                            .ok()
                            .flatten()
                    });
            if let Some(ingredient) = ingredient {
                resolved.push(Resolved {
                    ingredient,
                    recipe: parsed,
                });
            }
        }
        *cache = Some(resolved);
    }
    let recipes = cache.as_ref()?;
    recipes
        .iter()
        .find(|resolved| resolved.ingredient.test(host, input))
        .map(|resolved| resolved.recipe.clone())
}

/// Drop the parsed table (a world opened or closed: its data packs are new).
pub(crate) fn reset_recipes() {
    *RECIPES.lock().expect("the recipe cache lock is held") = None;
    RECIPE_TICKS.store(0, Ordering::Relaxed);
}

/// The item id a stack holds.
fn item_id(host: &dyn Host, stack: &ItemStack) -> String {
    stack.item().id(host)
}

/// An item id's key, `None` for one this world does not have.
fn item_key(host: &dyn Host, item: &str) -> Option<ItemKey> {
    Identifier::parse(item)
        .ok()
        .and_then(|id| host.item_key(&id))
}

/// `ItemInfo::max_stack` for an item id, 64 when unknown (vanilla's default).
pub(crate) fn max_stack(host: &dyn Host, item: &str) -> u32 {
    item_key(host, item)
        .and_then(|key| host.max_stack_size(key))
        .unwrap_or(DEFAULT_STACK)
}

/// The engine's fuel value (`minecraft:cooking_fuel.burn_time`), 0 if none.
fn fuel_burn_time(host: &dyn Host, stack: &ItemStack) -> u32 {
    host.item_burn_time(stack.item()).unwrap_or(0).max(0) as u32
}

/// `StackUtil.shrinkForContainer`: one item is consumed and a container item (a lava bucket's
/// bucket) takes its place when the stack runs out.
fn consume_one(host: &dyn Host, stack: &ItemStack) -> Option<ItemStack> {
    stack
        .clone()
        .shrink(1)
        .or_else(|| host.item_crafting_remainder(stack))
}

// ---------------------------------------------------------------------------
// The ticks
// ---------------------------------------------------------------------------

/// The level a block-entity tick is in: a tick is not told its level, so the one in place answers.
pub(crate) fn in_place_level(host: &dyn ServerHost) -> Option<LevelRef> {
    host.levels()
        .list_levels()
        .into_iter()
        .find(|level| level.in_place(host))
}

/// The generator: load fuel when upstream would, burn one tick and make 20 FE, then queue itself
/// for the energy push. True when the saved state or the fuel slot changed.
pub(crate) fn tick_generator(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    pos: [i32; 3],
    saved: &mut Tag,
    items: &mut [Option<ItemStack>],
) -> bool {
    let powered = level.is_some_and(|level| level.has_neighbor_signal(&*host, pos));
    let before = read_generator(saved);
    let mut state = before.clone();
    let mut changed = false;
    if state.wants_fuel(powered)
        && let Some(stack) = items.get(INPUT_SLOT).and_then(Option::clone)
        && state.load_fuel(fuel_burn_time(&*host, &stack))
    {
        items[INPUT_SLOT] = consume_one(&*host, &stack);
        changed = true;
    }
    if state.tick() > 0 {
        changed = true;
    }
    changed |= state != before;
    write_generator(saved, &state);
    if state.energy > 0
        && let Some(level) = level
    {
        queue_push(level, pos);
    }
    changed
}

/// The crusher: find the first matching recipe, check the output room and let the pure state
/// machine spend FE and advance. A finished operation applies the guaranteed output, then the
/// chance roll (`Level.random.nextFloat`). True when anything moved.
pub(crate) fn tick_crusher(
    host: &mut dyn ServerHost,
    level: Option<LevelRef>,
    saved: &mut Tag,
    items: &mut [Option<ItemStack>],
) -> bool {
    let input = items.get(INPUT_SLOT).and_then(Option::clone);
    let recipe = input.as_ref().and_then(|stack| find_recipe(&*host, stack));
    let mut output_one = None;
    if let Some(stack) = items.get(OUTPUT_ONE).and_then(Option::as_ref) {
        output_one = Some((item_id(&*host, stack), stack.count() as i32));
    }
    let mut output_two = None;
    if let Some(stack) = items.get(OUTPUT_TWO).and_then(Option::as_ref) {
        output_two = Some((item_id(&*host, stack), stack.count() as i32));
    }
    let has_work = recipe.as_ref().is_some_and(|recipe| {
        can_crush(
            recipe,
            output_one
                .as_ref()
                .map(|(item, count)| (item.as_str(), *count)),
            output_two
                .as_ref()
                .map(|(item, count)| (item.as_str(), *count)),
            |item| max_stack(&*host, item) as i32,
        )
    });
    let before = read_crusher(saved);
    let mut state = before.clone();
    let step = state.tick(has_work);
    if step == Step::Finished
        && let Some(recipe) = recipe.as_ref()
    {
        let roll = level
            .and_then(|level| level.with_random(host, |random| random.next_float()))
            .unwrap_or(1.0);
        finish_operation(&*host, items, recipe, roll);
    }
    write_crusher(saved, &state);
    step != Step::Idle || state != before
}

/// A finished operation: the guaranteed result, the chance result and one input item.
fn finish_operation(
    host: &dyn Host,
    items: &mut [Option<ItemStack>],
    recipe: &CrushingRecipe,
    roll: f32,
) {
    grow_output(host, items, OUTPUT_ONE, recipe.guaranteed());
    if let Some(bonus) = bonus_for(recipe, roll) {
        grow_output(host, items, OUTPUT_TWO, bonus);
    }
    let Some(input) = items.get_mut(INPUT_SLOT).and_then(Option::take) else {
        return;
    };
    if let Some(left) = input.shrink(1) {
        items[INPUT_SLOT] = Some(left);
    }
}

/// Add one result to an output slot: the same item with room, or an empty slot; a different item
/// leaves the slot alone (upstream's `canCrushOn` gate never lets that happen).
pub(crate) fn grow_output(
    host: &dyn Host,
    items: &mut [Option<ItemStack>],
    slot: usize,
    result: &CrushResult,
) {
    let Some(key) = item_key(host, &result.item) else {
        return;
    };
    let limit = host.max_stack_size(key).unwrap_or(DEFAULT_STACK);
    let count = (result.count.max(0) as u32).min(limit);
    match items.get(slot).and_then(Option::as_ref) {
        Some(stack) if stack.item() == key => {
            let mut stack = stack.clone();
            let merged = stack.count().saturating_add(count).min(limit);
            if stack.set_count(merged).is_ok() {
                items[slot] = Some(stack);
            }
        }
        Some(_) => {}
        None => items[slot] = ItemStack::new(key, count),
    }
}

// ---------------------------------------------------------------------------
// The energy push
// ---------------------------------------------------------------------------

/// Generator positions queued for an energy push, by level: a block entity is out of the world
/// during its own tick, so the push happens at `level_tick_post`, where both are back.
static PUSH: Mutex<Vec<(LevelRef, [i32; 3])>> = Mutex::new(Vec::new());

/// Queue one generator for its level's push, once.
fn queue_push(level: LevelRef, pos: [i32; 3]) {
    let mut queue = PUSH.lock().expect("the push queue lock is held");
    if !queue
        .iter()
        .any(|(queued, at)| *queued == level && *at == pos)
    {
        queue.push((level, pos));
    }
}

/// Drop every queued push (a world closed: its positions belong to it).
pub(crate) fn clear_push_queue() {
    PUSH.lock().expect("the push queue lock is held").clear();
}

/// After a level's tick: every queued generator pushes its FE into the crushers beside it, through
/// the energy capabilities (`move_energy`, the counterpart of `native_move_energy`).
pub(crate) fn on_level_tick_post(host: &mut dyn ServerHost, level: LevelRef) {
    let queued = {
        let mut queue = PUSH.lock().expect("the push queue lock is held");
        std::mem::take(&mut *queue)
    };
    if queued.is_empty() {
        return;
    }
    let mut later = Vec::new();
    for (queued_level, generator) in queued {
        if queued_level != level {
            later.push((queued_level, generator));
            continue;
        }
        if block_id(host, level, generator).as_deref() != Some(GENERATOR) {
            continue;
        }
        push_generator_energy(host, level, generator);
    }
    if !later.is_empty() {
        PUSH.lock()
            .expect("the push queue lock is held")
            .extend(later);
    }
}

/// One generator's six neighbours: each crusher beside it takes up to the generator's extract
/// limit, as upstream's buffers do.
fn push_generator_energy(host: &mut dyn ServerHost, level: LevelRef, pos: [i32; 3]) {
    let limit = u32::try_from(GENERATOR_MAX_EXTRACT).unwrap_or(0);
    for side in mod_api::Direction::ALL {
        let [dx, dy, dz] = side.normal();
        let neighbour = [pos[0] + dx, pos[1] + dy, pos[2] + dz];
        if block_id(host, level, neighbour).as_deref() != Some(CRUSHER) {
            continue;
        }
        let _ = host.transaction(|host, tx| -> Result<u32, ()> {
            let Some(from) = level.capability(&mut *host, &ENERGY, pos, Some(side)) else {
                return Ok(0);
            };
            let Some(to) = level.capability(&mut *host, &ENERGY, neighbour, Some(side.opposite()))
            else {
                return Ok(0);
            };
            Ok(move_energy(&mut *host, &from, &to, limit, tx).unwrap_or(0))
        });
    }
}

/// The block id at a position, `None` for an unknown block.
fn block_id(host: &dyn Host, level: LevelRef, pos: [i32; 3]) -> Option<String> {
    level.block(host, pos).map(|key| key.id(host))
}

// ---------------------------------------------------------------------------
// The click
// ---------------------------------------------------------------------------

/// A right click on a machine: there is no GUI in slice 1, so the click inserts a matching item
/// (fuel or a recipe input) and an empty hand reads the status. The click is always claimed, so
/// the furnace template never opens its own menu and a refused item is never placed.
pub(crate) fn machine_click(
    host: &mut dyn ServerHost,
    click: &BlockClick<'_>,
    held: Option<&ItemStack>,
) -> Option<InteractionResult> {
    let level = host.level(click.dimension.key().id())?;
    let pos = click.pos;
    let kind = block_id(&*host, level, pos)?;
    if kind != GENERATOR && kind != CRUSHER {
        return None;
    }
    let Some(held) = held.filter(|stack| stack.count() > 0) else {
        let line = status_line(host, pos);
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal(line));
        }
        return Some(InteractionResult::Success);
    };
    let accepted = if kind == GENERATOR {
        is_fuel(fuel_burn_time(&*host, held))
    } else {
        find_recipe(&*host, held).is_some()
    };
    if !accepted {
        let line = if kind == GENERATOR {
            format!("{} is not a fuel", item_id(&*host, held))
        } else {
            format!("{} has no crushing recipe", item_id(&*host, held))
        };
        if let Some(player) = host.player(click.player) {
            let _ = player.action_bar(host, Text::literal(line));
        }
        return Some(InteractionResult::Success);
    }
    let hand = ItemPlace::PlayerHand {
        player: click.player,
        hand: click.hand,
    };
    insert_from_hand(host, level, pos, held, &hand);
    Some(InteractionResult::Success)
}

/// Insert as much of the held stack as the input slot takes, and take exactly that from the hand,
/// in one transaction (a creative player's hand gives without losing any).
fn insert_from_hand(
    host: &mut dyn ServerHost,
    level: LevelRef,
    pos: [i32; 3],
    held: &ItemStack,
    hand: &ItemPlace,
) -> u32 {
    host.transaction(|host, tx| -> Result<u32, ()> {
        let entity = host.block_entity(level, pos).ok_or(())?;
        let key = held.item();
        let limit = host.max_stack_size(key).unwrap_or(DEFAULT_STACK);
        let existing = entity.item_slot(&*host, INPUT_SLOT as u32).ok().flatten();
        let (inserted, after) = match existing {
            None => {
                let count = held.count().min(limit);
                (count, ItemStack::new(key, count))
            }
            Some(existing) if existing.item() == key => {
                let room = limit.saturating_sub(existing.count());
                let count = held.count().min(room);
                let mut after = existing;
                let merged = after.count().saturating_add(count).min(limit);
                after.set_count(merged).map_err(|_| ())?;
                (count, Some(after))
            }
            Some(_) => (0, None),
        };
        if inserted == 0 {
            return Ok(0);
        }
        let Some(after) = after else {
            return Ok(0);
        };
        entity
            .set_item_slot(&mut *host, tx, INPUT_SLOT as u32, Some(after))
            .map_err(|_| ())?;
        let _ = entity.set_changed(&mut *host);
        let _ = hand.extract(&mut *host, tx, &ItemResource::of(held), inserted);
        Ok(inserted)
    })
    .unwrap_or(0)
}

// ---------------------------------------------------------------------------
// The command
// ---------------------------------------------------------------------------

/// `/actuallyadditions info <pos>`: the harness's readout of one machine (a harness addition, as
/// the 0.1.0 command was; there is no GUI in this slice).
pub(crate) fn declare_commands(commands: &mut Vec<Command>) {
    commands.push(Command::new("actuallyadditions info <pos:block_pos>"));
}

/// The one line the command prints for the block at `pos`.
pub(crate) fn status_line(host: &mut dyn ServerHost, pos: [i32; 3]) -> String {
    let Some(level) = host.level(host.dimension()) else {
        return NO_MACHINE.to_owned();
    };
    let Some(kind) = block_id(&*host, level, pos) else {
        return NO_MACHINE.to_owned();
    };
    if kind != GENERATOR && kind != CRUSHER {
        return NO_MACHINE.to_owned();
    }
    let Some(entity) = host.block_entity(level, pos) else {
        return NO_MACHINE.to_owned();
    };
    let Some(saved) = entity.data(&*host) else {
        return NO_MACHINE.to_owned();
    };
    let saved = Tag::Compound(saved);
    let t = level.game_time(&*host).unwrap_or(0);
    if kind == GENERATOR {
        return generator_line(pos, &read_generator(&saved), t);
    }
    let input = entity.item_slot(&*host, INPUT_SLOT as u32).ok().flatten();
    let recipe = input.as_ref().and_then(|stack| find_recipe(&*host, stack));
    let input = input
        .as_ref()
        .map(|stack| (stack.item().id(&*host), stack.count()));
    crusher_line(
        pos,
        &read_crusher(&saved),
        input.as_ref().map(|(item, count)| (item.as_str(), *count)),
        recipe.as_ref(),
        t,
    )
}

/// Run `/actuallyadditions info <pos>`; `Flow::Cancel` when it was ours.
pub(crate) fn run_command(host: &mut dyn ServerHost, event: &mut RunModCommandEvent<'_>) -> Flow {
    let literals: Vec<&str> = event.command.literals.iter().map(String::as_str).collect();
    if literals.as_slice() != ["actuallyadditions", "info"] {
        return Flow::Continue;
    }
    let Some(CommandArgumentValue::BlockPos(pos)) = event.command.argument("pos") else {
        return Flow::Continue;
    };
    let line = status_line(host, *pos);
    let _ = host.commands().feedback(Text::literal(line));
    Flow::Cancel
}

// ---------------------------------------------------------------------------
// The two Parts
// ---------------------------------------------------------------------------

/// The Coal Generator: it ticks, and a click puts fuel in its slot.
pub(crate) struct GeneratorPart;

#[mod_api::horizon_part]
impl BlockPart for GeneratorPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut mod_api::UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        machine_click(host, event.click, event.click.stack)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut mod_api::UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        machine_click(host, event.click, None)
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for GeneratorPart {
    /// `EntityBlock.newBlockEntity`: an empty saved compound; the tick fills it.
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    /// `EntityBlock.getTicker`: it ticks. Never clear a value an earlier mod set.
    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: fuel, burn, FE, then the queue for the push.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let pos = event.pos;
        let level = in_place_level(host);
        if event.entity.items.len() != GENERATOR_SLOTS {
            event.entity.items.resize(GENERATOR_SLOTS, None);
        }
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let items = &mut event.entity.items;
        let changed = tick_generator(host, level, pos, &mut saved, items);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

/// The Crusher: it ticks, and a click puts an input in its slot.
pub(crate) struct CrusherPart;

#[mod_api::horizon_part]
impl BlockPart for CrusherPart {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut mod_api::UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        machine_click(host, event.click, event.click.stack)
    }

    fn use_without_item(
        &self,
        host: &mut dyn ServerHost,
        event: &mut mod_api::UseWithoutItemEvent<'_>,
    ) -> Option<InteractionResult> {
        machine_click(host, event.click, None)
    }
}

#[mod_api::horizon_part]
impl BlockEntityPart for CrusherPart {
    fn block_entity(
        &self,
        _level: LevelSide,
        _event: &mut BlockEntityEvent<'_>,
    ) -> Option<Compound> {
        Some(Compound::new())
    }

    fn block_entity_ticks(&self, _host: &dyn Host, event: &mut BlockEntityTicksEvent<'_>) {
        event.ticks = true;
    }

    /// One server tick: the recipe, the FE, the progress and the outputs.
    fn block_entity_tick(&self, host: &mut dyn ServerHost, event: &mut BlockEntityTickEvent<'_>) {
        let level = in_place_level(host);
        if event.entity.items.len() != CRUSHER_SLOTS {
            event.entity.items.resize(CRUSHER_SLOTS, None);
        }
        let mut saved = Tag::Compound(std::mem::take(&mut event.entity.nbt));
        let items = &mut event.entity.items;
        let changed = tick_crusher(host, level, &mut saved, items);
        if let Tag::Compound(nbt) = saved {
            event.entity.nbt = nbt;
        }
        if !changed {
            *event.reply = BlockEntityTickReply::Unchanged;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn compound() -> Tag {
        Tag::Compound(Compound::new())
    }

    #[test]
    fn the_generator_has_one_insert_only_fuel_slot() {
        let container = generator_container();
        assert_eq!(container.slots, GENERATOR_SLOTS, "one fuel slot");
        assert_eq!(container.inputs, vec![INPUT_SLOT], "fuel may be inserted");
        assert_eq!(
            container.outputs,
            Vec::<usize>::new(),
            "automation takes nothing back out"
        );
        assert_eq!(
            container.faces,
            std::array::from_fn(|_| vec![INPUT_SLOT]),
            "automation reaches the slot from every face: there is no side configuration"
        );
        assert_eq!(container.menu, None, "no GUI in this slice");
    }

    #[test]
    fn the_crusher_has_an_input_and_two_outputs_on_every_face() {
        let container = crusher_container();
        assert_eq!(container.slots, CRUSHER_SLOTS);
        assert_eq!(container.inputs, vec![INPUT_SLOT]);
        assert_eq!(container.outputs, vec![OUTPUT_ONE, OUTPUT_TWO]);
        assert_eq!(
            container.faces,
            std::array::from_fn(|_| vec![0, 1, 2]),
            "a hopper reaches the input and both outputs from any side"
        );
        assert_eq!(container.menu, None);
    }

    #[test]
    fn the_two_buffers_are_upstreams_storage() {
        let generator = generator_battery();
        assert_eq!(generator.capacity, GENERATOR_CAPACITY);
        assert_eq!(generator.max_insert, 0, "the generator takes no FE in");
        assert_eq!(generator.max_extract, GENERATOR_MAX_EXTRACT);
        assert_eq!(generator.insert_faces, [false; 6]);
        assert_eq!(generator.extract_faces, [true; 6]);

        let crusher = crusher_battery();
        assert_eq!(crusher.capacity, CRUSHER_CAPACITY);
        assert_eq!(crusher.max_insert, CRUSHER_MAX_INSERT);
        assert_eq!(crusher.max_extract, 0, "the crusher gives no FE out");
        assert_eq!(crusher.insert_faces, [true; 6]);
        assert_eq!(crusher.extract_faces, [false; 6]);
    }

    #[test]
    fn a_fresh_compound_is_an_empty_generator_and_crusher() {
        let empty = compound();
        assert_eq!(read_generator(&empty), Generator::new());
        assert_eq!(read_crusher(&empty), Crusher::new());
    }

    #[test]
    fn the_tick_state_reads_back_from_the_compound_it_wrote() {
        let mut saved = compound();
        let generator = Generator {
            energy: 1_940,
            burn: 1_503,
            burn_max: 1_600,
        };
        write_generator(&mut saved, &generator);
        assert_eq!(read_generator(&saved), generator);
        assert_eq!(
            saved.get("energy"),
            Some(&Tag::Int(1_940)),
            "the buffer is the int `energy` the energy capability reads"
        );

        let crusher = Crusher {
            energy: 3_600,
            progress: 9,
        };
        write_crusher(&mut saved, &crusher);
        assert_eq!(read_crusher(&saved), crusher);
        assert_eq!(saved.get("progress"), Some(&Tag::Int(9)));
    }

    #[test]
    fn a_stale_over_capacity_buffer_reads_clamped() {
        let mut saved = compound();
        set_int(&mut saved, "energy", GENERATOR_CAPACITY + 20_000);
        assert_eq!(read_generator(&saved).energy, GENERATOR_CAPACITY);
        set_int(&mut saved, "energy", -5);
        assert_eq!(read_generator(&saved).energy, 0);
        set_int(&mut saved, "burn", -3);
        assert_eq!(
            read_generator(&saved).burn,
            0,
            "a negative burn is empty, not huge"
        );
    }

    #[test]
    fn the_generator_line_is_the_one_the_e2e_asserts() {
        let state = Generator {
            energy: 1_940,
            burn: 1_503,
            burn_max: 1_600,
        };
        assert_eq!(
            generator_line([0, 100, 0], &state, 324),
            "Coal Generator at 0,100,0: 1940/60000 FE (comparator 0, burning 1503/1600 ticks, t=324)"
        );
    }

    #[test]
    fn the_crusher_line_is_the_one_the_e2e_asserts() {
        let state = Crusher {
            energy: 3_600,
            progress: 0,
        };
        let recipe = CrushingRecipe::parse(
            "actuallyadditions:crushing/coal_ore",
            r#"{"ingredient": {"item": "minecraft:coal_ore"},
                "result": [{"result": {"id": "minecraft:coal", "count": 3}}]}"#,
        )
        .expect("the coal-ore recipe parses");
        assert_eq!(
            crusher_line(
                [1, 100, 0],
                &state,
                Some(("minecraft:coal_ore", 1)),
                Some(&recipe),
                488
            ),
            "Crusher at 1,100,0: 3600/60000 FE (comparator 0, progress 0/100, input \
             minecraft:coal_ore x1, crushing into minecraft:coal x3, bonus none, t=488)"
        );
        assert_eq!(
            crusher_line([4, 100, 0], &Crusher::new(), None, None, 607),
            "Crusher at 4,100,0: 0/60000 FE (comparator 0, progress 0/100, input empty, \
             crushing into nothing, bonus none, t=607)"
        );
    }

    #[test]
    fn the_crusher_line_names_the_chance_result() {
        let recipe = CrushingRecipe::parse(
            "actuallyadditions:crushing/gravel",
            r#"{"ingredient": {"item": "minecraft:gravel"},
                "result": [{"result": {"id": "minecraft:flint", "count": 1}},
                           {"chance": 0.5, "result": {"id": "minecraft:flint", "count": 1}}]}"#,
        )
        .expect("the gravel recipe parses");
        let line = crusher_line([1, 100, 0], &Crusher::new(), None, Some(&recipe), 7);
        assert!(
            line.contains("crushing into minecraft:flint x1, bonus minecraft:flint x1 @ 50%"),
            "{line}"
        );
    }

    #[test]
    fn the_command_is_the_readout_it_was_at_0_1_0() {
        let mut commands = Vec::new();
        declare_commands(&mut commands);
        assert_eq!(commands.len(), 1);
        assert_eq!(
            commands[0].usage, "actuallyadditions info <pos:block_pos>",
            "the 0.1.0 spelling, with the three words parsed as one block position"
        );
        assert_eq!(commands[0].level, 0, "no permission level, as at 0.1.0");
    }

    #[test]
    fn a_machine_line_and_a_status_read_name_the_same_two_blocks() {
        assert_ne!(GENERATOR, CRUSHER);
        assert!(
            generator_line([0, 100, 0], &Generator::new(), 0).starts_with("Coal Generator at "),
            "the generator's line names the block the jar calls coal_generator"
        );
        assert!(
            crusher_line([0, 100, 0], &Crusher::new(), None, None, 0).starts_with("Crusher at "),
            "the crusher's line names the block the jar calls crusher"
        );
        assert_eq!(
            NO_MACHINE, "No Actually Additions machine there.",
            "the reply a status read gives on anything else"
        );
    }
}
