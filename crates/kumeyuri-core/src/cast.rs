//! `.kumecast` v1 serialization and validation.

use std::collections::BTreeMap;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{
    animator::{KeyFrame, Timeline},
    frame::{CellStyle, Color, Frame, FrameRegion, GlyphCell, KeyFrameMarker, KeyFrameMarkerKind},
    theme::{RgbColor, Theme},
};

/// Current `.kumecast` schema version.
pub const KUMECAST_VERSION: u32 = 1;

/// Top-level `.kumecast` document.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct Kumecast {
    /// Schema version.
    pub version: u32,
    /// Original Mermaid source metadata.
    pub source: KumecastSource,
    /// Theme metadata used to render the timeline.
    pub theme: KumecastTheme,
    /// Serialized animation timeline.
    pub timeline: KumecastTimeline,
    /// Optional extension metadata.
    #[serde(default)]
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub metadata: BTreeMap<String, serde_json::Value>,
}

impl Kumecast {
    /// Build a cast document from source metadata, theme, and timeline.
    #[must_use]
    pub fn from_timeline(
        diagram_type: impl Into<String>,
        mermaid: impl Into<String>,
        theme: Theme,
        timeline: &Timeline,
    ) -> Self {
        Self {
            version: KUMECAST_VERSION,
            source: KumecastSource {
                diagram_type: diagram_type.into(),
                mermaid: mermaid.into(),
                sha256: None,
            },
            theme: KumecastTheme::from_theme(theme),
            timeline: KumecastTimeline::from_timeline(timeline),
            metadata: BTreeMap::new(),
        }
    }

    /// Serialize this cast as pretty JSON with a final newline.
    pub fn to_json_string(&self) -> Result<String, serde_json::Error> {
        let mut json = serde_json::to_string_pretty(self)?;
        json.push('\n');
        Ok(json)
    }

    /// Parse and validate a cast JSON document.
    pub fn from_json_str(source: &str) -> Result<Self, KumecastError> {
        let cast: Self = serde_json::from_str(source).map_err(KumecastError::Json)?;
        cast.validate()?;
        Ok(cast)
    }

    /// Validate schema version, source, theme, timeline, cells, and styles.
    pub fn validate(&self) -> Result<(), KumecastError> {
        if self.version != KUMECAST_VERSION {
            return Err(KumecastError::UnsupportedVersion(self.version));
        }
        if self.source.diagram_type.is_empty() {
            return Err(KumecastError::EmptySourceDiagramType);
        }
        if let Some(sha256) = &self.source.sha256
            && !is_sha256_hex(sha256)
        {
            return Err(KumecastError::InvalidSha256(sha256.clone()));
        }
        if self.theme.name.is_empty() {
            return Err(KumecastError::EmptyThemeName);
        }
        if !matches!(self.theme.charset.as_str(), "ascii" | "unicode") {
            return Err(KumecastError::InvalidCharset(self.theme.charset.clone()));
        }
        if self.timeline.frames.is_empty() {
            return Err(KumecastError::EmptyTimeline);
        }
        for (index, frame) in self.timeline.frames.iter().enumerate() {
            let expected = frame.width.saturating_mul(frame.height);
            if frame.cells.len() != expected {
                return Err(KumecastError::InvalidCellCount {
                    frame: index,
                    expected,
                    actual: frame.cells.len(),
                });
            }
            for cell in &frame.cells {
                if cell.glyph.chars().count() != 1 {
                    return Err(KumecastError::InvalidGlyph(cell.glyph.clone()));
                }
                if let Some(style) = &cell.style {
                    style.validate()?;
                }
            }
        }
        Ok(())
    }

    /// Convert this cast document back into a runtime timeline.
    pub fn to_timeline(&self) -> Result<Timeline, KumecastError> {
        self.validate()?;
        Ok(self
            .timeline
            .to_timeline()?
            .with_repeat(self.timeline.repeat))
    }
}

/// Source metadata for a `.kumecast` document.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct KumecastSource {
    /// Mermaid diagram root/type name.
    pub diagram_type: String,
    /// Original Mermaid source.
    pub mermaid: String,
    /// Optional lowercase hexadecimal SHA-256 for the source.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

/// Theme metadata for a `.kumecast` document.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KumecastTheme {
    /// Theme name.
    pub name: String,
    /// Serialized charset name.
    pub charset: String,
}

