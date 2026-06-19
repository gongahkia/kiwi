#![allow(dead_code)]

use base64::{Engine, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};

use crate::{
    RenderCharset, RenderFormat, RenderOptions, RenderTheme, layout_warnings, lint_source,
    parse_diagram, render_source,
};

pub(crate) const RENDER_DIAGRAM_TOOL_NAME: &str = "render_diagram";
pub(crate) const LINT_DIAGRAM_TOOL_NAME: &str = "lint_diagram";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct RenderDiagramRequest {
    pub source: String,
    #[serde(default)]
    pub format: McpRenderFormat,
    #[serde(default)]
    pub theme: Option<McpRenderTheme>,
    #[serde(default)]
    pub dark_theme: Option<McpRenderTheme>,
    #[serde(default)]
    pub charset: Option<McpRenderCharset>,
    #[serde(default)]
    pub width: Option<usize>,
    #[serde(default)]
    pub max_label_width: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct RenderDiagramResponse {
    pub format: McpRenderFormat,
    pub mime_type: String,
    pub encoding: McpContentEncoding,
    pub content: String,
    pub warnings: Vec<McpLayoutWarning>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct McpLayoutWarning {
    pub code: String,
    pub message: String,
    pub suggestion: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct LintDiagramRequest {
    pub source: String,
    #[serde(default)]
    pub file: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct LintDiagramResponse {
    pub file: String,
    pub ok: bool,
    pub warnings: Vec<McpLayoutWarning>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum McpRenderFormat {
    #[default]
    Text,
    Svg,
    Gif,
    Apng,
    Webp,
    Vtt,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum McpRenderTheme {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum McpRenderCharset {
    Ascii,
    Unicode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum McpContentEncoding {
    Utf8,
    Base64,
}

pub(crate) fn render_diagram(
    request: &RenderDiagramRequest,
) -> Result<RenderDiagramResponse, String> {
    let options = request.render_options();
    let diagram = parse_diagram(&request.source)?;
    let warnings = layout_warnings(&diagram, &options)
        .into_iter()
        .map(|warning| McpLayoutWarning {
            code: warning.code.to_owned(),
            message: warning.message,
            suggestion: warning.suggestion,
        })
        .collect();
    let format = request.format.render_format();
    let bytes = render_source(&request.source, format, &options)?;
    let (encoding, content) = if request.format.is_binary() {
        (McpContentEncoding::Base64, STANDARD.encode(bytes))
    } else {
        (
            McpContentEncoding::Utf8,
            String::from_utf8(bytes).map_err(|error| error.to_string())?,
        )
    };
    Ok(RenderDiagramResponse {
        format: request.format,
        mime_type: request.format.mime_type().to_owned(),
        encoding,
        content,
        warnings,
    })
}

pub(crate) fn lint_diagram(request: &LintDiagramRequest) -> Result<LintDiagramResponse, String> {
    let file = request.file.as_deref().unwrap_or("<inline>");
    let report = lint_source(file, &request.source)?;
    Ok(LintDiagramResponse {
        file: report.file,
        ok: report.ok,
        warnings: report
            .warnings
            .into_iter()
            .map(|warning| McpLayoutWarning {
                code: warning.code.to_owned(),
                message: warning.message,
                suggestion: warning.suggestion,
            })
            .collect(),
    })
}

impl RenderDiagramRequest {
    fn render_options(&self) -> RenderOptions {
        RenderOptions {
            theme: self.theme.map(McpRenderTheme::render_theme),
            dark_theme: self.dark_theme.map(McpRenderTheme::render_theme),
            charset: self.charset.map(McpRenderCharset::render_charset),
            width: self.width,
            max_label_width: self.max_label_width,
            ..RenderOptions::default()
        }
    }
}

impl McpRenderFormat {
    const fn render_format(self) -> RenderFormat {
        match self {
            Self::Text => RenderFormat::Text,
            Self::Svg => RenderFormat::Svg,
            Self::Gif => RenderFormat::Gif,
            Self::Apng => RenderFormat::Apng,
            Self::Webp => RenderFormat::Webp,
            Self::Vtt => RenderFormat::Vtt,
        }
    }

    const fn is_binary(self) -> bool {
        matches!(self, Self::Gif | Self::Apng | Self::Webp)
    }

    const fn mime_type(self) -> &'static str {
        match self {
            Self::Text => "text/plain; charset=utf-8",
            Self::Svg => "image/svg+xml",
            Self::Gif => "image/gif",
            Self::Apng => "image/apng",
            Self::Webp => "image/webp",
            Self::Vtt => "text/vtt; charset=utf-8",
        }
    }
}

impl McpRenderTheme {
    const fn render_theme(self) -> RenderTheme {
        match self {
            Self::Default => RenderTheme::Default,
            Self::Mono => RenderTheme::Mono,
            Self::TokyoNight => RenderTheme::TokyoNight,
            Self::Github => RenderTheme::Github,
            Self::Dracula => RenderTheme::Dracula,
            Self::SolarizedLight => RenderTheme::SolarizedLight,
            Self::SolarizedDark => RenderTheme::SolarizedDark,
            Self::Nord => RenderTheme::Nord,
            Self::CatppuccinMocha => RenderTheme::CatppuccinMocha,
            Self::HighContrast => RenderTheme::HighContrast,
            Self::PrintMono => RenderTheme::PrintMono,
        }
    }
}

impl McpRenderCharset {
    const fn render_charset(self) -> RenderCharset {
        match self {
            Self::Ascii => RenderCharset::Ascii,
            Self::Unicode => RenderCharset::Unicode,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        LINT_DIAGRAM_TOOL_NAME, LintDiagramRequest, McpContentEncoding, McpRenderCharset,
        McpRenderFormat, McpRenderTheme, RENDER_DIAGRAM_TOOL_NAME, RenderDiagramRequest,
        lint_diagram, render_diagram,
    };

    #[test]
    fn render_diagram_tool_surface_renders_text() {
        let response = render_diagram(&RenderDiagramRequest {
            source: "graph TD\nA --> B\n".to_owned(),
            format: McpRenderFormat::Text,
            theme: Some(McpRenderTheme::Mono),
            dark_theme: None,
            charset: Some(McpRenderCharset::Ascii),
            width: None,
            max_label_width: None,
        })
        .unwrap();

        assert_eq!(RENDER_DIAGRAM_TOOL_NAME, "render_diagram");
        assert_eq!(response.format, McpRenderFormat::Text);
        assert_eq!(response.encoding, McpContentEncoding::Utf8);
        assert_eq!(response.mime_type, "text/plain; charset=utf-8");
        assert!(response.content.contains("A"));
        assert!(response.content.contains("B"));
    }

    #[test]
    fn render_diagram_tool_surface_renders_svg() {
        let response = render_diagram(&RenderDiagramRequest {
            source: "sequenceDiagram\nAlice->>Bob: hello\n".to_owned(),
            format: McpRenderFormat::Svg,
            theme: Some(McpRenderTheme::Github),
            dark_theme: Some(McpRenderTheme::HighContrast),
            charset: None,
            width: None,
            max_label_width: None,
        })
        .unwrap();

        assert_eq!(response.encoding, McpContentEncoding::Utf8);
        assert_eq!(response.mime_type, "image/svg+xml");
        assert!(response.content.contains("<svg"));
        assert!(response.content.contains("Alice"));
    }

    #[test]
    fn render_diagram_tool_surface_reports_layout_warnings() {
        let response = render_diagram(&RenderDiagramRequest {
            source: "graph TD\nA\n".to_owned(),
            format: McpRenderFormat::Text,
            theme: None,
            dark_theme: None,
            charset: None,
            width: None,
            max_label_width: None,
        })
        .unwrap();

        assert_eq!(response.warnings.len(), 1);
        assert_eq!(response.warnings[0].code, "flowchart.orphan_node");
    }

    #[test]
    fn lint_diagram_tool_surface_reports_existing_lint_shape() {
        let response = lint_diagram(&LintDiagramRequest {
            source: "graph TD\nA\nB --> C\n".to_owned(),
            file: Some("diagram.mmd".to_owned()),
        })
        .unwrap();

        assert_eq!(LINT_DIAGRAM_TOOL_NAME, "lint_diagram");
        assert_eq!(response.file, "diagram.mmd");
        assert!(!response.ok);
        assert_eq!(response.warnings.len(), 1);
        assert_eq!(response.warnings[0].code, "flowchart.orphan_node");
    }

    #[test]
    fn lint_diagram_tool_surface_defaults_inline_file() {
        let response = lint_diagram(&LintDiagramRequest {
            source: "graph TD\nA --> B\n".to_owned(),
            file: None,
        })
        .unwrap();

        assert_eq!(response.file, "<inline>");
        assert!(response.ok);
        assert!(response.warnings.is_empty());
    }
}
