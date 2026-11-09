// After a level's tick: generator energy reaches adjacent crushers.
fn observe_level_tick_post(game: &mut crate::game::Game<'_>, dimension: &str) {
    crate::game::actuallyadditions_state::on_level_tick_post(game, dimension);
}
