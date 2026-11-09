// Game-side glue for Actually Additions slice 1 (Coal Generator, Crusher).
//
// Injected into `crate::game` as `actuallyadditions_state`; it needs the game,
// so it is not part of the standalone library (only `runtime.rs` is).
//
// Energy: both blocks declare a `Capabilities.Energy.BLOCK` buffer (API 142)
// whose amount is the int `energy` in the block entity's saved compound. The
// generator's own tick adds 20 FE/t while it burns; the crusher's own tick
// spends 40 FE/t while it works. A block entity is out of the world during its
// own tick, so the generator queues an adjacent-crusher transfer and the engine
// helper (`native_move_energy`, the `EnergyHandlerUtil.move` counterpart) runs
// it at `level_tick_post`, where both blocks are in the world.
//
// Fuel: the burn time is the engine's `minecraft:cooking_fuel` value
// (`Providers::burn_time`, the counterpart of upstream's
// `stack.getBurnTime(RecipeType.SMELTING)`), so no fuel table is invented.
//
// Recipes: `actuallyadditions:crushing` is a type outside `minecraft:`, which
// the pin keeps in its custom-recipe table as the file's JSON
// (`native_recipes_of_type`). The pure parser lives in `runtime.rs`; the
// ingredients are resolved by the engine's `native_recipe_ingredient` so tags
// match as vanilla matches them.

use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use horizon_client::containers::{BlockEntity, ModBlockEntity, ModContainer, ModEnergyBuffer};
use horizon_client::crafting::Ingredient;
use horizon_client::items::ItemStack;
use horizon_client::text::Text;
use horizon_core::geometry::Direction;
use horizon_core::random::RandomSource;
use horizon_world::nbt::{Compound, JavaString, Tag};

use crate::game::actuallyadditions::{
    CRUSHER_CAPACITY, CRUSHER_MAX_INSERT, Crusher, CrushingRecipe, GENERATOR_CAPACITY,
    GENERATOR_MAX_EXTRACT, Generator, Step, bonus_for, can_crush, clamp_energy,
    comparator_strength, is_fuel,
};
use crate::game::native_server::{NativeCommand, NativeServerPlayer};

const GENERATOR: &str = "actuallyadditions:coal_generator";
const CRUSHER: &str = "actuallyadditions:crusher";
const CRUSHING: &str = "actuallyadditions:crushing";
/// Rebuild the parsed recipe cache this often (ticks); a `/reload` lands
/// within two seconds, and the pure parser cost is paid once.
const RECIPE_CACHE_TICKS: u64 = 40;

fn nbt_key(name: &str) -> JavaString {
    JavaString::from(name)
}

fn read_int(nbt: &Compound, key: &str) -> i32 {
    match nbt.get(&nbt_key(key)) {
        Some(Tag::Int(value)) => *value,
        _ => 0,
    }
}

fn write_int(nbt: &mut Compound, key: &str, value: i32) {
    nbt.insert(nbt_key(key), Tag::Int(value));
}

fn state_name(
    game: &crate::game::Game<'_>,
    state: horizon_world::registry::BlockStateId,
) -> String {
    game.res.facts().get(state).name.to_string()
}

fn block_at(game: &crate::game::Game<'_>, pos: [i32; 3]) -> String {
    state_name(game, game.world.block(pos[0], pos[1], pos[2]))
}

/// `BlockEntity.setChanged`: the chunk is written at the next save.
fn mark_modified(game: &mut crate::game::Game<'_>, pos: [i32; 3]) {
    game.world.modified.insert((pos[0] >> 4, pos[2] >> 4));
}

fn generator_state(entity: &ModBlockEntity) -> Generator {
    Generator {
        energy: clamp_energy(read_int(&entity.nbt, "energy"), GENERATOR_CAPACITY),
        burn: read_int(&entity.nbt, "burn").max(0) as u32,
        burn_max: read_int(&entity.nbt, "burn_max").max(0) as u32,
    }
}

