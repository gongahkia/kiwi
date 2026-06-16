use std::{
    fs, io,
    io::Write,
    path::{Path, PathBuf},
    process::ExitCode,
};

use clap::{Parser, Subcommand, ValueEnum};
use kumeyuri_core::{
    frame::StaticFrameRenderer,
    parser::Parser as MermaidParser,
    text::{TextOutputBackend, TextOutputConfig},
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
        Command::Watch { file } | Command::Play { file } => {
            let _ = file;
            Ok(())
        }
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
            let diagram = MermaidParser::parse_diagram(source).map_err(|error| {
                format!(
                    "parse error {:?} at {}..{}",
                    error.kind, error.span.start, error.span.end
                )
            })?;
            let frame = StaticFrameRenderer::default().render_diagram(&diagram);
            Ok(TextOutputBackend::new(TextOutputConfig {
                trim_trailing_whitespace: true,
                final_newline: true,
            })
            .render_frame(&frame))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{RenderFormat, render_source};

    #[test]
    fn renders_mermaid_source_to_text() {
        let output = render_source("graph TD\nA --> B", RenderFormat::Text).unwrap();

        assert!(output.contains('A'));
        assert!(output.contains('B'));
        assert!(output.ends_with('\n'));
    }
}
