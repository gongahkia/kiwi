use std::{
    fs, io,
    io::Write,
    path::{Path, PathBuf},
    process::ExitCode,
};

use clap::{Args, Parser, Subcommand, ValueEnum};
use kumeyuri_core::{
    animator::{AnimationOptions, Animator, KeyFrame, Timeline},
    ast::Diagram,
    frame::{Charset, Frame, StaticFrameRenderer},
    parser::Parser as MermaidParser,
    text::{TextOutputBackend, TextOutputConfig},
    theme::{BuiltInTheme, RgbColor, Theme},
};
use kumeyuri_render_raster::{RasterRenderConfig, RasterRenderer, RgbaColor};
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};

#[cfg(not(target_arch = "wasm32"))]
use std::time::Duration;

#[cfg(not(target_arch = "wasm32"))]
use {
    crossterm::{
        cursor::MoveTo,
        event::{self, Event as TerminalEvent, KeyCode, KeyEventKind},
        execute,
        terminal::{
            Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode,
            enable_raw_mode,
        },
    },
    kumeyuri_render_tui::{TuiRenderConfig, TuiRenderer, TuiTransitionEffect},
    notify::{
        Config as NotifyConfig, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher,
    },
    ratatui::{Terminal, backend::CrosstermBackend},
};

#[derive(Debug, Parser)]
#[command(
    name = "kumeyuri",
    version,
    about = "Render Mermaid as animated text artifacts."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Compat {
        #[arg(long, value_name = "VERSION", value_parser = parse_non_empty_string)]
        mermaid_version: Option<String>,
    },
    Render {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_enum, default_value_t = RenderFormat::Text)]
        format: RenderFormat,
        #[command(flatten)]
        options: RenderOptions,
    },
    Watch {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
    Play {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_name = "FACTOR", value_parser = parse_speed_override)]
        speed: Option<f32>,
        #[arg(long = "loop")]
        repeat: bool,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderFormat {
    Text,
    Svg,
    Gif,
    Apng,
    Webp,
    Tui,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Args)]
