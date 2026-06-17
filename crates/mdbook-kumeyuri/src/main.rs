use std::{io, process};

use anyhow::{Result, anyhow, bail};
use clap::{Arg, ArgMatches, Command};
use kumeyuri_core::{
    animator::{AnimationOptions, Animator},
    frame::{Charset, Frame, StaticFrameRenderer},
    parser::Parser as MermaidParser,
    text::{TextOutputBackend, TextOutputConfig},
    theme::{BuiltInTheme, RgbColor, Theme},
};
use kumeyuri_render_svg::{SvgRenderConfig, SvgRenderer};
use mdbook_preprocessor::{
    Preprocessor, PreprocessorContext,
    book::{Book, Chapter},
};
use semver::{Version, VersionReq};

fn main() {
    let matches = app().get_matches();
    let preprocessor = KumeyuriPreprocessor;

    if let Some(args) = matches.subcommand_matches("supports") {
        handle_supports(&preprocessor, args);
    }
    if let Err(error) = handle_preprocessing(&preprocessor) {
        eprintln!("{error:?}");
        process::exit(1);
    }
}

fn app() -> Command {
    Command::new("mdbook-kumeyuri")
        .about("Render Mermaid fences in mdBook chapters with kumeyuri")
        .subcommand(
            Command::new("supports")
                .arg(Arg::new("renderer").required(true))
                .about("Check whether a renderer is supported"),
        )
}

fn handle_supports(preprocessor: &dyn Preprocessor, args: &ArgMatches) -> ! {
    let renderer = args
        .get_one::<String>("renderer")
        .expect("renderer is required");
    match preprocessor.supports_renderer(renderer) {
        Ok(true) => process::exit(0),
        Ok(false) => process::exit(1),
        Err(error) => {
            eprintln!("{error:?}");
            process::exit(1);
        }
    }
}

fn handle_preprocessing(preprocessor: &dyn Preprocessor) -> Result<()> {
    let (ctx, book) = mdbook_preprocessor::parse_input(io::stdin())?;
    let book_version = Version::parse(&ctx.mdbook_version)?;
    let version_req = VersionReq::parse(mdbook_preprocessor::MDBOOK_VERSION)?;
    if !version_req.matches(&book_version) {
        eprintln!(
            "warning: {} was built against mdBook {}, but mdBook {} invoked it",
            preprocessor.name(),
            mdbook_preprocessor::MDBOOK_VERSION,
            ctx.mdbook_version
        );
    }

    let processed = preprocessor.run(&ctx, book)?;
    serde_json::to_writer(io::stdout(), &processed)?;
    Ok(())
}

#[derive(Debug, Clone, Copy)]
struct KumeyuriPreprocessor;

impl Preprocessor for KumeyuriPreprocessor {
    fn name(&self) -> &str {
        "kumeyuri"
    }

    fn run(&self, ctx: &PreprocessorContext, mut book: Book) -> Result<Book> {
        let options = PreprocessorOptions::from_context(ctx)?;
        book.for_each_chapter_mut(|chapter| {
            if let Err(error) = process_chapter(chapter, &options) {
                chapter.content.push_str(&format!(
                    "\n\n<!-- kumeyuri render error in {}: {error} -->\n",
                    chapter.name
                ));
            }
        });
        Ok(book)
    }

    fn supports_renderer(&self, renderer: &str) -> Result<bool> {
        Ok(matches!(renderer, "html" | "markdown"))
    }
}

