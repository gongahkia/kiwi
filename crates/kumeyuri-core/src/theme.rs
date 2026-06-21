//! Built-in themes and `.kumetheme.toml` discovery/validation.

use std::{
    collections::BTreeSet,
    env, fs,
    path::{Path, PathBuf},
};

use crate::frame::{CellStyle, Charset, Color};
use serde::{Deserialize, Serialize};

/// Built-in theme identifier.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum BuiltInTheme {
    /// Default dark ASCII theme.
    #[default]
    Default,
    /// Black-and-white ASCII theme.
    Mono,
    /// Tokyo Night inspired Unicode theme.
    TokyoNight,
    /// GitHub light Unicode theme.
    Github,
    /// Dracula inspired Unicode theme.
    Dracula,
    /// Solarized light Unicode theme.
    SolarizedLight,
    /// Solarized dark Unicode theme.
    SolarizedDark,
    /// Nord inspired Unicode theme.
    Nord,
    /// Catppuccin Mocha inspired Unicode theme.
    CatppuccinMocha,
    /// High-contrast ASCII theme.
    HighContrast,
    /// Print-friendly monochrome ASCII theme.
    PrintMono,
}

impl BuiltInTheme {
    /// Every built-in theme in display order.
    pub const ALL: [Self; 11] = [
        Self::Default,
        Self::Mono,
        Self::TokyoNight,
        Self::Github,
        Self::Dracula,
        Self::SolarizedLight,
        Self::SolarizedDark,
        Self::Nord,
        Self::CatppuccinMocha,
        Self::HighContrast,
        Self::PrintMono,
    ];

    /// Return the stable kebab-case theme name.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Default => "default",
            Self::Mono => "mono",
            Self::TokyoNight => "tokyo-night",
            Self::Github => "github",
            Self::Dracula => "dracula",
            Self::SolarizedLight => "solarized-light",
            Self::SolarizedDark => "solarized-dark",
            Self::Nord => "nord",
            Self::CatppuccinMocha => "catppuccin-mocha",
            Self::HighContrast => "high-contrast",
            Self::PrintMono => "print-mono",
        }
    }

    /// Parse a built-in theme by kebab-case name.
    #[must_use]
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "default" => Some(Self::Default),
            "mono" => Some(Self::Mono),
            "tokyo-night" => Some(Self::TokyoNight),
            "github" => Some(Self::Github),
            "dracula" => Some(Self::Dracula),
            "solarized-light" => Some(Self::SolarizedLight),
            "solarized-dark" => Some(Self::SolarizedDark),
            "nord" => Some(Self::Nord),
            "catppuccin-mocha" => Some(Self::CatppuccinMocha),
            "high-contrast" => Some(Self::HighContrast),
            "print-mono" => Some(Self::PrintMono),
            _ => None,
        }
    }

    /// Return the theme values for this built-in theme.
    #[must_use]
    pub const fn theme(self) -> Theme {
        Theme::built_in(self)
    }
}

/// Location a discovered theme came from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ThemeSource {
    /// Theme file from the project search path.
    Project(PathBuf),
    /// Theme file from `XDG_DATA_HOME`.
    XdgDataHome(PathBuf),
    /// Theme file from `XDG_DATA_DIRS`.
    XdgDataDir(PathBuf),
    /// Bundled built-in theme.
    Bundled(BuiltInTheme),
}

/// Theme name plus its source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThemeSearchEntry {
    /// Theme name.
    pub name: String,
    /// Theme location.
    pub source: ThemeSource,
}

/// Directories searched for `.kumetheme.toml` files.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThemeSearchPaths {
    /// Project-local directories searched before user/system paths.
    pub project_dirs: Vec<PathBuf>,
    /// Optional XDG data-home root.
    pub xdg_data_home: Option<PathBuf>,
    /// XDG data-directory roots.
    pub xdg_data_dirs: Vec<PathBuf>,
}

impl ThemeSearchPaths {
    /// Build theme search paths from environment lookup and the process home.
    #[must_use]
    pub fn from_env(
        project_dir: impl Into<PathBuf>,
        lookup_env: impl FnMut(&str) -> Option<String>,
    ) -> Self {
        Self::from_env_with_home(
            project_dir,
            env::var_os("HOME").map(PathBuf::from),
            lookup_env,
        )
    }