struct RenderOptions {
    #[arg(long, value_enum)]
    theme: Option<RenderTheme>,
    #[arg(long, value_enum)]
    dark_theme: Option<RenderTheme>,
    #[arg(long, value_enum)]
    charset: Option<RenderCharset>,
    #[arg(long, value_name = "CELLS", value_parser = parse_positive_usize)]
    width: Option<usize>,
    #[arg(long, value_name = "PX")]
    padding: Option<u32>,
    #[arg(long, value_name = "FAMILY", value_parser = parse_non_empty_string)]
    font: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderTheme {
    Default,
    Mono,
    TokyoNight,
    Github,
    Dracula,
}

impl RenderTheme {
    const fn theme(self) -> BuiltInTheme {
        match self {
            Self::Default => BuiltInTheme::Default,
            Self::Mono => BuiltInTheme::Mono,
            Self::TokyoNight => BuiltInTheme::TokyoNight,
            Self::Github => BuiltInTheme::Github,
            Self::Dracula => BuiltInTheme::Dracula,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderCharset {
    Ascii,
    Unicode,
}

impl From<RenderCharset> for Charset {
    fn from(charset: RenderCharset) -> Self {
        match charset {
            RenderCharset::Ascii => Self::Ascii,
            RenderCharset::Unicode => Self::Unicode,
        }
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let cli = Cli::parse();

    match cli.command {
        Command::Compat { mermaid_version } => print_compat_report(mermaid_version.as_deref()),
        Command::Render {
            file,
            format,
            options,
        } => render_file(&file, format, &options),
        Command::Watch { file } => watch_file(&file),
        Command::Play {
            file,
            speed,
            repeat,
        } => play_file(&file, playback_options(speed, repeat)?),
    }
}

const MERMAID_COMPAT_VERSION: &str = "11.15.0";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CompatRoot {
    label: &'static str,
    roots: &'static [&'static str],
    caveat: &'static str,
}

const ANIMATED_PARTIAL_ROOTS: &[CompatRoot] = &[
    CompatRoot {
        label: "Flowchart",
        roots: &["graph", "flowchart"],
        caveat: "trace animation; Mermaid config, styling, and exact visual parity are partial",
    },
    CompatRoot {
        label: "Sequence Diagram",
        roots: &["sequenceDiagram"],
        caveat: "playback animation; colors, actor menus, links, and rich styling are partial",
    },
    CompatRoot {
        label: "State Diagram",
        roots: &["stateDiagram", "stateDiagram-v2"],
        caveat: "transition animation; Mermaid layout/look config is rejected",
    },
    CompatRoot {
        label: "Class Diagram",
        roots: &["classDiagram"],
        caveat: "relationship trace animation; callbacks, links, and CSS styling are semantic-only",
    },
    CompatRoot {
        label: "Entity Relationship Diagram",
        roots: &["erDiagram"],
        caveat: "relationship trace animation; Mermaid styling/config is not interpreted",
    },
    CompatRoot {
        label: "Gantt",
        roots: &["gantt"],
        caveat: "timeline trace animation; date handling is day-level",
    },
    CompatRoot {
        label: "Pie Chart",
        roots: &["pie"],
        caveat: "slice trace animation; theme variables and hover behavior are not rendered",
    },
    CompatRoot {
        label: "Mindmaps",
        roots: &["mindmap"],
        caveat: "tree trace animation; CSS classes and icon registration are semantic-only",
    },
    CompatRoot {
        label: "User Journey",
        roots: &["journey"],
        caveat: "trace animation; Mermaid color palettes are approximated",
    },
    CompatRoot {
        label: "GitGraph Diagram",
        roots: &["gitGraph"],
        caveat: "commit trace animation; display config fields are semantic-only",
    },
    CompatRoot {
        label: "Timeline",
        roots: &["timeline"],
        caveat: "reveal animation; theme variables and direction styling are not rendered",
    },
];

const STATIC_ONLY_ROOTS: &[CompatRoot] = &[
    CompatRoot {
        label: "Quadrant Chart",
        roots: &["quadrantChart"],
        caveat: "static frame; classes are semantic-only",
    },
    CompatRoot {
        label: "Requirement Diagram",
        roots: &["requirementDiagram"],
        caveat: "static frame; styles/classes are semantic-only",
    },
    CompatRoot {
        label: "C4 Diagram",
        roots: &[
            "C4Context",
            "C4Container",
            "C4Component",
            "C4Dynamic",
            "C4Deployment",
        ],
        caveat: "static frame; C4 geometry is schematic and CSS colors are style rows",
    },
    CompatRoot {
        label: "ZenUML",
        roots: &["zenuml"],
        caveat: "static frame; activation stack styling is not modeled",
    },
    CompatRoot {
        label: "Sankey",
        roots: &["sankey", "sankey-beta"],
        caveat: "static frame; link widths/colors are schematic",
    },
    CompatRoot {
        label: "XY Chart",
        roots: &["xychart", "xychart-beta"],
        caveat: "static frame; horizontal orientation is parsed but rendered schematically",
    },
    CompatRoot {
        label: "Block Diagram",
        roots: &["block"],
        caveat: "static frame; styles/classes and arrow geometry are approximate",
    },
    CompatRoot {
        label: "Packet",
        roots: &["packet", "packet-beta"],
        caveat: "static frame; packet sizing config is not interpreted",
    },
    CompatRoot {
        label: "Kanban",
        roots: &["kanban"],
        caveat: "static frame; metadata is rendered as text",
    },
    CompatRoot {
        label: "Architecture",
        roots: &["architecture-beta"],
        caveat: "static frame; icons/classes are text-only",
    },
    CompatRoot {
        label: "Radar",
        roots: &["radar-beta"],
        caveat: "static frame; circular styling and curve fills are approximate",
    },
    CompatRoot {
        label: "Event Modeling",
        roots: &["eventmodeling"],
        caveat: "static frame; Mermaid padding/rowHeight config is not interpreted",
    },
    CompatRoot {
        label: "Treemap",
        roots: &["treemap-beta"],
        caveat: "static frame; classDef and D3 value formatting are semantic-only",
    },
    CompatRoot {
        label: "Venn",
        roots: &["venn-beta"],
        caveat: "static frame; proportional area and theme colors are approximate",
    },
    CompatRoot {
        label: "Ishikawa",
        roots: &["ishikawa-beta"],
        caveat: "static frame; fishbone geometry is approximate",
    },
    CompatRoot {
        label: "Wardley",
        roots: &["wardley-beta"],
        caveat: "static frame; exact Mermaid geometry and styling are approximate",
    },
    CompatRoot {
        label: "TreeView",
        roots: &["treeView-beta"],
        caveat: "static frame; icons/classes are text-only",
    },
];

const UNSUPPORTED_ROOTS: &[CompatRoot] = &[
    CompatRoot {
        label: "Cynefin Framework Diagram",
        roots: &["cynefin-beta"],
        caveat: "no parser root; rejected at parser-header detection",
    },
    CompatRoot {
        label: "Railroad Diagram",
        roots: &["railroad-diagram"],
        caveat: "no parser root; rejected at parser-header detection",
    },
    CompatRoot {
        label: "Swimlanes Diagram",
        roots: &["swimlane"],
        caveat: "no parser root; rejected at parser-header detection",
    },
];

fn print_compat_report(mermaid_version: Option<&str>) -> Result<(), String> {
    let output = compat_report(mermaid_version);
    io::stdout()
        .write_all(output.as_bytes())
        .map_err(|error| format!("failed to write stdout: {error}"))
}

fn compat_report(mermaid_version: Option<&str>) -> String {
    let requested_version = mermaid_version.unwrap_or(MERMAID_COMPAT_VERSION);
    let mut output = String::new();
    output.push_str("Mermaid compatibility\n");
    output.push_str(&format!("requested Mermaid version: {requested_version}\n"));
    output.push_str(&format!(
        "reference Mermaid version: {MERMAID_COMPAT_VERSION}\n\n"
    ));
    if requested_version != MERMAID_COMPAT_VERSION {
        output.push_str(
            "version note: this build only verifies the reference Mermaid version listed above.\n\n",
        );
    }
    output.push_str("Supported roots - animated partial\n");
    append_compat_roots(&mut output, ANIMATED_PARTIAL_ROOTS);
    output.push_str("\nSupported roots - static-only partial\n");
    append_compat_roots(&mut output, STATIC_ONLY_ROOTS);
    output.push_str("\nUnsupported roots\n");
    append_compat_roots(&mut output, UNSUPPORTED_ROOTS);
    output.push_str("\nCaveats\n");
    output.push_str("- Partial: parser and renderer exist, but this is not full Mermaid parity.\n");
    output.push_str(
        "- Static-only: parser and renderer exist; animation collapses to a static frame.\n",
    );
    output.push_str("- Unsupported: no parser root exists; input is rejected.\n");
    output.push_str("- Common: Mermaid frontmatter/init/theme/layout/click parity is not supported except kumeyuri animation directives.\n");
    output
}

fn append_compat_roots(output: &mut String, roots: &[CompatRoot]) {
    for root in roots {
        output.push_str(&format!(
            "- {}: `{}`; {}\n",
            root.label,
            root.roots.join("`, `"),
            root.caveat
        ));
    }
}

fn render_file(path: &Path, format: RenderFormat, options: &RenderOptions) -> Result<(), String> {
    validate_render_options(format, options)?;
    let source = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    if format == RenderFormat::Tui {
        let timeline = timeline_from_source_with_render_options(
            &source,
            AnimationOptions::default(),
            options,
        )?;
        return play_timeline(&timeline);
    }
    let output = render_source(&source, format, options)?;
    io::stdout()
        .write_all(&output)
        .map_err(|error| format!("failed to write stdout: {error}"))
}

fn render_source(
    source: &str,
    format: RenderFormat,
    options: &RenderOptions,
) -> Result<Vec<u8>, String> {
    validate_render_options(format, options)?;
    match format {
        RenderFormat::Text => Ok(render_text_source(source, options)?.into_bytes()),
        RenderFormat::Svg => Ok(render_svg_source(source, options)?.into_bytes()),
        RenderFormat::Gif => render_raster_source(source, options, RasterRenderer::render_gif),
        RenderFormat::Apng => render_raster_source(source, options, RasterRenderer::render_apng),
        RenderFormat::Webp => render_raster_source(source, options, RasterRenderer::render_webp),
        RenderFormat::Tui => Err("tui format requires an interactive terminal".to_owned()),
    }
}

fn validate_render_options(format: RenderFormat, options: &RenderOptions) -> Result<(), String> {
    if options.dark_theme.is_some() && format != RenderFormat::Svg {
        return Err("--dark-theme only supports --format svg".to_owned());
    }
    Ok(())
}

fn render_text_source(source: &str, options: &RenderOptions) -> Result<String, String> {
    let diagram = parse_diagram(source)?;
    let frame = apply_frame_width(frame_renderer(options).render_diagram(&diagram), options);
    Ok(TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: options.width.is_none(),
        final_newline: true,
    })
    .render_frame(&frame))
}

fn render_svg_source(source: &str, options: &RenderOptions) -> Result<String, String> {
    let timeline =
        timeline_from_source_with_render_options(source, AnimationOptions::default(), options)?;
    Ok(SvgRenderer::new(svg_config(options)).render_timeline(&timeline))
}

fn render_raster_source(
    source: &str,
    options: &RenderOptions,
    render: fn(
        &RasterRenderer,
        &Timeline,
    ) -> Result<Vec<u8>, kumeyuri_render_raster::RasterRenderError>,
) -> Result<Vec<u8>, String> {
    let timeline =
        timeline_from_source_with_render_options(source, AnimationOptions::default(), options)?;
    render(&raster_renderer(options)?, &timeline)
        .map_err(|error| format!("raster render error: {error:?}"))
}

fn frame_renderer(options: &RenderOptions) -> StaticFrameRenderer {
    StaticFrameRenderer::default().with_theme(render_theme(options))
}

fn render_theme(options: &RenderOptions) -> Theme {
    let mut theme = options
        .theme
        .map_or_else(Theme::default_theme, |theme| theme.theme().theme());
    if let Some(charset) = options.charset {
        theme.charset = charset.into();
    }
    theme
}

fn svg_config(options: &RenderOptions) -> SvgRenderConfig {
    let theme = render_theme(options);
    let mut config = SvgRenderConfig {
        foreground: css_color(theme.colors.foreground),
        background: css_color(theme.colors.background),
        ..SvgRenderConfig::default()
    };
    if let Some(padding) = options.padding {
        config.padding = u16::try_from(padding).unwrap_or(u16::MAX);
    }
    if let Some(font) = &options.font {
        config.font_family = font.clone();
    }
    if let Some(dark_theme) = options.dark_theme {
        let dark_theme = dark_theme.theme().theme();
        config.dark_foreground = Some(css_color(dark_theme.colors.foreground));
        config.dark_background = Some(css_color(dark_theme.colors.background));
    }
    config
}

fn raster_renderer(options: &RenderOptions) -> Result<RasterRenderer, String> {
    let theme = render_theme(options);
    RasterRenderer::new(RasterRenderConfig {
        padding: options
            .padding
            .unwrap_or(RasterRenderConfig::default().padding),
        foreground: rgba_color(theme.colors.foreground),
        background: rgba_color(theme.colors.background),
        ..RasterRenderConfig::default()
    })
    .map_err(|error| format!("invalid raster render options: {error:?}"))
}

fn apply_frame_width(frame: Frame, options: &RenderOptions) -> Frame {
    match options.width {
        Some(width) => frame.with_min_width(width),
        None => frame,
    }
}

fn apply_timeline_width(timeline: Timeline, options: &RenderOptions) -> Timeline {
    let Some(width) = options.width else {
        return timeline;
    };
    let mut resized = Timeline::new().with_repeat(timeline.repeat());
    for keyframe in timeline.keyframes() {
        resized.push(KeyFrame::new(
            keyframe.frame().with_min_width(width),
            keyframe.duration(),
        ));
    }
    resized
}

fn css_color(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

fn rgba_color(color: RgbColor) -> RgbaColor {
    RgbaColor::rgb(color.red, color.green, color.blue)
}

fn play_file(path: &Path, options: AnimationOptions) -> Result<(), String> {
    let source = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let timeline = timeline_from_source_with_options(&source, options)?;
    play_timeline(&timeline)
}

#[cfg(not(target_arch = "wasm32"))]
fn watch_file(path: &Path) -> Result<(), String> {
    let watch_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    redraw_watched_file(&watch_path)?;

    let (tx, rx) = std::sync::mpsc::channel();
    let mut watcher = RecommendedWatcher::new(
        move |event| {
            let _ = tx.send(event);
        },
        NotifyConfig::default(),
    )
    .map_err(|error| format!("failed to create watcher: {error}"))?;
    watcher
        .watch(&watch_path, RecursiveMode::NonRecursive)
        .map_err(|error| format!("failed to watch {}: {error}", watch_path.display()))?;

    for event in rx {
        match event {
            Ok(event) if should_rerender(&event, &watch_path) => {
                redraw_watched_file(&watch_path)?;
            }
            Ok(_) => {}
            Err(error) => redraw_message(&format!("watch error: {error}\n"))?,
        }
    }
    Err("file watcher stopped".to_owned())
}

#[cfg(target_arch = "wasm32")]
fn watch_file(_path: &Path) -> Result<(), String> {
    Err("watch is unsupported on wasm32".to_owned())
}

#[cfg(not(target_arch = "wasm32"))]
fn should_rerender(event: &Event, path: &Path) -> bool {
    matches!(
        event.kind,
        EventKind::Any | EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
    ) && (event.paths.is_empty() || event.paths.iter().any(|event_path| event_path == path))
}

#[cfg(not(target_arch = "wasm32"))]
fn redraw_watched_file(path: &Path) -> Result<(), String> {
    let output = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))
        .and_then(|source| render_text_source(&source, &RenderOptions::default()))
        .unwrap_or_else(|error| format!("{error}\n"));
    redraw_message(&output)
}

#[cfg(not(target_arch = "wasm32"))]
fn redraw_message(output: &str) -> Result<(), String> {
    let mut stdout = io::stdout();
    execute!(stdout, Clear(ClearType::All), MoveTo(0, 0))
        .map_err(|error| format!("failed to redraw terminal: {error}"))?;
    stdout
        .write_all(output.as_bytes())
        .map_err(|error| format!("failed to write stdout: {error}"))?;
    stdout
        .flush()
        .map_err(|error| format!("failed to flush stdout: {error}"))
}

#[cfg(test)]
fn timeline_from_source(source: &str) -> Result<Timeline, String> {
    timeline_from_source_with_options(source, AnimationOptions::default())
}

fn timeline_from_source_with_options(
    source: &str,
    options: AnimationOptions,
) -> Result<Timeline, String> {
    timeline_from_source_with_render_options(source, options, &RenderOptions::default())
}

fn timeline_from_source_with_render_options(
    source: &str,
    options: AnimationOptions,
    render_options: &RenderOptions,
) -> Result<Timeline, String> {
    let diagram = parse_diagram(source)?;
    let timeline = Animator::animate_diagram_with_options_and_renderer(
        &diagram,
        options,
        frame_renderer(render_options),
    )
    .map_err(|error| format!("animation config error: {error:?}"))?;
    Ok(apply_timeline_width(timeline, render_options))
}

fn playback_options(speed: Option<f32>, repeat: bool) -> Result<AnimationOptions, String> {
    AnimationOptions::new(speed, repeat.then_some(true))
        .map_err(|error| format!("invalid playback options: {error:?}"))
}

fn parse_speed_override(value: &str) -> Result<f32, String> {
    let speed = value
        .parse::<f32>()
        .map_err(|_| format!("invalid speed {value:?}: expected finite f32 > 0"))?;
    if !speed.is_finite() || speed <= 0.0 {
        return Err(format!("invalid speed {value:?}: expected finite f32 > 0"));
    }
    Ok(speed)
}

fn parse_positive_usize(value: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("invalid width {value:?}: expected integer > 0"))?;
    if parsed == 0 {
        return Err(format!("invalid width {value:?}: expected integer > 0"));
    }
    Ok(parsed)
}