fn store_generator(entity: &mut ModBlockEntity, state: &Generator) {
    write_int(&mut entity.nbt, "energy", state.energy);
    write_int(&mut entity.nbt, "burn", state.burn as i32);
    write_int(&mut entity.nbt, "burn_max", state.burn_max as i32);
}

fn crusher_state(entity: &ModBlockEntity) -> Crusher {
    Crusher {
        energy: clamp_energy(read_int(&entity.nbt, "energy"), CRUSHER_CAPACITY),
        progress: read_int(&entity.nbt, "progress").max(0) as u32,
    }
}

fn store_crusher(entity: &mut ModBlockEntity, state: &Crusher) {
    write_int(&mut entity.nbt, "energy", state.energy);
    write_int(&mut entity.nbt, "progress", state.progress as i32);
}

/// The engine's fuel value (`minecraft:cooking_fuel.burn_time`), 0 if none.
fn fuel_burn_time(game: &crate::game::Game<'_>, stack: &ItemStack) -> u32 {
    let providers = game.res.providers();
    let items = game.res.items();
    providers.burn_time(items, stack, false).max(0) as u32
}

/// `ItemInfo::max_stack`, 64 when unknown (vanilla's default).
fn max_stack(game: &crate::game::Game<'_>, item: &str) -> i32 {
    game.res
        .items()
        .get(item)
        .map_or(64, |info| info.max_stack as i32)
}

/// The same limit as the stack count type.
fn max_count(game: &crate::game::Game<'_>, item: &str) -> u32 {
    max_stack(game, item).max(0) as u32
}

/// The configured energy buffer of either machine (`native_block_entity_energy`,
/// API 142): upstream's `CustomEnergyStorage(60000, 0, 80)` for the generator
/// and `CustomEnergyStorage(60000, 100, 0)` for the crusher.
#[allow(private_interfaces)]
pub fn on_block_entity_energy(block: &str, energy: &mut Option<ModEnergyBuffer>) {
    let (max_insert, max_extract) = match block {
        GENERATOR => (0, GENERATOR_MAX_EXTRACT),
        CRUSHER => (CRUSHER_MAX_INSERT, 0),
        _ => return,
    };
    let capacity = match block {
        GENERATOR => GENERATOR_CAPACITY,
        _ => CRUSHER_CAPACITY,
    };
    *energy = Some(ModEnergyBuffer {
        capacity,
        max_insert,
        max_extract,
        insert_faces: [max_insert > 0; 6],
        extract_faces: [max_extract > 0; 6],
    });
}

/// Both machines have a block entity (`native_block_entity`, API 15).
#[allow(private_interfaces)]
pub fn on_block_entity(block: &str, entity: &mut Option<(String, Compound)>) {
    if block == GENERATOR || block == CRUSHER {
        *entity = Some((block.to_owned(), Compound::new()));
    }
}

/// ... and tick (`native_block_entity_ticks`, API 15).
#[allow(private_interfaces)]
pub fn on_block_entity_ticks(block: &str, ticks: &mut bool) {
    if block == GENERATOR || block == CRUSHER {
        *ticks = true;
    }
}

/// The generator has its fuel slot; the crusher its input and two outputs
/// (`native_block_entity_container`, API 16). Automation may fill the input and
/// take the outputs; the generator's fuel slot is insert-only for automation.
#[allow(private_interfaces)]
pub fn on_block_entity_container(block: &str, container: &mut Option<ModContainer>) {
    let (slots, inputs, outputs) = match block {
        GENERATOR => (1, vec![0], vec![]),
        CRUSHER => (3, vec![0], vec![1, 2]),
        _ => return,
    };
    let all: Vec<usize> = (0..slots).collect();
    *container = Some(ModContainer {
        slots,
        faces: [
            all.clone(),
            all.clone(),
            all.clone(),
            all.clone(),
            all.clone(),
            all,
        ],
        inputs,
        outputs,
        menu: None,
    });
}

