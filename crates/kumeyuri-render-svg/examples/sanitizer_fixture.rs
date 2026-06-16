use std::time::Duration;

use kumeyuri_core::{
    animator::{KeyFrame, Timeline},
    frame::Frame,
};
use kumeyuri_render_svg::{SvgAnimationMode, SvgRenderConfig, SvgRenderer};

fn main() {
    let timeline = timeline();
    print_fixture("smil", &SvgRenderer::default().render_timeline(&timeline));
    print_fixture(
        "css",
        &SvgRenderer::new(SvgRenderConfig {
            animation: SvgAnimationMode::CssKeyframes,
            ..SvgRenderConfig::default()
        })
        .render_timeline(&timeline),
    );
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