fn parse_non_empty_string(value: &str) -> Result<String, String> {
    if value.trim().is_empty() {
        return Err("invalid font: expected non-empty family name".to_owned());
    }
    Ok(value.to_owned())
}

fn parse_diagram(source: &str) -> Result<Diagram, String> {
    MermaidParser::parse_diagram(source).map_err(|error| {
        format!(
            "parse error {:?} at {}..{}",
            error.kind, error.span.start, error.span.end
        )
    })
}

#[cfg(not(target_arch = "wasm32"))]
fn play_timeline(timeline: &Timeline) -> Result<(), String> {
    enable_raw_mode().map_err(|error| format!("failed to enable raw mode: {error}"))?;
    let mut stdout = io::stdout();
    if let Err(error) = execute!(stdout, EnterAlternateScreen) {
        let _ = disable_raw_mode();
        return Err(format!("failed to enter alternate screen: {error}"));
    }

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = match Terminal::new(backend) {
        Ok(terminal) => terminal,
        Err(error) => {
            let _ = execute!(io::stdout(), LeaveAlternateScreen);
            let _ = disable_raw_mode();
            return Err(format!("failed to create terminal: {error}"));
        }
    };
    let render_result = TuiRenderer::new(TuiRenderConfig {
        transition: TuiTransitionEffect::Fade,
        ..TuiRenderConfig::default()
    })
    .render_interactive_timeline(&mut terminal, timeline)
    .map_err(|error| format!("failed to render timeline: {error}"));
    let cursor_result = terminal
        .show_cursor()
        .map_err(|error| format!("failed to show cursor: {error}"));
    let leave_result = execute!(terminal.backend_mut(), LeaveAlternateScreen)
        .map_err(|error| format!("failed to leave alternate screen: {error}"));
    let raw_result =
        disable_raw_mode().map_err(|error| format!("failed to disable raw mode: {error}"));

    render_result?;
    cursor_result?;
    leave_result?;
    raw_result
}