impl KumecastTheme {
    /// Build theme metadata from a runtime theme.
    #[must_use]
    pub fn from_theme(theme: Theme) -> Self {
        Self {
            name: theme.name.to_owned(),
            charset: match theme.charset {
                crate::frame::Charset::Ascii => "ascii",
                crate::frame::Charset::Unicode => "unicode",
            }
            .to_owned(),
        }
    }
}

/// Serialized animation timeline.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KumecastTimeline {
    /// Whether playback repeats.
    pub repeat: bool,
    /// Serialized keyframes.
    pub frames: Vec<KumecastFrame>,
}

impl KumecastTimeline {
    /// Build a serialized timeline from a runtime timeline.
    #[must_use]
    pub fn from_timeline(timeline: &Timeline) -> Self {
        Self {
            repeat: timeline.repeat(),
            frames: timeline
                .keyframes()
                .iter()
                .map(|keyframe| KumecastFrame::from_frame(keyframe.frame(), keyframe.duration()))
                .collect(),
        }
    }

    /// Convert this serialized timeline back into runtime frames.
    pub fn to_timeline(&self) -> Result<Timeline, KumecastError> {
        let mut timeline = Timeline::new();
        for frame in &self.frames {
            timeline.push(frame.to_keyframe()?);
        }
        Ok(timeline)
    }
}

/// Serialized timeline frame.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct KumecastFrame {
    /// Frame duration in milliseconds.
    pub duration_ms: u64,
    /// Frame width in cells.
    pub width: usize,
    /// Frame height in cells.
    pub height: usize,
    /// Row-major serialized cells.
    pub cells: Vec<KumecastCell>,
    /// Optional keyframe markers.
    #[serde(default)]
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub markers: Vec<KumecastMarker>,
}

impl KumecastFrame {
    /// Build a serialized frame from a runtime frame and duration.
    #[must_use]
    pub fn from_frame(frame: &Frame, duration: std::time::Duration) -> Self {
        Self {
            duration_ms: duration.as_millis().try_into().unwrap_or(u64::MAX),
            width: frame.width(),
            height: frame.height(),
            cells: frame.cells().iter().map(KumecastCell::from).collect(),
            markers: frame.markers().iter().map(KumecastMarker::from).collect(),
        }
    }

    /// Convert this frame into a runtime keyframe.
    pub fn to_keyframe(&self) -> Result<KeyFrame, KumecastError> {
        let expected = self.width.saturating_mul(self.height);
        if self.cells.len() != expected {
            return Err(KumecastError::InvalidCellCount {
                frame: 0,
                expected,
                actual: self.cells.len(),
            });
        }
        let mut frame = Frame::new(self.width, self.height);
        for (index, cell) in self.cells.iter().enumerate() {
            let x = if self.width == 0 {
                0
            } else {
                index % self.width
            };
            let y = if self.width == 0 {
                0
            } else {
                index / self.width
            };
            frame.set_cell(x, y, cell.to_glyph_cell()?).map_err(|_| {
                KumecastError::InvalidCellCount {
                    frame: 0,
                    expected,
                    actual: self.cells.len(),
                }
            })?;
        }
        for marker in &self.markers {
            frame.add_marker(marker.to_keyframe_marker()?);
        }
        Ok(KeyFrame::new(
            frame,
            Duration::from_millis(self.duration_ms),
        ))
    }
}

/// Serialized frame cell.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KumecastCell {
    /// Single-character glyph.
    pub glyph: String,
    /// Optional style override.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub style: Option<KumecastStyle>,
    /// Optional marker id attached to this cell.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub marker: Option<String>,
}

impl From<&crate::frame::GlyphCell> for KumecastCell {
    fn from(cell: &crate::frame::GlyphCell) -> Self {
        Self {
            glyph: cell.glyph.to_string(),
            style: KumecastStyle::from_style(&cell.style),
            marker: cell.marker.clone(),
        }
    }
}

impl KumecastCell {
    /// Convert this serialized cell into a runtime glyph cell.
    pub fn to_glyph_cell(&self) -> Result<GlyphCell, KumecastError> {
        let mut chars = self.glyph.chars();
        let Some(glyph) = chars.next() else {
            return Err(KumecastError::InvalidGlyph(self.glyph.clone()));
        };
        if chars.next().is_some() {
            return Err(KumecastError::InvalidGlyph(self.glyph.clone()));
        }
        Ok(GlyphCell {
            glyph,
            style: self
                .style
                .as_ref()
                .map(KumecastStyle::to_cell_style)
                .transpose()?
                .unwrap_or_default(),
            marker: self.marker.clone(),
        })
    }
}