/// One server tick of either machine (`native_block_entity_tick`, API 17).
#[allow(private_interfaces)]
pub fn on_block_entity_tick(
    game: &mut crate::game::Game<'_>,
    pos: [i32; 3],
    entity: &mut ModBlockEntity,
) {
    if entity.id == GENERATOR {
        tick_generator(game, pos, entity);
    } else if entity.id == CRUSHER {
        tick_crusher(game, pos, entity);
    }
}

/// The generator: load fuel when upstream would, burn one tick and make 20 FE,
/// then queue the adjacent-crusher transfer.
fn tick_generator(game: &mut crate::game::Game<'_>, pos: [i32; 3], entity: &mut ModBlockEntity) {
    let dimension = game.native_dimension().to_owned();
    let powered = game.native_neighbor_signal(&dimension, pos) > 0;
    let mut state = generator_state(entity);
    if state.wants_fuel(powered) {
        if let Some(stack) = entity.items.first().and_then(Option::clone) {
            let burn = fuel_burn_time(game, &stack);
            if state.load_fuel(burn) {
                consume_fuel(game, entity, &stack);
            }
        }
    }
    if state.tick() > 0 {
        mark_modified(game, pos);
    }
    store_generator(entity, &state);
    if state.energy > 0 {
        let mut queue = push_queue()
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if !queue
            .iter()
            .any(|(dim, at)| dim == &dimension && *at == pos)
        {
            queue.push((dimension, pos));
        }
    }
}

/// `StackUtil.shrinkForContainer`: one item is consumed and a container item
/// (a lava bucket's bucket) takes its place when the stack runs out.
fn consume_fuel(game: &crate::game::Game<'_>, entity: &mut ModBlockEntity, stack: &ItemStack) {
    let remainder = game
        .res
        .items()
        .get(&stack.item)
        .and_then(|info| info.remainder.clone());
    let left = stack.count - 1;
    entity.items[0] = if left > 0 {
        let mut kept = stack.clone();
        kept.count = left;
        Some(kept)
    } else {
        remainder.map(|item| ItemStack::new(item.as_str(), 1))
    };
}

/// The crusher: find the first matching recipe, check the output room, and let
/// the pure state machine spend FE and advance. A finished operation applies
/// the guaranteed output, then the bonus roll (`level.random.nextFloat()`).
fn tick_crusher(game: &mut crate::game::Game<'_>, pos: [i32; 3], entity: &mut ModBlockEntity) {
    let input = entity.items.first().and_then(Option::clone);
    let recipe = input.as_ref().and_then(|stack| find_recipe(game, stack));
    let has_work = recipe.as_ref().is_some_and(|recipe| {
        let output_one = entity
            .items
            .get(1)
            .and_then(Option::as_ref)
            .map(|stack| (&*stack.item, stack.count as i32));
        let output_two = entity
            .items
            .get(2)
            .and_then(Option::as_ref)
            .map(|stack| (&*stack.item, stack.count as i32));
        can_crush(recipe, output_one, output_two, |item| max_stack(game, item))
    });
    let mut state = crusher_state(entity);
    let step = state.tick(has_work);
    if step == Step::Finished
        && let Some(recipe) = recipe.as_ref()
    {
        finish_operation(game, entity, recipe);
        mark_modified(game, pos);
    }
    if step != Step::Idle {
        mark_modified(game, pos);
    }
    store_crusher(entity, &state);
}

fn finish_operation(
    game: &mut crate::game::Game<'_>,
    entity: &mut ModBlockEntity,
    recipe: &CrushingRecipe,
) {
    grow_output(game, entity, 1, recipe.guaranteed());
    let roll = game.world.random.next_float();
    if let Some(bonus) = bonus_for(recipe, roll) {
        grow_output(game, entity, 2, bonus);
    }
    let Some(mut input) = entity.items.first_mut().and_then(Option::take) else {
        return;
    };
    input.count -= 1;
    if input.count > 0 {
        entity.items[0] = Some(input);
    }
}

