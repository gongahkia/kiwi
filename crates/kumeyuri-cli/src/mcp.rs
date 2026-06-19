#![allow(dead_code)]

use base64::{Engine, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};

use crate::{
    ANIMATED_PARTIAL_ROOTS, CompatRoot, RenderCharset, RenderFormat, RenderOptions, RenderTheme,
    STATIC_ONLY_ROOTS, ThemeSource, UNSUPPORTED_ROOTS, layout_warnings, lint_source, msg,
    parse_diagram, render_source, theme_entries_for_current_dir, theme_source_label,
};

pub(crate) const RENDER_DIAGRAM_TOOL_NAME: &str = "render_diagram";
pub(crate) const LINT_DIAGRAM_TOOL_NAME: &str = "lint_diagram";
pub(crate) const LIST_THEMES_TOOL_NAME: &str = "list_themes";
pub(crate) const LIST_DIAGRAM_TYPES_TOOL_NAME: &str = "list_diagram_types";

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ListThemesResponse {
    pub themes: Vec<McpThemeEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct McpThemeEntry {
    pub name: String,
    pub source: String,
    pub path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ListDiagramTypesResponse {
    pub diagram_types: Vec<McpDiagramType>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct McpDiagramType {
    pub id: String,
    pub label: String,
    pub roots: Vec<String>,
    pub support: McpDiagramSupport,
    pub caveat: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum McpDiagramSupport {
    AnimatedPartial,
    StaticOnly,
    Unsupported,
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

pub(crate) fn list_themes() -> Result<ListThemesResponse, String> {
    Ok(ListThemesResponse {
        themes: theme_entries_for_current_dir()?
            .into_iter()
            .map(|entry| McpThemeEntry {
                name: entry.name,
                source: theme_source_label(&entry.source).to_owned(),
                path: theme_path(&entry.source),
            })
            .collect(),
    })
}

pub(crate) fn list_diagram_types() -> ListDiagramTypesResponse {
    let mut diagram_types = Vec::new();
    append_diagram_types(
        &mut diagram_types,
        ANIMATED_PARTIAL_ROOTS,
        McpDiagramSupport::AnimatedPartial,
    );
    append_diagram_types(
        &mut diagram_types,
        STATIC_ONLY_ROOTS,
        McpDiagramSupport::StaticOnly,
    );
    append_diagram_types(
        &mut diagram_types,
        UNSUPPORTED_ROOTS,
        McpDiagramSupport::Unsupported,
    );
    ListDiagramTypesResponse { diagram_types }
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

fn theme_path(source: &ThemeSource) -> Option<String> {
    match source {
        ThemeSource::Project(path)
        | ThemeSource::XdgDataHome(path)
        | ThemeSource::XdgDataDir(path) => Some(path.display().to_string()),
        ThemeSource::Bundled(_) => None,
    }
}

fn append_diagram_types(
    output: &mut Vec<McpDiagramType>,
    roots: &[CompatRoot],
    support: McpDiagramSupport,
) {
    output.extend(roots.iter().map(|root| {
        McpDiagramType {
            id: root
                .label_id
                .strip_prefix("compat-label-")
                .unwrap_or(root.label_id)
                .to_owned(),
            label: msg(root.label_id),
            roots: root.roots.iter().map(|value| (*value).to_owned()).collect(),
            support,
            caveat: msg(root.caveat_id),
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::{
        LINT_DIAGRAM_TOOL_NAME, LIST_DIAGRAM_TYPES_TOOL_NAME, LIST_THEMES_TOOL_NAME,
        LintDiagramRequest, McpContentEncoding, McpDiagramSupport, McpRenderCharset,
        McpRenderFormat, McpRenderTheme, RENDER_DIAGRAM_TOOL_NAME, RenderDiagramRequest,
        lint_diagram, list_diagram_types, list_themes, render_diagram,
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

    #[test]
    fn list_themes_tool_surface_reports_discovered_themes() {
        let response = list_themes().unwrap();

        assert_eq!(LIST_THEMES_TOOL_NAME, "list_themes");
        assert!(response.themes.iter().any(|theme| theme.name == "default"));
        assert!(
            response
                .themes
                .iter()
                .any(|theme| theme.name == "print-mono" && theme.source == "bundled")
        );
    }

    #[test]
    fn list_diagram_types_tool_surface_reports_supported_and_unsupported_roots() {
        let response = list_diagram_types();

        assert_eq!(LIST_DIAGRAM_TYPES_TOOL_NAME, "list_diagram_types");
        assert_eq!(response.diagram_types.len(), 31);
        assert!(response.diagram_types.iter().any(|diagram| {
            diagram.id == "flowchart"
                && diagram.support == McpDiagramSupport::AnimatedPartial
                && diagram.roots == ["graph", "flowchart"]
        }));
        assert!(response.diagram_types.iter().any(|diagram| {
            diagram.id == "cynefin"
                && diagram.support == McpDiagramSupport::Unsupported
                && diagram.roots == ["cynefin-beta"]
        }));
    }
}
