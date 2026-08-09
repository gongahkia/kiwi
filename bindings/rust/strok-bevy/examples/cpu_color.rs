use bevy_app::App;
use strok_bevy::{
    CellGrid, CpuColorFrame, CpuDepthFrame, CpuNormalFrame, Grid, RendererConfig, StrokRenderer,
    StrokRendererPlugin,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut app = App::new();
    app.add_plugins(StrokRendererPlugin)
        .insert_non_send(StrokRenderer::new(
            RendererConfig::default().cell_aspect(1.0),
            Grid::new(2, 2)?,
        )?)
        .insert_resource(
            CpuColorFrame::rgb24(
                vec![0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64],
                2,
                2,
            )
            .with_depth(CpuDepthFrame::tightly_packed(vec![1.0; 4], 2, 2))
            .with_normals(CpuNormalFrame::tightly_packed(
                vec![[0.0, 0.0, 1.0]; 4],
                2,
                2,
            )),
        );
    app.update();

    let cells = app.world().resource::<CellGrid>();
    println!("rendered {}x{} strok cells", cells.columns, cells.rows);
    for row in 0..cells.rows {
        let glyphs: String = (0..cells.columns)
            .filter_map(|column| cells.get(column, row).map(|cell| cell.glyph))
            .collect();
        println!("{glyphs}");
    }
    Ok(())
}
