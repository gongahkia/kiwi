use std::time::Duration;

use kumeyuri_core::{
    animator::{KeyFrame, Timeline},
    frame::Frame,
};
use kumeyuri_render_svg::{SvgAnimationMode, SvgRenderConfig, SvgRenderer};

fn main() {
    let timeline = timeline();
    print_fixture(
        "smil",
        &SvgRenderer::new(color_scheme_config(SvgAnimationMode::Smil)).render_timeline(&timeline),
    );
    print_fixture(
        "css",
        &SvgRenderer::new(color_scheme_config(SvgAnimationMode::CssKeyframes))
            .render_timeline(&timeline),
    );
}

fn color_scheme_config(animation: SvgAnimationMode) -> SvgRenderConfig {
    SvgRenderConfig {
        animation,
        dark_foreground: Some("#f8f8f2".to_owned()),
        dark_background: Some("#282a36".to_owned()),
        ..SvgRenderConfig::default()
    }
}

fn timeline() -> Timeline {
    let mut first = Frame::new(3, 1);
    first.write_text(0, 0, "A->", Default::default()).unwrap();
    let mut second = Frame::new(3, 1);
    second.write_text(0, 0, "->B", Default::default()).unwrap();
    Timeline::from_keyframes(vec![
        KeyFrame::new(first, Duration::from_millis(100)),
        KeyFrame::new(second, Duration::from_millis(100)),
    ])
    .with_repeat(true)
}

fn print_fixture(mode: &str, svg: &str) {
    println!("--kumeyuri-svg-mode:{mode}--");
    print!("{svg}");
}
