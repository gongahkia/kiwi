use std::collections::BTreeMap;

use serde::Serialize;

use crate::{
    animator::Timeline,
    frame::{CellStyle, Color, Frame, FrameRegion, KeyFrameMarker, KeyFrameMarkerKind},
    theme::{RgbColor, Theme},
};

pub const KUMECAST_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Kumecast {
    pub version: u32,
    pub source: KumecastSource,
    pub theme: KumecastTheme,
    pub timeline: KumecastTimeline,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub metadata: BTreeMap<String, serde_json::Value>,
}

impl Kumecast {
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

    pub fn to_json_string(&self) -> Result<String, serde_json::Error> {
        let mut json = serde_json::to_string_pretty(self)?;
        json.push('\n');
        Ok(json)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KumecastSource {
    pub diagram_type: String,
    pub mermaid: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct KumecastTheme {
    pub name: String,
    pub charset: &'static str,
}

impl KumecastTheme {
    #[must_use]
    pub fn from_theme(theme: Theme) -> Self {
        Self {
            name: theme.name.to_owned(),
            charset: match theme.charset {
                crate::frame::Charset::Ascii => "ascii",
                crate::frame::Charset::Unicode => "unicode",
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct KumecastTimeline {
    pub repeat: bool,
    pub frames: Vec<KumecastFrame>,
}

impl KumecastTimeline {
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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KumecastFrame {
    pub duration_ms: u64,
    pub width: usize,
    pub height: usize,
    pub cells: Vec<KumecastCell>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub markers: Vec<KumecastMarker>,
}

impl KumecastFrame {
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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct KumecastCell {
    pub glyph: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub style: Option<KumecastStyle>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct KumecastStyle {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub foreground: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background: Option<String>,
    #[serde(skip_serializing_if = "is_false")]
    pub bold: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub italic: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub underline: bool,
}

impl KumecastStyle {
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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct KumecastMarker {
    pub id: String,
    pub kind: &'static str,
    pub region: KumecastRegion,
}

impl From<&KeyFrameMarker> for KumecastMarker {
    fn from(marker: &KeyFrameMarker) -> Self {
        Self {
            id: marker.id.clone(),
            kind: marker_kind_name(marker.kind),
            region: KumecastRegion::from(marker.region),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct KumecastRegion {
    pub x: usize,
    pub y: usize,
    pub width: usize,
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

fn color_hex(color: &Color) -> Option<String> {
    match color {
        Color::Rgb { red, green, blue } => Some(rgb_hex(RgbColor::new(*red, *green, *blue))),
        Color::Ansi(_) | Color::Theme(_) => None,
    }
}

fn rgb_hex(color: RgbColor) -> String {
    format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
}

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
}