fn grow_output(
    game: &crate::game::Game<'_>,
    entity: &mut ModBlockEntity,
    slot: usize,
    result: &crate::game::actuallyadditions::CrushResult,
) {
    let limit = max_count(game, &result.item);
    let count = result.count.max(0) as u32;
    let merged = match entity.items.get(slot).and_then(Option::as_ref) {
        Some(stack) if &*stack.item == result.item => {
            let mut stack = stack.clone();
            stack.count = stack.count.saturating_add(count).min(limit);
            stack
        }
        Some(_) => return,
        None => ItemStack::new(result.item.as_str(), count.min(limit)),
    };
    entity.items[slot] = Some(merged);
}

/// The parsed custom recipes with their engine-resolved ingredients.
struct Resolved {
    ingredient: Ingredient,
    recipe: CrushingRecipe,
}

static RECIPES: Mutex<Option<Vec<Resolved>>> = Mutex::new(None);
static RECIPE_TICKS: AtomicU64 = AtomicU64::new(0);

fn find_recipe(game: &crate::game::Game<'_>, input: &ItemStack) -> Option<CrushingRecipe> {
    let due = RECIPE_TICKS
        .fetch_add(1, Ordering::Relaxed)
        .is_multiple_of(RECIPE_CACHE_TICKS);
    let mut cache = RECIPES.lock().unwrap_or_else(|poison| poison.into_inner());
    if cache.is_none() || due {
        let mut resolved = Vec::new();
        let mut refused = 0;
        for recipe in game.native_recipes_of_type(CRUSHING) {
            let Ok(parsed) = CrushingRecipe::parse(&recipe.id, &recipe.json.to_string()) else {
                refused += 1;
                continue;
            };
            let ingredient = recipe
                .json
                .get("ingredient")
                .map(crate::game::actuallyadditions::ingredient_json)
                .and_then(|ingredient| game.native_recipe_ingredient(&ingredient));
            match ingredient {
                Some(ingredient) => resolved.push(Resolved {
                    ingredient,
                    recipe: parsed,
                }),
                None => refused += 1,
            }
        }
        if refused > 0 {
            log::debug!(
                "[actuallyadditions] {refused} crushing recipe(s) of {} were unreadable",
                game.native_recipes_of_type(CRUSHING).len()
            );
        }
        *cache = Some(resolved);
    }
    let recipes = cache.as_ref()?;
    recipes
        .iter()
        .find(|resolved| resolved.ingredient.test(input))
        .map(|resolved| resolved.recipe.clone())
}

fn reset_recipes() {
    *RECIPES.lock().unwrap_or_else(|poison| poison.into_inner()) = None;
    RECIPE_TICKS.store(0, Ordering::Relaxed);
}

/// Generator positions queued for an energy push, by dimension.
static PUSH: Mutex<Vec<(String, [i32; 3])>> = Mutex::new(Vec::new());

fn push_queue() -> &'static Mutex<Vec<(String, [i32; 3])>> {
    &PUSH
}

/// The six neighbours, their direction from the generator, and the opposite
/// direction as the crusher sees it.
const NEIGHBOURS: [([i32; 3], Direction, Direction); 6] = [
    ([0, -1, 0], Direction::Down, Direction::Up),
    ([0, 1, 0], Direction::Up, Direction::Down),
    ([0, 0, -1], Direction::North, Direction::South),
    ([0, 0, 1], Direction::South, Direction::North),
    ([-1, 0, 0], Direction::West, Direction::East),
    ([1, 0, 0], Direction::East, Direction::West),
];