    /// Build theme search paths from environment lookup and an explicit home.
    #[must_use]
    pub fn from_env_with_home(
        project_dir: impl Into<PathBuf>,
        home_dir: Option<PathBuf>,
        mut lookup_env: impl FnMut(&str) -> Option<String>,
    ) -> Self {
        let project_dir = project_dir.into();
        let xdg_data_home = lookup_env("XDG_DATA_HOME")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .or_else(|| home_dir.map(|home| home.join(".local/share")));
        let xdg_data_dirs = lookup_env("XDG_DATA_DIRS")
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".to_owned())
            .split(':')
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .collect();
        Self {
            project_dirs: vec![project_dir.join(".kumeyuri/themes"), project_dir],
            xdg_data_home,
            xdg_data_dirs,
        }
    }

    /// Return concrete theme directories with their source category.
    #[must_use]
    pub fn search_dirs(&self) -> Vec<(ThemeDirSource, PathBuf)> {
        let mut dirs = Vec::new();
        for path in &self.project_dirs {
            dirs.push((ThemeDirSource::Project, path.clone()));
        }
        if let Some(path) = &self.xdg_data_home {
            dirs.push((ThemeDirSource::XdgDataHome, path.join("kumeyuri/themes")));
        }
        for path in &self.xdg_data_dirs {
            dirs.push((ThemeDirSource::XdgDataDir, path.join("kumeyuri/themes")));
        }
        dirs
    }
}

/// Category for a theme search directory.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeDirSource {
    /// Project-local theme directory.
    Project,
    /// User data-home theme directory.
    XdgDataHome,
    /// System data-dir theme directory.
    XdgDataDir,
}

/// Discover custom themes, then append bundled themes not shadowed by files.
#[must_use]
pub fn discover_themes(paths: &ThemeSearchPaths) -> Vec<ThemeSearchEntry> {
    let mut entries = Vec::new();
    let mut seen = BTreeSet::new();
    for (source, dir) in paths.search_dirs() {
        discover_theme_dir(source, &dir, &mut seen, &mut entries);
    }
    for theme in BuiltInTheme::ALL {
        if seen.insert(theme.name().to_owned()) {
            entries.push(ThemeSearchEntry {
                name: theme.name().to_owned(),
                source: ThemeSource::Bundled(theme),
            });
        }
    }
    entries
}

fn discover_theme_dir(
    source: ThemeDirSource,
    dir: &Path,
    seen: &mut BTreeSet<String>,
    entries: &mut Vec<ThemeSearchEntry>,
) {
    let Ok(read_dir) = fs::read_dir(dir) else {
        return;
    };
    let mut files = read_dir
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter_map(kumetheme_file_name)
        .collect::<Vec<_>>();
    files.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    for (name, path) in files {
        if !seen.insert(name.clone()) {
            continue;
        }
        let source = match source {
            ThemeDirSource::Project => ThemeSource::Project(path),
            ThemeDirSource::XdgDataHome => ThemeSource::XdgDataHome(path),
            ThemeDirSource::XdgDataDir => ThemeSource::XdgDataDir(path),
        };
        entries.push(ThemeSearchEntry { name, source });
    }
}

fn kumetheme_file_name(path: PathBuf) -> Option<(String, PathBuf)> {
    let file_name = path.file_name()?.to_str()?;
    let name = file_name.strip_suffix(".kumetheme.toml")?;
    if is_kebab_case_identifier(name) {
        Some((name.to_owned(), path))
    } else {
        None
    }
}

/// RGB color used by themes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RgbColor {
    /// Red channel.
    pub red: u8,
    /// Green channel.
    pub green: u8,
    /// Blue channel.
    pub blue: u8,
}

impl RgbColor {
    /// Create an RGB color from channel values.
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

/// Parsed `.kumetheme.toml` schema.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KumethemeToml {
    /// Theme name.
    pub name: String,
    /// Glyph charset preference.
    pub charset: KumethemeCharset,
    /// Role colors as `#rrggbb` strings.
    pub colors: KumethemeColors,
}

/// Charset value accepted by `.kumetheme.toml`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum KumethemeCharset {
    /// ASCII glyph palette.
    Ascii,
    /// Unicode box-drawing glyph palette.
    Unicode,
}

impl From<KumethemeCharset> for Charset {
    fn from(charset: KumethemeCharset) -> Self {
        match charset {
            KumethemeCharset::Ascii => Self::Ascii,
            KumethemeCharset::Unicode => Self::Unicode,
        }
    }
}

