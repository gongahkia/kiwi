use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    ffi::OsString,
    fs,
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::ExitCode,
};

use clap::{Args, CommandFactory, FromArgMatches, Parser, Subcommand, ValueEnum};
use kumeyuri_core::{
    abi::{Capability, CapabilitySet, KUMEYURI_ABI_VERSION},
    animator::{AnimationOptions, Animator, KeyFrame, Timeline},
    ast::{Diagram, DiagramKind, Direction, FlowStatement, FlowchartAst},
    frame::{Charset, Frame, StaticFrameRenderer},
    layout::FlowLayoutConfig,
    parser::Parser as MermaidParser,
    plugins::{PluginCache, PluginRuntimePolicy},
    text::{TextOutputBackend, TextOutputConfig},
    theme::{BuiltInTheme, RgbColor, Theme},
};
use kumeyuri_render_raster::{RasterRenderConfig, RasterRenderer, RgbaColor};
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};
use serde::{Deserialize, Serialize};

mod i18n;

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
    Lint {
        #[arg(value_name = "FILE")]
        file: PathBuf,
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
    },
    Play {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_name = "FACTOR", value_parser = parse_speed_override)]
        speed: Option<f32>,
        #[arg(long = "loop")]
        repeat: bool,
    },
    Plugin {
        #[command(subcommand)]
        command: PluginCommand,
    },
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
    #[arg(long, value_name = "CELLS", value_parser = parse_positive_usize)]
    max_label_width: Option<usize>,
    #[arg(long, value_name = "PX")]
    padding: Option<u32>,
    #[arg(long, value_name = "FAMILY", value_parser = parse_non_empty_string)]
    font: Option<String>,
    #[arg(long = "plugin-allow", value_name = "CSV", value_parser = parse_plugin_allow)]
    plugin_allow: Option<CapabilitySet>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderTheme {
    Default,
    Mono,
    TokyoNight,
    Github,
    Dracula,
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

    match cli.command {
        Command::Compat { mermaid_version } => print_compat_report(mermaid_version.as_deref()),
        Command::Render {
            file,
            format,
            options,
        } => render_file(&file, format, &options, max_input_bytes),
        Command::Lint { file, json } => lint_file(&file, json, max_input_bytes),
        Command::Layout { file, ai } => layout_file(&file, ai, max_input_bytes),
        Command::Watch { file } => watch_file(&file, max_input_bytes),
        Command::Play {
            file,
            speed,
            repeat,
        } => play_file(&file, playback_options(speed, repeat)?, max_input_bytes),
        Command::Plugin { command } => run_plugin_command(command),
    }
}

const PLUGIN_KEYWORD: &str = "kumeyuri-plugin";
const KUMEYURI_USER_AGENT: &str = concat!("kumeyuri/", env!("CARGO_PKG_VERSION"));

const MERMAID_COMPAT_VERSION: &str = "11.15.0";
const EXTREME_ASPECT_RATIO: usize = 4;
const KUMEYURI_AI_DYLIB_ENV: &str = "KUMEYURI_AI_DYLIB";
const KUMEYURI_AI_ABI_VERSION: u32 = 1;
const DEFAULT_INPUT_LIMIT_BYTES: usize = 1024 * 1024;

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

const UNSUPPORTED_ROOTS: &[CompatRoot] = &[
    CompatRoot {
        label_id: "compat-label-cynefin",
        roots: &["cynefin-beta"],
        caveat_id: "compat-caveat-cynefin",
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
];

fn print_compat_report(mermaid_version: Option<&str>) -> Result<(), String> {
    let output = compat_report(mermaid_version);
    io::stdout()
        .write_all(output.as_bytes())
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
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
        return play_timeline(&timeline);
    }
    let output = render_source(&source, format, options)?;
    io::stdout()
        .write_all(&output)
        .map_err(|error| msg_args("error-write-stdout", &[msg_arg("error", error)]))
}