/// After a level's tick: move the queued generator energy into adjacent
/// crushers through the engine's energy handlers (`native_move_energy`, API
/// 142). Both block entities are in the world here, unlike inside their own
/// ticks. The generator gives at most 80 FE a call and the crusher takes at
/// most 100, as upstream's buffers do.
#[allow(private_interfaces)]
pub fn on_level_tick_post(game: &mut crate::game::Game<'_>, dimension: &str) {
    let queued = {
        let mut queue = push_queue()
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        std::mem::take(&mut *queue)
    };
    if queued.is_empty() {
        return;
    }
    let mut later = Vec::new();
    for (dim, generator) in queued {
        if dim != dimension {
            later.push((dim, generator));
            continue;
        }
        if block_at(game, generator) != GENERATOR {
            continue;
        }
        for (offset, from_face, to_face) in NEIGHBOURS {
            let crusher = [
                generator[0] + offset[0],
                generator[1] + offset[1],
                generator[2] + offset[2],
            ];
            if block_at(game, crusher) == CRUSHER {
                game.native_move_energy(
                    dimension,
                    generator,
                    from_face,
                    crusher,
                    to_face,
                    GENERATOR_MAX_EXTRACT,
                );
            }
        }
    }
    if !later.is_empty() {
        push_queue()
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .extend(later);
    }
}

/// The player a player hook acts for: the guest swapped in, or, in single
/// player, the owner (`native_acting_player` is none there).
fn acting_uuid(game: &crate::game::Game<'_>) -> Option<u128> {
    game.native_acting_player()
        .map(|player| player.uuid)
        .or_else(|| {
            game.native_server_players()
                .first()
                .map(|player| player.uuid)
        })
}

/// A right click on a machine: there is no GUI in slice 1, so the click inserts
/// a matching item (fuel / recipe input) and an empty hand reads the status.
/// The click is always claimed, so the furnace template never opens its own
/// menu.
#[allow(private_interfaces)]
pub fn on_right_click_block(
    game: &mut crate::game::Game<'_>,
    pos: [i32; 3],
    _face: [i32; 3],
    canceled: &mut bool,
) {
    if *canceled {
        return;
    }
    let name = block_at(game, pos);
    if name != GENERATOR && name != CRUSHER {
        return;
    }
    *canceled = true;
    let held = game.held().cloned();
    let Some(held) = held else {
        if let Some(uuid) = acting_uuid(game) {
            game.native_action_bar(uuid, Text::literal(status_text(game, pos)));
        }
        return;
    };
    if name == GENERATOR {
        if !is_fuel(fuel_burn_time(game, &held)) {
            if let Some(uuid) = acting_uuid(game) {
                game.native_action_bar(uuid, Text::literal(format!("{} is not a fuel", held.item)));
            }
            return;
        }
    } else if find_recipe(game, &held).is_none() {
        if let Some(uuid) = acting_uuid(game) {
            game.native_action_bar(
                uuid,
                Text::literal(format!("{} has no crushing recipe", held.item)),
            );
        }
        return;
    }
    const INPUT_SLOT: usize = 0;
    let slot = INPUT_SLOT;
    let limit = max_count(game, &held.item);
    let key = (pos[0], pos[1], pos[2]);
    let Some(BlockEntity::Mod(entity)) = game.world.block_entities.get_mut(&key) else {
        return;
    };
    if entity.items.get(slot).is_none() {
        entity.items.resize(slot + 1, None);
    }
    let inserted = match entity.items[slot].take() {
        None => {
            let inserted = held.count.min(limit);
            let mut stack = held.clone();
            stack.count = inserted;
            entity.items[slot] = Some(stack);
            inserted
        }
        Some(mut stack) if stack.item == held.item => {
            let room = (limit - stack.count).max(0);
            let inserted = held.count.min(room);
            stack.count += inserted;
            entity.items[slot] = Some(stack);
            inserted
        }
        Some(stack) => {
            entity.items[slot] = Some(stack);
            0
        }
    };
    if inserted > 0 {
        if !game.creative {
            let _ = game.native_take_items(&*held.item, inserted);
        }
        mark_modified(game, pos);
    }
}