/// Serialized cell style.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KumecastStyle {
    /// Optional foreground `#rrggbb` color.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub foreground: Option<String>,
    /// Optional background `#rrggbb` color.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background: Option<String>,
    /// Whether text is bold.
    #[serde(default)]
    #[serde(skip_serializing_if = "is_false")]
    pub bold: bool,
    /// Whether text is italic.
    #[serde(default)]
    #[serde(skip_serializing_if = "is_false")]
    pub italic: bool,
    /// Whether text is underlined.
    #[serde(default)]
    #[serde(skip_serializing_if = "is_false")]
    pub underline: bool,
}

impl KumecastStyle {
    /// Encode a runtime cell style, returning `None` for the default style.
    #[must_use]
    pub fn from_style(style: &CellStyle) -> Option<Self> {
        let encoded = Self {
            foreground: style.foreground.as_ref().and_then(color_hex),
            background: style.background.as_ref().and_then(color_hex),
            bold: style.bold,
            italic: style.italic,
            underline: style.underline,
        };
        (encoded.foreground.is_some()
            || encoded.background.is_some()
            || encoded.bold
            || encoded.italic
            || encoded.underline)
            .then_some(encoded)
    }

    fn validate(&self) -> Result<(), KumecastError> {
        validate_optional_color(self.foreground.as_deref())?;
        validate_optional_color(self.background.as_deref())?;
        Ok(())
    }

    fn to_cell_style(&self) -> Result<CellStyle, KumecastError> {
        self.validate()?;
        Ok(CellStyle {
            foreground: self.foreground.as_deref().map(parse_rgb_hex).transpose()?,
            background: self.background.as_deref().map(parse_rgb_hex).transpose()?,
            bold: self.bold,
            italic: self.italic,
            underline: self.underline,
        })
    }
}

/// Serialized keyframe marker.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KumecastMarker {
    /// Marker id.
    pub id: String,
    /// Marker kind name.
    pub kind: String,
    /// Marker region.
    pub region: KumecastRegion,
}

impl From<&KeyFrameMarker> for KumecastMarker {
    fn from(marker: &KeyFrameMarker) -> Self {
        Self {
            id: marker.id.clone(),
            kind: marker_kind_name(marker.kind).to_owned(),
            region: KumecastRegion::from(marker.region),
        }
    }
}

impl KumecastMarker {
    fn to_keyframe_marker(&self) -> Result<KeyFrameMarker, KumecastError> {
        Ok(KeyFrameMarker {
            id: self.id.clone(),
            kind: parse_marker_kind(&self.kind)?,
            region: FrameRegion {
                x: self.region.x,
                y: self.region.y,
                width: self.region.width,
                height: self.region.height,
            },
        })
    }
}

/// Serialized rectangular region.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KumecastRegion {
    /// Left cell coordinate.
    pub x: usize,
    /// Top cell coordinate.
    pub y: usize,
    /// Region width in cells.
    pub width: usize,
    /// Region height in cells.
    pub height: usize,
}

impl From<FrameRegion> for KumecastRegion {
    fn from(region: FrameRegion) -> Self {
        Self {
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height,
        }
    }
}

fn marker_kind_name(kind: KeyFrameMarkerKind) -> &'static str {
    match kind {
        KeyFrameMarkerKind::Enter => "enter",
        KeyFrameMarkerKind::Active => "active",
        KeyFrameMarkerKind::Exit => "exit",
        KeyFrameMarkerKind::Hold => "hold",
    }
}

fn parse_marker_kind(kind: &str) -> Result<KeyFrameMarkerKind, KumecastError> {
    match kind {
        "enter" => Ok(KeyFrameMarkerKind::Enter),
        "active" => Ok(KeyFrameMarkerKind::Active),
        "exit" => Ok(KeyFrameMarkerKind::Exit),
        "hold" => Ok(KeyFrameMarkerKind::Hold),
        _ => Err(KumecastError::InvalidMarkerKind(kind.to_owned())),
    }
}

fn color_hex(color: &Color) -> Option<String> {
    match color {
        Color::Rgb { red, green, blue } => Some(rgb_hex(RgbColor::new(*red, *green, *blue))),
        Color::Ansi(_) | Color::Theme(_) => None,
    }
}

