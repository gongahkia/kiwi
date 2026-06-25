//! Command-line interface for rendering and managing Kumeyuri diagrams.

use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    ffi::OsString,
    fs,
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::ExitCode,
    time::Duration,
};

use clap::{Args, CommandFactory, FromArgMatches, Parser, Subcommand, ValueEnum};
use flate2::{Compression, read::GzDecoder, write::GzEncoder};
use kumeyuri_core::{
    abi::{Capability, CapabilitySet, KUMEYURI_ABI_VERSION},
    animator::{AnimationOptions, Animator, KeyFrame, Timeline},
    ast::{
        Diagram, DiagramKind, Direction, FlowStatement, FlowchartAst, IshikawaNode, MindmapNode,
        SequenceStatement, TimelinePeriod, TreeViewNode, TreemapNode,
    },
    cast::Kumecast,
    frame::{Charset, Frame, StaticFrameRenderer},
    layout::FlowLayoutConfig,
    parser::{ParseErrorKind, Parser as MermaidParser},
    plugins::{PluginCache, PluginRuntimePolicy},
    text::{TextOutputBackend, TextOutputConfig},
    theme::{
        BuiltInTheme, KumethemeCharset, KumethemeColors, KumethemeError, KumethemeToml, RgbColor,
        Theme, ThemeSearchEntry, ThemeSearchPaths, ThemeSource, discover_themes,
    },
};
use kumeyuri_render_raster::{RasterRenderConfig, RasterRenderer, RgbaColor};
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};
use serde::{Deserialize, Serialize};

mod i18n;
mod mcp;

use std::net::SocketAddr;
#[cfg(not(target_arch = "wasm32"))]
use std::time::Instant;

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
    kumeyuri_render_tui::{TuiDebugOverlay, TuiRenderConfig, TuiRenderer, TuiTransitionEffect},
    notify::{
        Config as NotifyConfig, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher,
    },
    ratatui::{Terminal, backend::CrosstermBackend},
};

