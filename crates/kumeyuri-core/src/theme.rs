use crate::frame::{CellStyle, Charset, Color};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum BuiltInTheme {
    #[default]
    Default,
    Mono,
    TokyoNight,
    Github,
    Dracula,
    PrintMono,
}

impl BuiltInTheme {
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Default => "default",
            Self::Mono => "mono",
            Self::TokyoNight => "tokyo-night",
            Self::Github => "github",
            Self::Dracula => "dracula",
            Self::PrintMono => "print-mono",
        }
    }

    #[must_use]
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "default" => Some(Self::Default),
            "mono" => Some(Self::Mono),
            "tokyo-night" => Some(Self::TokyoNight),
            "github" => Some(Self::Github),
            "dracula" => Some(Self::Dracula),
            "print-mono" => Some(Self::PrintMono),
            _ => None,
        }
    }

    #[must_use]
    pub const fn theme(self) -> Theme {
        Theme::built_in(self)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RgbColor {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

impl RgbColor {
    #[must_use]
    pub const fn new(red: u8, green: u8, blue: u8) -> Self {
        Self { red, green, blue }
    }
}

impl From<RgbColor> for Color {
    fn from(color: RgbColor) -> Self {
        Self::Rgb {
            red: color.red,
            green: color.green,
            blue: color.blue,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThemeColors {
    pub background: RgbColor,
    pub foreground: RgbColor,
    pub accent: RgbColor,
    pub edge: RgbColor,
    pub edge_alt: RgbColor,
    pub highlight: RgbColor,
    pub muted: RgbColor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeRole {
    Background,
    Text,
    Node,
    Edge,
    EdgeAlt,
    Highlight,
    Muted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Theme {
    pub name: &'static str,
    pub charset: Charset,
    pub colors: ThemeColors,
}

impl Theme {
    #[must_use]
    pub const fn built_in(theme: BuiltInTheme) -> Self {
        match theme {
            BuiltInTheme::Default => Self::default_theme(),
            BuiltInTheme::Mono => Self::mono(),
            BuiltInTheme::TokyoNight => Self::tokyo_night(),
            BuiltInTheme::Github => Self::github(),
            BuiltInTheme::Dracula => Self::dracula(),
            BuiltInTheme::PrintMono => Self::print_mono(),
        }
    }

    #[must_use]
    pub const fn starter_themes() -> [Self; 6] {
        [
            Self::default_theme(),
            Self::mono(),
            Self::tokyo_night(),
            Self::github(),
            Self::dracula(),
            Self::print_mono(),
        ]
    }

    #[must_use]
    pub const fn default_theme() -> Self {
        Self {
            name: "default",
            charset: Charset::Ascii,
            colors: ThemeColors {
                background: RgbColor::new(0x10, 0x14, 0x18),
                foreground: RgbColor::new(0xe6, 0xed, 0xf3),
                accent: RgbColor::new(0x58, 0xa6, 0xff),
                edge: RgbColor::new(0x8b, 0x94, 0x9e),
                edge_alt: RgbColor::new(0xd2, 0xa8, 0xff),
                highlight: RgbColor::new(0xf2, 0xcc, 0x60),
                muted: RgbColor::new(0x7d, 0x85, 0x90),
            },
        }
    }

    #[must_use]
    pub const fn mono() -> Self {
        Self {
            name: "mono",
            charset: Charset::Ascii,
            colors: ThemeColors {
                background: RgbColor::new(0x00, 0x00, 0x00),
                foreground: RgbColor::new(0xff, 0xff, 0xff),
                accent: RgbColor::new(0xff, 0xff, 0xff),
                edge: RgbColor::new(0xd0, 0xd0, 0xd0),
                edge_alt: RgbColor::new(0xa8, 0xa8, 0xa8),
                highlight: RgbColor::new(0xff, 0xff, 0xff),
                muted: RgbColor::new(0x80, 0x80, 0x80),
            },
        }
    }

    #[must_use]
    pub const fn tokyo_night() -> Self {
        Self {
            name: "tokyo-night",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0x1a, 0x1b, 0x26),
                foreground: RgbColor::new(0xc0, 0xca, 0xf5),
                accent: RgbColor::new(0x7a, 0xa2, 0xf7),
                edge: RgbColor::new(0x9e, 0xce, 0x6a),
                edge_alt: RgbColor::new(0xf7, 0x76, 0x8e),
                highlight: RgbColor::new(0xe0, 0xaf, 0x68),
                muted: RgbColor::new(0x7c, 0x85, 0xb6),
            },
        }
    }

    #[must_use]
    pub const fn github() -> Self {
        Self {
            name: "github",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0xff, 0xff, 0xff),
                foreground: RgbColor::new(0x24, 0x29, 0x2f),
                accent: RgbColor::new(0x09, 0x69, 0xda),
                edge: RgbColor::new(0x57, 0x60, 0x6a),
                edge_alt: RgbColor::new(0x82, 0x50, 0xdf),
                highlight: RgbColor::new(0x9a, 0x67, 0x00),
                muted: RgbColor::new(0x6e, 0x77, 0x81),
            },
        }
    }

    #[must_use]
    pub const fn dracula() -> Self {
        Self {
            name: "dracula",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0x28, 0x2a, 0x36),
                foreground: RgbColor::new(0xf8, 0xf8, 0xf2),
                accent: RgbColor::new(0xbd, 0x93, 0xf9),
                edge: RgbColor::new(0x50, 0xfa, 0x7b),
                edge_alt: RgbColor::new(0xff, 0x79, 0xc6),
                highlight: RgbColor::new(0xf1, 0xfa, 0x8c),
                muted: RgbColor::new(0x8b, 0x96, 0xbd),
            },
        }
    }

    #[must_use]
    pub const fn print_mono() -> Self {
        Self {
            name: "print-mono",
            charset: Charset::Ascii,
            colors: ThemeColors {
                background: RgbColor::new(0xff, 0xff, 0xff),
                foreground: RgbColor::new(0x00, 0x00, 0x00),
                accent: RgbColor::new(0x00, 0x00, 0x00),
                edge: RgbColor::new(0x00, 0x00, 0x00),
                edge_alt: RgbColor::new(0x00, 0x00, 0x00),
                highlight: RgbColor::new(0x00, 0x00, 0x00),
                muted: RgbColor::new(0x00, 0x00, 0x00),
            },
        }
    }

    #[must_use]
    pub fn style_for(self, role: ThemeRole) -> CellStyle {
        let foreground = match role {
            ThemeRole::Background | ThemeRole::Text => self.colors.foreground,
            ThemeRole::Node => self.colors.accent,
            ThemeRole::Edge => self.colors.edge,
            ThemeRole::EdgeAlt => self.colors.edge_alt,
            ThemeRole::Highlight => self.colors.highlight,
            ThemeRole::Muted => self.colors.muted,
        };
        CellStyle {
            foreground: Some(foreground.into()),
            background: Some(self.colors.background.into()),
            bold: matches!(role, ThemeRole::Node | ThemeRole::Highlight),
            italic: false,
            underline: false,
        }
    }
}

impl Default for Theme {
    fn default() -> Self {
        Self::default_theme()
    }
}

#[cfg(test)]
mod tests {
    use super::{BuiltInTheme, RgbColor, Theme, ThemeRole};
    use crate::frame::{Charset, Color};

    #[test]
    fn exposes_built_in_themes() {
        let names = Theme::starter_themes().map(|theme| theme.name);

        assert_eq!(
            names,
            [
                "default",
                "mono",
                "tokyo-night",
                "github",
                "dracula",
                "print-mono",
            ]
        );
    }

    #[test]
    fn parses_built_in_theme_names() {
        assert_eq!(
            BuiltInTheme::from_name("github"),
            Some(BuiltInTheme::Github)
        );
        assert_eq!(BuiltInTheme::from_name("missing"), None);
        assert_eq!(BuiltInTheme::Dracula.name(), "dracula");
        assert_eq!(BuiltInTheme::PrintMono.name(), "print-mono");
    }

    #[test]
    fn built_in_themes_carry_charset_and_colors() {
        let theme = Theme::tokyo_night();

        assert_eq!(theme.charset, Charset::Unicode);
        assert_eq!(theme.colors.background, RgbColor::new(0x1a, 0x1b, 0x26));

        let print = Theme::print_mono();
        assert_eq!(print.charset, Charset::Ascii);
        assert_eq!(print.colors.background, RgbColor::new(0xff, 0xff, 0xff));
        assert_eq!(print.colors.foreground, RgbColor::new(0x00, 0x00, 0x00));
        assert_eq!(print.colors.accent, print.colors.foreground);
    }

    #[test]
    fn maps_roles_to_cell_styles() {
        let style = Theme::github().style_for(ThemeRole::Node);

        assert_eq!(
            style.foreground,
            Some(Color::Rgb {
                red: 0x09,
                green: 0x69,
                blue: 0xda,
            })
        );
        assert!(style.bold);
    }

    #[test]
    fn built_in_theme_roles_meet_wcag_aa_contrast() {
        let roles = [
            ThemeRole::Background,
            ThemeRole::Text,
            ThemeRole::Node,
            ThemeRole::Edge,
            ThemeRole::EdgeAlt,
            ThemeRole::Highlight,
            ThemeRole::Muted,
        ];

        for theme in Theme::starter_themes() {
            for role in roles {
                let style = theme.style_for(role);
                let foreground = rgb_from_style(style.foreground);
                let background = rgb_from_style(style.background);
                let ratio = contrast_ratio(foreground, background);
                assert!(
                    ratio >= 4.5,
                    "{} {role:?} contrast {ratio:.2} is below 4.5:1",
                    theme.name,
                );
            }
        }
    }

    fn rgb_from_style(color: Option<Color>) -> RgbColor {
        let Some(Color::Rgb { red, green, blue }) = color else {
            panic!("expected RGB style color");
        };
        RgbColor::new(red, green, blue)
    }

    fn contrast_ratio(first: RgbColor, second: RgbColor) -> f64 {
        let first = relative_luminance(first);
        let second = relative_luminance(second);
        let lighter = first.max(second);
        let darker = first.min(second);
        (lighter + 0.05) / (darker + 0.05)
    }

    fn relative_luminance(color: RgbColor) -> f64 {
        0.2126 * linear_channel(color.red)
            + 0.7152 * linear_channel(color.green)
            + 0.0722 * linear_channel(color.blue)
    }

    fn linear_channel(value: u8) -> f64 {
        let value = f64::from(value) / 255.0;
        if value <= 0.03928 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    }
}
