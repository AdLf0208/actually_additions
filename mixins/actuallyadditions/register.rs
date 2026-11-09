// Declare the `/actuallyadditions info` readout.
fn observe_register(commands: &mut Vec<NativeCommand>) {
    crate::game::actuallyadditions_state::on_register_commands(commands);
}