#[derive(Debug, Parser)]
#[command(name = "kumeyuri", version)]
struct Cli {
    #[arg(long, global = true, value_name = "LOCALE", value_parser = parse_locale_override)]
    lang: Option<String>,
    #[arg(
        long,
        global = true,
        value_name = "BYTES",
        default_value_t = DEFAULT_INPUT_LIMIT_BYTES,
        value_parser = parse_positive_input_bytes
    )]
    max_input_bytes: usize,
    #[arg(long, value_name = "FILE")]
    validate_theme: Option<PathBuf>,
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    Compat {
        #[arg(long, value_name = "VERSION", value_parser = parse_non_empty_string)]
        mermaid_version: Option<String>,
        #[arg(long)]
        json: bool,
    },
    Render {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_enum, default_value_t = RenderFormat::Text)]
        format: RenderFormat,
        #[command(flatten)]
        options: RenderOptions,
    },
    Export {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_enum, default_value_t = ExportFormat::Kumecast)]
        format: ExportFormat,
        #[command(flatten)]
        options: RenderOptions,
    },
    Convert {
        #[arg(value_name = "CAST")]
        cast: PathBuf,
        #[arg(long, value_enum, default_value_t = ConvertFormat::Svg)]
        format: ConvertFormat,
    },
    Lint {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long)]
        json: bool,
    },
    AuditMermaid {
        #[arg(value_name = "PATH", required = true)]
        paths: Vec<PathBuf>,
        #[arg(long)]
        json: bool,
    },
    Layout {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long)]
        ai: bool,
    },
    Watch {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_name = "FILE")]
        theme_file: Option<PathBuf>,
    },
    Play {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_name = "FACTOR", value_parser = parse_speed_override)]
        speed: Option<f32>,
        #[arg(long = "loop")]
        repeat: bool,
        #[arg(long)]
        debug: bool,
    },
    Plugin {
        #[command(subcommand)]
        command: PluginCommand,
    },
    Theme {
        #[command(subcommand)]
        command: ThemeCommand,
    },
    Mcp {
        #[arg(long, value_enum, default_value_t = McpTransport::Stdio)]
        transport: McpTransport,
        #[arg(long, value_name = "ADDR", default_value = "127.0.0.1:8000", value_parser = parse_socket_addr)]
        bind: SocketAddr,
        #[arg(long, value_name = "TOKEN", value_parser = parse_non_empty_string)]
        bearer_token: Option<String>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum McpTransport {
    Stdio,
    HttpSse,
}

#[derive(Debug, Subcommand)]
enum PluginCommand {
    Install {
        #[arg(value_name = "NAME", value_parser = parse_non_empty_string)]
        name: String,
    },
    List,
    Remove {
        #[arg(value_name = "NAME", value_parser = parse_non_empty_string)]
        name: String,
    },
    Update {
        #[arg(value_name = "NAME", value_parser = parse_non_empty_string)]
        name: String,
    },
    Disable {
        #[arg(value_name = "NAME", value_parser = parse_non_empty_string)]
        name: String,
    },
}

#[derive(Debug, Subcommand)]
enum ThemeCommand {
    List,
    Show {
        #[arg(value_name = "NAME", value_parser = parse_non_empty_string)]
        name: String,
    },
    New {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_name = "NAME", value_parser = parse_non_empty_string)]
        name: Option<String>,
    },
    Validate {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
    Publish {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_name = "DIR", default_value = "themes.kumeyuri.dev")]
        index_dir: PathBuf,
        #[arg(
            long,
            value_name = "URL",
            default_value = DEFAULT_THEME_INDEX_BASE_URL,
            value_parser = parse_non_empty_string
        )]
        base_url: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderFormat {
    Text,
    Svg,
    Gif,
    Apng,
    Webp,
    Vtt,
    Tui,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum ExportFormat {
    Kumecast,
    KumecastGz,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum ConvertFormat {
    Text,
    Svg,
    Gif,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Args)]
struct RenderOptions {
    #[arg(long)]
    narrate: bool,
    #[arg(long = "alt-text")]
    alt_text: bool,
    #[arg(long, value_enum)]
    theme: Option<RenderTheme>,
    #[arg(long, value_enum)]
    dark_theme: Option<RenderTheme>,
    #[arg(long, value_enum)]
    charset: Option<RenderCharset>,
    #[arg(long, value_name = "CELLS", value_parser = parse_positive_usize)]
    width: Option<usize>,
    #[arg(long, value_name = "CELLS", value_parser = parse_positive_usize)]
    max_label_width: Option<usize>,
    #[arg(long, value_name = "PX")]
    padding: Option<u32>,
    #[arg(long, value_name = "FAMILY", value_parser = parse_non_empty_string)]
    font: Option<String>,
    #[arg(long = "allow-external")]
    allow_external: bool,
    #[arg(long = "plugin-allow", value_name = "CSV", value_parser = parse_plugin_allow)]
    plugin_allow: Option<CapabilitySet>,
    #[arg(skip)]
    custom_theme: Option<Theme>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderTheme {
    Default,
    Mono,
    TokyoNight,
    Github,
    Dracula,
    SolarizedLight,
    SolarizedDark,
    Nord,
    CatppuccinMocha,
    HighContrast,
    PrintMono,
}

impl RenderTheme {
    const fn theme(self) -> BuiltInTheme {
        match self {
            Self::Default => BuiltInTheme::Default,
            Self::Mono => BuiltInTheme::Mono,
            Self::TokyoNight => BuiltInTheme::TokyoNight,
            Self::Github => BuiltInTheme::Github,
            Self::Dracula => BuiltInTheme::Dracula,
            Self::SolarizedLight => BuiltInTheme::SolarizedLight,
            Self::SolarizedDark => BuiltInTheme::SolarizedDark,
            Self::Nord => BuiltInTheme::Nord,
            Self::CatppuccinMocha => BuiltInTheme::CatppuccinMocha,
            Self::HighContrast => BuiltInTheme::HighContrast,
            Self::PrintMono => BuiltInTheme::PrintMono,
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
    let matches = Cli::command().about(msg("cli-about")).get_matches();
    let cli = Cli::from_arg_matches(&matches).unwrap_or_else(|error| error.exit());
    i18n::configure(cli.lang.as_deref(), |name| env::var(name).ok())?;
    let max_input_bytes = cli.max_input_bytes;

    if let Some(path) = cli.validate_theme {
        return validate_theme_file(&path, max_input_bytes);
    }

    match cli.command.ok_or_else(|| msg("missing-command"))? {
        Command::Compat {
            mermaid_version,
            json,
        } => print_compat_report(mermaid_version.as_deref(), json),
        Command::Render {
            file,
            format,
            options,
        } => render_file(&file, format, &options, max_input_bytes),
        Command::Export {
            file,
            format,
            options,
        } => export_file(&file, format, &options, max_input_bytes),
        Command::Convert { cast, format } => convert_file(&cast, format, max_input_bytes),
        Command::Lint { file, json } => lint_file(&file, json, max_input_bytes),
        Command::AuditMermaid { paths, json } => audit_mermaid(&paths, json, max_input_bytes),
        Command::Layout { file, ai } => layout_file(&file, ai, max_input_bytes),
        Command::Watch { file, theme_file } => {
            watch_file(&file, theme_file.as_deref(), max_input_bytes)
        }
        Command::Play {
            file,
            speed,
            repeat,
            debug,
        } => play_file(
            &file,
            playback_options(speed, repeat)?,
            max_input_bytes,
            debug,
        ),
        Command::Plugin { command } => run_plugin_command(command),
        Command::Theme { command } => run_theme_command(command, max_input_bytes),
        Command::Mcp {
            transport,
            bind,
            bearer_token,
        } => mcp::run_server(mcp::McpServerConfig {
            transport,
            bind,
            bearer_token,
        }),
    }
}

const PLUGIN_KEYWORD: &str = "kumeyuri-plugin";
const KUMEYURI_USER_AGENT: &str = concat!("kumeyuri/", env!("CARGO_PKG_VERSION"));

const MERMAID_COMPAT_VERSION: &str = "11.15.0";
const EXTREME_ASPECT_RATIO: usize = 4;
const KUMEYURI_AI_DYLIB_ENV: &str = "KUMEYURI_AI_DYLIB";
const KUMEYURI_AI_ABI_VERSION: u32 = 1;
const DEFAULT_INPUT_LIMIT_BYTES: usize = 1024 * 1024;
const DEFAULT_THEME_INDEX_BASE_URL: &str = "https://themes.kumeyuri.dev";
const THEME_INDEX_VERSION: u32 = 1;

fn msg(id: &str) -> String {
    i18n::message(id)
}

fn msg_args(id: &str, args: &[(&str, String)]) -> String {
    i18n::format_message(id, args)
}

fn msg_arg(name: &'static str, value: impl ToString) -> (&'static str, String) {
    (name, value.to_string())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CompatRoot {
    label_id: &'static str,
    roots: &'static [&'static str],
    caveat_id: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct CompatJsonReport {
    requested_version: String,
    reference_version: String,
    version_verified: bool,
    counts: CompatJsonCounts,
    roots: Vec<CompatJsonRoot>,
    caveats: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct CompatJsonCounts {
    families: usize,
    animated_partial: usize,
    static_only_partial: usize,
    unsupported: usize,
    root_spellings: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct CompatJsonRoot {
    label: String,
    roots: Vec<&'static str>,
    support: &'static str,
    caveat: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct MermaidAuditReport {
    schema_version: u8,
    paths: Vec<String>,
    counts: MermaidAuditCounts,
    findings: Vec<MermaidAuditFinding>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct MermaidAuditCounts {
    diagrams: usize,
    parsed: usize,
    rendered: usize,
    animated_partial: usize,
    static_only_partial: usize,
    unsupported: usize,
    warnings: usize,
    errors: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct MermaidAuditFinding {
    path: String,
    line: usize,
    source: &'static str,
    root: Option<String>,
    support: &'static str,
    parse_ok: bool,
    render_ok: bool,
    frames: usize,
    warnings: Vec<String>,
    error: Option<String>,
    suggestion: Option<&'static str>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MermaidAuditSource {
    path: PathBuf,
    line: usize,
    source_kind: &'static str,
    source: String,
}

const ANIMATED_PARTIAL_ROOTS: &[CompatRoot] = &[
    CompatRoot {
        label_id: "compat-label-flowchart",
        roots: &["graph", "flowchart"],
        caveat_id: "compat-caveat-flowchart",
    },
    CompatRoot {
        label_id: "compat-label-sequence",
        roots: &["sequenceDiagram"],
        caveat_id: "compat-caveat-sequence",
    },
    CompatRoot {
        label_id: "compat-label-state",
        roots: &["stateDiagram", "stateDiagram-v2"],
        caveat_id: "compat-caveat-state",
    },
    CompatRoot {
        label_id: "compat-label-class",
        roots: &["classDiagram"],
        caveat_id: "compat-caveat-class",
    },
    CompatRoot {
        label_id: "compat-label-er",
        roots: &["erDiagram"],
        caveat_id: "compat-caveat-er",
    },
    CompatRoot {
        label_id: "compat-label-gantt",
        roots: &["gantt"],
        caveat_id: "compat-caveat-gantt",
    },
    CompatRoot {
        label_id: "compat-label-pie",
        roots: &["pie"],
        caveat_id: "compat-caveat-pie",
    },
    CompatRoot {
        label_id: "compat-label-mindmap",
        roots: &["mindmap"],
        caveat_id: "compat-caveat-mindmap",
    },
    CompatRoot {
        label_id: "compat-label-journey",
        roots: &["journey"],
        caveat_id: "compat-caveat-journey",
    },
    CompatRoot {
        label_id: "compat-label-gitgraph",
        roots: &["gitGraph"],
        caveat_id: "compat-caveat-gitgraph",
    },
    CompatRoot {
        label_id: "compat-label-timeline",
        roots: &["timeline"],
        caveat_id: "compat-caveat-timeline",
    },
];

const STATIC_ONLY_ROOTS: &[CompatRoot] = &[
    CompatRoot {
        label_id: "compat-label-quadrant",
        roots: &["quadrantChart"],
        caveat_id: "compat-caveat-quadrant",
    },
    CompatRoot {
        label_id: "compat-label-requirement",
        roots: &["requirementDiagram"],
        caveat_id: "compat-caveat-requirement",
    },
    CompatRoot {
        label_id: "compat-label-cynefin",
        roots: &["cynefin-beta"],
        caveat_id: "compat-caveat-cynefin",
    },
    CompatRoot {
        label_id: "compat-label-c4",
        roots: &[
            "C4Context",
            "C4Container",
            "C4Component",
            "C4Dynamic",
            "C4Deployment",
        ],
        caveat_id: "compat-caveat-c4",
    },
    CompatRoot {
        label_id: "compat-label-zenuml",
        roots: &["zenuml"],
        caveat_id: "compat-caveat-zenuml",
    },
    CompatRoot {
        label_id: "compat-label-sankey",
        roots: &["sankey", "sankey-beta"],
        caveat_id: "compat-caveat-sankey",
    },
    CompatRoot {
        label_id: "compat-label-xy",
        roots: &["xychart", "xychart-beta"],
        caveat_id: "compat-caveat-xy",
    },
    CompatRoot {
        label_id: "compat-label-block",
        roots: &["block"],
        caveat_id: "compat-caveat-block",
    },
    CompatRoot {
        label_id: "compat-label-packet",
        roots: &["packet", "packet-beta"],
        caveat_id: "compat-caveat-packet",
    },
    CompatRoot {
        label_id: "compat-label-kanban",
        roots: &["kanban"],
        caveat_id: "compat-caveat-kanban",
    },
    CompatRoot {
        label_id: "compat-label-architecture",
        roots: &["architecture-beta"],
        caveat_id: "compat-caveat-architecture",
    },
    CompatRoot {
        label_id: "compat-label-radar",
        roots: &["radar-beta"],
        caveat_id: "compat-caveat-radar",
    },
    CompatRoot {
        label_id: "compat-label-railroad",
        roots: &["railroad-diagram"],
        caveat_id: "compat-caveat-railroad",
    },
    CompatRoot {
        label_id: "compat-label-swimlanes",
        roots: &["swimlane"],
        caveat_id: "compat-caveat-swimlanes",
    },
    CompatRoot {
        label_id: "compat-label-event-modeling",
        roots: &["eventmodeling"],
        caveat_id: "compat-caveat-event-modeling",
    },
    CompatRoot {
        label_id: "compat-label-treemap",
        roots: &["treemap-beta"],
        caveat_id: "compat-caveat-treemap",
    },
    CompatRoot {
        label_id: "compat-label-venn",
        roots: &["venn-beta"],
        caveat_id: "compat-caveat-venn",
    },
    CompatRoot {
        label_id: "compat-label-ishikawa",
        roots: &["ishikawa-beta"],
        caveat_id: "compat-caveat-ishikawa",
    },
    CompatRoot {
        label_id: "compat-label-wardley",
        roots: &["wardley-beta"],
        caveat_id: "compat-caveat-wardley",
    },
    CompatRoot {
        label_id: "compat-label-treeview",
        roots: &["treeView-beta"],
        caveat_id: "compat-caveat-treeview",
    },
];

const UNSUPPORTED_ROOTS: &[CompatRoot] = &[];

fn print_compat_report(mermaid_version: Option<&str>, json: bool) -> Result<(), String> {
    let output = if json {
        serde_json::to_string_pretty(&compat_json_report(mermaid_version))
            .map_err(|error| format!("failed to encode compat json: {error}"))?
    } else {
        compat_report(mermaid_version)
    };
    io::stdout()
        .write_all(output.as_bytes())
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn compat_json_report(mermaid_version: Option<&str>) -> CompatJsonReport {
    let requested_version = mermaid_version.unwrap_or(MERMAID_COMPAT_VERSION);
    let mut roots = Vec::new();
    append_compat_json_roots(&mut roots, ANIMATED_PARTIAL_ROOTS, "animated-partial");
    append_compat_json_roots(&mut roots, STATIC_ONLY_ROOTS, "static-only-partial");
    append_compat_json_roots(&mut roots, UNSUPPORTED_ROOTS, "unsupported");
    CompatJsonReport {
        requested_version: requested_version.to_owned(),
        reference_version: MERMAID_COMPAT_VERSION.to_owned(),
        version_verified: requested_version == MERMAID_COMPAT_VERSION,
        counts: CompatJsonCounts {
            families: roots.len(),
            animated_partial: ANIMATED_PARTIAL_ROOTS.len(),
            static_only_partial: STATIC_ONLY_ROOTS.len(),
            unsupported: UNSUPPORTED_ROOTS.len(),
            root_spellings: roots.iter().map(|root| root.roots.len()).sum(),
        },
        roots,
        caveats: [
            "compat-caveat-partial",
            "compat-caveat-static",
            "compat-caveat-unsupported",
            "compat-caveat-common",
        ]
        .into_iter()
        .map(msg)
        .collect(),
    }
}

fn append_compat_json_roots(
    output: &mut Vec<CompatJsonRoot>,
    roots: &[CompatRoot],
    support: &'static str,
) {
    output.extend(roots.iter().map(|root| CompatJsonRoot {
        label: msg(root.label_id),
        roots: root.roots.to_vec(),
        support,
        caveat: msg(root.caveat_id),
    }));
}

fn compat_report(mermaid_version: Option<&str>) -> String {
    let requested_version = mermaid_version.unwrap_or(MERMAID_COMPAT_VERSION);
    let mut output = String::new();
    output.push_str(&msg("compat-title"));
    output.push('\n');
    output.push_str(&msg_args(
        "compat-requested-version",
        &[msg_arg("version", requested_version)],
    ));
    output.push('\n');
    output.push_str(&msg_args(
        "compat-reference-version",
        &[msg_arg("version", MERMAID_COMPAT_VERSION)],
    ));
    output.push_str("\n\n");
    if requested_version != MERMAID_COMPAT_VERSION {
        output.push_str(&msg("compat-version-note"));
        output.push_str("\n\n");
    }
    output.push_str(&msg("compat-supported-animated"));
    output.push('\n');
    append_compat_roots(&mut output, ANIMATED_PARTIAL_ROOTS);
    output.push('\n');
    output.push_str(&msg("compat-supported-static"));
    output.push('\n');
    append_compat_roots(&mut output, STATIC_ONLY_ROOTS);
    output.push('\n');
    output.push_str(&msg("compat-unsupported"));
    output.push('\n');
    append_compat_roots(&mut output, UNSUPPORTED_ROOTS);
    output.push('\n');
    output.push_str(&msg("compat-caveats"));
    output.push('\n');
    for caveat in [
        "compat-caveat-partial",
        "compat-caveat-static",
        "compat-caveat-unsupported",
        "compat-caveat-common",
    ] {
        output.push_str("- ");
        output.push_str(&msg(caveat));
        output.push('\n');
    }
    output
}

fn append_compat_roots(output: &mut String, roots: &[CompatRoot]) {
    for root in roots {
        output.push_str(&msg_args(
            "compat-root",
            &[
                msg_arg("label", msg(root.label_id)),
                msg_arg("roots", root.roots.join("`, `")),
                msg_arg("caveat", msg(root.caveat_id)),
            ],
        ));
        output.push('\n');
    }
}

fn render_file(
    path: &Path,
    format: RenderFormat,
    options: &RenderOptions,
    max_input_bytes: usize,
) -> Result<(), String> {
    validate_render_options(format, options)?;
    let source = read_source_file(path, max_input_bytes)?;
    let diagram = parse_diagram(&source)?;
    emit_layout_warnings(&diagram, options);
    if format == RenderFormat::Tui {
        let timeline = timeline_from_source_with_render_options(
            &source,
            AnimationOptions::default(),
            options,
        )?;
        return play_timeline(&timeline, false);
    }
    let output = render_source(&source, format, options)?;
    io::stdout()
        .write_all(&output)
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn export_file(
    path: &Path,
    format: ExportFormat,
    options: &RenderOptions,
    max_input_bytes: usize,
) -> Result<(), String> {
    let source = read_source_file(path, max_input_bytes)?;
    let output = export_source(&source, format, options)?;
    io::stdout()
        .write_all(&output)
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn convert_file(path: &Path, format: ConvertFormat, max_input_bytes: usize) -> Result<(), String> {
    let source = read_cast_source_file(path, max_input_bytes)?;
    let output = convert_cast_source(&source, format)?;
    io::stdout()
        .write_all(&output)
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn lint_file(path: &Path, json: bool, max_input_bytes: usize) -> Result<(), String> {
    let source = read_source_file(path, max_input_bytes)?;
    let report = lint_source(&path.display().to_string(), &source)?;
    print_lint_report(&report, json)
}

fn audit_mermaid(paths: &[PathBuf], json: bool, max_input_bytes: usize) -> Result<(), String> {
    let report = audit_mermaid_paths(paths, max_input_bytes)?;
    let output = if json {
        format!(
            "{}\n",
            serde_json::to_string_pretty(&report)
                .map_err(|error| format!("failed to encode Mermaid audit json: {error}"))?
        )
    } else {
        format_mermaid_audit_text(&report)
    };
    io::stdout()
        .write_all(output.as_bytes())
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn audit_mermaid_paths(
    paths: &[PathBuf],
    max_input_bytes: usize,
) -> Result<MermaidAuditReport, String> {
    let mut files = Vec::new();
    for path in paths {
        collect_mermaid_audit_files(path, &mut files)?;
    }
    files.sort();
    files.dedup();

    let mut findings = Vec::new();
    for file in files {
        let source = read_source_file(&file, max_input_bytes)?;
        findings.extend(
            extract_mermaid_audit_sources(&file, &source)
                .into_iter()
                .map(audit_mermaid_source),
        );
    }

    let mut counts = MermaidAuditCounts {
        diagrams: findings.len(),
        ..MermaidAuditCounts::default()
    };
    for finding in &findings {
        counts.parsed += usize::from(finding.parse_ok);
        counts.rendered += usize::from(finding.render_ok);
        counts.animated_partial += usize::from(finding.support == "animated-partial");
        counts.static_only_partial += usize::from(finding.support == "static-only-partial");
        counts.unsupported += usize::from(finding.support == "unsupported");
        counts.warnings += finding.warnings.len();
        counts.errors += usize::from(finding.error.is_some());
    }

    Ok(MermaidAuditReport {
        schema_version: 1,
        paths: paths
            .iter()
            .map(|path| path.display().to_string())
            .collect(),
        counts,
        findings,
    })
}

fn collect_mermaid_audit_files(path: &Path, files: &mut Vec<PathBuf>) -> Result<(), String> {
    if path.is_file() {
        if is_mermaid_audit_file(path) {
            files.push(path.to_owned());
        }
        return Ok(());
    }
    if !path.is_dir() {
        return Err(format!("audit path does not exist: {}", path.display()));
    }
    let mut entries = fs::read_dir(path)
        .map_err(|error| msg_args("error-read-dir", &[msg_arg("error", error)]))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| msg_args("error-read-dir", &[msg_arg("error", error)]))?;
    entries.sort_by_key(|entry| entry.path());
    for entry in entries {
        let child = entry.path();
        if child.is_dir() {
            if should_skip_audit_dir(&child) {
                continue;
            }
            collect_mermaid_audit_files(&child, files)?;
        } else if is_mermaid_audit_file(&child) {
            files.push(child);
        }
    }
    Ok(())
}

fn should_skip_audit_dir(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| matches!(name, ".git" | "node_modules" | "target" | ".playwright-cli"))
}

fn is_mermaid_audit_file(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(
                extension.to_ascii_lowercase().as_str(),
                "mmd" | "mermaid" | "md" | "mdx" | "markdown"
            )
        })
}

fn extract_mermaid_audit_sources(path: &Path, source: &str) -> Vec<MermaidAuditSource> {
    if path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(extension.to_ascii_lowercase().as_str(), "mmd" | "mermaid")
        })
    {
        return vec![MermaidAuditSource {
            path: path.to_owned(),
            line: 1,
            source_kind: "file",
            source: source.to_owned(),
        }];
    }
    extract_mermaid_fences(path, source)
}

fn extract_mermaid_fences(path: &Path, source: &str) -> Vec<MermaidAuditSource> {
    let mut blocks = Vec::new();
    let mut active: Option<(char, usize, String)> = None;
    for (line_index, line) in source.lines().enumerate() {
        let trimmed = line.trim_start();
        if let Some((marker, start_line, body)) = active.as_mut() {
            if is_closing_fence(trimmed, *marker) {
                blocks.push(MermaidAuditSource {
                    path: path.to_owned(),
                    line: *start_line,
                    source_kind: "markdown-fence",
                    source: body.clone(),
                });
                active = None;
            } else {
                body.push_str(line);
                body.push('\n');
            }
            continue;
        }
        if let Some((marker, info)) = opening_fence(trimmed)
            && is_mermaid_fence_info(info)
        {
            active = Some((marker, line_index + 1, String::new()));
        }
    }
    blocks
}

fn opening_fence(line: &str) -> Option<(char, &str)> {
    let marker = line.chars().next()?;
    if marker != '`' && marker != '~' {
        return None;
    }
    let count = line.chars().take_while(|char| *char == marker).count();
    (count >= 3).then(|| (marker, line[count..].trim()))
}

fn is_closing_fence(line: &str, marker: char) -> bool {
    line.chars().take_while(|char| *char == marker).count() >= 3
}

fn is_mermaid_fence_info(info: &str) -> bool {
    let first = info.split_whitespace().next().unwrap_or_default();
    matches!(
        first.trim_matches(|char| matches!(char, '{' | '}' | '.')),
        "mermaid" | "mmd"
    )
}

fn audit_mermaid_source(source: MermaidAuditSource) -> MermaidAuditFinding {
    let root = detect_mermaid_root(&source.source);
    let mut warnings = mermaid_audit_warnings(&source.source);
    match MermaidParser::parse_diagram(&source.source) {
        Ok(diagram) => {
            let support = diagram_support(&diagram.kind);
            let timeline_result = timeline_from_diagram_with_render_options(
                &diagram,
                AnimationOptions::default(),
                &RenderOptions::default(),
            );
            match timeline_result {
                Ok(timeline) => {
                    let frames = timeline.keyframes().len();
                    let svg = SvgRenderer::new(svg_config_for_diagram(
                        &RenderOptions::default(),
                        &diagram,
                    ))
                    .render_timeline(&timeline);
                    let render_ok = svg.contains("<svg") && svg.contains("</svg>");
                    if support == "animated-partial" && frames < 2 {
                        warnings.push("animated support produced fewer than two frames".to_owned());
                    }
                    if support == "static-only-partial" && frames != 1 {
                        warnings
                            .push("static-only support produced more than one frame".to_owned());
                    }
                    MermaidAuditFinding {
                        path: source.path.display().to_string(),
                        line: source.line,
                        source: source.source_kind,
                        root,
                        support,
                        parse_ok: true,
                        render_ok,
                        frames,
                        warnings,
                        error: (!render_ok)
                            .then(|| "SVG renderer did not emit an SVG document".to_owned()),
                        suggestion: None,
                    }
                }
                Err(error) => MermaidAuditFinding {
                    path: source.path.display().to_string(),
                    line: source.line,
                    source: source.source_kind,
                    root,
                    support,
                    parse_ok: true,
                    render_ok: false,
                    frames: 0,
                    warnings,
                    error: Some(error),
                    suggestion: Some(
                        "render this diagram with Mermaid.js until kumeyuri animation/layout support is extended",
                    ),
                },
            }
        }
        Err(error) => MermaidAuditFinding {
            path: source.path.display().to_string(),
            line: source.line,
            source: source.source_kind,
            root,
            support: "unsupported",
            parse_ok: false,
            render_ok: false,
            frames: 0,
            warnings,
            error: Some(format_parse_error(
                &source.source,
                error.kind,
                error.span.start,
                error.span.end,
            )),
            suggestion: parse_error_suggestion(error.kind),
        },
    }
}

fn detect_mermaid_root(source: &str) -> Option<String> {
    for raw_line in source.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with("%%") {
            continue;
        }
        if line == "---" || line.starts_with("title:") || line.starts_with("config:") {
            continue;
        }
        if line.starts_with("graph ") {
            return Some("graph".to_owned());
        }
        if line.starts_with("flowchart ") {
            return Some("flowchart".to_owned());
        }
        return line
            .split(|char: char| char.is_whitespace() || char == ':')
            .next()
            .filter(|root| !root.is_empty())
            .map(str::to_owned);
    }
    None
}

fn mermaid_audit_warnings(source: &str) -> Vec<String> {
    let mut warnings = Vec::new();
    let trimmed = source.trim_start();
    if trimmed.starts_with("---") {
        warnings.push("Mermaid frontmatter/config is outside kumeyuri parity; use CLI flags, element attributes, or site build config".to_owned());
    }
    if source.lines().any(|line| {
        let line = line.trim_start();
        line.starts_with("%%{")
            && (line.contains("init")
                || line.contains("config")
                || line.contains("theme")
                || line.contains("layout"))
    }) {
        warnings.push("Mermaid init/config/theme/layout directives are accepted as source directives but not interpreted except kumeyuri animate".to_owned());
    }
    if source.lines().any(|line| {
        let line = line.trim_start();
        line.starts_with("click ") || line.contains(" href ") || line.contains(" call ")
    }) {
        warnings.push(
            "Mermaid click/callback/link behavior is not executed by kumeyuri website embeds"
                .to_owned(),
        );
    }
    warnings
}

fn diagram_support(kind: &DiagramKind) -> &'static str {
    match kind {
        DiagramKind::Flowchart(_)
        | DiagramKind::Sequence(_)
        | DiagramKind::State(_)
        | DiagramKind::Class(_)
        | DiagramKind::Er(_)
        | DiagramKind::Gantt(_)
        | DiagramKind::Pie(_)
        | DiagramKind::Mindmap(_)
        | DiagramKind::Journey(_)
        | DiagramKind::GitGraph(_)
        | DiagramKind::Timeline(_) => "animated-partial",
        _ => "static-only-partial",
    }
}

fn format_parse_error(source: &str, kind: ParseErrorKind, start: usize, end: usize) -> String {
    let location = parse_error_location(source, start);
    let mut message = msg_args(
        "parse-error",
        &[
            msg_arg("kind", parse_error_kind_label(kind)),
            msg_arg("start", start),
            msg_arg("end", end),
        ],
    );
    message.push_str(&format!(
        " at line {}, column {}",
        location.line, location.column
    ));
    message
}

fn format_mermaid_audit_text(report: &MermaidAuditReport) -> String {
    let mut output = format!(
        "Mermaid audit: {} diagrams, {} parsed, {} rendered, {} warnings, {} errors\n",
        report.counts.diagrams,
        report.counts.parsed,
        report.counts.rendered,
        report.counts.warnings,
        report.counts.errors
    );
    for finding in &report.findings {
        output.push_str(&format!(
            "{}:{} {} {} frames={} parse={} render={}\n",
            finding.path,
            finding.line,
            finding.root.as_deref().unwrap_or("<unknown>"),
            finding.support,
            finding.frames,
            finding.parse_ok,
            finding.render_ok
        ));
        for warning in &finding.warnings {
            output.push_str("  warning: ");
            output.push_str(warning);
            output.push('\n');
        }
        if let Some(error) = &finding.error {
            output.push_str("  error: ");
            output.push_str(error.lines().next().unwrap_or(error));
            output.push('\n');
        }
        if let Some(suggestion) = finding.suggestion {
            output.push_str("  suggestion: ");
            output.push_str(suggestion);
            output.push('\n');
        }
    }
    output
}

fn lint_source(file: &str, source: &str) -> Result<LayoutReport, String> {
    let diagram = parse_diagram(source)?;
    let warnings = layout_warnings(&diagram, &RenderOptions::default());
    Ok(LayoutReport {
        file: file.to_owned(),
        ok: warnings.is_empty(),
        warnings,
    })
}

fn print_lint_report(report: &LayoutReport, json: bool) -> Result<(), String> {
    let output = if json {
        format!(
            "{}\n",
            serde_json::to_string_pretty(report).map_err(|error| msg_args(
                "error-encode-lint-report",
                &[msg_arg("error", error)]
            ))?
        )
    } else {
        format_lint_text(report)
    };
    io::stdout()
        .write_all(output.as_bytes())
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn format_lint_text(report: &LayoutReport) -> String {
    if report.warnings.is_empty() {
        return format!(
            "{}\n",
            msg_args("lint-ok", &[msg_arg("file", &report.file)])
        );
    }
    let mut output = String::new();
    for warning in &report.warnings {
        output.push_str(&msg_args(
            "lint-warning-line",
            &[
                msg_arg("file", &report.file),
                msg_arg("warning", warning.line()),
            ],
        ));
        output.push('\n');
    }
    output
}

fn layout_file(path: &Path, ai: bool, max_input_bytes: usize) -> Result<(), String> {
    if !ai {
        return Err(msg("layout-requires-ai"));
    }
    let source = read_source_file(path, max_input_bytes)?;
    let _diagram = parse_diagram(&source)?;
    let library_path = resolve_ai_library_path(|name| env::var_os(name))?;
    let version = load_ai_binding_version(&library_path)?;
    println!(
        "{}",
        msg_args(
            "layout-loaded-ai",
            &[
                msg_arg("version", version),
                msg_arg("path", library_path.display()),
            ],
        )
    );
    Ok(())
}

fn resolve_ai_library_path(
    mut lookup: impl FnMut(&str) -> Option<OsString>,
) -> Result<PathBuf, String> {
    lookup(KUMEYURI_AI_DYLIB_ENV)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| {
            msg_args(
                "layout-ai-env-required",
                &[msg_arg("env", KUMEYURI_AI_DYLIB_ENV)],
            )
        })
}

#[cfg(not(target_arch = "wasm32"))]
fn load_ai_binding_version(path: &Path) -> Result<u32, String> {
    unsafe {
        let library = libloading::Library::new(path).map_err(|error| {
            msg_args(
                "layout-ai-load",
                &[msg_arg("path", path.display()), msg_arg("error", error)],
            )
        })?;
        let abi_version = library
            .get::<unsafe extern "C" fn() -> u32>(b"kumeyuri_ai_abi_version\0")
            .map_err(|error| {
                msg_args(
                    "layout-ai-symbol",
                    &[msg_arg("path", path.display()), msg_arg("error", error)],
                )
            })?;
        let version = abi_version();
        if version != KUMEYURI_AI_ABI_VERSION {
            return Err(msg_args(
                "layout-ai-unsupported-abi",
                &[
                    msg_arg("version", version),
                    msg_arg("expected", KUMEYURI_AI_ABI_VERSION),
                ],
            ));
        }
        Ok(version)
    }
}

#[cfg(target_arch = "wasm32")]
fn load_ai_binding_version(_path: &Path) -> Result<u32, String> {
    Err(msg("layout-ai-wasm"))
}

fn run_plugin_command(command: PluginCommand) -> Result<(), String> {
    match command {
        PluginCommand::Install { name } => {
            let installed = install_plugin_package(&name)?;
            println!(
                "{}",
                msg_args(
                    "plugin-installed",
                    &[
                        msg_arg("name", &installed.package.name),
                        msg_arg("version", &installed.package.version),
                        msg_arg("registry", installed.package.registry),
                        msg_arg("path", installed.cache_dir.display()),
                    ],
                )
            );
            Ok(())
        }
        PluginCommand::List => list_plugin_packages(),
        PluginCommand::Remove { name } => remove_plugin_package(&name),
        PluginCommand::Update { name } => {
            let installed = install_plugin_package(&name)?;
            println!(
                "{}",
                msg_args(
                    "plugin-updated",
                    &[
                        msg_arg("name", &installed.package.name),
                        msg_arg("version", &installed.package.version),
                        msg_arg("registry", installed.package.registry),
                        msg_arg("path", installed.cache_dir.display()),
                    ],
                )
            );
            Ok(())
        }
        PluginCommand::Disable { name } => disable_plugin_package(&name),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PluginRegistry {
    Npm,
    CratesIo,
}

impl std::fmt::Display for PluginRegistry {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Npm => formatter.write_str("npm"),
            Self::CratesIo => formatter.write_str("crates.io"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ResolvedPluginPackage {
    registry: PluginRegistry,
    name: String,
    version: String,
    archive_url: String,
    content_hash: String,
    archive_file: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct InstalledPluginPackage {
    package: ResolvedPluginPackage,
    cache_dir: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct PluginInstallRecord {
    registry: String,
    name: String,
    version: String,
    archive_url: String,
    content_hash: String,
    archive_file: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct InstalledPluginRecord {
    cache_dir: PathBuf,
    record: PluginInstallRecord,
    disabled: bool,
}

fn install_plugin_package(name: &str) -> Result<InstalledPluginPackage, String> {
    let package = resolve_plugin_package(name)?;
    let cache = PluginCache::from_env().map_err(|error| {
        msg_args(
            "plugin-cache-error",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })?;
    let cache_dir = cache
        .package_dir_for(
            &package.name,
            &package.version,
            KUMEYURI_ABI_VERSION.major,
            &package.content_hash,
        )
        .map_err(|error| {
            msg_args(
                "plugin-cache-error",
                &[msg_arg("error", format!("{error:?}"))],
            )
        })?;
    fs::create_dir_all(&cache_dir).map_err(|error| {
        msg_args(
            "error-create-dir",
            &[
                msg_arg("path", cache_dir.display()),
                msg_arg("error", error),
            ],
        )
    })?;
    let archive = fetch_url_bytes(&package.archive_url)?;
    fs::write(cache_dir.join(package.archive_file), archive)
        .map_err(|error| msg_args("plugin-write-archive", &[msg_arg("error", error)]))?;
    fs::write(
        cache_dir.join("source.txt"),
        format!(
            "registry={}\nname={}\nversion={}\nurl={}\n",
            package.registry, package.name, package.version, package.archive_url
        ),
    )
    .map_err(|error| msg_args("plugin-write-source-metadata", &[msg_arg("error", error)]))?;
    write_plugin_install_record(&cache_dir, &package)?;

    Ok(InstalledPluginPackage { package, cache_dir })
}

fn list_plugin_packages() -> Result<(), String> {
    let cache = PluginCache::from_env().map_err(|error| {
        msg_args(
            "plugin-cache-error",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })?;
    let records = read_installed_plugin_records(cache.root())?;
    if records.is_empty() {
        println!("{}", msg("plugin-no-installed"));
        return Ok(());
    }
    for installed in records {
        let suffix = if installed.disabled {
            msg("plugin-list-disabled-suffix")
        } else {
            String::new()
        };
        println!(
            "{}",
            msg_args(
                "plugin-list-entry",
                &[
                    msg_arg("name", &installed.record.name),
                    msg_arg("version", &installed.record.version),
                    msg_arg("registry", &installed.record.registry),
                    msg_arg("suffix", suffix),
                ],
            )
        );
    }
    Ok(())
}

fn remove_plugin_package(name: &str) -> Result<(), String> {
    let cache = PluginCache::from_env().map_err(|error| {
        msg_args(
            "plugin-cache-error",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })?;
    let removed = remove_plugin_records(cache.root(), name)?;
    println!(
        "{}",
        msg_args(
            "plugin-removed",
            &[msg_arg("count", removed), msg_arg("name", name)],
        )
    );
    Ok(())
}

fn disable_plugin_package(name: &str) -> Result<(), String> {
    let cache = PluginCache::from_env().map_err(|error| {
        msg_args(
            "plugin-cache-error",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })?;
    let disabled = disable_plugin_records(cache.root(), name)?;
    println!(
        "{}",
        msg_args(
            "plugin-disabled",
            &[msg_arg("count", disabled), msg_arg("name", name)],
        )
    );
    Ok(())
}

fn write_plugin_install_record(
    cache_dir: &Path,
    package: &ResolvedPluginPackage,
) -> Result<(), String> {
    let record = PluginInstallRecord {
        registry: package.registry.to_string(),
        name: package.name.clone(),
        version: package.version.clone(),
        archive_url: package.archive_url.clone(),
        content_hash: package.content_hash.clone(),
        archive_file: package.archive_file.to_owned(),
    };
    let json = serde_json::to_string_pretty(&record)
        .map_err(|error| msg_args("plugin-encode-install-metadata", &[msg_arg("error", error)]))?;
    fs::write(cache_dir.join("install.json"), format!("{json}\n"))
        .map_err(|error| msg_args("plugin-write-install-metadata", &[msg_arg("error", error)]))
}

fn read_installed_plugin_records(root: &Path) -> Result<Vec<InstalledPluginRecord>, String> {
    let mut records = Vec::new();
    if !root.exists() {
        return Ok(records);
    }
    collect_installed_plugin_records(root, &mut records)?;
    records.sort_by(|left, right| {
        left.record
            .name
            .cmp(&right.record.name)
            .then_with(|| left.record.version.cmp(&right.record.version))
            .then_with(|| left.cache_dir.cmp(&right.cache_dir))
    });
    Ok(records)
}

fn collect_installed_plugin_records(
    dir: &Path,
    records: &mut Vec<InstalledPluginRecord>,
) -> Result<(), String> {
    let record_path = dir.join("install.json");
    if record_path.is_file() {
        let record_source = fs::read_to_string(&record_path).map_err(|error| {
            msg_args(
                "error-read-path",
                &[
                    msg_arg("path", record_path.display()),
                    msg_arg("error", error),
                ],
            )
        })?;
        let record: PluginInstallRecord =
            serde_json::from_str(&record_source).map_err(|error| {
                msg_args(
                    "plugin-invalid-install-metadata",
                    &[msg_arg("error", error)],
                )
            })?;
        records.push(InstalledPluginRecord {
            cache_dir: dir.to_path_buf(),
            record,
            disabled: dir.join(".disabled").exists(),
        });
        return Ok(());
    }
    for entry in
        fs::read_dir(dir).map_err(|error| msg_args("error-read-dir", &[msg_arg("error", error)]))?
    {
        let entry =
            entry.map_err(|error| msg_args("error-read-dir-entry", &[msg_arg("error", error)]))?;
        if entry
            .file_type()
            .map_err(|error| msg_args("error-read-file-type", &[msg_arg("error", error)]))?
            .is_dir()
        {
            collect_installed_plugin_records(&entry.path(), records)?;
        }
    }
    Ok(())
}

fn remove_plugin_records(root: &Path, name: &str) -> Result<usize, String> {
    let records = read_installed_plugin_records(root)?;
    let mut removed = 0;
    for installed in records
        .into_iter()
        .filter(|installed| installed.record.name == name)
    {
        fs::remove_dir_all(&installed.cache_dir).map_err(|error| {
            msg_args(
                "plugin-remove-path",
                &[
                    msg_arg("path", installed.cache_dir.display()),
                    msg_arg("error", error),
                ],
            )
        })?;
        removed += 1;
    }
    if removed == 0 {
        return Err(msg_args("plugin-not-installed", &[msg_arg("name", name)]));
    }
    Ok(removed)
}

fn disable_plugin_records(root: &Path, name: &str) -> Result<usize, String> {
    let records = read_installed_plugin_records(root)?;
    let mut disabled = 0;
    for installed in records
        .into_iter()
        .filter(|installed| installed.record.name == name)
    {
        fs::write(installed.cache_dir.join(".disabled"), b"").map_err(|error| {
            msg_args(
                "plugin-disable",
                &[msg_arg("name", name), msg_arg("error", error)],
            )
        })?;
        disabled += 1;
    }
    if disabled == 0 {
        return Err(msg_args("plugin-not-installed", &[msg_arg("name", name)]));
    }
    Ok(disabled)
}

fn resolve_plugin_package(name: &str) -> Result<ResolvedPluginPackage, String> {
    let npm_error = match resolve_npm_plugin(name) {
        Ok(package) => return Ok(package),
        Err(error) => error,
    };
    let crates_error = match resolve_crates_plugin(name) {
        Ok(package) => return Ok(package),
        Err(error) => error,
    };
    Err(msg_args(
        "plugin-resolve",
        &[
            msg_arg("name", name),
            msg_arg("keyword", PLUGIN_KEYWORD),
            msg_arg("npm_error", npm_error),
            msg_arg("crates_error", crates_error),
        ],
    ))
}

fn resolve_npm_plugin(name: &str) -> Result<ResolvedPluginPackage, String> {
    resolve_npm_plugin_metadata(
        name,
        &fetch_url_string(
            &format!(
                "https://registry.npmjs.org/{}",
                encode_url_path_component(name)
            ),
            Some("application/vnd.npm.install-v1+json"),
        )?,
    )
}

fn resolve_crates_plugin(name: &str) -> Result<ResolvedPluginPackage, String> {
    resolve_crates_plugin_metadata(
        name,
        &fetch_url_string(
            &format!(
                "https://crates.io/api/v1/crates/{}",
                encode_url_path_component(name)
            ),
            Some("application/json"),
        )?,
    )
}

fn resolve_npm_plugin_metadata(name: &str, source: &str) -> Result<ResolvedPluginPackage, String> {
    let metadata: NpmPackageMetadata = serde_json::from_str(source)
        .map_err(|error| msg_args("plugin-invalid-npm-metadata", &[msg_arg("error", error)]))?;
    let latest = metadata
        .dist_tags
        .get("latest")
        .ok_or_else(|| msg("plugin-npm-no-latest"))?;
    let version = metadata
        .versions
        .get(latest)
        .ok_or_else(|| msg_args("plugin-npm-latest-missing", &[msg_arg("version", latest)]))?;
    let keywords = if version.keywords.is_empty() {
        &metadata.keywords
    } else {
        &version.keywords
    };
    if !has_plugin_keyword(keywords) {
        return Err(msg_args(
            "plugin-npm-missing-keyword",
            &[msg_arg("keyword", PLUGIN_KEYWORD)],
        ));
    }
    let content_hash = version
        .dist
        .shasum
        .as_deref()
        .filter(|value| is_hex(value))
        .ok_or_else(|| msg("plugin-npm-no-shasum"))?;

    Ok(ResolvedPluginPackage {
        registry: PluginRegistry::Npm,
        name: metadata.name.unwrap_or_else(|| name.to_owned()),
        version: latest.clone(),
        archive_url: version.dist.tarball.clone(),
        content_hash: content_hash.to_owned(),
        archive_file: "package.tgz",
    })
}

fn resolve_crates_plugin_metadata(
    name: &str,
    source: &str,
) -> Result<ResolvedPluginPackage, String> {
    let metadata: CratesPackageMetadata = serde_json::from_str(source)
        .map_err(|error| msg_args("plugin-invalid-crates-metadata", &[msg_arg("error", error)]))?;
    if !has_plugin_keyword(&metadata.krate.keywords) {
        return Err(msg_args(
            "plugin-crate-missing-keyword",
            &[msg_arg("keyword", PLUGIN_KEYWORD)],
        ));
    }
    let version_number = metadata
        .krate
        .max_version
        .or(metadata.krate.default_version)
        .ok_or_else(|| msg("plugin-crate-no-version"))?;
    let version = metadata
        .versions
        .iter()
        .find(|version| version.num == version_number && !version.yanked)
        .ok_or_else(|| {
            msg_args(
                "plugin-crate-version-missing",
                &[msg_arg("version", &version_number)],
            )
        })?;
    if !is_hex(&version.checksum) {
        return Err(msg("plugin-crate-checksum-not-hex"));
    }
    let archive_url = if version.dl_path.starts_with("https://") {
        version.dl_path.clone()
    } else {
        format!("https://crates.io{}", version.dl_path)
    };

    Ok(ResolvedPluginPackage {
        registry: PluginRegistry::CratesIo,
        name: metadata.krate.name.unwrap_or_else(|| name.to_owned()),
        version: version.num.clone(),
        archive_url,
        content_hash: version.checksum.clone(),
        archive_file: "package.crate",
    })
}

#[derive(Debug, Deserialize)]
struct NpmPackageMetadata {
    name: Option<String>,
    #[serde(rename = "dist-tags")]
    dist_tags: BTreeMap<String, String>,
    #[serde(default)]
    keywords: Vec<String>,
    versions: BTreeMap<String, NpmVersionMetadata>,
}

#[derive(Debug, Deserialize)]
struct NpmVersionMetadata {
    #[serde(default)]
    keywords: Vec<String>,
    dist: NpmDistMetadata,
}

#[derive(Debug, Deserialize)]
struct NpmDistMetadata {
    tarball: String,
    shasum: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CratesPackageMetadata {
    #[serde(rename = "crate")]
    krate: CrateSummaryMetadata,
    versions: Vec<CrateVersionMetadata>,
}

#[derive(Debug, Deserialize)]
struct CrateSummaryMetadata {
    name: Option<String>,
    max_version: Option<String>,
    default_version: Option<String>,
    #[serde(default)]
    keywords: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct CrateVersionMetadata {
    num: String,
    checksum: String,
    yanked: bool,
    dl_path: String,
}

fn fetch_url_string(url: &str, accept: Option<&str>) -> Result<String, String> {
    let mut request = ureq::get(url).header("User-Agent", KUMEYURI_USER_AGENT);
    if let Some(accept) = accept {
        request = request.header("Accept", accept);
    }
    request
        .call()
        .map_err(|error| msg_args("http-get", &[msg_arg("url", url), msg_arg("error", error)]))?
        .body_mut()
        .read_to_string()
        .map_err(|error| msg_args("http-read", &[msg_arg("url", url), msg_arg("error", error)]))
}

fn fetch_url_bytes(url: &str) -> Result<Vec<u8>, String> {
    ureq::get(url)
        .header("User-Agent", KUMEYURI_USER_AGENT)
        .call()
        .map_err(|error| msg_args("http-get", &[msg_arg("url", url), msg_arg("error", error)]))?
        .body_mut()
        .read_to_vec()
        .map_err(|error| msg_args("http-read", &[msg_arg("url", url), msg_arg("error", error)]))
}

fn read_bytes_file(path: &Path, max_input_bytes: usize) -> Result<Vec<u8>, String> {
    let file = fs::File::open(path).map_err(|error| {
        msg_args(
            "error-read-path",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })?;
    let mut bytes = Vec::new();
    file.take(u64::try_from(max_input_bytes.saturating_add(1)).unwrap_or(u64::MAX))
        .read_to_end(&mut bytes)
        .map_err(|error| {
            msg_args(
                "error-read-path",
                &[msg_arg("path", path.display()), msg_arg("error", error)],
            )
        })?;
    if bytes.len() > max_input_bytes {
        return Err(msg_args(
            "error-input-too-large",
            &[
                msg_arg("path", path.display()),
                msg_arg("bytes", bytes.len()),
                msg_arg("limit", max_input_bytes),
            ],
        ));
    }
    Ok(bytes)
}

fn read_source_file(path: &Path, max_input_bytes: usize) -> Result<String, String> {
    let bytes = read_bytes_file(path, max_input_bytes)?;
    String::from_utf8(bytes).map_err(|error| {
        msg_args(
            "error-read-utf8",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })
}

fn read_playback_file_source(path: &Path, max_input_bytes: usize) -> Result<String, String> {
    if is_kumecast_gz_path(path) {
        return read_cast_source_file(path, max_input_bytes);
    }
    read_source_file(path, max_input_bytes)
}

fn read_cast_source_file(path: &Path, max_input_bytes: usize) -> Result<String, String> {
    if !is_kumecast_gz_path(path) {
        return read_source_file(path, max_input_bytes);
    }
    let bytes = read_bytes_file(path, max_input_bytes)?;
    decode_gzip_bytes(&bytes, max_input_bytes)
}

fn decode_gzip_bytes(bytes: &[u8], max_output_bytes: usize) -> Result<String, String> {
    let mut decoded = Vec::new();
    GzDecoder::new(bytes)
        .take(u64::try_from(max_output_bytes.saturating_add(1)).unwrap_or(u64::MAX))
        .read_to_end(&mut decoded)
        .map_err(|error| format!("invalid gzip stream: {error}"))?;
    if decoded.len() > max_output_bytes {
        return Err(format!(
            "decompressed kumecast is too large: {} bytes exceeds limit {}",
            decoded.len(),
            max_output_bytes
        ));
    }
    String::from_utf8(decoded).map_err(|error| format!("invalid kumecast UTF-8: {error}"))
}

fn validate_theme_file(path: &Path, max_input_bytes: usize) -> Result<(), String> {
    load_valid_theme_file(path, max_input_bytes)?;
    println!(
        "{}",
        msg_args("theme-valid", &[msg_arg("path", path.display())])
    );
    Ok(())
}

fn load_valid_theme_file(path: &Path, max_input_bytes: usize) -> Result<KumethemeToml, String> {
    let source = read_source_file(path, max_input_bytes)?;
    let theme: KumethemeToml = toml::from_str(&source).map_err(|error| {
        msg_args(
            "theme-invalid-toml",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })?;
    theme.validate().map_err(|error| {
        msg_args(
            "theme-invalid-schema",
            &[
                msg_arg("path", path.display()),
                msg_arg("error", format_theme_error(&error)),
            ],
        )
    })?;
    Ok(theme)
}

fn load_render_theme_file(path: &Path, max_input_bytes: usize) -> Result<Theme, String> {
    let theme = load_valid_theme_file(path, max_input_bytes)?
        .to_theme()
        .map_err(|error| {
            msg_args(
                "theme-invalid-schema",
                &[
                    msg_arg("path", path.display()),
                    msg_arg("error", format_theme_error(&error)),
                ],
            )
        })?;
    Ok(Theme {
        name: "custom",
        charset: theme.charset,
        colors: theme.colors,
    })
}

fn format_theme_error(error: &KumethemeError) -> String {
    match error {
        KumethemeError::InvalidName(name) => {
            format!("invalid name `{name}`: expected kebab-case ASCII identifier")
        }
        KumethemeError::InvalidHexColor { field, value } => {
            format!("invalid color `{field}` = `{value}`: expected #RRGGBB")
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct ThemeIndex {
    version: u32,
    base_url: String,
    #[serde(default)]
    themes: Vec<ThemeIndexEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ThemeIndexEntry {
    name: String,
    charset: String,
    url: String,
    colors: KumethemeColors,
}

fn run_theme_command(command: ThemeCommand, max_input_bytes: usize) -> Result<(), String> {
    match command {
        ThemeCommand::List => {
            print!("{}", format_theme_list(&theme_entries_for_current_dir()?));
            Ok(())
        }
        ThemeCommand::Show { name } => {
            print!(
                "{}",
                show_theme(&name, &theme_entries_for_current_dir()?, max_input_bytes)?
            );
            Ok(())
        }
        ThemeCommand::New { file, name } => write_theme_template(&file, name.as_deref()),
        ThemeCommand::Validate { file } => validate_theme_file(&file, max_input_bytes),
        ThemeCommand::Publish {
            file,
            index_dir,
            base_url,
        } => publish_theme_file(&file, &index_dir, &base_url, max_input_bytes),
    }
}

fn theme_entries_for_current_dir() -> Result<Vec<ThemeSearchEntry>, String> {
    let current_dir = env::current_dir()
        .map_err(|error| msg_args("theme-current-dir", &[msg_arg("error", error)]))?;
    let paths = ThemeSearchPaths::from_env(current_dir, |name| env::var(name).ok());
    Ok(discover_themes(&paths))
}

fn format_theme_list(entries: &[ThemeSearchEntry]) -> String {
    entries
        .iter()
        .map(|entry| format!("{}\t{}\n", entry.name, theme_source_label(&entry.source)))
        .collect()
}

fn show_theme(
    name: &str,
    entries: &[ThemeSearchEntry],
    max_input_bytes: usize,
) -> Result<String, String> {
    let entry = entries
        .iter()
        .find(|entry| entry.name == name)
        .ok_or_else(|| msg_args("theme-not-found", &[msg_arg("name", name)]))?;
    match &entry.source {
        ThemeSource::Bundled(theme) => Ok(format_kumetheme_toml(&kumetheme_from_built_in(*theme))),
        ThemeSource::Project(path)
        | ThemeSource::XdgDataHome(path)
        | ThemeSource::XdgDataDir(path) => Ok(format_kumetheme_toml(&load_valid_theme_file(
            path,
            max_input_bytes,
        )?)),
    }
}

fn write_theme_template(path: &Path, name: Option<&str>) -> Result<(), String> {
    if path.exists() {
        return Err(msg_args(
            "theme-new-exists",
            &[msg_arg("path", path.display())],
        ));
    }
    let name = name
        .map(ToOwned::to_owned)
        .or_else(|| {
            path.file_name()
                .and_then(|file_name| file_name.to_str())
                .and_then(|file_name| file_name.strip_suffix(".kumetheme.toml"))
                .map(ToOwned::to_owned)
        })
        .unwrap_or_else(|| "custom-theme".to_owned());
    let theme = KumethemeToml {
        name,
        charset: KumethemeCharset::Unicode,
        colors: KumethemeColors {
            background: "#101418".to_owned(),
            foreground: "#e6edf3".to_owned(),
            accent: "#58a6ff".to_owned(),
            edge: "#8b949e".to_owned(),
            edge_alt: "#d2a8ff".to_owned(),
            highlight: "#f2cc60".to_owned(),
            muted: "#7d8590".to_owned(),
        },
    };
    theme.validate().map_err(|error| {
        msg_args(
            "theme-invalid-schema",
            &[
                msg_arg("path", path.display()),
                msg_arg("error", format_theme_error(&error)),
            ],
        )
    })?;
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent).map_err(|error| {
            msg_args(
                "error-create-dir",
                &[msg_arg("path", parent.display()), msg_arg("error", error)],
            )
        })?;
    }
    fs::write(path, format_kumetheme_toml(&theme)).map_err(|error| {
        msg_args(
            "theme-new-write",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })?;
    println!(
        "{}",
        msg_args("theme-new-created", &[msg_arg("path", path.display())])
    );
    Ok(())
}

fn publish_theme_file(
    path: &Path,
    index_dir: &Path,
    base_url: &str,
    max_input_bytes: usize,
) -> Result<(), String> {
    let theme = load_valid_theme_file(path, max_input_bytes)?;
    let theme_dir = index_dir.join("themes");
    fs::create_dir_all(&theme_dir).map_err(|error| {
        msg_args(
            "error-create-dir",
            &[
                msg_arg("path", theme_dir.display()),
                msg_arg("error", error),
            ],
        )
    })?;
    let theme_file = theme_dir.join(format!("{}.kumetheme.toml", theme.name));
    fs::write(&theme_file, format_kumetheme_toml(&theme)).map_err(|error| {
        msg_args(
            "theme-publish-write-theme",
            &[
                msg_arg("path", theme_file.display()),
                msg_arg("error", error),
            ],
        )
    })?;

    let index_path = index_dir.join("index.json");
    let mut index = read_theme_index(&index_path)?;
    index.version = THEME_INDEX_VERSION;
    index.base_url = base_url.trim_end_matches('/').to_owned();
    let entry = ThemeIndexEntry {
        name: theme.name.clone(),
        charset: theme_charset_name(theme.charset).to_owned(),
        url: format!(
            "{}/themes/{}.kumetheme.toml",
            index.base_url,
            encode_url_path_component(&theme.name)
        ),
        colors: theme.colors.clone(),
    };
    index.themes.retain(|existing| existing.name != entry.name);
    index.themes.push(entry);
    index
        .themes
        .sort_by(|left, right| left.name.cmp(&right.name));
    let mut json = serde_json::to_string_pretty(&index)
        .map_err(|error| msg_args("theme-publish-encode-index", &[msg_arg("error", error)]))?;
    json.push('\n');
    fs::write(&index_path, json).map_err(|error| {
        msg_args(
            "theme-publish-write-index",
            &[
                msg_arg("path", index_path.display()),
                msg_arg("error", error),
            ],
        )
    })?;
    println!(
        "{}",
        msg_args(
            "theme-published",
            &[
                msg_arg("name", theme.name),
                msg_arg("path", index_path.display()),
            ],
        )
    );
    Ok(())
}

fn read_theme_index(path: &Path) -> Result<ThemeIndex, String> {
    if !path.exists() {
        return Ok(ThemeIndex {
            version: THEME_INDEX_VERSION,
            base_url: DEFAULT_THEME_INDEX_BASE_URL.to_owned(),
            themes: Vec::new(),
        });
    }
    let source = fs::read_to_string(path).map_err(|error| {
        msg_args(
            "error-read-path",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })?;
    serde_json::from_str(&source).map_err(|error| {
        msg_args(
            "theme-publish-invalid-index",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })
}

fn theme_source_label(source: &ThemeSource) -> &'static str {
    match source {
        ThemeSource::Project(_) => "project",
        ThemeSource::XdgDataHome(_) => "xdg-data-home",
        ThemeSource::XdgDataDir(_) => "xdg-data-dir",
        ThemeSource::Bundled(_) => "bundled",
    }
}

fn kumetheme_from_built_in(theme: BuiltInTheme) -> KumethemeToml {
    let theme = theme.theme();
    KumethemeToml {
        name: theme.name.to_owned(),
        charset: match theme.charset {
            Charset::Ascii => KumethemeCharset::Ascii,
            Charset::Unicode => KumethemeCharset::Unicode,
        },
        colors: KumethemeColors {
            background: rgb_hex(theme.colors.background),
            foreground: rgb_hex(theme.colors.foreground),
            accent: rgb_hex(theme.colors.accent),
            edge: rgb_hex(theme.colors.edge),
            edge_alt: rgb_hex(theme.colors.edge_alt),
            highlight: rgb_hex(theme.colors.highlight),
            muted: rgb_hex(theme.colors.muted),
        },
    }
}

fn format_kumetheme_toml(theme: &KumethemeToml) -> String {
    format!(
        "name = \"{}\"\ncharset = \"{}\"\n\n[colors]\nbackground = \"{}\"\nforeground = \"{}\"\naccent = \"{}\"\nedge = \"{}\"\nedge_alt = \"{}\"\nhighlight = \"{}\"\nmuted = \"{}\"\n",
        theme.name,
        theme_charset_name(theme.charset),
        theme.colors.background,
        theme.colors.foreground,
        theme.colors.accent,
        theme.colors.edge,
        theme.colors.edge_alt,
        theme.colors.highlight,
        theme.colors.muted,
    )
}

fn theme_charset_name(charset: KumethemeCharset) -> &'static str {
    match charset {
        KumethemeCharset::Ascii => "ascii",
        KumethemeCharset::Unicode => "unicode",
    }
}

fn rgb_hex(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

fn has_plugin_keyword(keywords: &[String]) -> bool {
    keywords.iter().any(|keyword| keyword == PLUGIN_KEYWORD)
}

fn is_hex(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn encode_url_path_component(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            encoded.push(char::from(byte));
        } else {
            encoded.push('%');
            encoded.push(hex_digit(byte >> 4));
            encoded.push(hex_digit(byte & 0x0f));
        }
    }
    encoded
}

fn hex_digit(value: u8) -> char {
    match value {
        0..=9 => char::from(b'0' + value),
        10..=15 => char::from(b'A' + value - 10),
        _ => unreachable!("hex digit input is masked to four bits"),
    }
}

fn render_source(
    source: &str,
    format: RenderFormat,
    options: &RenderOptions,
) -> Result<Vec<u8>, String> {
    validate_render_options(format, options)?;
    if options.narrate {
        return Ok(render_narration_source(source)?.into_bytes());
    }
    if options.alt_text {
        return Ok(render_alt_text_source(source)?.into_bytes());
    }
    match format {
        RenderFormat::Text => Ok(render_text_source(source, options)?.into_bytes()),
        RenderFormat::Svg => Ok(render_svg_source(source, options)?.into_bytes()),
        RenderFormat::Gif => render_raster_source(source, options, RasterRenderer::render_gif),
        RenderFormat::Apng => render_raster_source(source, options, RasterRenderer::render_apng),
        RenderFormat::Webp => render_raster_source(source, options, RasterRenderer::render_webp),
        RenderFormat::Vtt => Ok(render_vtt_source(source, options)?.into_bytes()),
        RenderFormat::Tui => Err(msg("render-tui-interactive")),
    }
}

fn export_source(
    source: &str,
    format: ExportFormat,
    options: &RenderOptions,
) -> Result<Vec<u8>, String> {
    match format {
        ExportFormat::Kumecast => Ok(render_kumecast_source(source, options)?.into_bytes()),
        ExportFormat::KumecastGz => gzip_bytes(render_kumecast_source(source, options)?.as_bytes()),
    }
}

fn gzip_bytes(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(bytes)
        .map_err(|error| format!("failed to encode gzip: {error}"))?;
    encoder
        .finish()
        .map_err(|error| format!("failed to finish gzip stream: {error}"))
}

fn convert_cast_source(source: &str, format: ConvertFormat) -> Result<Vec<u8>, String> {
    let cast = Kumecast::from_json_str(source).map_err(|error| error.to_string())?;
    let timeline = cast.to_timeline().map_err(|error| error.to_string())?;
    match format {
        ConvertFormat::Text => Ok(render_cast_text(&timeline).into_bytes()),
        ConvertFormat::Svg => Ok(SvgRenderer::default()
            .render_timeline(&timeline)
            .into_bytes()),
        ConvertFormat::Gif => RasterRenderer::default()
            .render_gif(&timeline)
            .map_err(|error| {
                msg_args(
                    "render-raster-error",
                    &[msg_arg("error", format!("{error:?}"))],
                )
            }),
    }
}

fn validate_render_options(format: RenderFormat, options: &RenderOptions) -> Result<(), String> {
    if options.narrate && options.alt_text {
        return Err("--narrate and --alt-text cannot be used together".to_owned());
    }
    if (options.narrate || options.alt_text) && format != RenderFormat::Text {
        return Err("--narrate and --alt-text cannot be combined with --format".to_owned());
    }
    if !options.narrate
        && !options.alt_text
        && options.dark_theme.is_some()
        && format != RenderFormat::Svg
    {
        return Err(msg("render-dark-theme-svg-only"));
    }
    let _plugin_policy = plugin_runtime_policy(options);
    Ok(())
}

fn plugin_runtime_policy(options: &RenderOptions) -> PluginRuntimePolicy {
    let mut grants = options.plugin_allow.unwrap_or_default();
    if options.allow_external {
        grants.insert(Capability::NetFetch);
    }
    PluginRuntimePolicy::with_grants(grants)
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
    let diagram = parse_diagram(source)?;
    let timeline =
        timeline_from_diagram_with_render_options(&diagram, AnimationOptions::default(), options)?;
    Ok(SvgRenderer::new(svg_config_for_diagram(options, &diagram)).render_timeline(&timeline))
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
    render(&raster_renderer(options)?, &timeline).map_err(|error| {
        msg_args(
            "render-raster-error",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })
}

fn render_vtt_source(source: &str, options: &RenderOptions) -> Result<String, String> {
    let timeline =
        timeline_from_source_with_render_options(source, AnimationOptions::default(), options)?;
    Ok(render_timeline_vtt(&timeline))
}

fn render_cast_text(timeline: &Timeline) -> String {
    let text = TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: true,
        final_newline: false,
    });
    let mut output = String::new();
    for (index, keyframe) in timeline.keyframes().iter().enumerate() {
        output.push_str(&format!(
            "frame:{index}:duration_ms:{}\n",
            keyframe.duration().as_millis()
        ));
        output.push_str(&text.render_frame(keyframe.frame()));
        output.push('\n');
    }
    output
}

fn render_kumecast_source(source: &str, options: &RenderOptions) -> Result<String, String> {
    if options.narrate || options.alt_text {
        return Err("--narrate and --alt-text cannot be used with export".to_owned());
    }
    if options.dark_theme.is_some() {
        return Err(msg("render-dark-theme-svg-only"));
    }
    let diagram = parse_diagram(source)?;
    let timeline =
        timeline_from_diagram_with_render_options(&diagram, AnimationOptions::default(), options)?;
    let cast = Kumecast::from_timeline(
        diagram_kind_id(&diagram.kind),
        source,
        render_theme(options),
        &timeline,
    );
    cast.to_json_string()
        .map_err(|error| format!("failed to encode kumecast: {error}"))
}

fn render_narration_source(source: &str) -> Result<String, String> {
    let diagram = parse_diagram(source)?;
    Ok(format!("{}\n", narrate_diagram(&diagram)))
}

fn render_alt_text_source(source: &str) -> Result<String, String> {
    let diagram = parse_diagram(source)?;
    Ok(format!("{}\n", alt_text_for_diagram(&diagram)))
}

fn frame_renderer(options: &RenderOptions) -> StaticFrameRenderer {
    let renderer = StaticFrameRenderer::default().with_theme(render_theme(options));
    let Some(max_label_width) = options.max_label_width else {
        return renderer;
    };
    renderer.with_flow_layout_config(FlowLayoutConfig {
        max_label_width: Some(i32::try_from(max_label_width).unwrap_or(i32::MAX)),
        ..FlowLayoutConfig::default()
    })
}

fn render_theme(options: &RenderOptions) -> Theme {
    if let Some(theme) = options.custom_theme {
        return theme;
    }
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

fn svg_config_for_diagram(options: &RenderOptions, diagram: &Diagram) -> SvgRenderConfig {
    let mut config = svg_config(options);
    if let Some(title) = &diagram.metadata.accessibility_title {
        config.title = title.text.clone();
    }
    if let Some(description) = &diagram.metadata.accessibility_description {
        config.description = description.text.clone();
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
    .map_err(|error| {
        msg_args(
            "render-invalid-raster-options",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })
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

fn play_file(
    path: &Path,
    options: AnimationOptions,
    max_input_bytes: usize,
    debug: bool,
) -> Result<(), String> {
    let source = read_playback_file_source(path, max_input_bytes)?;
    let timeline = playback_timeline_from_source(&source, options, is_kumecast_path(path))?;
    play_timeline(&timeline, debug)
}

fn is_kumecast_path(path: &Path) -> bool {
    is_kumecast_gz_path(path)
        || path
            .extension()
            .and_then(|extension| extension.to_str())
            .is_some_and(|extension| extension == "kumecast")
}

fn is_kumecast_gz_path(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension == "gz")
        && path
            .file_name()
            .and_then(|file_name| file_name.to_str())
            .is_some_and(|file_name| file_name.ends_with(".kumecast.gz"))
}

#[cfg(not(target_arch = "wasm32"))]
fn watch_file(
    path: &Path,
    theme_file: Option<&Path>,
    max_input_bytes: usize,
) -> Result<(), String> {
    let watch_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    let theme_path =
        theme_file.map(|path| path.canonicalize().unwrap_or_else(|_| path.to_path_buf()));
    redraw_watched_file(&watch_path, theme_path.as_deref(), max_input_bytes)?;

    let (tx, rx) = std::sync::mpsc::channel();
    let mut watcher = RecommendedWatcher::new(
        move |event| {
            let _ = tx.send(event);
        },
        NotifyConfig::default(),
    )
    .map_err(|error| msg_args("watch-create", &[msg_arg("error", error)]))?;
    watcher
        .watch(&watch_path, RecursiveMode::NonRecursive)
        .map_err(|error| {
            msg_args(
                "watch-path",
                &[
                    msg_arg("path", watch_path.display()),
                    msg_arg("error", error),
                ],
            )
        })?;
    if let Some(theme_path) = &theme_path {
        watcher
            .watch(theme_path, RecursiveMode::NonRecursive)
            .map_err(|error| {
                msg_args(
                    "watch-path",
                    &[
                        msg_arg("path", theme_path.display()),
                        msg_arg("error", error),
                    ],
                )
            })?;
    }
    let watch_targets = std::iter::once(watch_path.clone())
        .chain(theme_path.iter().cloned())
        .collect::<Vec<_>>();

    for event in rx {
        match event {
            Ok(event) if should_rerender_any(&event, &watch_targets) => {
                redraw_watched_file(&watch_path, theme_path.as_deref(), max_input_bytes)?;
            }
            Ok(_) => {}
            Err(error) => redraw_message(&format!(
                "{}\n",
                msg_args("watch-error", &[msg_arg("error", error)])
            ))?,
        }
    }
    Err(msg("watch-stopped"))
}

#[cfg(target_arch = "wasm32")]
fn watch_file(
    _path: &Path,
    _theme_file: Option<&Path>,
    _max_input_bytes: usize,
) -> Result<(), String> {
    Err(msg("watch-wasm"))
}

#[cfg(not(target_arch = "wasm32"))]
fn should_rerender_any(event: &Event, paths: &[PathBuf]) -> bool {
    matches!(
        event.kind,
        EventKind::Any | EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
    ) && (event.paths.is_empty()
        || event
            .paths
            .iter()
            .any(|event_path| paths.iter().any(|path| event_path == path)))
}

#[cfg(not(target_arch = "wasm32"))]
fn redraw_watched_file(
    path: &Path,
    theme_file: Option<&Path>,
    max_input_bytes: usize,
) -> Result<(), String> {
    let output = read_source_file(path, max_input_bytes)
        .and_then(|source| render_watched_source(&source, theme_file, max_input_bytes))
        .unwrap_or_else(|error| format!("{error}\n"));
    redraw_message(&output)
}

#[cfg(not(target_arch = "wasm32"))]
fn render_watched_source(
    source: &str,
    theme_file: Option<&Path>,
    max_input_bytes: usize,
) -> Result<String, String> {
    let mut options = RenderOptions::default();
    if let Some(theme_file) = theme_file {
        options.custom_theme = Some(load_render_theme_file(theme_file, max_input_bytes)?);
    }
    render_text_source(source, &options)
}

#[cfg(not(target_arch = "wasm32"))]
fn redraw_message(output: &str) -> Result<(), String> {
    let mut stdout = io::stdout();
    execute!(stdout, Clear(ClearType::All), MoveTo(0, 0))
        .map_err(|error| msg_args("terminal-redraw", &[msg_arg("error", error)]))?;
    stdout
        .write_all(output.as_bytes())
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))?;
    stdout
        .flush()
        .map_err(|error| msg_args("terminal-flush-stdout", &[msg_arg("error", error)]))
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

fn playback_timeline_from_source(
    source: &str,
    options: AnimationOptions,
    prefer_cast: bool,
) -> Result<Timeline, String> {
    if prefer_cast {
        return timeline_from_kumecast_source(source, options);
    }
    if let Ok(cast) = Kumecast::from_json_str(source) {
        return timeline_from_kumecast(cast, options);
    }
    timeline_from_source_with_options(source, options)
}

fn timeline_from_kumecast_source(
    source: &str,
    options: AnimationOptions,
) -> Result<Timeline, String> {
    let cast = Kumecast::from_json_str(source).map_err(|error| error.to_string())?;
    timeline_from_kumecast(cast, options)
}

fn timeline_from_kumecast(cast: Kumecast, options: AnimationOptions) -> Result<Timeline, String> {
    let timeline = cast.to_timeline().map_err(|error| error.to_string())?;
    Ok(apply_playback_options_to_timeline(timeline, options))
}

fn apply_playback_options_to_timeline(timeline: Timeline, options: AnimationOptions) -> Timeline {
    let repeat = options.repeat().unwrap_or(timeline.repeat());
    let Some(speed) = options.speed() else {
        return timeline.with_repeat(repeat);
    };
    let mut scaled = Timeline::new().with_repeat(repeat);
    for keyframe in timeline.keyframes() {
        scaled.push(KeyFrame::new(
            keyframe.frame().clone(),
            scaled_keyframe_duration(keyframe.duration(), speed),
        ));
    }
    scaled
}

fn scaled_keyframe_duration(duration: Duration, speed: f32) -> Duration {
    Duration::from_secs_f64(duration.as_secs_f64() / f64::from(speed))
}

fn timeline_from_source_with_render_options(
    source: &str,
    options: AnimationOptions,
    render_options: &RenderOptions,
) -> Result<Timeline, String> {
    let diagram = parse_diagram(source)?;
    timeline_from_diagram_with_render_options(&diagram, options, render_options)
}

fn timeline_from_diagram_with_render_options(
    diagram: &Diagram,
    options: AnimationOptions,
    render_options: &RenderOptions,
) -> Result<Timeline, String> {
    let timeline = Animator::animate_diagram_with_options_and_renderer(
        diagram,
        options,
        frame_renderer(render_options),
    )
    .map_err(|error| {
        msg_args(
            "animation-config",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })?;
    Ok(apply_timeline_width(timeline, render_options))
}

fn playback_options(speed: Option<f32>, repeat: bool) -> Result<AnimationOptions, String> {
    AnimationOptions::new(speed, repeat.then_some(true)).map_err(|error| {
        msg_args(
            "playback-options",
            &[msg_arg("error", format!("{error:?}"))],
        )
    })
}

fn parse_speed_override(value: &str) -> Result<f32, String> {
    let speed = value
        .parse::<f32>()
        .map_err(|_| msg_args("parse-speed", &[msg_arg("value", format!("{value:?}"))]))?;
    if !speed.is_finite() || speed <= 0.0 {
        return Err(msg_args(
            "parse-speed",
            &[msg_arg("value", format!("{value:?}"))],
        ));
    }
    Ok(speed)
}

fn parse_positive_usize(value: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| msg_args("parse-width", &[msg_arg("value", format!("{value:?}"))]))?;
    if parsed == 0 {
        return Err(msg_args(
            "parse-width",
            &[msg_arg("value", format!("{value:?}"))],
        ));
    }
    Ok(parsed)
}

fn parse_positive_input_bytes(value: &str) -> Result<usize, String> {
    let parsed = value.parse::<usize>().map_err(|_| {
        msg_args(
            "parse-max-input-bytes",
            &[msg_arg("value", format!("{value:?}"))],
        )
    })?;
    if parsed == 0 {
        return Err(msg_args(
            "parse-max-input-bytes",
            &[msg_arg("value", format!("{value:?}"))],
        ));
    }
    Ok(parsed)
}

fn parse_plugin_allow(value: &str) -> Result<CapabilitySet, String> {
    let mut capabilities = CapabilitySet::empty();
    if value.trim().is_empty() {
        return Ok(capabilities);
    }
    for raw in value.split(',') {
        let capability = raw.trim();
        if capability.is_empty() {
            return Err(msg("plugin-allow-empty"));
        }
        let capability = capability
            .parse::<Capability>()
            .map_err(|_| msg_args("plugin-allow-unknown", &[msg_arg("capability", capability)]))?;
        capabilities.insert(capability);
    }
    Ok(capabilities)
}

fn parse_non_empty_string(value: &str) -> Result<String, String> {
    if value.trim().is_empty() {
        return Err(msg("invalid-non-empty"));
    }
    Ok(value.to_owned())
}

fn parse_locale_override(value: &str) -> Result<String, String> {
    i18n::canonical_locale(value)
}

fn parse_socket_addr(value: &str) -> Result<SocketAddr, String> {
    value
        .parse()
        .map_err(|error| format!("invalid socket address {value:?}: {error}"))
}

fn parse_diagram(source: &str) -> Result<Diagram, String> {
    MermaidParser::parse_diagram(source).map_err(|error| {
        let location = parse_error_location(source, error.span.start);
        let mut message = msg_args(
            "parse-error",
            &[
                msg_arg("kind", parse_error_kind_label(error.kind)),
                msg_arg("start", error.span.start),
                msg_arg("end", error.span.end),
            ],
        );
        message.push_str(&format!(
            " at line {}, column {}",
            location.line, location.column
        ));
        if !location.line_text.trim().is_empty() {
            message.push('\n');
            message.push_str(&location.line_text);
            message.push('\n');
            message.push_str(&location.caret);
        }
        if let Some(suggestion) = parse_error_suggestion(error.kind) {
            message.push('\n');
            message.push_str("suggestion: ");
            message.push_str(suggestion);
        }
        message
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParseErrorLocation {
    line: usize,
    column: usize,
    line_text: String,
    caret: String,
}

fn parse_error_location(source: &str, offset: usize) -> ParseErrorLocation {
    let offset = floor_char_boundary(source, offset.min(source.len()));
    let line_start = source[..offset].rfind('\n').map_or(0, |index| index + 1);
    let line_end = source[offset..]
        .find('\n')
        .map_or(source.len(), |index| offset + index);
    let line = source[..offset]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1;
    let column = source[line_start..offset].chars().count() + 1;
    ParseErrorLocation {
        line,
        column,
        line_text: source[line_start..line_end].to_owned(),
        caret: format!("{}^", " ".repeat(column.saturating_sub(1))),
    }
}

fn floor_char_boundary(source: &str, offset: usize) -> usize {
    if source.is_char_boundary(offset) {
        return offset;
    }
    source
        .char_indices()
        .map(|(index, _)| index)
        .take_while(|index| *index < offset)
        .last()
        .unwrap_or(0)
}

fn parse_error_kind_label(kind: ParseErrorKind) -> String {
    match kind {
        ParseErrorKind::UnsupportedMermaidConfig => concat!(
            "UnsupportedMermaidConfig: Mermaid frontmatter/init/layout/theme config is outside ",
            "kumeyuri's compatibility surface; use kumeyuri CLI options or %%{ animate: ... }%%"
        )
        .to_owned(),
        _ => format!("{kind:?}"),
    }
}

fn parse_error_suggestion(kind: ParseErrorKind) -> Option<&'static str> {
    match kind {
        ParseErrorKind::ExpectedDiagramHeader => Some(
            "start with a supported Mermaid root such as graph, sequenceDiagram, stateDiagram-v2, classDiagram, erDiagram, gantt, pie, mindmap, journey, gitGraph, or timeline",
        ),
        ParseErrorKind::UnsupportedMermaidConfig => Some(
            "remove Mermaid frontmatter/init/layout/theme config and use kumeyuri CLI options, attributes, or %%{ animate: ... }%%",
        ),
        _ => None,
    }
}

fn render_timeline_vtt(timeline: &Timeline) -> String {
    let mut output = String::from("WEBVTT\n\n");
    let mut cursor_ms = 0_u128;
    for (index, keyframe) in timeline.keyframes().iter().enumerate() {
        let start_ms = cursor_ms;
        let end_ms = start_ms.saturating_add(keyframe.duration().as_millis().max(1));
        cursor_ms = end_ms;
        output.push_str(&format!(
            "frame-{index}\n{} --> {}\n",
            format_vtt_timestamp(start_ms),
            format_vtt_timestamp(end_ms),
        ));
        for line in keyframe.frame().to_lines() {
            if line.trim().is_empty() {
                output.push_str(" \n");
            } else {
                output.push_str(&escape_vtt_text(&line));
                output.push('\n');
            }
        }
        output.push('\n');
    }
    output
}

fn format_vtt_timestamp(value_ms: u128) -> String {
    let hours = value_ms / 3_600_000;
    let minutes = (value_ms / 60_000) % 60;
    let seconds = (value_ms / 1_000) % 60;
    let milliseconds = value_ms % 1_000;
    format!("{hours:02}:{minutes:02}:{seconds:02}.{milliseconds:03}")
}

fn escape_vtt_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn narrate_diagram(diagram: &Diagram) -> String {
    let summary = diagram_kind_summary(&diagram.kind);
    match accessible_title(diagram) {
        Some(title) => format!("{title}. {summary}"),
        None => summary,
    }
}

fn alt_text_for_diagram(diagram: &Diagram) -> String {
    if let Some(description) = &diagram.metadata.accessibility_description {
        return normalize_inline_text(&description.text);
    }
    narrate_diagram(diagram)
}

fn accessible_title(diagram: &Diagram) -> Option<String> {
    diagram
        .metadata
        .accessibility_title
        .as_ref()
        .or(diagram.metadata.title.as_ref())
        .map(|label| normalize_inline_text(&label.text))
        .or_else(|| diagram_kind_title(&diagram.kind))
}

fn diagram_kind_title(kind: &DiagramKind) -> Option<String> {
    match kind {
        DiagramKind::Gantt(ast) => ast.title.as_ref(),
        DiagramKind::Pie(ast) => ast.title.as_ref(),
        DiagramKind::Quadrant(ast) => ast.title.as_ref(),
        DiagramKind::ZenUml(ast) => ast.title.as_ref(),
        DiagramKind::XyChart(ast) => ast.title.as_ref(),
        DiagramKind::Packet(ast) => ast.title.as_ref(),
        DiagramKind::Radar(ast) => ast.title.as_ref(),
        DiagramKind::Venn(ast) => ast.title.as_ref(),
        DiagramKind::Wardley(ast) => ast.title.as_ref(),
        DiagramKind::Journey(ast) => ast.title.as_ref(),
        DiagramKind::Timeline(ast) => ast.title.as_ref(),
        DiagramKind::C4(ast) => ast.title.as_ref(),
        DiagramKind::Cynefin(ast) => ast.title.as_ref(),
        DiagramKind::Railroad(ast) => ast.title.as_ref(),
        DiagramKind::Flowchart(_)
        | DiagramKind::Sequence(_)
        | DiagramKind::State(_)
        | DiagramKind::Class(_)
        | DiagramKind::Er(_)
        | DiagramKind::Sankey(_)
        | DiagramKind::Block(_)
        | DiagramKind::Kanban(_)
        | DiagramKind::Architecture(_)
        | DiagramKind::EventModeling(_)
        | DiagramKind::Treemap(_)
        | DiagramKind::Ishikawa(_)
        | DiagramKind::TreeView(_)
        | DiagramKind::Mindmap(_)
        | DiagramKind::GitGraph(_)
        | DiagramKind::Requirement(_)
        | DiagramKind::Swimlanes(_) => None,
    }
    .map(|label| normalize_inline_text(&label.text))
}

fn diagram_kind_id(kind: &DiagramKind) -> &'static str {
    match kind {
        DiagramKind::Flowchart(_) => "flowchart",
        DiagramKind::Sequence(_) => "sequence",
        DiagramKind::State(_) => "state",
        DiagramKind::Class(_) => "class",
        DiagramKind::Er(_) => "er",
        DiagramKind::Gantt(_) => "gantt",
        DiagramKind::Pie(_) => "pie",
        DiagramKind::Quadrant(_) => "quadrant",
        DiagramKind::ZenUml(_) => "zenuml",
        DiagramKind::Sankey(_) => "sankey",
        DiagramKind::XyChart(_) => "xychart",
        DiagramKind::Block(_) => "block",
        DiagramKind::Packet(_) => "packet",
        DiagramKind::Kanban(_) => "kanban",
        DiagramKind::Architecture(_) => "architecture",
        DiagramKind::Radar(_) => "radar",
        DiagramKind::EventModeling(_) => "event-modeling",
        DiagramKind::Treemap(_) => "treemap",
        DiagramKind::Venn(_) => "venn",
        DiagramKind::Ishikawa(_) => "ishikawa",
        DiagramKind::Wardley(_) => "wardley",
        DiagramKind::TreeView(_) => "treeview",
        DiagramKind::Mindmap(_) => "mindmap",
        DiagramKind::Journey(_) => "journey",
        DiagramKind::GitGraph(_) => "gitgraph",
        DiagramKind::Timeline(_) => "timeline",
        DiagramKind::Requirement(_) => "requirement",
        DiagramKind::C4(_) => "c4",
        DiagramKind::Cynefin(_) => "cynefin",
        DiagramKind::Railroad(_) => "railroad",
        DiagramKind::Swimlanes(_) => "swimlanes",
    }
}

fn diagram_kind_summary(kind: &DiagramKind) -> String {
    match kind {
        DiagramKind::Flowchart(ast) => format!(
            "Flowchart with {}, {}, {}, and {} direction.",
            count_phrase(flowchart_node_count(ast), "node", "nodes"),
            count_phrase(ast.edges.len(), "edge", "edges"),
            count_phrase(ast.subgraphs.len(), "subgraph", "subgraphs"),
            direction_label(ast.header.direction.value)
        ),
        DiagramKind::Sequence(ast) => format!(
            "Sequence diagram with {}, {}, and {}.",
            count_phrase(ast.participants.len(), "participant", "participants"),
            count_phrase(
                sequence_message_count(&ast.statements),
                "message",
                "messages"
            ),
            count_phrase(ast.boxes.len(), "box", "boxes")
        ),
        DiagramKind::State(ast) => format!(
            "State diagram with {} and {}.",
            count_phrase(ast.states.len(), "state", "states"),
            count_phrase(ast.transitions.len(), "transition", "transitions")
        ),
        DiagramKind::Class(ast) => format!(
            "Class diagram with {} and {}.",
            count_phrase(ast.classes.len(), "class", "classes"),
            count_phrase(ast.relationships.len(), "relationship", "relationships")
        ),
        DiagramKind::Er(ast) => format!(
            "Entity relationship diagram with {} and {}.",
            count_phrase(ast.entities.len(), "entity", "entities"),
            count_phrase(ast.relationships.len(), "relationship", "relationships")
        ),
        DiagramKind::Gantt(ast) => {
            format!(
                "Gantt chart with {}.",
                count_phrase(ast.tasks.len(), "task", "tasks")
            )
        }
        DiagramKind::Pie(ast) => format!(
            "Pie chart with {} totaling {} units.",
            count_phrase(ast.slices.len(), "slice", "slices"),
            ast.slices
                .iter()
                .map(|slice| slice.value_units.value)
                .sum::<u64>()
        ),
        DiagramKind::Quadrant(ast) => format!(
            "Quadrant chart with {}, {}, and {}.",
            count_phrase(ast.points.len(), "point", "points"),
            count_phrase(ast.quadrants.len(), "quadrant label", "quadrant labels"),
            count_phrase(
                axis_count(ast.x_axis.is_some(), ast.y_axis.is_some()),
                "axis",
                "axes"
            )
        ),
        DiagramKind::ZenUml(ast) => format!(
            "ZenUML sequence with {}, {}, and {}.",
            count_phrase(ast.participants.len(), "participant", "participants"),
            count_phrase(ast.messages.len(), "message", "messages"),
            count_phrase(ast.fragments.len(), "fragment", "fragments")
        ),
        DiagramKind::Sankey(ast) => {
            format!(
                "Sankey diagram with {}.",
                count_phrase(ast.links.len(), "link", "links")
            )
        }
        DiagramKind::XyChart(ast) => format!(
            "XY chart with {}, {}, and {}.",
            count_phrase(ast.series.len(), "series", "series"),
            count_phrase(
                axis_count(ast.x_axis.is_some(), ast.y_axis.is_some()),
                "axis",
                "axes"
            ),
            xy_series_kinds(ast.series.iter().map(|series| series.kind.value))
        ),
        DiagramKind::Block(ast) => format!(
            "Block diagram with {}, {}, and {}.",
            count_phrase(ast.blocks.len(), "block", "blocks"),
            count_phrase(ast.edges.len(), "edge", "edges"),
            count_phrase(ast.styles.len(), "style rule", "style rules")
        ),
        DiagramKind::Packet(ast) => format!(
            "Packet diagram with {}.",
            count_phrase(ast.fields.len(), "field", "fields")
        ),
        DiagramKind::Kanban(ast) => format!(
            "Kanban board with {} and {}.",
            count_phrase(ast.columns.len(), "column", "columns"),
            count_phrase(
                ast.columns
                    .iter()
                    .map(|column| column.tasks.len())
                    .sum::<usize>(),
                "task",
                "tasks"
            )
        ),
        DiagramKind::Architecture(ast) => format!(
            "Architecture diagram with {}, {}, {}, and {}.",
            count_phrase(ast.groups.len(), "group", "groups"),
            count_phrase(ast.services.len(), "service", "services"),
            count_phrase(ast.junctions.len(), "junction", "junctions"),
            count_phrase(ast.edges.len(), "edge", "edges")
        ),
        DiagramKind::Radar(ast) => format!(
            "Radar chart with {} and {}.",
            count_phrase(ast.axes.len(), "axis", "axes"),
            count_phrase(ast.curves.len(), "curve", "curves")
        ),
        DiagramKind::EventModeling(ast) => format!(
            "Event modeling diagram with {} and {}.",
            count_phrase(ast.timeframes.len(), "timeframe", "timeframes"),
            count_phrase(ast.data_blocks.len(), "data block", "data blocks")
        ),
        DiagramKind::Treemap(ast) => format!(
            "Treemap with {} and {} total.",
            count_phrase(ast.roots.len(), "root", "roots"),
            count_phrase(
                ast.roots.iter().map(treemap_node_count).sum::<usize>(),
                "node",
                "nodes"
            )
        ),
        DiagramKind::Venn(ast) => format!(
            "Venn diagram with {}, {}, and {}.",
            count_phrase(ast.sets.len(), "set", "sets"),
            count_phrase(ast.unions.len(), "union", "unions"),
            count_phrase(ast.texts.len(), "text label", "text labels")
        ),
        DiagramKind::Ishikawa(ast) => format!(
            "Ishikawa diagram for {} with {}.",
            normalize_inline_text(&ast.event.text),
            count_phrase(
                ast.causes.iter().map(ishikawa_node_count).sum::<usize>(),
                "cause",
                "causes"
            )
        ),
        DiagramKind::Wardley(ast) => format!(
            "Wardley map with {}, {}, {}, and {}.",
            count_phrase(ast.components.len(), "component", "components"),
            count_phrase(ast.links.len(), "link", "links"),
            count_phrase(ast.evolves.len(), "evolution marker", "evolution markers"),
            count_phrase(ast.annotations.len(), "annotation", "annotations")
        ),
        DiagramKind::TreeView(ast) => format!(
            "Tree view with {} and {} total.",
            count_phrase(ast.roots.len(), "root", "roots"),
            count_phrase(
                ast.roots.iter().map(tree_view_node_count).sum::<usize>(),
                "node",
                "nodes"
            )
        ),
        DiagramKind::Mindmap(ast) => format!(
            "Mind map with {} and {} total.",
            count_phrase(ast.roots.len(), "root", "roots"),
            count_phrase(
                ast.roots.iter().map(mindmap_node_count).sum::<usize>(),
                "node",
                "nodes"
            )
        ),
        DiagramKind::Journey(ast) => format!(
            "User journey with {}.",
            count_phrase(ast.tasks.len(), "task", "tasks")
        ),
        DiagramKind::GitGraph(ast) => format!(
            "Git graph with {}, {}, {}, and {}.",
            count_phrase(ast.commits.len(), "commit", "commits"),
            count_phrase(ast.branches.len(), "branch", "branches"),
            count_phrase(ast.merges.len(), "merge", "merges"),
            count_phrase(ast.cherry_picks.len(), "cherry-pick", "cherry-picks")
        ),
        DiagramKind::Timeline(ast) => format!(
            "Timeline with {}, {}, and {}.",
            count_phrase(ast.periods.len(), "period", "periods"),
            count_phrase(timeline_event_count(&ast.periods), "event", "events"),
            count_phrase(
                ast.periods
                    .iter()
                    .filter(|period| period.section.is_some())
                    .count(),
                "sectioned period",
                "sectioned periods"
            )
        ),
        DiagramKind::Requirement(ast) => format!(
            "Requirement diagram with {}, {}, and {}.",
            count_phrase(ast.requirements.len(), "requirement", "requirements"),
            count_phrase(ast.elements.len(), "element", "elements"),
            count_phrase(ast.relationships.len(), "relationship", "relationships")
        ),
        DiagramKind::C4(ast) => format!(
            "C4 {} diagram with {}, {}, and {}.",
            c4_diagram_type_label(ast.header.diagram_type.value),
            count_phrase(ast.elements.len(), "element", "elements"),
            count_phrase(ast.relationships.len(), "relationship", "relationships"),
            count_phrase(ast.boundaries.len(), "boundary", "boundaries")
        ),
        DiagramKind::Cynefin(ast) => format!(
            "Cynefin framework diagram with {}, {}, and {}.",
            count_phrase(ast.domains.len(), "domain block", "domain blocks"),
            count_phrase(
                ast.domains
                    .iter()
                    .map(|domain| domain.items.len())
                    .sum::<usize>(),
                "item",
                "items"
            ),
            count_phrase(ast.transitions.len(), "transition", "transitions")
        ),
        DiagramKind::Railroad(ast) => format!(
            "Railroad diagram with {}.",
            count_phrase(ast.rules.len(), "grammar rule", "grammar rules")
        ),
        DiagramKind::Swimlanes(ast) => format!(
            "Swimlanes diagram with {}, {}, and {}.",
            count_phrase(ast.graph.subgraphs.len(), "lane", "lanes"),
            count_phrase(flowchart_node_count(&ast.graph), "node", "nodes"),
            count_phrase(ast.graph.edges.len(), "edge", "edges")
        ),
    }
}

fn sequence_message_count(statements: &[SequenceStatement]) -> usize {
    statements
        .iter()
        .map(|statement| match statement {
            SequenceStatement::Message(_) => 1,
            SequenceStatement::Control(block) => sequence_message_count(&block.statements),
            SequenceStatement::Participant(_)
            | SequenceStatement::Create(_)
            | SequenceStatement::Destroy(_)
            | SequenceStatement::Box(_)
            | SequenceStatement::ActivationStart(_)
            | SequenceStatement::ActivationEnd(_)
            | SequenceStatement::Note(_)
            | SequenceStatement::AutoNumber(_)
            | SequenceStatement::Comment(_)
            | SequenceStatement::Directive(_) => 0,
        })
        .sum()
}

fn flowchart_node_count(ast: &FlowchartAst) -> usize {
    let mut nodes = Vec::new();
    let mut connected = BTreeSet::new();
    collect_flow_statements(&ast.statements, &mut nodes, &mut connected);
    nodes.len()
}

fn treemap_node_count(node: &TreemapNode) -> usize {
    1 + node.children.iter().map(treemap_node_count).sum::<usize>()
}

fn tree_view_node_count(node: &TreeViewNode) -> usize {
    1 + node
        .children
        .iter()
        .map(tree_view_node_count)
        .sum::<usize>()
}

fn mindmap_node_count(node: &MindmapNode) -> usize {
    1 + node.children.iter().map(mindmap_node_count).sum::<usize>()
}

fn ishikawa_node_count(node: &IshikawaNode) -> usize {
    1 + node.causes.iter().map(ishikawa_node_count).sum::<usize>()
}

fn timeline_event_count(periods: &[TimelinePeriod]) -> usize {
    periods.iter().map(|period| period.events.len()).sum()
}

fn xy_series_kinds(
    values: impl IntoIterator<Item = kumeyuri_core::ast::XyChartSeriesKind>,
) -> String {
    let mut bar = 0_usize;
    let mut line = 0_usize;
    for value in values {
        match value {
            kumeyuri_core::ast::XyChartSeriesKind::Bar => bar += 1,
            kumeyuri_core::ast::XyChartSeriesKind::Line => line += 1,
        }
    }
    format!(
        "{} and {}",
        count_phrase(bar, "bar series", "bar series"),
        count_phrase(line, "line series", "line series")
    )
}

fn axis_count(x_axis: bool, y_axis: bool) -> usize {
    usize::from(u8::from(x_axis) + u8::from(y_axis))
}

fn direction_label(direction: Direction) -> &'static str {
    match direction {
        Direction::TopDown => "top-down",
        Direction::BottomTop => "bottom-top",
        Direction::LeftRight => "left-to-right",
        Direction::RightLeft => "right-to-left",
    }
}

fn c4_diagram_type_label(diagram_type: kumeyuri_core::ast::C4DiagramType) -> &'static str {
    match diagram_type {
        kumeyuri_core::ast::C4DiagramType::Context => "context",
        kumeyuri_core::ast::C4DiagramType::Container => "container",
        kumeyuri_core::ast::C4DiagramType::Component => "component",
        kumeyuri_core::ast::C4DiagramType::Dynamic => "dynamic",
        kumeyuri_core::ast::C4DiagramType::Deployment => "deployment",
    }
}

fn count_phrase(count: usize, singular: &str, plural: &str) -> String {
    if count == 1 {
        format!("1 {singular}")
    } else {
        format!("{count} {plural}")
    }
}

fn normalize_inline_text(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
struct LayoutReport {
    file: String,
    ok: bool,
    warnings: Vec<LayoutWarning>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
struct LayoutWarning {
    code: &'static str,
    message: String,
    suggestion: String,
}

impl LayoutWarning {
    fn line(&self) -> String {
        msg_args(
            "warning-line",
            &[
                msg_arg("message", &self.message),
                msg_arg("suggestion", &self.suggestion),
            ],
        )
    }
}

fn emit_layout_warnings(diagram: &Diagram, options: &RenderOptions) {
    for warning in layout_warnings(diagram, options) {
        eprintln!("{}", warning.line());
    }
}

fn layout_warnings(diagram: &Diagram, options: &RenderOptions) -> Vec<LayoutWarning> {
    let mut warnings = match &diagram.kind {
        DiagramKind::Flowchart(ast) => orphan_flowchart_nodes(ast)
            .into_iter()
            .map(orphan_flowchart_node_warning)
            .collect(),
        _ => Vec::new(),
    };
    if let Some(warning) = direction_swap_warning(diagram, options) {
        warnings.push(warning);
    }
    warnings
}

fn orphan_flowchart_node_warning(id: String) -> LayoutWarning {
    LayoutWarning {
        code: "flowchart.orphan_node",
        message: msg_args("layout-warning-orphan-message", &[msg_arg("id", &id)]),
        suggestion: msg_args("layout-warning-orphan-suggestion", &[msg_arg("id", &id)]),
    }
}

fn direction_swap_warning(diagram: &Diagram, options: &RenderOptions) -> Option<LayoutWarning> {
    let DiagramKind::Flowchart(ast) = &diagram.kind else {
        return None;
    };
    let frame = frame_renderer(options).render_diagram(diagram);
    let width = frame.width().max(1);
    let height = frame.height().max(1);
    let direction = ast.header.direction.value;
    match direction {
        Direction::TopDown | Direction::BottomTop
            if height >= width.saturating_mul(EXTREME_ASPECT_RATIO) =>
        {
            Some(LayoutWarning {
                code: "flowchart.extreme_aspect_ratio",
                message: msg_args(
                    "layout-warning-tall-message",
                    &[msg_arg("width", width), msg_arg("height", height)],
                ),
                suggestion: msg_args(
                    "layout-warning-tall-suggestion",
                    &[msg_arg(
                        "direction",
                        suggested_flowchart_direction(direction),
                    )],
                ),
            })
        }
        Direction::LeftRight | Direction::RightLeft
            if width >= height.saturating_mul(EXTREME_ASPECT_RATIO) =>
        {
            Some(LayoutWarning {
                code: "flowchart.extreme_aspect_ratio",
                message: msg_args(
                    "layout-warning-wide-message",
                    &[msg_arg("width", width), msg_arg("height", height)],
                ),
                suggestion: msg_args(
                    "layout-warning-wide-suggestion",
                    &[msg_arg(
                        "direction",
                        suggested_flowchart_direction(direction),
                    )],
                ),
            })
        }
        _ => None,
    }
}

fn suggested_flowchart_direction(direction: Direction) -> &'static str {
    match direction {
        Direction::TopDown => "LR",
        Direction::BottomTop => "RL",
        Direction::LeftRight => "TD",
        Direction::RightLeft => "BT",
    }
}

fn orphan_flowchart_nodes(ast: &FlowchartAst) -> Vec<String> {
    let mut nodes = Vec::new();
    let mut connected = BTreeSet::new();
    for node in &ast.nodes {
        push_unique_node_id(&mut nodes, &node.id.value);
    }
    for edge in &ast.edges {
        collect_flow_edge(
            &mut nodes,
            &mut connected,
            &edge.from.id.value,
            &edge.to.id.value,
        );
    }
    collect_flow_statements(&ast.statements, &mut nodes, &mut connected);
    for subgraph in &ast.subgraphs {
        collect_flow_statements(&subgraph.statements, &mut nodes, &mut connected);
    }
    nodes
        .into_iter()
        .filter(|id| !connected.contains(id))
        .collect()
}

fn collect_flow_statements(
    statements: &[FlowStatement],
    nodes: &mut Vec<String>,
    connected: &mut BTreeSet<String>,
) {
    for statement in statements {
        match statement {
            FlowStatement::Node(node) => push_unique_node_id(nodes, &node.id.value),
            FlowStatement::Edge(edge) => {
                collect_flow_edge(nodes, connected, &edge.from.id.value, &edge.to.id.value);
            }
            FlowStatement::Subgraph(subgraph) => {
                collect_flow_statements(&subgraph.statements, nodes, connected);
            }
            FlowStatement::ClassDef(_)
            | FlowStatement::ClassApply(_)
            | FlowStatement::Comment(_)
            | FlowStatement::Directive(_) => {}
        }
    }
}

fn collect_flow_edge(
    nodes: &mut Vec<String>,
    connected: &mut BTreeSet<String>,
    from: &str,
    to: &str,
) {
    push_unique_node_id(nodes, from);
    push_unique_node_id(nodes, to);
    connected.insert(from.to_owned());
    connected.insert(to.to_owned());
}

fn push_unique_node_id(nodes: &mut Vec<String>, id: &str) {
    if !nodes.iter().any(|node| node == id) {
        nodes.push(id.to_owned());
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn play_timeline(timeline: &Timeline, debug: bool) -> Result<(), String> {
    enable_raw_mode()
        .map_err(|error| msg_args("tui-enable-raw-mode", &[msg_arg("error", error)]))?;
    let mut stdout = io::stdout();
    if let Err(error) = execute!(stdout, EnterAlternateScreen) {
        let _ = disable_raw_mode();
        return Err(msg_args(
            "tui-enter-alternate-screen",
            &[msg_arg("error", error)],
        ));
    }

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = match Terminal::new(backend) {
        Ok(terminal) => terminal,
        Err(error) => {
            let _ = execute!(io::stdout(), LeaveAlternateScreen);
            let _ = disable_raw_mode();
            return Err(msg_args("tui-create-terminal", &[msg_arg("error", error)]));
        }
    };
    let render_result = TuiRenderer::new(TuiRenderConfig {
        transition: TuiTransitionEffect::Fade,
        ..TuiRenderConfig::default()
    })
    .render_interactive_timeline(&mut terminal, timeline, debug)
    .map_err(|error| msg_args("tui-render-timeline", &[msg_arg("error", error)]));
    let cursor_result = terminal
        .show_cursor()
        .map_err(|error| msg_args("tui-show-cursor", &[msg_arg("error", error)]));
    let leave_result = execute!(terminal.backend_mut(), LeaveAlternateScreen)
        .map_err(|error| msg_args("tui-leave-alternate-screen", &[msg_arg("error", error)]));
    let raw_result = disable_raw_mode()
        .map_err(|error| msg_args("tui-disable-raw-mode", &[msg_arg("error", error)]));

    render_result?;
    cursor_result?;
    leave_result?;
    raw_result
}

#[cfg(target_arch = "wasm32")]
fn play_timeline(_timeline: &Timeline, _debug: bool) -> Result<(), String> {
    Err(msg("play-wasm"))
}

#[cfg(not(target_arch = "wasm32"))]
trait InteractiveTimelineRenderer {
    fn render_interactive_timeline(
        self,
        terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
        timeline: &Timeline,
        debug: bool,
    ) -> Result<(), io::Error>;
}

#[cfg(not(target_arch = "wasm32"))]
impl InteractiveTimelineRenderer for TuiRenderer {
    fn render_interactive_timeline(
        self,
        terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
        timeline: &Timeline,
        debug: bool,
    ) -> Result<(), io::Error> {
        if timeline.is_empty() {
            return Ok(());
        }

        let mut state = PlaybackState::new();
        let mut debug_state = PlaybackDebug::new(debug);
        loop {
            debug_state.record_draw(Instant::now());
            self.draw_with_debug(
                terminal,
                timeline.keyframes()[state.index].frame(),
                debug_state.overlay(state.index, timeline.len()),
            )?;
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
#[derive(Debug, Clone, Copy, PartialEq)]
struct PlaybackDebug {
    enabled: bool,
    last_draw: Option<Instant>,
    fps: f64,
}

#[cfg(not(target_arch = "wasm32"))]
impl PlaybackDebug {
    const fn new(enabled: bool) -> Self {
        Self {
            enabled,
            last_draw: None,
            fps: 0.0,
        }
    }

    fn record_draw(&mut self, now: Instant) {
        if let Some(last_draw) = self.last_draw {
            let elapsed = now.saturating_duration_since(last_draw).as_secs_f64();
            if elapsed > 0.0 {
                let current = 1.0 / elapsed;
                self.fps = if self.fps == 0.0 {
                    current
                } else {
                    (self.fps * 0.8) + (current * 0.2)
                };
            }
        }
        self.last_draw = Some(now);
    }

    const fn overlay(self, frame_index: usize, frame_count: usize) -> Option<TuiDebugOverlay> {
        if !self.enabled {
            return None;
        }
        Some(TuiDebugOverlay {
            fps: self.fps,
            frame_index,
            frame_count,
        })
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
        ANIMATED_PARTIAL_ROOTS, Cli, Command, ConvertFormat, DEFAULT_INPUT_LIMIT_BYTES,
        ExportFormat, McpTransport, MermaidAuditSource, PluginCommand, PluginRegistry,
        RenderCharset, RenderFormat, RenderOptions, RenderTheme, ResolvedPluginPackage,
        STATIC_ONLY_ROOTS, Theme, ThemeCommand, UNSUPPORTED_ROOTS, audit_mermaid_source,
        compat_json_report, compat_report, convert_cast_source, convert_file, count_phrase,
        decode_gzip_bytes, diagram_kind_id, diagram_kind_summary, direction_label,
        disable_plugin_records, encode_url_path_component, export_file, export_source,
        extract_mermaid_audit_sources, format_lint_text, format_theme_error, format_theme_list,
        is_hex, is_kumecast_gz_path, is_kumecast_path, layout_file, layout_warnings, lint_file,
        lint_source, load_render_theme_file, normalize_inline_text, parse_diagram,
        parse_locale_override, parse_non_empty_string, parse_positive_input_bytes,
        parse_positive_usize, parse_socket_addr, parse_speed_override, playback_options,
        playback_timeline_from_source, plugin_runtime_policy, print_compat_report,
        print_lint_report, publish_theme_file, read_cast_source_file,
        read_installed_plugin_records, read_playback_file_source, read_source_file,
        read_theme_index, remove_plugin_records, render_file, render_source, render_theme,
        render_timeline_vtt, resolve_ai_library_path, resolve_crates_plugin_metadata,
        resolve_npm_plugin_metadata, show_theme, svg_config, theme_charset_name,
        timeline_from_source, timeline_from_source_with_options,
        timeline_from_source_with_render_options, validate_theme_file, write_plugin_install_record,
        write_theme_template,
    };
    #[cfg(not(target_arch = "wasm32"))]
    use super::{
        PlaybackAction, PlaybackDebug, PlaybackState, TuiDebugOverlay, render_watched_source,
        should_rerender_any,
    };
    use clap::Parser as _;
    #[cfg(not(target_arch = "wasm32"))]
    use crossterm::event::KeyCode;
    use flate2::{Compression, write::GzEncoder};
    use kumeyuri_core::{
        abi::Capability,
        animator::{AnimationOptions, KeyFrame, Timeline},
        ast::Direction,
        cast::Kumecast,
        frame::{Charset, Frame},
    };
    #[cfg(not(target_arch = "wasm32"))]
    use notify::{
        Event, EventKind,
        event::{DataChange, ModifyKind},
    };
    #[cfg(not(target_arch = "wasm32"))]
    use std::path::{Path, PathBuf};
    use std::{
        env,
        ffi::OsString,
        fs,
        io::Write as _,
        process,
        time::{Duration, Instant, SystemTime},
    };

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
    fn layout_warnings_flag_orphan_flowchart_nodes() {
        let diagram = parse_diagram("graph TD\nA\nB --> C\nsubgraph group\nD\nend").unwrap();
        let warnings = warning_lines(&layout_warnings(&diagram, &RenderOptions::default()));

        assert_eq!(
            warnings,
            vec![
                "warning: orphan flowchart node `A` has no edges; add an edge such as `A --> <target>` or remove the node",
                "warning: orphan flowchart node `D` has no edges; add an edge such as `D --> <target>` or remove the node",
            ]
        );
    }

    #[test]
    fn layout_warnings_ignore_connected_flowchart_nodes() {
        let diagram = parse_diagram("graph TD\nA --> B").unwrap();

        assert!(layout_warnings(&diagram, &RenderOptions::default()).is_empty());
    }

    #[test]
    fn layout_warnings_suggest_lr_for_tall_flowcharts() {
        let diagram = parse_diagram("graph TD\nA --> B\nB --> C").unwrap();
        let warnings = warning_lines(&layout_warnings(&diagram, &RenderOptions::default()));

        assert_eq!(
            warnings,
            vec![
                "warning: flowchart layout is very tall (6x26); try `graph LR` to reduce vertical space"
            ]
        );
    }

    #[test]
    fn layout_warnings_suggest_td_for_wide_flowcharts() {
        let diagram = parse_diagram("graph LR\nA --> B\nB --> C").unwrap();
        let warnings = warning_lines(&layout_warnings(&diagram, &RenderOptions::default()));

        assert_eq!(
            warnings,
            vec![
                "warning: flowchart layout is very wide (26x6); try `graph TD` to reduce horizontal space"
            ]
        );
    }

    #[test]
    fn lint_parser_accepts_json_flag() {
        let cli = Cli::try_parse_from(["kumeyuri", "lint", "diagram.mmd", "--json"]).unwrap();
        let Some(Command::Lint { file, json }) = cli.command else {
            panic!("expected lint command");
        };

        assert_eq!(file, std::path::PathBuf::from("diagram.mmd"));
        assert!(json);
    }

    #[test]
    fn layout_parser_accepts_ai_flag() {
        let cli = Cli::try_parse_from(["kumeyuri", "layout", "diagram.mmd", "--ai"]).unwrap();
        let Some(Command::Layout { file, ai }) = cli.command else {
            panic!("expected layout command");
        };

        assert_eq!(file, std::path::PathBuf::from("diagram.mmd"));
        assert!(ai);
    }

    #[test]
    fn mcp_parser_accepts_stdio_transport() {
        let cli = Cli::try_parse_from(["kumeyuri", "mcp", "--transport", "stdio"]).unwrap();
        let Some(Command::Mcp { transport, .. }) = cli.command else {
            panic!("expected mcp command");
        };

        assert_eq!(transport, McpTransport::Stdio);
    }

    #[test]
    fn mcp_parser_accepts_http_sse_transport() {
        let cli = Cli::try_parse_from([
            "kumeyuri",
            "mcp",
            "--transport",
            "http-sse",
            "--bind",
            "127.0.0.1:9000",
            "--bearer-token",
            "test-token",
        ])
        .unwrap();
        let Some(Command::Mcp {
            transport,
            bind,
            bearer_token,
        }) = cli.command
        else {
            panic!("expected mcp command");
        };

        assert_eq!(transport, McpTransport::HttpSse);
        assert_eq!(bind, "127.0.0.1:9000".parse().unwrap());
        assert_eq!(bearer_token.as_deref(), Some("test-token"));
    }

    #[test]
    fn watch_parser_accepts_theme_file() {
        let cli = Cli::try_parse_from([
            "kumeyuri",
            "watch",
            "diagram.mmd",
            "--theme-file",
            "custom.kumetheme.toml",
        ])
        .unwrap();
        let Some(Command::Watch { file, theme_file }) = cli.command else {
            panic!("expected watch command");
        };

        assert_eq!(file, std::path::PathBuf::from("diagram.mmd"));
        assert_eq!(
            theme_file.as_deref(),
            Some(Path::new("custom.kumetheme.toml"))
        );
    }

    #[test]
    fn ai_layout_requires_dynamic_library_path() {
        let error = resolve_ai_library_path(|_| None).unwrap_err();

        assert!(error.contains("KUMEYURI_AI_DYLIB"));
        assert_eq!(
            resolve_ai_library_path(|name| {
                (name == "KUMEYURI_AI_DYLIB").then(|| OsString::from("/tmp/libkumeyuri_ai.dylib"))
            })
            .unwrap(),
            std::path::PathBuf::from("/tmp/libkumeyuri_ai.dylib")
        );
    }

    #[test]
    fn lint_report_formats_text_and_json() {
        let report = lint_source("diagram.mmd", "graph TD\nA\nB --> C").unwrap();

        assert!(!report.ok);
        assert_eq!(report.warnings[0].code, "flowchart.orphan_node");
        assert_eq!(
            format_lint_text(&report),
            "diagram.mmd: warning: orphan flowchart node `A` has no edges; add an edge such as `A --> <target>` or remove the node\n"
        );
        let json = serde_json::to_string(&report).unwrap();
        assert!(json.contains(r#""file":"diagram.mmd""#));
        assert!(json.contains(r#""code":"flowchart.orphan_node""#));

        let ok = lint_source("ok.mmd", "graph TD\nA --> B").unwrap();
        assert!(ok.ok);
        assert_eq!(format_lint_text(&ok), "ok.mmd: ok\n");
    }

    #[test]
    fn render_format_parser_accepts_all_values() {
        for value in ["text", "svg", "gif", "apng", "webp", "vtt", "tui"] {
            let cli = Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd", "--format", value])
                .unwrap();
            assert!(matches!(cli.command, Some(Command::Render { .. })));
        }
    }

    #[test]
    fn export_parser_accepts_kumecast_format() {
        for (value, expected) in [
            ("kumecast", ExportFormat::Kumecast),
            ("kumecast-gz", ExportFormat::KumecastGz),
        ] {
            let cli = Cli::try_parse_from(["kumeyuri", "export", "diagram.mmd", "--format", value])
                .unwrap();
            let Some(Command::Export { file, format, .. }) = cli.command else {
                panic!("expected export command");
            };

            assert_eq!(file, PathBuf::from("diagram.mmd"));
            assert_eq!(format, expected);
        }
    }

    #[test]
    fn exports_mermaid_source_to_kumecast() {
        let output = String::from_utf8(
            export_source(
                "graph TD\nA --> B",
                ExportFormat::Kumecast,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();
        let cast = Kumecast::from_json_str(&output).unwrap();

        assert_eq!(cast.version, 1);
        assert_eq!(cast.source.diagram_type, "flowchart");
        assert_eq!(cast.source.mermaid, "graph TD\nA --> B");
        assert_eq!(cast.theme.name, "default");
        assert!(!cast.timeline.frames.is_empty());
        assert!(output.ends_with('\n'));
    }

    #[test]
    fn exports_and_reads_gzipped_kumecast() {
        let gzipped = export_source(
            "graph TD\nA --> B",
            ExportFormat::KumecastGz,
            &RenderOptions::default(),
        )
        .unwrap();

        assert_eq!(&gzipped[..2], &[0x1f, 0x8b]);
        let json = decode_gzip_bytes(&gzipped, DEFAULT_INPUT_LIMIT_BYTES).unwrap();
        let cast = Kumecast::from_json_str(&json).unwrap();
        assert_eq!(cast.source.diagram_type, "flowchart");

        let root = unique_temp_dir("kumecast-gzip");
        fs::create_dir_all(&root).unwrap();
        let path = root.join("diagram.kumecast.gz");
        fs::write(&path, gzipped).unwrap();
        let source = read_cast_source_file(&path, DEFAULT_INPUT_LIMIT_BYTES).unwrap();
        assert_eq!(
            Kumecast::from_json_str(&source).unwrap().source.mermaid,
            "graph TD\nA --> B"
        );
        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn kumecast_export_hashes_are_stable() {
        for (name, source, expected_hash) in [
            ("flowchart", "graph TD\nA --> B\n", 0xaba1_ce3b_a849_e3be),
            (
                "sequence",
                "sequenceDiagram\nAlice->>Bob: hi\n",
                0x381d_d15d_17b8_2da3,
            ),
            (
                "state",
                "stateDiagram-v2\n[*] --> Idle\nIdle --> Busy\n",
                0xf690_9a8b_3a11_2f50,
            ),
        ] {
            let output =
                export_source(source, ExportFormat::Kumecast, &RenderOptions::default()).unwrap();

            assert_eq!(fnv1a64(&output), expected_hash, "{name} cast hash drifted");
        }
    }

    #[test]
    fn convert_parser_accepts_cast_formats() {
        for (value, expected) in [
            ("text", ConvertFormat::Text),
            ("svg", ConvertFormat::Svg),
            ("gif", ConvertFormat::Gif),
        ] {
            let cli =
                Cli::try_parse_from(["kumeyuri", "convert", "diagram.kumecast", "--format", value])
                    .unwrap();
            let Some(Command::Convert { cast, format }) = cli.command else {
                panic!("expected convert command");
            };

            assert_eq!(cast, PathBuf::from("diagram.kumecast"));
            assert_eq!(format, expected);
        }
    }

    #[test]
    fn converts_kumecast_to_text_and_svg() {
        let cast = String::from_utf8(
            export_source(
                "graph TD\nA --> B",
                ExportFormat::Kumecast,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();
        let text =
            String::from_utf8(convert_cast_source(&cast, ConvertFormat::Text).unwrap()).unwrap();
        let svg =
            String::from_utf8(convert_cast_source(&cast, ConvertFormat::Svg).unwrap()).unwrap();

        assert!(text.contains("frame:0:duration_ms:"));
        assert!(text.contains('A'));
        assert!(text.contains('B'));
        assert!(svg.starts_with("<svg "));
        assert!(svg.contains("kumeyuri diagram"));
    }

    #[test]
    fn play_timeline_loader_accepts_kumecast_and_mermaid_sources() {
        let cast = String::from_utf8(
            export_source(
                "graph TD\nA --> B",
                ExportFormat::Kumecast,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();
        let options = playback_options(Some(2.0), true).unwrap();
        let timeline = playback_timeline_from_source(&cast, options, true).unwrap();

        assert!(timeline.repeat());
        assert_eq!(
            timeline.keyframes()[0].duration(),
            Duration::from_millis(275)
        );

        let mermaid =
            playback_timeline_from_source("graph TD\nA --> B", AnimationOptions::default(), false)
                .unwrap();
        assert!(!mermaid.keyframes().is_empty());
    }

    #[test]
    fn play_timeline_loader_rejects_invalid_kumecast_when_cast_is_expected() {
        let error =
            playback_timeline_from_source("graph TD\nA --> B", AnimationOptions::default(), true)
                .unwrap_err();

        assert!(error.contains("invalid kumecast JSON"));
    }

    #[test]
    fn render_theme_parser_accepts_all_built_ins() {
        for value in [
            "default",
            "mono",
            "tokyo-night",
            "github",
            "dracula",
            "solarized-light",
            "solarized-dark",
            "nord",
            "catppuccin-mocha",
            "high-contrast",
            "print-mono",
        ] {
            let cli = Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd", "--theme", value])
                .unwrap();
            assert!(matches!(cli.command, Some(Command::Render { .. })));
        }
    }

    #[test]
    fn render_theme_maps_every_variant_to_core_theme() {
        for (theme, expected) in [
            (
                RenderTheme::Default,
                kumeyuri_core::theme::BuiltInTheme::Default,
            ),
            (RenderTheme::Mono, kumeyuri_core::theme::BuiltInTheme::Mono),
            (
                RenderTheme::TokyoNight,
                kumeyuri_core::theme::BuiltInTheme::TokyoNight,
            ),
            (
                RenderTheme::Github,
                kumeyuri_core::theme::BuiltInTheme::Github,
            ),
            (
                RenderTheme::Dracula,
                kumeyuri_core::theme::BuiltInTheme::Dracula,
            ),
            (
                RenderTheme::SolarizedLight,
                kumeyuri_core::theme::BuiltInTheme::SolarizedLight,
            ),
            (
                RenderTheme::SolarizedDark,
                kumeyuri_core::theme::BuiltInTheme::SolarizedDark,
            ),
            (RenderTheme::Nord, kumeyuri_core::theme::BuiltInTheme::Nord),
            (
                RenderTheme::CatppuccinMocha,
                kumeyuri_core::theme::BuiltInTheme::CatppuccinMocha,
            ),
            (
                RenderTheme::HighContrast,
                kumeyuri_core::theme::BuiltInTheme::HighContrast,
            ),
            (
                RenderTheme::PrintMono,
                kumeyuri_core::theme::BuiltInTheme::PrintMono,
            ),
        ] {
            assert_eq!(theme.theme(), expected);
        }
    }

    #[test]
    fn file_level_command_helpers_execute_and_report_errors() {
        let root = unique_temp_dir("file-command-helpers");
        fs::create_dir_all(&root).unwrap();
        let diagram = root.join("diagram.mmd");
        fs::write(&diagram, "graph TD\nA --> B\n").unwrap();

        render_file(
            &diagram,
            RenderFormat::Text,
            &RenderOptions::default(),
            DEFAULT_INPUT_LIMIT_BYTES,
        )
        .unwrap();
        render_file(
            &diagram,
            RenderFormat::Svg,
            &RenderOptions::default(),
            DEFAULT_INPUT_LIMIT_BYTES,
        )
        .unwrap();
        assert!(
            render_file(
                &diagram,
                RenderFormat::Text,
                &RenderOptions {
                    dark_theme: Some(RenderTheme::Dracula),
                    ..RenderOptions::default()
                },
                DEFAULT_INPUT_LIMIT_BYTES,
            )
            .unwrap_err()
            .contains("--dark-theme")
        );

        export_file(
            &diagram,
            ExportFormat::Kumecast,
            &RenderOptions::default(),
            DEFAULT_INPUT_LIMIT_BYTES,
        )
        .unwrap();
        let cast = root.join("diagram.kumecast");
        fs::write(
            &cast,
            export_source(
                "graph TD\nA --> B\n",
                ExportFormat::Kumecast,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();
        convert_file(&cast, ConvertFormat::Text, DEFAULT_INPUT_LIMIT_BYTES).unwrap();
        convert_file(&cast, ConvertFormat::Svg, DEFAULT_INPUT_LIMIT_BYTES).unwrap();

        lint_file(&diagram, false, DEFAULT_INPUT_LIMIT_BYTES).unwrap();
        lint_file(&diagram, true, DEFAULT_INPUT_LIMIT_BYTES).unwrap();
        assert!(layout_file(&diagram, false, DEFAULT_INPUT_LIMIT_BYTES).is_err());
        assert!(
            layout_file(&root.join("missing.mmd"), true, DEFAULT_INPUT_LIMIT_BYTES)
                .unwrap_err()
                .contains("missing.mmd")
        );
        print_compat_report(None, false).unwrap();
        print_lint_report(
            &lint_source("diagram.mmd", "graph TD\nA --> B\n").unwrap(),
            true,
        )
        .unwrap();

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn renders_vtt_captions_synced_to_animation() {
        let mut first = Frame::new(3, 1);
        first.write_text(0, 0, "A&B", Default::default()).unwrap();
        let mut second = Frame::new(3, 1);
        second.write_text(0, 0, "<C>", Default::default()).unwrap();
        let timeline = Timeline::from_keyframes(vec![
            KeyFrame::new(first, Duration::from_millis(100)),
            KeyFrame::new(second, Duration::from_millis(2_500)),
        ]);

        assert_eq!(
            render_timeline_vtt(&timeline),
            "WEBVTT\n\nframe-0\n00:00:00.000 --> 00:00:00.100\nA&amp;B\n\nframe-1\n00:00:00.100 --> 00:00:02.600\n&lt;C&gt;\n\n"
        );
    }

    #[test]
    fn compat_parser_accepts_mermaid_version() {
        let cli = Cli::try_parse_from([
            "kumeyuri",
            "compat",
            "--mermaid-version",
            "11.15.0",
            "--json",
        ])
        .unwrap();
        let Some(Command::Compat {
            mermaid_version,
            json,
        }) = cli.command
        else {
            panic!("expected compat command");
        };

        assert_eq!(mermaid_version.as_deref(), Some("11.15.0"));
        assert!(json);
    }

    #[test]
    fn global_lang_parser_accepts_locale_override() {
        let cli = Cli::try_parse_from(["kumeyuri", "--lang", "ja_JP.UTF-8", "compat"]).unwrap();

        assert_eq!(cli.lang.as_deref(), Some("ja-JP"));
    }

    #[test]
    fn validate_theme_flag_accepts_file_without_subcommand() {
        let cli = Cli::try_parse_from([
            "kumeyuri",
            "--validate-theme",
            "solarized-light.kumetheme.toml",
        ])
        .unwrap();

        assert_eq!(
            cli.validate_theme.as_deref(),
            Some(Path::new("solarized-light.kumetheme.toml"))
        );
        assert!(cli.command.is_none());
    }

    #[test]
    fn validate_theme_file_accepts_schema_and_rejects_bad_values() {
        let root = unique_temp_dir("theme-validation");
        fs::create_dir_all(&root).unwrap();
        let valid = root.join("valid.kumetheme.toml");
        fs::write(
            &valid,
            r##"
name = "solarized-light"
charset = "unicode"

[colors]
background = "#fdf6e3"
foreground = "#073642"
accent = "#268bd2"
edge = "#586e75"
edge_alt = "#6c71c4"
highlight = "#b58900"
muted = "#657b83"
"##,
        )
        .unwrap();

        validate_theme_file(&valid, 1024).unwrap();

        let invalid = root.join("invalid.kumetheme.toml");
        fs::write(
            &invalid,
            r##"
name = "BadName"
charset = "unicode"

[colors]
background = "#fdf6e3"
foreground = "#073642"
accent = "268bd2"
edge = "#586e75"
edge_alt = "#6c71c4"
highlight = "#b58900"
muted = "#657b83"
"##,
        )
        .unwrap();

        let error = validate_theme_file(&invalid, 1024).unwrap_err();
        assert!(error.contains("invalid theme schema"));
        assert!(error.contains("BadName"));

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn theme_subcommand_parser_accepts_list_show_new_and_validate() {
        let list = Cli::try_parse_from(["kumeyuri", "theme", "list"]).unwrap();
        assert!(matches!(
            list.command,
            Some(Command::Theme {
                command: ThemeCommand::List
            })
        ));

        let show = Cli::try_parse_from(["kumeyuri", "theme", "show", "github"]).unwrap();
        assert!(matches!(
            show.command,
            Some(Command::Theme {
                command: ThemeCommand::Show { .. }
            })
        ));

        let new = Cli::try_parse_from([
            "kumeyuri",
            "theme",
            "new",
            "custom.kumetheme.toml",
            "--name",
            "custom",
        ])
        .unwrap();
        assert!(matches!(
            new.command,
            Some(Command::Theme {
                command: ThemeCommand::New { .. }
            })
        ));

        let validate =
            Cli::try_parse_from(["kumeyuri", "theme", "validate", "custom.kumetheme.toml"])
                .unwrap();
        assert!(matches!(
            validate.command,
            Some(Command::Theme {
                command: ThemeCommand::Validate { .. }
            })
        ));

        let publish = Cli::try_parse_from([
            "kumeyuri",
            "theme",
            "publish",
            "custom.kumetheme.toml",
            "--index-dir",
            "site",
            "--base-url",
            "https://themes.kumeyuri.dev",
        ])
        .unwrap();
        assert!(matches!(
            publish.command,
            Some(Command::Theme {
                command: ThemeCommand::Publish { .. }
            })
        ));
    }

    #[test]
    fn theme_commands_format_list_show_and_new_template() {
        let root = unique_temp_dir("theme-commands");
        fs::create_dir_all(&root).unwrap();
        let file = root.join("custom-theme.kumetheme.toml");

        write_theme_template(&file, None).unwrap();
        validate_theme_file(&file, 1024).unwrap();

        let entries = vec![
            kumeyuri_core::theme::ThemeSearchEntry {
                name: "custom-theme".to_owned(),
                source: kumeyuri_core::theme::ThemeSource::Project(file.clone()),
            },
            kumeyuri_core::theme::ThemeSearchEntry {
                name: "github".to_owned(),
                source: kumeyuri_core::theme::ThemeSource::Bundled(
                    kumeyuri_core::theme::BuiltInTheme::Github,
                ),
            },
        ];
        let list = format_theme_list(&entries);
        assert!(list.contains("custom-theme\tproject"));
        assert!(list.contains("github\tbundled"));

        let custom = show_theme("custom-theme", &entries, 1024).unwrap();
        assert!(custom.contains("name = \"custom-theme\""));
        assert!(custom.contains("charset = \"unicode\""));

        let github = show_theme("github", &entries, 1024).unwrap();
        assert!(github.contains("name = \"github\""));
        assert!(github.contains("background = \"#ffffff\""));

        let error = write_theme_template(&file, None).unwrap_err();
        assert!(error.contains("already exists"));
        assert!(
            show_theme("missing", &entries, 1024)
                .unwrap_err()
                .contains("not found")
        );

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn theme_publish_writes_static_index_and_canonical_theme() {
        let root = unique_temp_dir("theme-publish");
        let source = root.join("demo.kumetheme.toml");
        let index_dir = root.join("site");
        fs::create_dir_all(&root).unwrap();
        fs::write(
            &source,
            r##"
name = "demo-theme"
charset = "unicode"

[colors]
background = "#101418"
foreground = "#e6edf3"
accent = "#58a6ff"
edge = "#8b949e"
edge_alt = "#d2a8ff"
highlight = "#f2cc60"
muted = "#7d8590"
"##,
        )
        .unwrap();

        publish_theme_file(&source, &index_dir, "https://themes.example.test/", 1024).unwrap();

        let theme = fs::read_to_string(index_dir.join("themes/demo-theme.kumetheme.toml")).unwrap();
        assert!(theme.starts_with("name = \"demo-theme\"\ncharset = \"unicode\""));
        let index = fs::read_to_string(index_dir.join("index.json")).unwrap();
        assert!(index.contains(r#""version": 1"#));
        assert!(index.contains(r#""base_url": "https://themes.example.test""#));
        assert!(index.contains(r#""name": "demo-theme""#));
        assert!(
            index.contains(
                r#""url": "https://themes.example.test/themes/demo-theme.kumetheme.toml""#
            )
        );

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn theme_publish_replaces_existing_index_entries_and_reports_shape_errors() {
        let root = unique_temp_dir("theme-publish-replace");
        let source = root.join("demo.kumetheme.toml");
        let index_dir = root.join("site");
        fs::create_dir_all(&index_dir).unwrap();
        fs::write(
            index_dir.join("index.json"),
            r##"{
  "version": 1,
  "base_url": "https://old.example.test",
  "themes": [
    {
      "name": "zeta-theme",
      "charset": "ascii",
      "url": "https://old.example.test/themes/zeta-theme.kumetheme.toml",
      "colors": {
        "background": "#000000",
        "foreground": "#ffffff",
        "accent": "#111111",
        "edge": "#222222",
        "edge_alt": "#333333",
        "highlight": "#444444",
        "muted": "#555555"
      }
    },
    {
      "name": "demo-theme",
      "charset": "ascii",
      "url": "https://old.example.test/themes/demo-theme.kumetheme.toml",
      "colors": {
        "background": "#000000",
        "foreground": "#ffffff",
        "accent": "#111111",
        "edge": "#222222",
        "edge_alt": "#333333",
        "highlight": "#444444",
        "muted": "#555555"
      }
    }
  ]
}"##,
        )
        .unwrap();
        fs::write(
            &source,
            r##"
name = "demo-theme"
charset = "ascii"

[colors]
background = "#101418"
foreground = "#e6edf3"
accent = "#58a6ff"
edge = "#8b949e"
edge_alt = "#d2a8ff"
highlight = "#f2cc60"
muted = "#7d8590"
"##,
        )
        .unwrap();

        publish_theme_file(&source, &index_dir, "https://themes.example.test/", 1024).unwrap();
        let index = read_theme_index(&index_dir.join("index.json")).unwrap();

        assert_eq!(index.themes.len(), 2);
        assert_eq!(index.themes[0].name, "demo-theme");
        assert_eq!(index.themes[0].charset, "ascii");
        assert_eq!(index.themes[1].name, "zeta-theme");

        fs::write(index_dir.join("index.json"), "{").unwrap();
        assert!(
            read_theme_index(&index_dir.join("index.json"))
                .unwrap_err()
                .contains("invalid theme index")
        );

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn theme_formatting_helpers_cover_error_and_charset_edges() {
        assert_eq!(
            theme_charset_name(kumeyuri_core::theme::KumethemeCharset::Ascii),
            "ascii"
        );
        assert_eq!(
            format_theme_error(&kumeyuri_core::theme::KumethemeError::InvalidName(
                "Bad Name".to_owned()
            )),
            "invalid name `Bad Name`: expected kebab-case ASCII identifier"
        );
        assert_eq!(
            format_theme_error(&kumeyuri_core::theme::KumethemeError::InvalidHexColor {
                field: "accent",
                value: "blue".to_owned(),
            }),
            "invalid color `accent` = `blue`: expected #RRGGBB"
        );
    }

    #[test]
    fn plugin_install_parser_accepts_package_name() {
        let cli =
            Cli::try_parse_from(["kumeyuri", "plugin", "install", "kumeyuri-render-pdf"]).unwrap();
        let Some(Command::Plugin {
            command: PluginCommand::Install { name },
        }) = cli.command
        else {
            panic!("expected plugin install command");
        };

        assert_eq!(name, "kumeyuri-render-pdf");
    }

    #[test]
    fn plugin_management_parser_accepts_subcommands() {
        for args in [
            ["kumeyuri", "plugin", "list", ""],
            ["kumeyuri", "plugin", "remove", "kumeyuri-render-pdf"],
            ["kumeyuri", "plugin", "update", "kumeyuri-render-pdf"],
            ["kumeyuri", "plugin", "disable", "kumeyuri-render-pdf"],
        ] {
            let cli =
                Cli::try_parse_from(args.into_iter().filter(|value| !value.is_empty())).unwrap();
            assert!(matches!(cli.command, Some(Command::Plugin { .. })));
        }
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
        assert!(output.contains("`cynefin-beta`"));
        assert!(output.contains("`railroad-diagram`"));
        assert!(output.contains("`swimlane`"));
        assert!(output.contains("Unsupported roots"));
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
    fn compat_json_report_is_machine_readable() {
        let output = compat_json_report(Some("11.15.0"));

        assert_eq!(output.requested_version, "11.15.0");
        assert_eq!(output.reference_version, "11.15.0");
        assert!(output.version_verified);
        assert_eq!(output.counts.families, 31);
        assert_eq!(output.counts.animated_partial, 11);
        assert_eq!(output.counts.static_only_partial, 20);
        assert_eq!(output.counts.unsupported, 0);
        assert_eq!(output.counts.root_spellings, 40);
        assert!(output.roots.iter().any(|root| {
            root.support == "animated-partial" && root.roots.as_slice() == ["graph", "flowchart"]
        }));
        assert!(output.roots.iter().any(|root| {
            root.support == "static-only-partial" && root.roots.as_slice() == ["cynefin-beta"]
        }));
    }

    #[test]
    fn compat_tables_match_current_coverage_counts() {
        assert_eq!(ANIMATED_PARTIAL_ROOTS.len(), 11);
        assert_eq!(STATIC_ONLY_ROOTS.len(), 20);
        assert_eq!(UNSUPPORTED_ROOTS.len(), 0);
    }

    #[test]
    fn audit_mermaid_parser_accepts_paths_and_json_flag() {
        let cli = Cli::try_parse_from(["kumeyuri", "audit-mermaid", "docs", "examples", "--json"])
            .unwrap();
        let Some(Command::AuditMermaid { paths, json }) = cli.command else {
            panic!("expected audit-mermaid command");
        };

        assert!(json);
        assert_eq!(paths, [PathBuf::from("docs"), PathBuf::from("examples")]);
    }

    #[test]
    fn audit_mermaid_extracts_markdown_fences() {
        let blocks = extract_mermaid_audit_sources(
            Path::new("README.md"),
            "text\n```mermaid\ngraph TD\nA --> B\n```\n```rust\nfn main() {}\n```\n",
        );

        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].line, 2);
        assert_eq!(blocks[0].source_kind, "markdown-fence");
        assert!(blocks[0].source.contains("graph TD"));
    }

    #[test]
    fn audit_mermaid_reports_support_warnings_and_errors() {
        let animated = audit_mermaid_source(MermaidAuditSource {
            path: PathBuf::from("sequence.mmd"),
            line: 1,
            source_kind: "file",
            source: "%%{ init: { 'theme': 'base' } }%%\nsequenceDiagram\nA->>B: hello\n".to_owned(),
        });
        let static_only = audit_mermaid_source(MermaidAuditSource {
            path: PathBuf::from("packet.mmd"),
            line: 1,
            source_kind: "file",
            source: "packet\n0-7: \"Version\"\n".to_owned(),
        });
        let unsupported = audit_mermaid_source(MermaidAuditSource {
            path: PathBuf::from("bad.mmd"),
            line: 1,
            source_kind: "file",
            source: "notMermaid\nA --> B\n".to_owned(),
        });

        assert_eq!(animated.support, "animated-partial");
        assert!(animated.render_ok);
        assert!(animated.frames >= 2);
        assert_eq!(animated.warnings.len(), 1);
        assert_eq!(static_only.support, "static-only-partial");
        assert_eq!(static_only.frames, 1);
        assert_eq!(unsupported.support, "unsupported");
        assert!(!unsupported.parse_ok);
        assert!(unsupported.error.is_some());
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
            "--max-label-width",
            "12",
            "--padding",
            "12",
            "--font",
            "Fira Code",
            "--allow-external",
            "--plugin-allow",
            "fs.write,cache.read",
        ])
        .unwrap();
        let Some(Command::Render { options, .. }) = cli.command else {
            panic!("expected render command");
        };

        assert_eq!(options.theme, Some(RenderTheme::TokyoNight));
        assert_eq!(options.dark_theme, Some(RenderTheme::Dracula));
        assert_eq!(options.charset, Some(RenderCharset::Unicode));
        assert_eq!(options.width, Some(40));
        assert_eq!(options.max_label_width, Some(12));
        assert_eq!(options.padding, Some(12));
        assert_eq!(options.font.as_deref(), Some("Fira Code"));
        assert!(options.allow_external);
        let plugin_allow = options.plugin_allow.unwrap();
        assert!(plugin_allow.contains(Capability::FsWrite));
        assert!(plugin_allow.contains(Capability::CacheRead));
        assert!(!plugin_allow.contains(Capability::NetFetch));
        assert!(plugin_runtime_policy(&options).allows(Capability::FsWrite));
        assert!(plugin_runtime_policy(&options).allows(Capability::NetFetch));
    }

    #[test]
    fn external_fetch_is_denied_unless_explicitly_allowed() {
        let default = Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd"]).unwrap();
        let Some(Command::Render { options, .. }) = default.command else {
            panic!("expected render command");
        };
        assert!(!options.allow_external);
        assert!(!plugin_runtime_policy(&options).allows(Capability::NetFetch));

        let allowed =
            Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd", "--allow-external"]).unwrap();
        let Some(Command::Render { options, .. }) = allowed.command else {
            panic!("expected render command");
        };
        assert!(options.allow_external);
        assert!(plugin_runtime_policy(&options).allows(Capability::NetFetch));
    }

    #[test]
    fn render_mode_parser_accepts_narrate_and_alt_text_flags() {
        let narrate =
            Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd", "--narrate"]).unwrap();
        let Some(Command::Render { options, .. }) = narrate.command else {
            panic!("expected render command");
        };
        assert!(options.narrate);
        assert!(!options.alt_text);

        let alt_text =
            Cli::try_parse_from(["kumeyuri", "render", "diagram.mmd", "--alt-text"]).unwrap();
        let Some(Command::Render { options, .. }) = alt_text.command else {
            panic!("expected render command");
        };
        assert!(options.alt_text);
        assert!(!options.narrate);
    }

    #[test]
    fn plugin_allow_parser_rejects_unknown_capabilities() {
        let error = Cli::try_parse_from([
            "kumeyuri",
            "render",
            "diagram.mmd",
            "--plugin-allow",
            "fs.write,process.spawn",
        ])
        .unwrap_err()
        .to_string();

        assert!(error.contains("unknown plugin capability `process.spawn`"));
    }

    #[test]
    fn npm_plugin_metadata_resolves_tagged_latest_package() {
        let package = resolve_npm_plugin_metadata(
            "kumeyuri-render-pdf",
            r#"{
  "name": "kumeyuri-render-pdf",
  "dist-tags": { "latest": "0.1.0" },
  "versions": {
    "0.1.0": {
      "keywords": ["kumeyuri-plugin"],
      "dist": {
        "tarball": "https://registry.npmjs.org/kumeyuri-render-pdf/-/kumeyuri-render-pdf-0.1.0.tgz",
        "shasum": "abcdef0123456789"
      }
    }
  }
}"#,
        )
        .unwrap();

        assert_eq!(package.registry, PluginRegistry::Npm);
        assert_eq!(package.name, "kumeyuri-render-pdf");
        assert_eq!(package.version, "0.1.0");
        assert_eq!(package.content_hash, "abcdef0123456789");
        assert_eq!(package.archive_file, "package.tgz");
    }

    #[test]
    fn crates_plugin_metadata_resolves_tagged_package() {
        let package = resolve_crates_plugin_metadata(
            "kumeyuri-render-pdf",
            r#"{
  "crate": {
    "name": "kumeyuri-render-pdf",
    "max_version": "0.1.0",
    "keywords": ["kumeyuri-plugin"]
  },
  "versions": [
    {
      "num": "0.1.0",
      "checksum": "0123456789abcdef",
      "yanked": false,
      "dl_path": "/api/v1/crates/kumeyuri-render-pdf/0.1.0/download"
    }
  ]
}"#,
        )
        .unwrap();

        assert_eq!(package.registry, PluginRegistry::CratesIo);
        assert_eq!(package.name, "kumeyuri-render-pdf");
        assert_eq!(package.version, "0.1.0");
        assert_eq!(package.content_hash, "0123456789abcdef");
        assert_eq!(
            package.archive_url,
            "https://crates.io/api/v1/crates/kumeyuri-render-pdf/0.1.0/download"
        );
        assert_eq!(package.archive_file, "package.crate");
    }

    #[test]
    fn plugin_metadata_requires_keyword() {
        let error = resolve_npm_plugin_metadata(
            "not-a-plugin",
            r#"{
  "name": "not-a-plugin",
  "dist-tags": { "latest": "0.1.0" },
  "versions": {
    "0.1.0": {
      "keywords": ["other"],
      "dist": { "tarball": "https://registry.npmjs.org/not-a-plugin.tgz", "shasum": "abcdef" }
    }
  }
}"#,
        )
        .unwrap_err();

        assert!(error.contains("kumeyuri-plugin"));
    }

    #[test]
    fn plugin_metadata_falls_back_to_package_keywords_and_rejects_yanked_versions() {
        let package = resolve_npm_plugin_metadata(
            "kumeyuri-render-pdf",
            r#"{
  "dist-tags": { "latest": "0.1.0" },
  "keywords": ["kumeyuri-plugin"],
  "versions": {
    "0.1.0": {
      "dist": {
        "tarball": "https://registry.npmjs.org/kumeyuri-render-pdf/-/pkg.tgz",
        "shasum": "abcdef"
      }
    }
  }
}"#,
        )
        .unwrap();

        assert_eq!(package.name, "kumeyuri-render-pdf");
        assert_eq!(package.content_hash, "abcdef");
        assert!(
            resolve_crates_plugin_metadata(
                "kumeyuri-render-pdf",
                r#"{
  "crate": {
    "max_version": "0.1.0",
    "keywords": ["kumeyuri-plugin"]
  },
  "versions": [
    {
      "num": "0.1.0",
      "checksum": "0123456789abcdef",
      "yanked": true,
      "dl_path": "/api/v1/crates/kumeyuri-render-pdf/0.1.0/download"
    }
  ]
}"#,
            )
            .unwrap_err()
            .contains("0.1.0")
        );
    }

    #[test]
    fn plugin_metadata_reports_registry_shape_errors() {
        assert!(
            resolve_npm_plugin_metadata("missing-latest", r#"{"dist-tags": {}, "versions": {}}"#)
                .unwrap_err()
                .contains("latest")
        );
        assert!(
            resolve_npm_plugin_metadata(
                "missing-version",
                r#"{
  "dist-tags": { "latest": "0.2.0" },
  "keywords": ["kumeyuri-plugin"],
  "versions": {
    "0.1.0": {
      "dist": { "tarball": "https://registry.npmjs.org/pkg.tgz", "shasum": "abcdef" }
    }
  }
}"#,
            )
            .unwrap_err()
            .contains("0.2.0")
        );
        assert!(
            resolve_npm_plugin_metadata(
                "bad-sha",
                r#"{
  "dist-tags": { "latest": "0.1.0" },
  "keywords": ["kumeyuri-plugin"],
  "versions": {
    "0.1.0": {
      "dist": { "tarball": "https://registry.npmjs.org/pkg.tgz", "shasum": "not hex" }
    }
  }
}"#,
            )
            .unwrap_err()
            .contains("shasum")
        );
        assert!(
            resolve_crates_plugin_metadata(
                "missing-version",
                r#"{
  "crate": { "keywords": ["kumeyuri-plugin"] },
  "versions": []
}"#,
            )
            .unwrap_err()
            .contains("version")
        );
        assert!(
            resolve_crates_plugin_metadata(
                "bad-checksum",
                r#"{
  "crate": {
    "max_version": "0.1.0",
    "keywords": ["kumeyuri-plugin"]
  },
  "versions": [
    {
      "num": "0.1.0",
      "checksum": "not hex",
      "yanked": false,
      "dl_path": "https://example.test/pkg.crate"
    }
  ]
}"#,
            )
            .unwrap_err()
            .contains("checksum")
        );
    }

    #[test]
    fn plugin_metadata_uses_default_crate_version_and_absolute_download_url() {
        let package = resolve_crates_plugin_metadata(
            "kumeyuri-render-pdf",
            r#"{
  "crate": {
    "name": "kumeyuri-render-pdf",
    "default_version": "0.2.0",
    "keywords": ["kumeyuri-plugin"]
  },
  "versions": [
    {
      "num": "0.2.0",
      "checksum": "0123456789abcdef",
      "yanked": false,
      "dl_path": "https://mirror.example.test/kumeyuri-render-pdf.crate"
    }
  ]
}"#,
        )
        .unwrap();

        assert_eq!(package.version, "0.2.0");
        assert_eq!(
            package.archive_url,
            "https://mirror.example.test/kumeyuri-render-pdf.crate"
        );
    }

    #[test]
    fn plugin_records_list_disable_and_remove_from_cache() {
        let root = unique_temp_dir("plugin-records");
        let cache_dir = root
            .join("kumeyuri-render-pdf")
            .join("0.1.0")
            .join("abi-1")
            .join("abcdef");
        fs::create_dir_all(&cache_dir).unwrap();
        let package = ResolvedPluginPackage {
            registry: PluginRegistry::Npm,
            name: "kumeyuri-render-pdf".to_owned(),
            version: "0.1.0".to_owned(),
            archive_url: "https://registry.npmjs.org/kumeyuri-render-pdf.tgz".to_owned(),
            content_hash: "abcdef".to_owned(),
            archive_file: "package.tgz",
        };
        write_plugin_install_record(&cache_dir, &package).unwrap();

        let records = read_installed_plugin_records(&root).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].record.name, "kumeyuri-render-pdf");
        assert!(!records[0].disabled);

        assert_eq!(
            disable_plugin_records(&root, "kumeyuri-render-pdf").unwrap(),
            1
        );
        let records = read_installed_plugin_records(&root).unwrap();
        assert!(records[0].disabled);

        assert_eq!(
            remove_plugin_records(&root, "kumeyuri-render-pdf").unwrap(),
            1
        );
        assert!(read_installed_plugin_records(&root).unwrap().is_empty());

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn plugin_records_sort_nested_records_and_report_invalid_metadata() {
        let root = unique_temp_dir("plugin-record-sort");
        let alpha = root.join("alpha").join("0.2.0").join("abi-1").join("aaaa");
        let zeta = root.join("zeta").join("0.1.0").join("abi-1").join("zzzz");
        fs::create_dir_all(&alpha).unwrap();
        fs::create_dir_all(&zeta).unwrap();
        write_plugin_install_record(
            &zeta,
            &ResolvedPluginPackage {
                registry: PluginRegistry::CratesIo,
                name: "zeta".to_owned(),
                version: "0.1.0".to_owned(),
                archive_url: "https://crates.io/api/v1/crates/zeta/0.1.0/download".to_owned(),
                content_hash: "zzzz".to_owned(),
                archive_file: "package.crate",
            },
        )
        .unwrap();
        write_plugin_install_record(
            &alpha,
            &ResolvedPluginPackage {
                registry: PluginRegistry::Npm,
                name: "alpha".to_owned(),
                version: "0.2.0".to_owned(),
                archive_url: "https://registry.npmjs.org/alpha/-/alpha-0.2.0.tgz".to_owned(),
                content_hash: "aaaa".to_owned(),
                archive_file: "package.tgz",
            },
        )
        .unwrap();
        fs::write(alpha.join(".disabled"), b"").unwrap();

        let records = read_installed_plugin_records(&root).unwrap();
        assert_eq!(records[0].record.name, "alpha");
        assert!(records[0].disabled);
        assert_eq!(records[1].record.name, "zeta");

        fs::write(alpha.join("install.json"), "{").unwrap();
        assert!(
            read_installed_plugin_records(&root)
                .unwrap_err()
                .contains("invalid plugin install metadata")
        );

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn plugin_records_missing_name_errors_without_mutating_cache() {
        let root = unique_temp_dir("plugin-record-missing");
        fs::create_dir_all(&root).unwrap();

        assert!(
            remove_plugin_records(&root, "missing")
                .unwrap_err()
                .contains("not installed")
        );
        assert!(
            disable_plugin_records(&root, "missing")
                .unwrap_err()
                .contains("not installed")
        );
        assert!(
            read_installed_plugin_records(&root.join("absent"))
                .unwrap()
                .is_empty()
        );

        fs::remove_dir_all(root).ok();
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
    fn renders_svg_accessibility_metadata_from_mermaid_source() {
        let output = String::from_utf8(
            render_source(
                "graph TD\naccTitle: Checkout & pay\naccDescr: Choose <card>\nA --> B",
                RenderFormat::Svg,
                &RenderOptions::default(),
            )
            .unwrap(),
        )
        .unwrap();

        assert!(output.contains(r#"<title id="kumeyuri-title">Checkout &amp; pay</title>"#));
        assert!(output.contains(r#"<desc id="kumeyuri-desc">Choose &lt;card&gt;</desc>"#));
    }

    #[test]
    fn narrate_flag_emits_type_specific_prose() {
        let output = String::from_utf8(
            render_source(
                "graph TD\nA --> B",
                RenderFormat::Text,
                &RenderOptions {
                    narrate: true,
                    ..RenderOptions::default()
                },
            )
            .unwrap(),
        )
        .unwrap();

        assert_eq!(
            output,
            "Flowchart with 2 nodes, 1 edge, 0 subgraphs, and top-down direction.\n"
        );
    }

    #[test]
    fn alt_text_flag_prefers_accessibility_description() {
        let output = String::from_utf8(
            render_source(
                "graph TD\naccTitle: Checkout flow\naccDescr: Choose <card>\nA --> B",
                RenderFormat::Text,
                &RenderOptions {
                    alt_text: true,
                    ..RenderOptions::default()
                },
            )
            .unwrap(),
        )
        .unwrap();

        assert_eq!(output, "Choose <card>\n");
    }

    #[test]
    fn narration_mode_flags_reject_conflicts() {
        let conflict = render_source(
            "graph TD\nA --> B",
            RenderFormat::Text,
            &RenderOptions {
                narrate: true,
                alt_text: true,
                ..RenderOptions::default()
            },
        )
        .unwrap_err();
        assert!(conflict.contains("--narrate and --alt-text cannot be used together"));

        let format_conflict = render_source(
            "graph TD\nA --> B",
            RenderFormat::Svg,
            &RenderOptions {
                alt_text: true,
                ..RenderOptions::default()
            },
        )
        .unwrap_err();
        assert!(format_conflict.contains("cannot be combined with --format"));
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
    fn max_label_width_wraps_flowchart_labels() {
        let text = String::from_utf8(
            render_source(
                "graph TD\nA[Alpha Beta Gamma]",
                RenderFormat::Text,
                &RenderOptions {
                    max_label_width: Some(5),
                    ..RenderOptions::default()
                },
            )
            .unwrap(),
        )
        .unwrap();

        assert!(text.lines().any(|line| line.contains("Alpha")));
        assert!(text.lines().any(|line| line.contains("Beta")));
        assert!(text.lines().any(|line| line.contains("Gamma")));
        assert!(!text.contains("Alpha Beta Gamma"));
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
    fn render_config_and_export_error_edges_are_covered() {
        assert!(
            export_source(
                "graph TD\nA --> B",
                ExportFormat::Kumecast,
                &RenderOptions {
                    narrate: true,
                    ..RenderOptions::default()
                },
            )
            .unwrap_err()
            .contains("cannot be used with export")
        );
        assert!(
            export_source(
                "graph TD\nA --> B",
                ExportFormat::Kumecast,
                &RenderOptions {
                    dark_theme: Some(RenderTheme::Dracula),
                    ..RenderOptions::default()
                },
            )
            .unwrap_err()
            .contains("--dark-theme")
        );

        let custom = Theme {
            name: "custom",
            charset: Charset::Unicode,
            colors: kumeyuri_core::theme::BuiltInTheme::HighContrast
                .theme()
                .colors,
        };
        let options = RenderOptions {
            custom_theme: Some(custom),
            charset: Some(RenderCharset::Ascii),
            padding: Some(u32::MAX),
            font: Some("Test Mono".to_owned()),
            ..RenderOptions::default()
        };
        let theme = render_theme(&options);
        assert_eq!(theme.name, "custom");
        assert_eq!(theme.charset, Charset::Unicode);

        let svg = svg_config(&options);
        assert_eq!(svg.padding, u16::MAX);
        assert_eq!(svg.font_family, "Test Mono");

        let parse_error =
            render_source("notARoot\nA", RenderFormat::Vtt, &RenderOptions::default()).unwrap_err();
        assert!(parse_error.contains("parse error"));
        assert!(parse_error.contains("line 1, column 1"));
        assert!(parse_error.contains("suggestion: start with a supported Mermaid root"));
        let config_error = parse_diagram("---\ntitle: bad\n---\ngraph TD\nA --> B").unwrap_err();
        assert!(config_error.contains("Mermaid frontmatter/init/layout/theme config"));
        assert!(
            config_error
                .contains("suggestion: remove Mermaid frontmatter/init/layout/theme config")
        );
    }

    #[test]
    fn narrates_each_supported_diagram_kind_fixture() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        for (kind, name, expected_id) in [
            ("flowchart", "01_single_node", "flowchart"),
            ("sequence", "01_single_message", "sequence"),
            ("state", "01_start_to_idle", "state"),
            ("class", "01_basic_class", "class"),
            ("er", "01_basic_relationship", "er"),
            ("gantt", "01_basic_schedule", "gantt"),
            ("pie", "01_basic", "pie"),
            ("quadrant", "01_basic", "quadrant"),
            ("zenuml", "01_basic", "zenuml"),
            ("sankey", "01_basic", "sankey"),
            ("xychart", "01_basic", "xychart"),
            ("block", "01_basic", "block"),
            ("packet", "01_tcp", "packet"),
            ("kanban", "01_basic", "kanban"),
            ("architecture", "01_basic", "architecture"),
            ("radar", "01_basic", "radar"),
            ("event_modeling", "01_basic", "event-modeling"),
            ("treemap", "01_basic", "treemap"),
            ("venn", "01_basic", "venn"),
            ("ishikawa", "01_basic", "ishikawa"),
            ("wardley", "01_basic", "wardley"),
            ("tree_view", "01_basic", "treeview"),
            ("mindmap", "01_basic_tree", "mindmap"),
            ("journey", "01_basic", "journey"),
            ("gitgraph", "01_basic", "gitgraph"),
            ("timeline", "01_basic", "timeline"),
            ("requirement", "01_basic", "requirement"),
            ("c4", "01_context", "c4"),
            ("cynefin", "01_basic", "cynefin"),
            ("railroad", "01_basic", "railroad"),
            ("swimlanes", "01_basic", "swimlanes"),
        ] {
            let path = root
                .join("tests/snapshots")
                .join(kind)
                .join("input")
                .join(format!("{name}.mmd"));
            let source = fs::read_to_string(&path)
                .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
            let diagram = parse_diagram(&source)
                .unwrap_or_else(|error| panic!("failed to parse {}/{}: {error}", kind, name));
            let summary = diagram_kind_summary(&diagram.kind);

            assert_eq!(diagram_kind_id(&diagram.kind), expected_id);
            assert!(!summary.is_empty(), "{kind}/{name}");
            assert!(!summary.contains("  "), "{summary}");
        }
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
    fn playback_timelines_build_for_all_snapshot_fixtures() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join("tests/snapshots");
        let paths = snapshot_input_paths(&root);

        assert_eq!(paths.len(), 141);

        for path in paths {
            let source = fs::read_to_string(&path)
                .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
            let timeline =
                playback_timeline_from_source(&source, AnimationOptions::default(), false)
                    .unwrap_or_else(|error| panic!("{}: {error}", path.display()));

            assert!(!timeline.is_empty(), "{}", path.display());
        }
    }

    fn snapshot_input_paths(root: &Path) -> Vec<PathBuf> {
        let mut paths = Vec::new();
        collect_snapshot_input_paths(root, &mut paths);
        paths.sort();
        paths
    }

    fn collect_snapshot_input_paths(dir: &Path, paths: &mut Vec<PathBuf>) {
        for entry in fs::read_dir(dir)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", dir.display()))
        {
            let path = entry
                .unwrap_or_else(|error| {
                    panic!("failed to read entry in {}: {error}", dir.display())
                })
                .path();
            if path.is_dir() {
                if path.file_name().is_some_and(|name| name == "parse-errors") {
                    continue;
                }
                collect_snapshot_input_paths(&path, paths);
            } else if path.extension().is_some_and(|extension| extension == "mmd")
                && path
                    .parent()
                    .and_then(Path::file_name)
                    .is_some_and(|name| name == "input")
            {
                paths.push(path);
            }
        }
    }

    fn warning_lines(warnings: &[super::LayoutWarning]) -> Vec<String> {
        warnings.iter().map(super::LayoutWarning::line).collect()
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
        assert_eq!(parse_positive_input_bytes("64").unwrap(), 64);
        assert!(parse_positive_input_bytes("0").is_err());
        assert_eq!(parse_non_empty_string("Fira Code").unwrap(), "Fira Code");
        assert!(parse_non_empty_string(" ").is_err());
    }

    #[test]
    fn parsers_and_small_helpers_cover_error_edges() {
        assert!(parse_positive_usize("abc").unwrap_err().contains("invalid"));
        assert!(
            parse_positive_input_bytes("abc")
                .unwrap_err()
                .contains("invalid")
        );
        assert_eq!(parse_locale_override("en_US.UTF-8").unwrap(), "en-US");
        assert!(parse_locale_override(" ").is_err());
        assert_eq!(
            parse_socket_addr("127.0.0.1:9000").unwrap(),
            "127.0.0.1:9000".parse().unwrap()
        );
        assert!(parse_socket_addr("not-an-addr").is_err());
        assert_eq!(direction_label(Direction::BottomTop), "bottom-top");
        assert_eq!(direction_label(Direction::LeftRight), "left-to-right");
        assert_eq!(direction_label(Direction::RightLeft), "right-to-left");
        assert_eq!(count_phrase(1, "node", "nodes"), "1 node");
        assert_eq!(count_phrase(2, "node", "nodes"), "2 nodes");
        assert_eq!(
            normalize_inline_text(" alpha\n beta\tgamma "),
            "alpha beta gamma"
        );
        assert_eq!(
            encode_url_path_component("@scope/pkg name"),
            "%40scope%2Fpkg%20name"
        );
        assert!(is_hex("abcdef0123456789"));
        assert!(!is_hex(""));
        assert!(!is_hex("xyz"));
    }

    #[test]
    fn global_input_limit_parser_accepts_override() {
        let cli = Cli::try_parse_from([
            "kumeyuri",
            "render",
            "diagram.mmd",
            "--max-input-bytes",
            "64",
        ])
        .unwrap();

        assert_eq!(cli.max_input_bytes, 64);
    }

    #[test]
    fn source_reader_enforces_configured_input_limit() {
        let root = unique_temp_dir("input-limit");
        fs::create_dir_all(&root).unwrap();
        let path = root.join("diagram.mmd");
        fs::write(&path, "graph TD\nA --> B\n").unwrap();

        assert_eq!(read_source_file(&path, 64).unwrap(), "graph TD\nA --> B\n");
        let error = read_source_file(&path, 8).unwrap_err();
        assert!(error.contains("larger than 8 bytes"));

        fs::write(&path, vec![b'a'; DEFAULT_INPUT_LIMIT_BYTES + 1]).unwrap();
        let error = read_source_file(&path, DEFAULT_INPUT_LIMIT_BYTES).unwrap_err();
        assert!(error.contains(&format!("larger than {DEFAULT_INPUT_LIMIT_BYTES} bytes")));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn source_readers_report_utf8_gzip_and_path_variants() {
        let root = unique_temp_dir("source-reader-variants");
        fs::create_dir_all(&root).unwrap();
        let invalid_utf8 = root.join("bad.mmd");
        fs::write(&invalid_utf8, [0xff, 0xfe]).unwrap();
        assert!(
            read_source_file(&invalid_utf8, 16)
                .unwrap_err()
                .contains("UTF-8")
        );

        let cast = root.join("diagram.kumecast");
        fs::write(&cast, "{\"version\":1}").unwrap();
        assert!(is_kumecast_path(&cast));
        assert!(!is_kumecast_gz_path(&cast));
        assert_eq!(
            read_playback_file_source(&cast, 64).unwrap(),
            "{\"version\":1}"
        );

        let gz = root.join("diagram.kumecast.gz");
        fs::write(&gz, b"not gzip").unwrap();
        assert!(is_kumecast_path(&gz));
        assert!(is_kumecast_gz_path(&gz));
        assert!(
            read_cast_source_file(&gz, 64)
                .unwrap_err()
                .contains("invalid gzip stream")
        );

        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(b"0123456789").unwrap();
        let compressed = encoder.finish().unwrap();
        assert!(
            decode_gzip_bytes(&compressed, 4)
                .unwrap_err()
                .contains("too large")
        );

        fs::remove_dir_all(root).ok();
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn watch_rerenders_relevant_modify_events() {
        let event = Event::new(EventKind::Modify(ModifyKind::Data(DataChange::Content)))
            .add_path("diagram.mmd".into());

        assert!(should_rerender_any(&event, &[PathBuf::from("diagram.mmd")]));
        assert!(!should_rerender_any(&event, &[PathBuf::from("other.mmd")]));
        assert!(should_rerender_any(
            &event,
            &[PathBuf::from("other.mmd"), PathBuf::from("diagram.mmd")]
        ));
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn watch_renders_with_reloaded_theme_file() {
        let root = unique_temp_dir("watch-theme");
        let theme = root.join("custom.kumetheme.toml");
        fs::create_dir_all(&root).unwrap();
        fs::write(
            &theme,
            r##"
name = "watch-theme"
charset = "unicode"

[colors]
background = "#101418"
foreground = "#e6edf3"
accent = "#58a6ff"
edge = "#8b949e"
edge_alt = "#d2a8ff"
highlight = "#f2cc60"
muted = "#7d8590"
"##,
        )
        .unwrap();

        let loaded = load_render_theme_file(&theme, 1024).unwrap();
        assert_eq!(loaded.name, "custom");
        assert_eq!(loaded.charset, Charset::Unicode);
        let rendered = render_watched_source("graph TD\nA --> B", Some(&theme), 1024).unwrap();

        assert!(rendered.contains('┌'));
        fs::remove_dir_all(root).ok();
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

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn playback_debug_tracks_fps_overlay() {
        let mut debug = PlaybackDebug::new(true);
        let start = Instant::now();

        debug.record_draw(start);
        debug.record_draw(start + Duration::from_millis(100));

        assert_eq!(
            debug.overlay(1, 3),
            Some(TuiDebugOverlay {
                fps: 10.0,
                frame_index: 1,
                frame_count: 3,
            }),
        );
        assert_eq!(PlaybackDebug::new(false).overlay(0, 1), None);
    }

    fn unique_temp_dir(label: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        env::temp_dir().join(format!("kumeyuri-cli-{label}-{}-{nanos}", process::id()))
    }

    fn fnv1a64(bytes: &[u8]) -> u64 {
        let mut hash = 0xcbf2_9ce4_8422_2325;
        for byte in bytes {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
        hash
    }
}