fn rgb_hex(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

fn validate_optional_color(color: Option<&str>) -> Result<(), KumecastError> {
    if let Some(color) = color {
        parse_rgb_hex(color)?;
    }
    Ok(())
}

fn parse_rgb_hex(value: &str) -> Result<Color, KumecastError> {
    let Some(hex) = value.strip_prefix('#') else {
        return Err(KumecastError::InvalidColor(value.to_owned()));
    };
    if hex.len() != 6 || !hex.bytes().all(is_lower_hex_digit) {
        return Err(KumecastError::InvalidColor(value.to_owned()));
    }
    Ok(Color::Rgb {
        red: parse_hex_byte(&hex[0..2]),
        green: parse_hex_byte(&hex[2..4]),
        blue: parse_hex_byte(&hex[4..6]),
    })
}

fn parse_hex_byte(value: &str) -> u8 {
    u8::from_str_radix(value, 16).expect("validated hex byte")
}

fn is_sha256_hex(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(is_lower_hex_digit)
}

const fn is_lower_hex_digit(byte: u8) -> bool {
    byte.is_ascii_digit() || matches!(byte, b'a'..=b'f')
}

/// Error returned while decoding, validating, or rebuilding `.kumecast` data.
#[derive(Debug)]
pub enum KumecastError {
    /// JSON parsing or shape validation failed.
    Json(serde_json::Error),
    /// The document version is not supported.
    UnsupportedVersion(u32),
    /// `source.diagramType` is empty.
    EmptySourceDiagramType,
    /// `source.sha256` is not lowercase hexadecimal SHA-256.
    InvalidSha256(String),
    /// `theme.name` is empty.
    EmptyThemeName,
    /// `theme.charset` is not supported.
    InvalidCharset(String),
    /// The timeline has no frames.
    EmptyTimeline,
    /// Frame cell count does not equal width times height.
    InvalidCellCount {
        /// Frame index.
        frame: usize,
        /// Expected cell count.
        expected: usize,
        /// Actual cell count.
        actual: usize,
    },
    /// Cell glyph is empty or has more than one scalar value.
    InvalidGlyph(String),
    /// Color value is not lowercase `#rrggbb`.
    InvalidColor(String),
    /// Marker kind string is not supported.
    InvalidMarkerKind(String),
}

impl std::fmt::Display for KumecastError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Json(error) => write!(formatter, "invalid kumecast JSON: {error}"),
            Self::UnsupportedVersion(version) => {
                write!(formatter, "unsupported kumecast version {version}")
            }
            Self::EmptySourceDiagramType => write!(formatter, "source.diagramType is empty"),
            Self::InvalidSha256(value) => write!(formatter, "invalid source sha256 `{value}`"),
            Self::EmptyThemeName => write!(formatter, "theme.name is empty"),
            Self::InvalidCharset(value) => write!(formatter, "invalid theme charset `{value}`"),
            Self::EmptyTimeline => write!(formatter, "timeline.frames is empty"),
            Self::InvalidCellCount {
                frame,
                expected,
                actual,
            } => write!(
                formatter,
                "frame {frame} has {actual} cells; expected {expected}"
            ),
            Self::InvalidGlyph(value) => write!(formatter, "invalid cell glyph `{value}`"),
            Self::InvalidColor(value) => write!(formatter, "invalid color `{value}`"),
            Self::InvalidMarkerKind(value) => write!(formatter, "invalid marker kind `{value}`"),
        }
    }
}

impl std::error::Error for KumecastError {}