fn process_chapter(chapter: &mut Chapter, options: &PreprocessorOptions) -> Result<()> {
    chapter.content = render_mermaid_fences(&chapter.content, options)?;
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PreprocessorOptions {
    format: RenderFormat,
    replace: bool,
    theme: Option<BuiltInTheme>,
    dark_theme: Option<BuiltInTheme>,
    charset: Option<Charset>,
    width: Option<usize>,
    padding: Option<u16>,
    font: Option<String>,
}

impl PreprocessorOptions {
    fn from_context(ctx: &PreprocessorContext) -> Result<Self> {
        Ok(Self {
            format: config_string(ctx, "format")?
                .as_deref()
                .map(RenderFormat::parse)
                .transpose()?
                .unwrap_or(RenderFormat::Svg),
            replace: config_bool(ctx, "replace")?.unwrap_or(false),
            theme: config_string(ctx, "theme")?
                .as_deref()
                .map(parse_theme)
                .transpose()?,
            dark_theme: config_string(ctx, "dark-theme")?
                .as_deref()
                .map(parse_theme)
                .transpose()?,
            charset: config_string(ctx, "charset")?
                .as_deref()
                .map(parse_charset)
                .transpose()?,
            width: config_usize(ctx, "width")?,
            padding: config_usize(ctx, "padding")?
                .map(|padding| u16::try_from(padding).unwrap_or(u16::MAX)),
            font: config_string(ctx, "font")?,
        })
    }
}

impl Default for PreprocessorOptions {
    fn default() -> Self {
        Self {
            format: RenderFormat::Svg,
            replace: false,
            theme: None,
            dark_theme: None,
            charset: None,
            width: None,
            padding: None,
            font: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RenderFormat {
    Svg,
    Text,
}

impl RenderFormat {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "svg" => Ok(Self::Svg),
            "text" => Ok(Self::Text),
            _ => bail!("unsupported kumeyuri mdBook format {value:?}; expected svg or text"),
        }
    }
}

fn config_string(ctx: &PreprocessorContext, name: &str) -> Result<Option<String>> {
    ctx.config
        .get(&format!("preprocessor.kumeyuri.{name}"))
        .map_err(|error| anyhow!("invalid preprocessor.kumeyuri.{name}: {error}"))
}

fn config_bool(ctx: &PreprocessorContext, name: &str) -> Result<Option<bool>> {
    ctx.config
        .get(&format!("preprocessor.kumeyuri.{name}"))
        .map_err(|error| anyhow!("invalid preprocessor.kumeyuri.{name}: {error}"))
}

fn config_usize(ctx: &PreprocessorContext, name: &str) -> Result<Option<usize>> {
    ctx.config
        .get(&format!("preprocessor.kumeyuri.{name}"))
        .map_err(|error| anyhow!("invalid preprocessor.kumeyuri.{name}: {error}"))
}

fn parse_theme(value: &str) -> Result<BuiltInTheme> {
    match value {
        "default" => Ok(BuiltInTheme::Default),
        "mono" => Ok(BuiltInTheme::Mono),
        "tokyo-night" => Ok(BuiltInTheme::TokyoNight),
        "github" => Ok(BuiltInTheme::Github),
        "dracula" => Ok(BuiltInTheme::Dracula),
        _ => bail!("unsupported kumeyuri theme {value:?}"),
    }
}

fn parse_charset(value: &str) -> Result<Charset> {
    match value {
        "ascii" => Ok(Charset::Ascii),
        "unicode" => Ok(Charset::Unicode),
        _ => bail!("unsupported kumeyuri charset {value:?}"),
    }
}

fn render_mermaid_fences(markdown: &str, options: &PreprocessorOptions) -> Result<String> {
    let mut output = String::new();
    let mut lines = markdown.split_inclusive('\n').peekable();
    while let Some(line) = lines.next() {
        let Some(info) = mermaid_fence_info(line) else {
            output.push_str(line);
            continue;
        };

        let mut source = String::new();
        let mut closed = false;
        for inner in lines.by_ref() {
            if is_closing_fence(inner) {
                let rendered = render_source(&source, options)?;
                if options.replace {
                    output.push_str(&rendered_block(&rendered, options.format));
                } else {
                    output.push_str(line);
                    output.push_str(&source);
                    output.push_str(inner);
                    output.push('\n');
                    output.push_str(&rendered_block(&rendered, options.format));
                }
                closed = true;
                break;
            }
            source.push_str(inner);
        }
        if !closed {
            output.push_str(line);
            output.push_str(&source);
        }
        let _ = info;
    }
    Ok(output)
}

fn mermaid_fence_info(line: &str) -> Option<&str> {
    let trimmed = line.trim_start();
    let info = trimmed.strip_prefix("```")?.trim();
    let first = info.split_whitespace().next().unwrap_or_default();
    matches!(first, "mermaid" | "mmd").then_some(info)
}

fn is_closing_fence(line: &str) -> bool {
    line.trim() == "```"
}

fn render_source(source: &str, options: &PreprocessorOptions) -> Result<String> {
    match options.format {
        RenderFormat::Svg => render_svg_source(source, options),
        RenderFormat::Text => render_text_source(source, options),
    }
}

fn render_text_source(source: &str, options: &PreprocessorOptions) -> Result<String> {
    let diagram = MermaidParser::parse(source)?;
    let frame = apply_frame_width(frame_renderer(options).render_diagram(&diagram), options);
    Ok(TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: options.width.is_none(),
        final_newline: false,
    })
    .render_frame(&frame))
}

