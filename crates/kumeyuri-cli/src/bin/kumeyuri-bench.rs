//! Release-only component benchmark probe consumed by the comparison harness.

use std::{fs, hint::black_box, path::PathBuf, process::ExitCode, time::Instant};

use clap::{Parser, ValueEnum};
use kumeyuri_core::{
    animator::{AnimationOptions, Animator, Timeline},
    ast::{Diagram, DiagramKind},
    cast::Kumecast,
    frame::StaticFrameRenderer,
    layout::{FlowLayoutEngine, SequenceLayoutEngine, StateLayoutEngine},
    parser::Parser as MermaidParser,
    theme::Theme,
};
use kumeyuri_render_raster::RasterRenderer;
use kumeyuri_render_svg::SvgRenderer;
use serde::Serialize;

#[derive(Debug, Parser)]
#[command(
    name = "kumeyuri-bench",
    version,
    about = "Measure isolated kumeyuri renderer phases"
)]
struct Args {
    #[arg(long, value_name = "FILE")]
    input: PathBuf,
    #[arg(long, value_enum)]
    operation: Operation,
    #[arg(long, default_value_t = 10, value_parser = parse_positive_usize)]
    iterations: usize,
    #[arg(long, default_value_t = 2, value_parser = clap::value_parser!(usize))]
    warmup: usize,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Operation {
    Parse,
    Layout,
    Frames,
    Svg,
    Kumecast,
    RasterGif,
    RasterApng,
    RasterWebp,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ProbeReport {
    schema_version: u8,
    input: PathBuf,
    operation: &'static str,
    iterations: usize,
    warmup: usize,
    samples_ns: Vec<u64>,
}

fn main() -> ExitCode {
    match run(Args::parse()) {
        Ok(report) => match serde_json::to_string(&report) {
            Ok(json) => {
                println!("{json}");
                ExitCode::SUCCESS
            }
            Err(error) => {
                eprintln!("failed to serialize benchmark report: {error}");
                ExitCode::FAILURE
            }
        },
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run(args: Args) -> Result<ProbeReport, String> {
    let source = fs::read_to_string(&args.input)
        .map_err(|error| format!("failed to read {}: {error}", args.input.display()))?;
    let samples_ns = match args.operation {
        Operation::Parse => measure(args.warmup, args.iterations, || parse(&source))?,
        Operation::Layout => {
            let diagram = parse(&source)?;
            measure(args.warmup, args.iterations, || layout(&diagram))?
        }
        Operation::Frames => {
            let diagram = parse(&source)?;
            measure(args.warmup, args.iterations, || timeline(&diagram))?
        }
        Operation::Svg => {
            let rendered = timeline(&parse(&source)?)?;
            let renderer = SvgRenderer::default();
            measure(args.warmup, args.iterations, || {
                Ok(renderer.render_timeline(&rendered))
            })?
        }
        Operation::Kumecast => {
            let diagram = parse(&source)?;
            let rendered = timeline(&diagram)?;
            measure(args.warmup, args.iterations, || {
                Kumecast::from_timeline("benchmark", &source, Theme::default_theme(), &rendered)
                    .to_json_string()
                    .map_err(|error| format!("{error:?}"))
            })?
        }
        Operation::RasterGif => {
            let rendered = timeline(&parse(&source)?)?;
            let renderer = RasterRenderer::default();
            measure(args.warmup, args.iterations, || {
                renderer
                    .render_gif(&rendered)
                    .map_err(|error| format!("{error:?}"))
            })?
        }
        Operation::RasterApng => {
            let rendered = timeline(&parse(&source)?)?;
            let renderer = RasterRenderer::default();
            measure(args.warmup, args.iterations, || {
                renderer
                    .render_apng(&rendered)
                    .map_err(|error| format!("{error:?}"))
            })?
        }
        Operation::RasterWebp => {
            let rendered = timeline(&parse(&source)?)?;
            let renderer = RasterRenderer::default();
            measure(args.warmup, args.iterations, || {
                renderer
                    .render_webp(&rendered)
                    .map_err(|error| format!("{error:?}"))
            })?
        }
    };

    Ok(ProbeReport {
        schema_version: 1,
        input: args.input,
        operation: operation_name(args.operation),
        iterations: args.iterations,
        warmup: args.warmup,
        samples_ns,
    })
}

fn measure<T>(
    warmup: usize,
    iterations: usize,
    mut operation: impl FnMut() -> Result<T, String>,
) -> Result<Vec<u64>, String> {
    for _ in 0..warmup {
        black_box(operation()?);
    }

    let mut samples = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let started = Instant::now();
        black_box(operation()?);
        samples.push(
            u64::try_from(started.elapsed().as_nanos())
                .map_err(|_| "benchmark duration exceeds u64 nanoseconds".to_owned())?,
        );
    }
    Ok(samples)
}

fn parse(source: &str) -> Result<Diagram, String> {
    MermaidParser::parse_diagram(source)
        .map_err(|error| format!("failed to parse benchmark input: {error:?}"))
}

fn layout(diagram: &Diagram) -> Result<(), String> {
    match &diagram.kind {
        DiagramKind::Flowchart(ast) => {
            black_box(FlowLayoutEngine::default().layout(ast));
        }
        DiagramKind::Sequence(ast) => {
            black_box(SequenceLayoutEngine::default().layout(ast));
        }
        DiagramKind::State(ast) => {
            black_box(StateLayoutEngine::default().layout(ast));
        }
        _ => {
            return Err(
                "the isolated layout probe supports flowchart, sequenceDiagram, and stateDiagram inputs"
                    .to_owned(),
            );
        }
    };
    Ok(())
}

fn timeline(diagram: &Diagram) -> Result<Timeline, String> {
    Animator::animate_diagram_with_options_and_renderer(
        diagram,
        AnimationOptions::default(),
        StaticFrameRenderer::default(),
    )
    .map_err(|error| format!("failed to build benchmark timeline: {error:?}"))
}

const fn operation_name(operation: Operation) -> &'static str {
    match operation {
        Operation::Parse => "parse",
        Operation::Layout => "layout",
        Operation::Frames => "frames",
        Operation::Svg => "svg",
        Operation::Kumecast => "kumecast",
        Operation::RasterGif => "raster-gif",
        Operation::RasterApng => "raster-apng",
        Operation::RasterWebp => "raster-webp",
    }
}

fn parse_positive_usize(value: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("expected a positive integer, got {value:?}"))?;
    if parsed == 0 {
        return Err("expected a positive integer, got 0".to_owned());
    }
    Ok(parsed)
}
