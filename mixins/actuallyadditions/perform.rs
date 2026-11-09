// Run the `/actuallyadditions` command a player types.
fn observe_perform(
    game: &mut crate::game::Game<'_>,
    player: &NativeServerPlayer,
    command: &str,
    ran: &mut bool,
) {
    crate::game::actuallyadditions_state::on_perform_command(game, player, command, ran);
}
