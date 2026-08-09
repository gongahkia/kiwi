use bevy_app::App;
use strok_bevy::{
    CellGrid, CpuColorFrame, Grid, RendererConfig, StrokRenderer, StrokRendererPlugin,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut app = App::new();
    app.add_plugins(StrokRendererPlugin)
        .insert_non_send(StrokRenderer::new(
            RendererConfig::default().cell_aspect(1.0),
            Grid::new(2, 2)?,
        )?)
        .insert_resource(CpuColorFrame::rgb24(
            vec![0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64],
            2,
            2,
        ));
    app.update();

    let cells = app.world().resource::<CellGrid>();
    println!("rendered {}x{} strok cells", cells.columns, cells.rows);
    Ok(())
}