/// Color fields accepted by `.kumetheme.toml`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KumethemeColors {
    /// Background color.
    pub background: String,
    /// Foreground color.
    pub foreground: String,
    /// Accent color.
    pub accent: String,
    /// Primary edge color.
    pub edge: String,
    /// Secondary edge color.
    pub edge_alt: String,
    /// Highlight color.
    pub highlight: String,
    /// Muted text color.
    pub muted: String,
}

/// Error returned when a `.kumetheme.toml` value is invalid.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KumethemeError {
    /// Theme name is not a kebab-case identifier.
    InvalidName(String),
    /// Color field is not a six-digit hex color.
    InvalidHexColor {
        /// Invalid color field name.
        field: &'static str,
        /// Invalid color value.
        value: String,
    },
}

impl KumethemeToml {
    /// Validate theme name and all color fields.
    pub fn validate(&self) -> Result<(), KumethemeError> {
        validate_theme_name(&self.name)?;
        self.colors.validate()
    }

    /// Validate and convert this schema to an owned runtime theme.
    pub fn to_theme(&self) -> Result<OwnedTheme, KumethemeError> {
        self.validate()?;
        Ok(OwnedTheme {
            name: self.name.clone(),
            charset: self.charset.into(),
            colors: ThemeColors {
                background: parse_hex_color("background", &self.colors.background)?,
                foreground: parse_hex_color("foreground", &self.colors.foreground)?,
                accent: parse_hex_color("accent", &self.colors.accent)?,
                edge: parse_hex_color("edge", &self.colors.edge)?,
                edge_alt: parse_hex_color("edge_alt", &self.colors.edge_alt)?,
                highlight: parse_hex_color("highlight", &self.colors.highlight)?,
                muted: parse_hex_color("muted", &self.colors.muted)?,
            },
        })
    }
}

impl KumethemeColors {
    /// Validate all color strings.
    pub fn validate(&self) -> Result<(), KumethemeError> {
        parse_hex_color("background", &self.background)?;
        parse_hex_color("foreground", &self.foreground)?;
        parse_hex_color("accent", &self.accent)?;
        parse_hex_color("edge", &self.edge)?;
        parse_hex_color("edge_alt", &self.edge_alt)?;
        parse_hex_color("highlight", &self.highlight)?;
        parse_hex_color("muted", &self.muted)?;
        Ok(())
    }
}

/// Owned theme converted from a custom theme file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OwnedTheme {
    /// Theme name.
    pub name: String,
    /// Glyph charset preference.
    pub charset: Charset,
    /// Runtime color palette.
    pub colors: ThemeColors,
}

fn validate_theme_name(name: &str) -> Result<(), KumethemeError> {
    if is_kebab_case_identifier(name) {
        Ok(())
    } else {
        Err(KumethemeError::InvalidName(name.to_owned()))
    }
}

fn is_kebab_case_identifier(value: &str) -> bool {
    if value.is_empty() || value.starts_with('-') || value.ends_with('-') || value.contains("--") {
        return false;
    }
    value
        .bytes()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

fn parse_hex_color(field: &'static str, value: &str) -> Result<RgbColor, KumethemeError> {
    let Some(hex) = value.strip_prefix('#') else {
        return Err(KumethemeError::InvalidHexColor {
            field,
            value: value.to_owned(),
        });
    };
    if hex.len() != 6 || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(KumethemeError::InvalidHexColor {
            field,
            value: value.to_owned(),
        });
    }
    Ok(RgbColor::new(
        parse_hex_byte(&hex[0..2]),
        parse_hex_byte(&hex[2..4]),
        parse_hex_byte(&hex[4..6]),
    ))
}

fn parse_hex_byte(value: &str) -> u8 {
    u8::from_str_radix(value, 16).expect("validated hex byte")
}

/// Runtime color palette for frame roles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThemeColors {
    /// Background color.
    pub background: RgbColor,
    /// Foreground text color.
    pub foreground: RgbColor,
    /// Node/accent color.
    pub accent: RgbColor,
    /// Primary edge color.
    pub edge: RgbColor,
    /// Secondary edge color.
    pub edge_alt: RgbColor,
    /// Highlight color.
    pub highlight: RgbColor,
    /// Muted text color.
    pub muted: RgbColor,
}

/// Logical role mapped to a theme style.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeRole {
    /// Background role.
    Background,
    /// Plain text role.
    Text,
    /// Node role.
    Node,
    /// Primary edge role.
    Edge,
    /// Secondary edge role.
    EdgeAlt,
    /// Highlight role.
    Highlight,
    /// Muted text role.
    Muted,
}