fn render_svg_source(source: &str, options: &PreprocessorOptions) -> Result<String> {
    let diagram = MermaidParser::parse(source)?;
    let timeline = Animator::animate_diagram_with_options_and_renderer(
        &diagram,
        AnimationOptions::default(),
        frame_renderer(options),
    )?;
    Ok(SvgRenderer::new(svg_config(options)).render_timeline(&timeline))
}

fn frame_renderer(options: &PreprocessorOptions) -> StaticFrameRenderer {
    StaticFrameRenderer::default().with_theme(render_theme(options))
}

fn render_theme(options: &PreprocessorOptions) -> Theme {
    let mut theme = options
        .theme
        .map_or_else(Theme::default_theme, |theme| theme.theme());
    if let Some(charset) = options.charset {
        theme.charset = charset;
    }
    theme
}

fn svg_config(options: &PreprocessorOptions) -> SvgRenderConfig {
    let theme = render_theme(options);
    let mut config = SvgRenderConfig {
        foreground: css_color(theme.colors.foreground),
        background: css_color(theme.colors.background),
        ..SvgRenderConfig::default()
    };
    if let Some(padding) = options.padding {
        config.padding = padding;
    }
    if let Some(font) = &options.font {
        config.font_family = font.clone();
    }
    if let Some(dark_theme) = options.dark_theme {
        let dark_theme = dark_theme.theme();
        config.dark_foreground = Some(css_color(dark_theme.colors.foreground));
        config.dark_background = Some(css_color(dark_theme.colors.background));
    }
    config
}

fn apply_frame_width(frame: Frame, options: &PreprocessorOptions) -> Frame {
    match options.width {
        Some(width) => frame.with_min_width(width),
        None => frame,
    }
}

fn css_color(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

fn rendered_block(rendered: &str, format: RenderFormat) -> String {
    match format {
        RenderFormat::Svg => format!(
            "<div class=\"kumeyuri-render kumeyuri-render-svg\">\n{}\n</div>\n",
            rendered.trim_end()
        ),
        RenderFormat::Text => format!("```text\n{}\n```\n", rendered.trim_end()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mdbook_preprocessor::book::BookItem;

    #[test]
    fn renders_text_below_mermaid_fence() {
        let markdown = "before\n```mermaid\ngraph TD\nA --> B\n```\nafter\n";
        let output = render_mermaid_fences(
            markdown,
            &PreprocessorOptions {
                format: RenderFormat::Text,
                ..PreprocessorOptions::default()
            },
        )
        .unwrap();

        assert!(output.contains("```mermaid\ngraph TD\nA --> B\n```"));
        assert!(output.contains("```text\n"));
        assert!(output.contains("| A |"));
        assert!(output.contains("after\n"));
    }

    #[test]
    fn can_replace_mermaid_fence_with_svg() {
        let markdown = "```mmd\ngraph TD\nA --> B\n```\n";
        let output = render_mermaid_fences(
            markdown,
            &PreprocessorOptions {
                replace: true,
                ..PreprocessorOptions::default()
            },
        )
        .unwrap();

        assert!(!output.contains("```mmd"));
        assert!(output.contains("<div class=\"kumeyuri-render kumeyuri-render-svg\">"));
        assert!(output.contains("<svg "));
    }

    #[test]
    fn leaves_unclosed_fence_unchanged() {
        let markdown = "```mermaid\ngraph TD\n";
        let output = render_mermaid_fences(markdown, &PreprocessorOptions::default()).unwrap();
        assert_eq!(output, markdown);
    }

    #[test]
    fn preprocesses_all_book_chapters() {
        let mut book = Book::new();
        book.push_item(Chapter::new(
            "chapter",
            "```mermaid\ngraph TD\nA --> B\n```\n".to_owned(),
            "chapter.md",
            Vec::new(),
        ));
        let mut chapter = Chapter::new(
            "nested",
            "```mermaid\ngraph TD\nC --> D\n```\n".to_owned(),
            "nested.md",
            vec!["chapter".to_owned()],
        );
        process_chapter(
            &mut chapter,
            &PreprocessorOptions {
                format: RenderFormat::Text,
                ..PreprocessorOptions::default()
            },
        )
        .unwrap();
        assert!(chapter.content.contains("| C |"));

        let BookItem::Chapter(first) = &book.items[0] else {
            panic!("expected chapter");
        };
        assert!(!first.content.contains("kumeyuri-render"));
    }
}
