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
use serde_json::Value;

fn main() {
    let matches = app().get_matches();
    if let Some(args) = matches.subcommand_matches("supports") {
        handle_supports(args);
    }
    if let Err(error) = handle_preprocessing() {
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

fn handle_supports(args: &ArgMatches) -> ! {
    let renderer = args
        .get_one::<String>("renderer")
        .expect("renderer is required");
    process::exit(i32::from(!matches!(renderer.as_str(), "html" | "markdown")));
}

fn handle_preprocessing() -> Result<()> {
    let input: Value = serde_json::from_reader(io::stdin())?;
    let book = preprocess_input(input)?;
    serde_json::to_writer(io::stdout(), &book)?;
    Ok(())
}

fn preprocess_input(input: Value) -> Result<Value> {
    let Value::Array(mut payload) = input else {
        bail!("mdBook preprocessor input must be [context, book]");
    };
    if payload.len() != 2 {
        bail!("mdBook preprocessor input must contain context and book");
    }
    let book = payload.pop().expect("book value exists");
    let context = payload.pop().expect("context value exists");
    let options = PreprocessorOptions::from_context(&context)?;
    process_book(book, &options)
}

fn process_book(mut book: Value, options: &PreprocessorOptions) -> Result<Value> {
    let items = book
        .get_mut("items")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| anyhow!("mdBook Book.items must be an array"))?;
    process_items(items, options)?;
    Ok(book)
}

fn process_items(items: &mut [Value], options: &PreprocessorOptions) -> Result<()> {
    for item in items {
        let Some(chapter) = item.get_mut("Chapter") else {
            continue;
        };
        let name = chapter
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("<unnamed>")
            .to_owned();
        let content = chapter
            .get("content")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("chapter {name} content must be a string"))?;
        let rendered = render_mermaid_fences(content, options)
            .map_err(|error| anyhow!("kumeyuri mdBook render failed in chapter {name}: {error}"))?;
        chapter["content"] = Value::String(rendered);

        if let Some(sub_items) = chapter.get_mut("sub_items").and_then(Value::as_array_mut) {
            process_items(sub_items, options)?;
        }
    }
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
    fn from_context(context: &Value) -> Result<Self> {
        let config = context
            .get("config")
            .and_then(|config| config.get("preprocessor"))
            .and_then(|preprocessors| preprocessors.get("kumeyuri"));
        Ok(Self {
            format: config_string(config, "format")?
                .as_deref()
                .map(RenderFormat::parse)
                .transpose()?
                .unwrap_or(RenderFormat::Svg),
            replace: config_bool(config, "replace")?.unwrap_or(false),
            theme: config_string(config, "theme")?
                .as_deref()
                .map(parse_theme)
                .transpose()?,
            dark_theme: config_string(config, "dark-theme")?
                .as_deref()
                .map(parse_theme)
                .transpose()?,
            charset: config_string(config, "charset")?
                .as_deref()
                .map(parse_charset)
                .transpose()?,
            width: config_usize(config, "width")?,
            padding: config_usize(config, "padding")?
                .map(|padding| u16::try_from(padding).unwrap_or(u16::MAX)),
            font: config_string(config, "font")?,
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

fn config_string(config: Option<&Value>, name: &str) -> Result<Option<String>> {
    let Some(value) = config.and_then(|config| config.get(name)) else {
        return Ok(None);
    };
    value
        .as_str()
        .map(ToOwned::to_owned)
        .map(Some)
        .ok_or_else(|| anyhow!("preprocessor.kumeyuri.{name} must be a string"))
}

fn config_bool(config: Option<&Value>, name: &str) -> Result<Option<bool>> {
    let Some(value) = config.and_then(|config| config.get(name)) else {
        return Ok(None);
    };
    value
        .as_bool()
        .map(Some)
        .ok_or_else(|| anyhow!("preprocessor.kumeyuri.{name} must be a boolean"))
}

fn config_usize(config: Option<&Value>, name: &str) -> Result<Option<usize>> {
    let Some(value) = config.and_then(|config| config.get(name)) else {
        return Ok(None);
    };
    let number = value
        .as_u64()
        .ok_or_else(|| anyhow!("preprocessor.kumeyuri.{name} must be an unsigned integer"))?;
    usize::try_from(number)
        .map(Some)
        .map_err(|_| anyhow!("preprocessor.kumeyuri.{name} is too large"))
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
        if mermaid_fence_info(line).is_none() {
            output.push_str(line);
            continue;
        }

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
    let diagram = MermaidParser::parse_diagram(source).map_err(parser_error)?;
    let frame = apply_frame_width(frame_renderer(options).render_diagram(&diagram), options);
    Ok(TextOutputBackend::new(TextOutputConfig {
        trim_trailing_whitespace: options.width.is_none(),
        final_newline: false,
    })
    .render_frame(&frame))
}

fn render_svg_source(source: &str, options: &PreprocessorOptions) -> Result<String> {
    let diagram = MermaidParser::parse_diagram(source).map_err(parser_error)?;
    let timeline = Animator::animate_diagram_with_options_and_renderer(
        &diagram,
        AnimationOptions::default(),
        frame_renderer(options),
    )
    .map_err(|error| anyhow!("animation config error: {error:?}"))?;
    Ok(SvgRenderer::new(svg_config(options)).render_timeline(&timeline))
}

fn parser_error(error: kumeyuri_core::parser::ParseError) -> anyhow::Error {
    anyhow!(
        "parse error {:?} at {}..{}",
        error.kind,
        error.span.start,
        error.span.end
    )
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
    use serde_json::json;

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
    fn preprocesses_nested_chapters_from_mdbook_payload() {
        let payload = json!([
            {
                "config": {
                    "preprocessor": {
                        "kumeyuri": {
                            "format": "text",
                            "replace": true
                        }
                    }
                },
                "mdbook_version": "0.5.3",
                "renderer": "html",
                "root": "/tmp/book"
            },
            {
                "items": [
                    {
                        "Chapter": {
                            "name": "Chapter 1",
                            "content": "```mermaid\ngraph TD\nA --> B\n```\n",
                            "sub_items": [
                                {
                                    "Chapter": {
                                        "name": "Nested",
                                        "content": "```mermaid\ngraph TD\nC --> D\n```\n",
                                        "sub_items": []
                                    }
                                }
                            ]
                        }
                    }
                ]
            }
        ]);

        let book = preprocess_input(payload).unwrap();
        let first = book["items"][0]["Chapter"]["content"].as_str().unwrap();
        let nested = book["items"][0]["Chapter"]["sub_items"][0]["Chapter"]["content"]
            .as_str()
            .unwrap();
        assert!(!first.contains("```mermaid"));
        assert!(first.contains("| A |"));
        assert!(nested.contains("| C |"));
    }
}