/// Runtime theme with a static name, charset, and colors.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Theme {
    /// Theme name.
    pub name: &'static str,
    /// Glyph charset preference.
    pub charset: Charset,
    /// Runtime color palette.
    pub colors: ThemeColors,
}

impl Theme {
    /// Return the runtime theme for a built-in theme identifier.
    #[must_use]
    pub const fn built_in(theme: BuiltInTheme) -> Self {
        match theme {
            BuiltInTheme::Default => Self::default_theme(),
            BuiltInTheme::Mono => Self::mono(),
            BuiltInTheme::TokyoNight => Self::tokyo_night(),
            BuiltInTheme::Github => Self::github(),
            BuiltInTheme::Dracula => Self::dracula(),
            BuiltInTheme::SolarizedLight => Self::solarized_light(),
            BuiltInTheme::SolarizedDark => Self::solarized_dark(),
            BuiltInTheme::Nord => Self::nord(),
            BuiltInTheme::CatppuccinMocha => Self::catppuccin_mocha(),
            BuiltInTheme::HighContrast => Self::high_contrast(),
            BuiltInTheme::PrintMono => Self::print_mono(),
        }
    }

    /// Return all starter themes in display order.
    #[must_use]
    pub const fn starter_themes() -> [Self; 11] {
        [
            Self::default_theme(),
            Self::mono(),
            Self::tokyo_night(),
            Self::github(),
            Self::dracula(),
            Self::solarized_light(),
            Self::solarized_dark(),
            Self::nord(),
            Self::catppuccin_mocha(),
            Self::high_contrast(),
            Self::print_mono(),
        ]
    }

    /// Return the default dark ASCII theme.
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

    /// Return the monochrome ASCII theme.
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

    /// Return the Tokyo Night inspired Unicode theme.
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

    /// Return the GitHub light Unicode theme.
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

    /// Return the Dracula inspired Unicode theme.
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

