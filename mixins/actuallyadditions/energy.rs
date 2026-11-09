// The FE buffer both machines declare (API 142).
fn observe_block_entity_energy(
    block: &str,
    energy: &mut Option<horizon_client::containers::ModEnergyBuffer>,
) {
    crate::game::actuallyadditions_state::on_block_entity_energy(block, energy);
}
