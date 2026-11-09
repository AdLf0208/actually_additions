// A world opened or closed: drop the parsed recipe cache and the push queue.
fn observe_world_lifecycle(game: &mut crate::game::Game<'_>, phase: WorldPhase) {
    crate::game::actuallyadditions_state::on_world_lifecycle(game, phase);
}