    /// Return the Solarized light Unicode theme.
    #[must_use]
    pub const fn solarized_light() -> Self {
        Self {
            name: "solarized-light",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0xfd, 0xf6, 0xe3),
                foreground: RgbColor::new(0x07, 0x36, 0x42),
                accent: RgbColor::new(0x07, 0x36, 0x42),
                edge: RgbColor::new(0x58, 0x6e, 0x75),
                edge_alt: RgbColor::new(0x07, 0x36, 0x42),
                highlight: RgbColor::new(0x58, 0x6e, 0x75),
                muted: RgbColor::new(0x58, 0x6e, 0x75),
            },
        }
    }

    /// Return the Solarized dark Unicode theme.
    #[must_use]
    pub const fn solarized_dark() -> Self {
        Self {
            name: "solarized-dark",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0x00, 0x2b, 0x36),
                foreground: RgbColor::new(0xee, 0xe8, 0xd5),
                accent: RgbColor::new(0x2a, 0xa1, 0x98),
                edge: RgbColor::new(0x93, 0xa1, 0xa1),
                edge_alt: RgbColor::new(0x2a, 0xa1, 0x98),
                highlight: RgbColor::new(0xb5, 0x89, 0x00),
                muted: RgbColor::new(0x83, 0x94, 0x96),
            },
        }
    }

    /// Return the Nord inspired Unicode theme.
    #[must_use]
    pub const fn nord() -> Self {
        Self {
            name: "nord",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0x2e, 0x34, 0x40),
                foreground: RgbColor::new(0xec, 0xef, 0xf4),
                accent: RgbColor::new(0x88, 0xc0, 0xd0),
                edge: RgbColor::new(0xd8, 0xde, 0xe9),
                edge_alt: RgbColor::new(0x81, 0xa1, 0xc1),
                highlight: RgbColor::new(0xeb, 0xcb, 0x8b),
                muted: RgbColor::new(0xe5, 0xe9, 0xf0),
            },
        }
    }

    /// Return the Catppuccin Mocha inspired Unicode theme.
    #[must_use]
    pub const fn catppuccin_mocha() -> Self {
        Self {
            name: "catppuccin-mocha",
            charset: Charset::Unicode,
            colors: ThemeColors {
                background: RgbColor::new(0x1e, 0x1e, 0x2e),
                foreground: RgbColor::new(0xcd, 0xd6, 0xf4),
                accent: RgbColor::new(0xcb, 0xa6, 0xf7),
                edge: RgbColor::new(0xa6, 0xe3, 0xa1),
                edge_alt: RgbColor::new(0x89, 0xb4, 0xfa),
                highlight: RgbColor::new(0xf9, 0xe2, 0xaf),
                muted: RgbColor::new(0xba, 0xc2, 0xde),
            },
        }
    }

    /// Return the high-contrast ASCII theme.
    #[must_use]
    pub const fn high_contrast() -> Self {
        Self {
            name: "high-contrast",
            charset: Charset::Ascii,
            colors: ThemeColors {
                background: RgbColor::new(0x00, 0x00, 0x00),
                foreground: RgbColor::new(0xff, 0xff, 0xff),
                accent: RgbColor::new(0x00, 0xff, 0xff),
                edge: RgbColor::new(0xff, 0xff, 0xff),
                edge_alt: RgbColor::new(0xff, 0xff, 0x00),
                highlight: RgbColor::new(0x00, 0xff, 0x00),
                muted: RgbColor::new(0xd0, 0xd0, 0xd0),
            },
        }
    }

    /// Return the print-friendly monochrome ASCII theme.
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

    /// Build a cell style for a logical theme role.
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
    use super::{
        BuiltInTheme, KumethemeCharset, KumethemeColors, KumethemeError, KumethemeToml, RgbColor,
        Theme, ThemeRole, ThemeSearchEntry, ThemeSearchPaths, ThemeSource, discover_themes,
    };
    use crate::frame::{Charset, Color};
    use std::{env, fs, process, time::SystemTime};

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
                "solarized-light",
                "solarized-dark",
                "nord",
                "catppuccin-mocha",
                "high-contrast",
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
        assert_eq!(BuiltInTheme::CatppuccinMocha.name(), "catppuccin-mocha");
        assert_eq!(
            BuiltInTheme::from_name("solarized-dark"),
            Some(BuiltInTheme::SolarizedDark)
        );
        assert_eq!(BuiltInTheme::PrintMono.name(), "print-mono");
    }

    #[test]
    fn built_in_themes_carry_charset_and_colors() {
        let theme = Theme::tokyo_night();

        assert_eq!(theme.charset, Charset::Unicode);
        assert_eq!(theme.colors.background, RgbColor::new(0x1a, 0x1b, 0x26));

        let solarized = Theme::solarized_light();
        assert_eq!(solarized.name, "solarized-light");
        assert_eq!(solarized.colors.background, RgbColor::new(0xfd, 0xf6, 0xe3));

        let nord = Theme::nord();
        assert_eq!(nord.name, "nord");
        assert_eq!(nord.colors.accent, RgbColor::new(0x88, 0xc0, 0xd0));

        let catppuccin = Theme::catppuccin_mocha();
        assert_eq!(catppuccin.name, "catppuccin-mocha");
        assert_eq!(
            catppuccin.colors.background,
            RgbColor::new(0x1e, 0x1e, 0x2e)
        );

        let high_contrast = Theme::high_contrast();
        assert_eq!(high_contrast.charset, Charset::Ascii);
        assert_eq!(high_contrast.colors.accent, RgbColor::new(0x00, 0xff, 0xff));

        let print = Theme::print_mono();
        assert_eq!(print.charset, Charset::Ascii);
        assert_eq!(print.colors.background, RgbColor::new(0xff, 0xff, 0xff));
        assert_eq!(print.colors.foreground, RgbColor::new(0x00, 0x00, 0x00));
        assert_eq!(print.colors.accent, print.colors.foreground);
    }

    #[test]
    fn discovers_project_xdg_and_bundled_themes_in_precedence_order() {
        let root = unique_temp_dir("theme-search");
        let project = root.join("project");
        let data_home = root.join("data-home");
        let data_dir = root.join("data-dir");
        fs::create_dir_all(project.join(".kumeyuri/themes")).unwrap();
        fs::create_dir_all(data_home.join("kumeyuri/themes")).unwrap();
        fs::create_dir_all(data_dir.join("kumeyuri/themes")).unwrap();
        fs::write(
            project.join(".kumeyuri/themes/project-theme.kumetheme.toml"),
            "",
        )
        .unwrap();
        fs::write(project.join("local-theme.kumetheme.toml"), "").unwrap();
        fs::write(
            data_home.join("kumeyuri/themes/user-theme.kumetheme.toml"),
            "",
        )
        .unwrap();
        fs::write(data_home.join("kumeyuri/themes/github.kumetheme.toml"), "").unwrap();
        fs::write(
            data_dir.join("kumeyuri/themes/system-theme.kumetheme.toml"),
            "",
        )
        .unwrap();
        fs::write(data_dir.join("kumeyuri/themes/BadName.kumetheme.toml"), "").unwrap();

        let paths = ThemeSearchPaths::from_env_with_home(&project, None, |name| match name {
            "XDG_DATA_HOME" => Some(data_home.display().to_string()),
            "XDG_DATA_DIRS" => Some(data_dir.display().to_string()),
            _ => None,
        });
        let entries = discover_themes(&paths);
        let names = entries
            .iter()
            .map(|entry| entry.name.as_str())
            .collect::<Vec<_>>();

        assert_eq!(
            &names[..5],
            [
                "project-theme",
                "local-theme",
                "github",
                "user-theme",
                "system-theme",
            ]
        );
        assert!(names.contains(&"default"));
        assert!(!names.contains(&"BadName"));
        assert_eq!(
            entries
                .iter()
                .filter(|entry| entry.name == "github")
                .count(),
            1
        );
        assert!(matches!(
            entries.iter().find(|entry| entry.name == "github"),
            Some(ThemeSearchEntry {
                source: ThemeSource::XdgDataHome(_),
                ..
            })
        ));

        fs::remove_dir_all(root).ok();
    }

    #[test]
    fn theme_search_paths_follow_xdg_defaults_and_ignore_relative_dirs() {
        let root = unique_temp_dir("theme-search-defaults");
        let paths =
            ThemeSearchPaths::from_env_with_home(
                &root,
                Some(root.join("home")),
                |name| match name {
                    "XDG_DATA_HOME" => Some("relative-home".to_owned()),
                    "XDG_DATA_DIRS" => Some(format!("relative:{}", root.join("share").display())),
                    _ => None,
                },
            );
        let search_dirs = paths.search_dirs();

        assert_eq!(paths.xdg_data_home, Some(root.join("home/.local/share")));
        assert_eq!(paths.xdg_data_dirs, vec![root.join("share")]);
        assert!(search_dirs.contains(&(
            super::ThemeDirSource::Project,
            root.join(".kumeyuri/themes")
        )));
        assert!(search_dirs.contains(&(super::ThemeDirSource::Project, root.clone())));
        assert!(search_dirs.contains(&(
            super::ThemeDirSource::XdgDataHome,
            root.join("home/.local/share/kumeyuri/themes")
        )));
        assert!(search_dirs.contains(&(
            super::ThemeDirSource::XdgDataDir,
            root.join("share/kumeyuri/themes")
        )));
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
    fn validates_kumetheme_schema_and_converts_to_owned_theme() {
        let schema = KumethemeToml {
            name: "solarized-light".to_owned(),
            charset: KumethemeCharset::Unicode,
            colors: KumethemeColors {
                background: "#fdf6e3".to_owned(),
                foreground: "#073642".to_owned(),
                accent: "#268bd2".to_owned(),
                edge: "#586e75".to_owned(),
                edge_alt: "#6c71c4".to_owned(),
                highlight: "#b58900".to_owned(),
                muted: "#657b83".to_owned(),
            },
        };

        let theme = schema.to_theme().unwrap();

        assert_eq!(theme.name, "solarized-light");
        assert_eq!(theme.charset, Charset::Unicode);
        assert_eq!(theme.colors.background, RgbColor::new(0xfd, 0xf6, 0xe3));
        assert_eq!(theme.colors.edge_alt, RgbColor::new(0x6c, 0x71, 0xc4));
    }

    #[test]
    fn rejects_invalid_kumetheme_fields() {
        let mut schema = KumethemeToml {
            name: "BadName".to_owned(),
            charset: KumethemeCharset::Ascii,
            colors: KumethemeColors {
                background: "#000000".to_owned(),
                foreground: "#ffffff".to_owned(),
                accent: "#ffffff".to_owned(),
                edge: "#ffffff".to_owned(),
                edge_alt: "#ffffff".to_owned(),
                highlight: "#ffffff".to_owned(),
                muted: "#ffffff".to_owned(),
            },
        };

        assert_eq!(
            schema.validate(),
            Err(KumethemeError::InvalidName("BadName".to_owned())),
        );

        schema.name = "valid-name".to_owned();
        schema.colors.accent = "ffffff".to_owned();

        assert_eq!(
            schema.validate(),
            Err(KumethemeError::InvalidHexColor {
                field: "accent",
                value: "ffffff".to_owned(),
            }),
        );
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

    fn unique_temp_dir(label: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        env::temp_dir().join(format!("kumeyuri-core-{label}-{}-{nanos}", process::id()))
    }
}
