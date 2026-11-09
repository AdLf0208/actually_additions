// The generator's fuel slot and the crusher's input/output slots.
fn observe_block_entity_container(
    block: &str,
    container: &mut Option<horizon_client::containers::ModContainer>,
) {
    crate::game::actuallyadditions_state::on_block_entity_container(block, container);
}