#[cfg(target_arch = "wasm32")]
fn play_timeline(_timeline: &Timeline) -> Result<(), String> {
    Err("play is unsupported on wasm32".to_owned())
}

#[cfg(not(target_arch = "wasm32"))]
trait InteractiveTimelineRenderer {
    fn render_interactive_timeline(
        self,
        terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
        timeline: &Timeline,
    ) -> Result<(), io::Error>;
}

#[cfg(not(target_arch = "wasm32"))]
impl InteractiveTimelineRenderer for TuiRenderer {
    fn render_interactive_timeline(
        self,
        terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
        timeline: &Timeline,
    ) -> Result<(), io::Error> {
        if timeline.is_empty() {
            return Ok(());
        }

        let mut state = PlaybackState::new();
        loop {
            self.draw(terminal, timeline.keyframes()[state.index].frame())?;
            let timeout = if state.paused {
                Duration::from_millis(100)
            } else {
                timeline.keyframes()[state.index].duration()
            };

            if event::poll(timeout)? {
                if let TerminalEvent::Key(key) = event::read()?
                    && key.kind == KeyEventKind::Press
                    && state.handle_key(key.code, timeline.len(), timeline.repeat())
                        == PlaybackAction::Quit
                {
                    break;
                }
            } else if !state.paused && !state.advance(timeline.len(), timeline.repeat()) {
                break;
            }
        }
        Ok(())
    }
}