/// `/actuallyadditions info <x> <y> <z>` (`register_commands`, API 8).
#[allow(private_interfaces)]
pub fn on_register_commands(commands: &mut Vec<NativeCommand>) {
    commands.push(NativeCommand::new("actuallyadditions info <pos:block_pos>"));
}

fn parse_pos(words: &[&str]) -> Option<[i32; 3]> {
    Some([
        words.first()?.parse().ok()?,
        words.get(1)?.parse().ok()?,
        words.get(2)?.parse().ok()?,
    ])
}

fn status_text(game: &crate::game::Game<'_>, pos: [i32; 3]) -> String {
    let key = (pos[0], pos[1], pos[2]);
    let Some(BlockEntity::Mod(entity)) = game.world.block_entities.get(&key) else {
        return "No Actually Additions machine there.".to_owned();
    };
    match entity.id.as_str() {
        GENERATOR => {
            let state = generator_state(entity);
            format!(
                "Coal Generator at {},{},{}: {}/{} FE (comparator {}, burning {}/{} ticks, t={})",
                pos[0],
                pos[1],
                pos[2],
                state.energy,
                GENERATOR_CAPACITY,
                comparator_strength(state.energy, GENERATOR_CAPACITY),
                state.burn,
                state.burn_max,
                game.world.game_time
            )
        }
        CRUSHER => {
            let state = crusher_state(entity);
            let recipe = entity
                .items
                .first()
                .and_then(Option::as_ref)
                .and_then(|stack| find_recipe(game, stack));
            let input = entity
                .items
                .first()
                .and_then(Option::as_ref)
                .map_or("empty".to_owned(), |stack| {
                    format!("{} x{}", stack.item, stack.count)
                });
            let crushing = recipe.as_ref().map_or("nothing".to_owned(), |recipe| {
                format!(
                    "{} x{}",
                    recipe.guaranteed().item,
                    recipe.guaranteed().count
                )
            });
            let bonus = recipe.as_ref().and_then(|recipe| recipe.bonus()).map_or(
                "none".to_owned(),
                |bonus| {
                    format!(
                        "{} x{} @ {:.0}%",
                        bonus.item,
                        bonus.count,
                        bonus.chance * 100.0
                    )
                },
            );
            format!(
                "Crusher at {},{},{}: {}/{} FE (comparator {}, progress {}/{}, input {}, crushing into {}, bonus {}, t={})",
                pos[0],
                pos[1],
                pos[2],
                state.energy,
                CRUSHER_CAPACITY,
                comparator_strength(state.energy, CRUSHER_CAPACITY),
                state.progress,
                crate::game::actuallyadditions::CRUSHER_TICKS,
                input,
                crushing,
                bonus,
                game.world.game_time
            )
        }
        _ => "No Actually Additions machine there.".to_owned(),
    }
}

/// The `/actuallyadditions` command body (`perform_command`, API 8).
#[allow(private_interfaces)]
pub fn on_perform_command(
    game: &mut crate::game::Game<'_>,
    _player: &NativeServerPlayer,
    command: &str,
    ran: &mut bool,
) {
    let words: Vec<&str> = command.split_whitespace().collect();
    match words.as_slice() {
        ["actuallyadditions", "info", x, y, z] => {
            *ran = true;
            let Some(pos) = parse_pos(&[*x, *y, *z]) else {
                game.native_feedback(Text::literal("Usage: /actuallyadditions info <x> <y> <z>"));
                return;
            };
            game.native_feedback(Text::literal(status_text(game, pos)));
        }
        // The world opened: the recipe table is new.
        _ => {}
    }
}

/// Reset per-world caches when a world opens or closes.
#[allow(private_interfaces)]
pub fn on_world_lifecycle(
    _game: &mut crate::game::Game<'_>,
    _phase: crate::game::native_lifecycle::WorldPhase,
) {
    reset_recipes();
    push_queue()
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .clear();
}
