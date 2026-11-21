//! Actually Additions for Horizon — slice 1, the Coal Generator and the Crusher.
//!
//! One flat SDK package (mod API 0.2): the carried blocks, items, models, textures, lang, loot
//! tables, the two machine recipes, the 49 `actuallyadditions:crushing` recipes and the two
//! advancements are this package's `assets/` and `data/`, and the behaviour is the one
//! `impl mod_api::Hooks` below plus the two block-entity Parts in [`support`]. The rules
//! themselves live in [`runtime`], byte-identical to the retired `.hnmod` bundle's `runtime.rs`.
//!
//! # Where the retired container's hooks went
//!
//! The 2026-11-17 mod-API merge (#16941, launcher ≥ 0.2.70) retired `.hnmod`: the plan, the
//! injection points and the per-hook helper files are gone. A hook is a typed method here, a
//! moment that belongs to one block or block entity is a **Part** attached to it, and what
//! upstream registers as a capability is a `Registrar` declaration.
//!
//! | `.hnmod` injection (API) | here |
//! |---|---|
//! | `embedded-content` (`content_root` HEAD) | gone: one flat `.hmod` carries `assets/` and `data/` itself |
//! | `block-entity` (15) | the two block entity **types** declared in [`Mod::register`] |
//! | `block-entity-ticks` (15) | `BlockEntityPart::block_entity_ticks` on both Parts |
//! | `block-entity-container` (16) | `Registrar::block_container` (1 fuel slot / 3 crusher slots) |
//! | `block-entity-energy` (142) | `Registrar::block_energy` (upstream's two `CustomEnergyStorage`s) |
//! | `block-entity-tick` (17) | `BlockEntityPart::block_entity_tick` on both Parts |
//! | `level-tick-post` (23) | [`Mod::level_tick_post`] → the queued generator→crusher push |
//! | `right-click-block` (21) | `BlockPart::use_item_on` + `use_without_item` on both Parts |
//! | `register-commands` (8) | [`Mod::register_commands`] |
//! | `perform-command` (8) | [`Mod::run_mod_command`] (typed `CommandInvocation`) |
//! | `world-lifecycle` (v1) | [`Mod::world_lifecycle`] (drop the recipe cache and the push queue) |
use mod_api::{
    self, BlockDropsEvent, Flow, Hooks, HostSide, LevelHost, LevelTickPostEvent,
    RegisterCommandsEvent, Registrar, RegistrationContext, RunModCommandEvent, ServerHost,
    WorldLifecycleEvent,
};

pub mod runtime;
pub mod support;

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Declare both machines: a block entity type each with its Part, the container and the energy
    /// buffer. Keyed by the block, so another mod's machine is another key.
    fn register(&self, registrar: &mut dyn Registrar, context: &RegistrationContext) {
        support::declare(registrar, context);
    }

    /// `/actuallyadditions info <pos>`: the harness readout (there is no GUI in this slice).
    fn register_commands(&self, _host: &mut dyn ServerHost, event: &mut RegisterCommandsEvent<'_>) {
        support::declare_commands(event.commands);
    }

    /// The command body: the parsed position, then one line about the machine there.
    fn run_mod_command(
        &self,
        host: &mut dyn ServerHost,
        event: &mut RunModCommandEvent<'_>,
    ) -> Flow {
        support::run_command(host, event)
    }

    /// After a level's tick: the generators queued by their own tick push FE into the crushers
    /// beside them. A block entity is out of the world during its own tick.
    fn level_tick_post(&self, host: HostSide<'_>, event: &mut LevelTickPostEvent) {
        let HostSide::Server(host) = host else {
            return;
        };
        support::on_level_tick_post(host, event.level);
    }

    /// A world opened or closed: the recipe table and the push queue belong to that world.
    fn world_lifecycle(&self, _host: &mut dyn ServerHost, _event: &mut WorldLifecycleEvent<'_>) {
        support::reset_recipes();
        support::clear_push_queue();
    }

    /// A block broke: a machine's item keeps its saved state (FE, burn, progress), which vanilla
    /// applies when the item is placed again (upstream's `actuallyadditions:energy` component).
    fn block_drops(&self, level: &dyn LevelHost, event: &mut BlockDropsEvent<'_>) -> Flow {
        support::on_block_drops(level, event)
    }
}