#[cfg(not(target_arch = "wasm32"))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PlaybackState {
    index: usize,
    paused: bool,
}

#[cfg(not(target_arch = "wasm32"))]
impl PlaybackState {
    const fn new() -> Self {
        Self {
            index: 0,
            paused: false,
        }
    }

    fn handle_key(&mut self, key: KeyCode, len: usize, repeat: bool) -> PlaybackAction {
        match key {
            KeyCode::Char('q') | KeyCode::Esc => PlaybackAction::Quit,
            KeyCode::Char(' ') => {
                self.paused = !self.paused;
                PlaybackAction::Continue
            }
            KeyCode::Right | KeyCode::Down => {
                self.paused = true;
                self.step_forward(len, repeat);
                PlaybackAction::Continue
            }
            KeyCode::Left | KeyCode::Up => {
                self.paused = true;
                self.step_backward(len, repeat);
                PlaybackAction::Continue
            }
            KeyCode::Char('r') => {
                self.index = 0;
                self.paused = false;
                PlaybackAction::Continue
            }
            _ => PlaybackAction::Continue,
        }
    }

    fn advance(&mut self, len: usize, repeat: bool) -> bool {
        if len == 0 {
            return false;
        }
        if self.index + 1 < len {
            self.index += 1;
            return true;
        }
        if repeat {
            self.index = 0;
            return true;
        }
        false
    }

