use std::{
    fs, io,
    io::Write,
    path::{Path, PathBuf},
    process::ExitCode,
};

use clap::{Parser, Subcommand, ValueEnum};
use kumeyuri_core::{
    animator::{Animator, Timeline},
    ast::Diagram,
    frame::StaticFrameRenderer,
    parser::Parser as MermaidParser,
    text::{TextOutputBackend, TextOutputConfig},
};

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
    Render {
        #[arg(value_name = "FILE")]
        file: PathBuf,
        #[arg(long, value_enum, default_value_t = RenderFormat::Text)]
        format: RenderFormat,
    },
    Watch {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
    Play {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum RenderFormat {
    Text,
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
        Command::Render { file, format } => render_file(&file, format),
        Command::Watch { file } => watch_file(&file),
        Command::Play { file } => play_file(&file),
    }
}

fn render_file(path: &Path, format: RenderFormat) -> Result<(), String> {
    let source = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let output = render_source(&source, format)?;
    io::stdout()
        .write_all(output.as_bytes())
        .map_err(|error| format!("failed to write stdout: {error}"))
}

fn render_source(source: &str, format: RenderFormat) -> Result<String, String> {
    match format {
        RenderFormat::Text => {
            let diagram = parse_diagram(source)?;
            let frame = StaticFrameRenderer::default().render_diagram(&diagram);
            Ok(TextOutputBackend::new(TextOutputConfig {
                trim_trailing_whitespace: true,
                final_newline: true,
            })
            .render_frame(&frame))
        }
    }
}

fn play_file(path: &Path) -> Result<(), String> {
    let source = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let timeline = timeline_from_source(&source)?;
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
        .and_then(|source| render_source(&source, RenderFormat::Text))
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

fn timeline_from_source(source: &str) -> Result<Timeline, String> {
    let diagram = parse_diagram(source)?;
    Animator::animate_diagram(&diagram)
        .map_err(|error| format!("animation config error: {error:?}"))
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
    #[cfg(not(target_arch = "wasm32"))]
    use super::{PlaybackAction, PlaybackState, should_rerender};
    use super::{RenderFormat, render_source, timeline_from_source};
    #[cfg(not(target_arch = "wasm32"))]
    use crossterm::event::KeyCode;
    #[cfg(not(target_arch = "wasm32"))]
    use notify::{
        Event, EventKind,
        event::{DataChange, ModifyKind},
    };
    #[cfg(not(target_arch = "wasm32"))]
    use std::path::Path;

    #[test]
    fn renders_mermaid_source_to_text() {
        let output = render_source("graph TD\nA --> B", RenderFormat::Text).unwrap();

        assert!(output.contains('A'));
        assert!(output.contains('B'));
        assert!(output.ends_with('\n'));
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