fn lint_file(path: &Path, json: bool, max_input_bytes: usize) -> Result<(), String> {
    let source = read_source_file(path, max_input_bytes)?;
    let report = lint_source(&path.display().to_string(), &source)?;
    print_lint_report(&report, json)
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

fn read_source_file(path: &Path, max_input_bytes: usize) -> Result<String, String> {
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
    String::from_utf8(bytes).map_err(|error| {
        msg_args(
            "error-read-utf8",
            &[msg_arg("path", path.display()), msg_arg("error", error)],
        )
    })
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
    match format {
        RenderFormat::Text => Ok(render_text_source(source, options)?.into_bytes()),
        RenderFormat::Svg => Ok(render_svg_source(source, options)?.into_bytes()),
        RenderFormat::Gif => render_raster_source(source, options, RasterRenderer::render_gif),
        RenderFormat::Apng => render_raster_source(source, options, RasterRenderer::render_apng),
        RenderFormat::Webp => render_raster_source(source, options, RasterRenderer::render_webp),
        RenderFormat::Tui => Err(msg("render-tui-interactive")),
    }
}

fn validate_render_options(format: RenderFormat, options: &RenderOptions) -> Result<(), String> {
    if options.dark_theme.is_some() && format != RenderFormat::Svg {
        return Err(msg("render-dark-theme-svg-only"));
    }
    let _plugin_policy = plugin_runtime_policy(options);
    Ok(())
}

fn plugin_runtime_policy(options: &RenderOptions) -> PluginRuntimePolicy {
    PluginRuntimePolicy::with_grants(options.plugin_allow.unwrap_or_default())
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

fn play_file(path: &Path, options: AnimationOptions, max_input_bytes: usize) -> Result<(), String> {
    let source = read_source_file(path, max_input_bytes)?;
    let timeline = timeline_from_source_with_options(&source, options)?;
    play_timeline(&timeline)
}

#[cfg(not(target_arch = "wasm32"))]
fn watch_file(path: &Path, max_input_bytes: usize) -> Result<(), String> {
    let watch_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    redraw_watched_file(&watch_path, max_input_bytes)?;

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

    for event in rx {
        match event {
            Ok(event) if should_rerender(&event, &watch_path) => {
                redraw_watched_file(&watch_path, max_input_bytes)?;
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
fn watch_file(_path: &Path, _max_input_bytes: usize) -> Result<(), String> {
    Err(msg("watch-wasm"))
}

#[cfg(not(target_arch = "wasm32"))]
fn should_rerender(event: &Event, path: &Path) -> bool {
    matches!(
        event.kind,
        EventKind::Any | EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
    ) && (event.paths.is_empty() || event.paths.iter().any(|event_path| event_path == path))
}

#[cfg(not(target_arch = "wasm32"))]
fn redraw_watched_file(path: &Path, max_input_bytes: usize) -> Result<(), String> {
    let output = read_source_file(path, max_input_bytes)
        .and_then(|source| render_text_source(&source, &RenderOptions::default()))
        .unwrap_or_else(|error| format!("{error}\n"));
    redraw_message(&output)
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

fn parse_diagram(source: &str) -> Result<Diagram, String> {
    MermaidParser::parse_diagram(source).map_err(|error| {
        msg_args(
            "parse-error",
            &[
                msg_arg("kind", format!("{:?}", error.kind)),
                msg_arg("start", error.span.start),
                msg_arg("end", error.span.end),
            ],
        )
    })
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
fn play_timeline(timeline: &Timeline) -> Result<(), String> {
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
    .render_interactive_timeline(&mut terminal, timeline)
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
fn play_timeline(_timeline: &Timeline) -> Result<(), String> {
    Err(msg("play-wasm"))
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
        ANIMATED_PARTIAL_ROOTS, Cli, Command, DEFAULT_INPUT_LIMIT_BYTES, PluginCommand,
        PluginRegistry, RenderCharset, RenderFormat, RenderOptions, RenderTheme,
        ResolvedPluginPackage, STATIC_ONLY_ROOTS, UNSUPPORTED_ROOTS, compat_report,
        disable_plugin_records, format_lint_text, layout_warnings, lint_source, parse_diagram,
        parse_non_empty_string, parse_positive_input_bytes, parse_positive_usize,
        parse_speed_override, playback_options, plugin_runtime_policy,
        read_installed_plugin_records, read_source_file, remove_plugin_records, render_source,
        resolve_ai_library_path, resolve_crates_plugin_metadata, resolve_npm_plugin_metadata,
        timeline_from_source, timeline_from_source_with_options,
        timeline_from_source_with_render_options, write_plugin_install_record,
    };
    #[cfg(not(target_arch = "wasm32"))]
    use super::{PlaybackAction, PlaybackState, should_rerender};
    use clap::Parser as _;
    #[cfg(not(target_arch = "wasm32"))]
    use crossterm::event::KeyCode;
    use kumeyuri_core::{abi::Capability, animator::AnimationOptions};
    #[cfg(not(target_arch = "wasm32"))]
    use notify::{
        Event, EventKind,
        event::{DataChange, ModifyKind},
    };
    #[cfg(not(target_arch = "wasm32"))]
    use std::path::Path;
    use std::{
        env,
        ffi::OsString,
        fs, process,
        time::{Duration, SystemTime},
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
        let Command::Lint { file, json } = cli.command else {
            panic!("expected lint command");
        };

        assert_eq!(file, std::path::PathBuf::from("diagram.mmd"));
        assert!(json);
    }

    #[test]
    fn layout_parser_accepts_ai_flag() {
        let cli = Cli::try_parse_from(["kumeyuri", "layout", "diagram.mmd", "--ai"]).unwrap();
        let Command::Layout { file, ai } = cli.command else {
            panic!("expected layout command");
        };

        assert_eq!(file, std::path::PathBuf::from("diagram.mmd"));
        assert!(ai);
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
    fn global_lang_parser_accepts_locale_override() {
        let cli = Cli::try_parse_from(["kumeyuri", "--lang", "ja_JP.UTF-8", "compat"]).unwrap();

        assert_eq!(cli.lang.as_deref(), Some("ja-JP"));
    }

    #[test]
    fn plugin_install_parser_accepts_package_name() {
        let cli =
            Cli::try_parse_from(["kumeyuri", "plugin", "install", "kumeyuri-render-pdf"]).unwrap();
        let Command::Plugin {
            command: PluginCommand::Install { name },
        } = cli.command
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
            assert!(matches!(cli.command, Command::Plugin { .. }));
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
            "--max-label-width",
            "12",
            "--padding",
            "12",
            "--font",
            "Fira Code",
            "--plugin-allow",
            "fs.write,cache.read",
        ])
        .unwrap();
        let Command::Render { options, .. } = cli.command else {
            panic!("expected render command");
        };

        assert_eq!(options.theme, Some(RenderTheme::TokyoNight));
        assert_eq!(options.dark_theme, Some(RenderTheme::Dracula));
        assert_eq!(options.charset, Some(RenderCharset::Unicode));
        assert_eq!(options.width, Some(40));
        assert_eq!(options.max_label_width, Some(12));
        assert_eq!(options.padding, Some(12));
        assert_eq!(options.font.as_deref(), Some("Fira Code"));
        let plugin_allow = options.plugin_allow.unwrap();
        assert!(plugin_allow.contains(Capability::FsWrite));
        assert!(plugin_allow.contains(Capability::CacheRead));
        assert!(!plugin_allow.contains(Capability::NetFetch));
        assert!(plugin_runtime_policy(&options).allows(Capability::FsWrite));
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

    fn unique_temp_dir(label: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        env::temp_dir().join(format!("kumeyuri-cli-{label}-{}-{nanos}", process::id()))
    }
}