    fn step_forward(&mut self, len: usize, repeat: bool) {
        if len == 0 {
            return;
        }
        if self.index + 1 < len {
            self.index += 1;
        } else if repeat {
            self.index = 0;
        }
    }

    fn step_backward(&mut self, len: usize, repeat: bool) {
        if len == 0 {
            return;
        }
        if self.index > 0 {
            self.index -= 1;
        } else if repeat {
            self.index = len - 1;
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PlaybackAction {
    Continue,
    Quit,
}

#[cfg(test)]
mod tests {
    use super::{
        ANIMATED_PARTIAL_ROOTS, Cli, Command, RenderCharset, RenderFormat, RenderOptions,
        RenderTheme, STATIC_ONLY_ROOTS, UNSUPPORTED_ROOTS, compat_report, parse_non_empty_string,
        parse_positive_usize, parse_speed_override, playback_options, render_source,
        timeline_from_source, timeline_from_source_with_options,
        timeline_from_source_with_render_options,
    };
    #[cfg(not(target_arch = "wasm32"))]
    use super::{PlaybackAction, PlaybackState, should_rerender};
    use clap::Parser as _;
    #[cfg(not(target_arch = "wasm32"))]
    use crossterm::event::KeyCode;
    use kumeyuri_core::animator::AnimationOptions;
    #[cfg(not(target_arch = "wasm32"))]
    use notify::{
        Event, EventKind,
        event::{DataChange, ModifyKind},
    };
    #[cfg(not(target_arch = "wasm32"))]
    use std::path::Path;
    use std::time::Duration;

    #[test]
    fn renders_mermaid_source_to_text() {
        let output = String::from_utf8(
            render_source(
                "graph TD\nA --> B",
                RenderFormat::Text,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();

        assert!(output.contains('A'));
        assert!(output.contains('B'));
        assert!(output.ends_with('\n'));
    }

    #[test]
    fn render_format_parser_accepts_all_values() {
        for value in ["text", "svg", "gif", "apng", "webp", "tui"] {
            let cli = Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd", "--format", value])
                .unwrap();
            assert!(matches!(cli.command, Command::Render { .. }));
        }
    }

    #[test]
    fn compat_parser_accepts_mermaid_version() {
        let cli =
            Cli::try_parse_from(["kumeyuri", "compat", "--mermaid-version", "11.15.0"]).unwrap();
        let Command::Compat { mermaid_version } = cli.command else {
            panic!("expected compat command");
        };

        assert_eq!(mermaid_version.as_deref(), Some("11.15.0"));
    }

    #[test]
    fn compat_report_lists_roots_and_caveats() {
        let output = compat_report(Some("11.15.0"));

        assert!(output.contains("requested Mermaid version: 11.15.0"));
        assert!(output.contains("reference Mermaid version: 11.15.0"));
        assert!(output.contains("Supported roots - animated partial"));
        assert!(output.contains("`graph`, `flowchart`"));
        assert!(output.contains("Supported roots - static-only partial"));
        assert!(output.contains("`quadrantChart`"));
        assert!(output.contains("Unsupported roots"));
        assert!(output.contains("`cynefin-beta`"));
        assert!(output.contains("Partial: parser and renderer exist"));
        assert!(output.contains("Static-only: parser and renderer exist"));
    }

    #[test]
    fn compat_report_labels_unverified_requested_versions() {
        let output = compat_report(Some("12.0.0"));

        assert!(output.contains("requested Mermaid version: 12.0.0"));
        assert!(output.contains("version note: this build only verifies"));
    }

    #[test]
    fn compat_tables_match_current_coverage_counts() {
        assert_eq!(ANIMATED_PARTIAL_ROOTS.len(), 11);
        assert_eq!(STATIC_ONLY_ROOTS.len(), 17);
        assert_eq!(UNSUPPORTED_ROOTS.len(), 3);
    }

    #[test]
    fn render_option_parser_accepts_theme_charset_width_padding_and_font() {
        let cli = Cli::try_parse_from([
            "kumeyuri",
            "render",
            "diagram.mmd",
            "--theme",
            "tokyo-night",
            "--dark-theme",
            "dracula",
            "--charset",
            "unicode",
            "--width",
            "40",
            "--padding",
            "12",
            "--font",
            "Fira Code",
        ])
        .unwrap();
        let Command::Render { options, .. } = cli.command else {
            panic!("expected render command");
        };

        assert_eq!(options.theme, Some(RenderTheme::TokyoNight));
        assert_eq!(options.dark_theme, Some(RenderTheme::Dracula));
        assert_eq!(options.charset, Some(RenderCharset::Unicode));
        assert_eq!(options.width, Some(40));
        assert_eq!(options.padding, Some(12));
        assert_eq!(options.font.as_deref(), Some("Fira Code"));
    }

    #[test]
    fn renders_mermaid_source_to_svg() {
        let output = String::from_utf8(
            render_source(
                "graph TD\nA --> B",
                RenderFormat::Svg,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();

        assert!(output.starts_with("<svg "));
        assert!(output.contains("<animate "));
    }

    #[test]
    fn renders_mermaid_source_to_gif() {
        let output = render_source(
            "graph TD\nA --> B",
            RenderFormat::Gif,
            &RenderOptions::default(),
        )
        .unwrap();

        assert!(output.starts_with(b"GIF89a"));
    }

    #[test]
    fn renders_mermaid_source_to_apng() {
        let output = render_source(
            "graph TD\nA --> B",
            RenderFormat::Apng,
            &RenderOptions::default(),
        )
        .unwrap();

        assert!(output.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert!(output.windows(4).any(|chunk| chunk == b"acTL"));
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn renders_mermaid_source_to_webp() {
        let output = render_source(
            "graph TD\nA --> B",
            RenderFormat::Webp,
            &RenderOptions::default(),
        )
        .unwrap();

        assert_eq!(&output[..4], b"RIFF");
        assert_eq!(&output[8..12], b"WEBP");
    }

    #[test]
    fn tui_format_requires_render_file_terminal_path() {
        let error = render_source(
            "graph TD\nA --> B",
            RenderFormat::Tui,
            &RenderOptions::default(),
        )
        .unwrap_err();

        assert!(error.contains("interactive terminal"));
    }

    #[test]
    fn render_options_apply_to_text_svg_and_timeline_frames() {
        let options = RenderOptions {
            theme: Some(RenderTheme::TokyoNight),
            charset: Some(RenderCharset::Unicode),
            width: Some(40),
            padding: Some(3),
            font: Some("Fira Code".to_owned()),
            ..RenderOptions::default()
        };
        let svg_options = RenderOptions {
            dark_theme: Some(RenderTheme::Dracula),
            ..options.clone()
        };
        let text = String::from_utf8(
            render_source("graph TD\nA --> B", RenderFormat::Text, &options).unwrap(),
        )
        .unwrap();
        let svg = String::from_utf8(
            render_source("graph TD\nA --> B", RenderFormat::Svg, &svg_options).unwrap(),
        )
        .unwrap();
        let timeline = timeline_from_source_with_render_options(
            "graph TD\nA --> B",
            AnimationOptions::default(),
            &options,
        )
        .unwrap();

        assert!(text.lines().all(|line| line.chars().count() == 40));
        assert!(text.contains('┌'));
        assert!(svg.contains(r#"font-family="Fira Code""#));
        assert!(svg.contains(r##"fill="#1a1b26""##));
        assert!(svg.contains(r##"fill="#c0caf5""##));
        assert!(svg.contains("@media (prefers-color-scheme: dark)"));
        assert!(svg.contains(r##"rect { fill: #282a36; }"##));
        assert!(svg.contains(r##"text { fill: #f8f8f2; }"##));
        assert!(svg.contains(r#"<text x="3""#));
        assert!(
            timeline
                .keyframes()
                .iter()
                .all(|keyframe| keyframe.frame().width() == 40)
        );
    }

    #[test]
    fn dark_theme_requires_svg_output() {
        let error = render_source(
            "graph TD\nA --> B",
            RenderFormat::Text,
            &RenderOptions {
                dark_theme: Some(RenderTheme::Dracula),
                ..RenderOptions::default()
            },
        )
        .unwrap_err();

        assert!(error.contains("--dark-theme only supports --format svg"));
    }

    #[test]
    fn builds_timeline_from_mermaid_source() {
        let timeline = timeline_from_source("graph TD\nA --> B").unwrap();

        assert_eq!(timeline.len(), 3);
        assert!(!timeline.repeat());
    }

    #[test]
    fn timeline_source_honors_animation_directives() {
        let timeline = timeline_from_source("%%{ animate: 'none' }%%\ngraph TD\nA --> B").unwrap();

        assert_eq!(timeline.len(), 1);
    }

    #[test]
    fn playback_options_override_timeline_speed_and_loop() {
        let options = playback_options(Some(4.0), true).unwrap();
        let timeline = timeline_from_source_with_options(
            "%%{ animate: 'playback', speed: 2.0, loop: false }%%\nsequenceDiagram\nAlice->>Bob: hi",
            options,
        )
        .unwrap();

        assert_eq!(
            timeline.keyframes()[0].duration(),
            Duration::from_millis(175)
        );
        assert!(timeline.repeat());
    }

    #[test]
    fn speed_override_parser_rejects_invalid_values() {
        assert_eq!(parse_speed_override("1.25").unwrap(), 1.25);
        assert!(parse_speed_override("0").is_err());
        assert!(parse_speed_override("NaN").is_err());
    }

    #[test]
    fn render_option_parsers_reject_invalid_values() {
        assert_eq!(parse_positive_usize("12").unwrap(), 12);
        assert!(parse_positive_usize("0").is_err());
        assert_eq!(parse_non_empty_string("Fira Code").unwrap(), "Fira Code");
        assert!(parse_non_empty_string(" ").is_err());
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn watch_rerenders_relevant_modify_events() {
        let event = Event::new(EventKind::Modify(ModifyKind::Data(DataChange::Content)))
            .add_path("diagram.mmd".into());

        assert!(should_rerender(&event, Path::new("diagram.mmd")));
        assert!(!should_rerender(&event, Path::new("other.mmd")));
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn playback_controls_pause_step_restart_and_quit() {
        let mut state = PlaybackState::new();

        assert_eq!(
            state.handle_key(KeyCode::Char(' '), 3, false),
            PlaybackAction::Continue,
        );
        assert!(state.paused);

        state.handle_key(KeyCode::Right, 3, false);
        assert_eq!(state.index, 1);
        assert!(state.paused);

        state.handle_key(KeyCode::Left, 3, false);
        assert_eq!(state.index, 0);

        state.handle_key(KeyCode::Right, 3, false);
        state.handle_key(KeyCode::Char('r'), 3, false);
        assert_eq!(state.index, 0);
        assert!(!state.paused);

        assert_eq!(
            state.handle_key(KeyCode::Char('q'), 3, false),
            PlaybackAction::Quit,
        );
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn playback_advance_respects_repeat_flag() {
        let mut state = PlaybackState {
            index: 1,
            paused: false,
        };

        assert!(!state.advance(2, false));
        assert_eq!(state.index, 1);
        assert!(state.advance(2, true));
        assert_eq!(state.index, 0);
    }
}