const fn is_false(value: &bool) -> bool {
    !*value
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use crate::{
        animator::{KeyFrame, Timeline},
        cast::Kumecast,
        frame::{CellStyle, Color, Frame, FrameRegion, KeyFrameMarker, KeyFrameMarkerKind},
        theme::Theme,
    };

    #[test]
    fn encodes_kumecast_v1_timeline() {
        let mut frame = Frame::new(2, 1);
        let style = CellStyle {
            foreground: Some(Color::Rgb {
                red: 0x24,
                green: 0x29,
                blue: 0x2f,
            }),
            background: Some(Color::Rgb {
                red: 0xff,
                green: 0xff,
                blue: 0xff,
            }),
            bold: true,
            italic: false,
            underline: false,
        };
        frame.put_styled_glyph(0, 0, 'A', style).unwrap();
        frame.mark_cell(0, 0, "node:A").unwrap();
        frame.add_marker(KeyFrameMarker {
            id: "node:A".to_owned(),
            kind: KeyFrameMarkerKind::Active,
            region: FrameRegion {
                x: 0,
                y: 0,
                width: 1,
                height: 1,
            },
        });
        let timeline =
            Timeline::from_keyframes(vec![KeyFrame::new(frame, Duration::from_millis(550))])
                .with_repeat(true);

        let cast =
            Kumecast::from_timeline("flowchart", "graph TD\nA --> B", Theme::github(), &timeline);
        let json = cast.to_json_string().unwrap();

        assert!(json.contains(r#""version": 1"#));
        assert!(json.contains(r#""diagramType": "flowchart""#));
        assert!(json.contains(r#""charset": "unicode""#));
        assert!(json.contains(r#""durationMs": 550"#));
        assert!(json.contains(r##""foreground": "#24292f""##));
        assert!(json.contains(r##""background": "#ffffff""##));
        assert!(json.contains(r#""marker": "node:A""#));
        assert!(json.contains(r#""kind": "active""#));
    }

    #[test]
    fn decodes_and_rebuilds_timeline() {
        let mut frame = Frame::new(1, 1);
        frame
            .put_styled_glyph(
                0,
                0,
                'A',
                CellStyle {
                    foreground: Some(Color::Rgb {
                        red: 0x24,
                        green: 0x29,
                        blue: 0x2f,
                    }),
                    background: Some(Color::Rgb {
                        red: 0xff,
                        green: 0xff,
                        blue: 0xff,
                    }),
                    bold: true,
                    italic: false,
                    underline: true,
                },
            )
            .unwrap();
        let timeline =
            Timeline::from_keyframes(vec![KeyFrame::new(frame, Duration::from_millis(25))]);
        let json = Kumecast::from_timeline("flowchart", "graph TD\nA", Theme::github(), &timeline)
            .to_json_string()
            .unwrap();

        let cast = Kumecast::from_json_str(&json).unwrap();
        let decoded = cast.to_timeline().unwrap();
        let cell = decoded.keyframes()[0].frame().cell(0, 0).unwrap();

        assert_eq!(decoded.len(), 1);
        assert_eq!(decoded.keyframes()[0].duration(), Duration::from_millis(25));
        assert_eq!(cell.glyph, 'A');
        assert!(cell.style.bold);
        assert!(cell.style.underline);
        assert_eq!(
            cell.style.foreground,
            Some(Color::Rgb {
                red: 0x24,
                green: 0x29,
                blue: 0x2f,
            })
        );
    }

    #[test]
    fn rejects_invalid_kumecast_shapes() {
        let wrong_version = r#"{
  "version": 2,
  "source": { "diagramType": "flowchart", "mermaid": "graph TD\nA" },
  "theme": { "name": "github", "charset": "unicode" },
  "timeline": { "repeat": false, "frames": [{ "durationMs": 1, "width": 1, "height": 1, "cells": [{ "glyph": "A" }] }] }
}"#;
        assert!(matches!(
            Kumecast::from_json_str(wrong_version).unwrap_err(),
            super::KumecastError::UnsupportedVersion(2)
        ));

        let bad_cell_count = r#"{
  "version": 1,
  "source": { "diagramType": "flowchart", "mermaid": "graph TD\nA" },
  "theme": { "name": "github", "charset": "unicode" },
  "timeline": { "repeat": false, "frames": [{ "durationMs": 1, "width": 2, "height": 1, "cells": [{ "glyph": "A" }] }] }
}"#;
        assert!(matches!(
            Kumecast::from_json_str(bad_cell_count).unwrap_err(),
            super::KumecastError::InvalidCellCount {
                expected: 2,
                actual: 1,
                ..
            }
        ));

        let unknown_field = r#"{
  "version": 1,
  "extra": true,
  "source": { "diagramType": "flowchart", "mermaid": "graph TD\nA" },
  "theme": { "name": "github", "charset": "unicode" },
  "timeline": { "repeat": false, "frames": [{ "durationMs": 1, "width": 1, "height": 1, "cells": [{ "glyph": "A" }] }] }
}"#;
        assert!(matches!(
            Kumecast::from_json_str(unknown_field).unwrap_err(),
            super::KumecastError::Json(_)
        ));

        let bad_color = r##"{
  "version": 1,
  "source": { "diagramType": "flowchart", "mermaid": "graph TD\nA" },
  "theme": { "name": "github", "charset": "unicode" },
  "timeline": { "repeat": false, "frames": [{ "durationMs": 1, "width": 1, "height": 1, "cells": [{ "glyph": "A", "style": { "foreground": "#ABCDEF" } }] }] }
}"##;
        assert!(matches!(
            Kumecast::from_json_str(bad_color).unwrap_err(),
            super::KumecastError::InvalidColor(_)
        ));
    }
}
