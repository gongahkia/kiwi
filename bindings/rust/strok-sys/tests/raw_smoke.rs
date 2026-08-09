use std::mem::MaybeUninit;

#[test]
fn generated_bindings_detect_the_c_abi_version() {
    let mut config = MaybeUninit::<strok_sys::StrokRendererConfig>::zeroed();
    let mut grid = MaybeUninit::<strok_sys::StrokRenderGrid>::zeroed();
    unsafe {
        strok_sys::strok_renderer_config_init(config.as_mut_ptr());
        strok_sys::strok_render_grid_init(grid.as_mut_ptr());
        assert_eq!(config.assume_init().version, strok_sys::STROK_C_ABI_VERSION);
        assert_eq!(grid.assume_init().version, strok_sys::STROK_C_ABI_VERSION);
    }
}
