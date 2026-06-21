//! Stable host/plugin ABI contracts.

use std::{fmt, str::FromStr};

use crate::{animator::Timeline, frame::Frame, theme::Theme};

/// Current kumeyuri plugin ABI version supported by this host crate.
pub const KUMEYURI_ABI_VERSION: AbiVersion = AbiVersion::new(1, 0);

/// Semantic version for plugin ABI compatibility.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct AbiVersion {
    /// ABI major version; mismatches are incompatible.
    pub major: u16,
    /// ABI minor version; higher host minors can load lower required minors.
    pub minor: u16,
}

impl AbiVersion {
    /// Build an ABI version from major and minor parts.
    #[must_use]
    pub const fn new(major: u16, minor: u16) -> Self {
        Self { major, minor }
    }

    /// Return whether this host ABI supports a required plugin ABI.
    #[must_use]
    pub const fn supports(self, required: Self) -> bool {
        self.major == required.major && self.minor >= required.minor
    }
}

impl fmt::Display for AbiVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}.{}", self.major, self.minor)
    }
}

impl FromStr for AbiVersion {
    type Err = AbiVersionParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        let Some((major, minor)) = value.split_once('.') else {
            return Err(AbiVersionParseError);
        };
        if minor.contains('.') {
            return Err(AbiVersionParseError);
        }
        Ok(Self {
            major: major.parse().map_err(|_| AbiVersionParseError)?,
            minor: minor.parse().map_err(|_| AbiVersionParseError)?,
        })
    }
}

/// Error returned when an ABI version string cannot be parsed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AbiVersionParseError;

/// Optional runtime capability a plugin can request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Capability {
    /// Read files from an explicitly granted filesystem scope.
    FsRead = 0,
    /// Write files in an explicitly granted filesystem scope.
    FsWrite = 1,
    /// Fetch external network resources.
    NetFetch = 2,
    /// Read selected environment variables.
    EnvRead = 3,
    /// Read from the kumeyuri plugin cache.
    CacheRead = 4,
    /// Write to the kumeyuri plugin cache.
    CacheWrite = 5,
    /// Read wall-clock time.
    ClockNow = 6,
    /// Request random bytes from the host.
    RandomBytes = 7,
}

impl Capability {
    /// Every known capability in a stable display order.
    pub const ALL: [Self; 8] = [
        Self::FsRead,
        Self::FsWrite,
        Self::NetFetch,
        Self::EnvRead,
        Self::CacheRead,
        Self::CacheWrite,
        Self::ClockNow,
        Self::RandomBytes,
    ];

    /// Return the manifest spelling for this capability.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::FsRead => "fs.read",
            Self::FsWrite => "fs.write",
            Self::NetFetch => "net.fetch",
            Self::EnvRead => "env.read",
            Self::CacheRead => "cache.read",
            Self::CacheWrite => "cache.write",
            Self::ClockNow => "clock.now",
            Self::RandomBytes => "random.bytes",
        }
    }

    const fn bit(self) -> u64 {
        1 << self as u8
    }
}

impl fmt::Display for Capability {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for Capability {
    type Err = CapabilityParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "fs.read" => Ok(Self::FsRead),
            "fs.write" => Ok(Self::FsWrite),
            "net.fetch" => Ok(Self::NetFetch),
            "env.read" => Ok(Self::EnvRead),
            "cache.read" => Ok(Self::CacheRead),
            "cache.write" => Ok(Self::CacheWrite),
            "clock.now" => Ok(Self::ClockNow),
            "random.bytes" => Ok(Self::RandomBytes),
            _ => Err(CapabilityParseError),
        }
    }
}

/// Error returned when a capability string cannot be parsed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapabilityParseError;

/// Bitset of plugin runtime capabilities.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct CapabilitySet {
    bits: u64,
}

impl CapabilitySet {
    /// Return an empty capability set.
    #[must_use]
    pub const fn empty() -> Self {
        Self { bits: 0 }
    }

    /// Return a set containing every known capability.
    #[must_use]
    pub fn all() -> Self {
        Self::from_capabilities(Capability::ALL)
    }

    /// Build a capability set from capability values.
    #[must_use]
    pub fn from_capabilities(capabilities: impl IntoIterator<Item = Capability>) -> Self {
        let mut set = Self::empty();
        for capability in capabilities {
            set.insert(capability);
        }
        set
    }

    /// Build a capability set from capability values.
    #[must_use]
    #[allow(clippy::should_implement_trait)]
    pub fn from_iter(capabilities: impl IntoIterator<Item = Capability>) -> Self {
        Self::from_capabilities(capabilities)
    }

    /// Return whether the set contains a capability.
    #[must_use]
    pub const fn contains(self, capability: Capability) -> bool {
        self.bits & capability.bit() != 0
    }

    /// Add a capability to the set.
    pub fn insert(&mut self, capability: Capability) {
        self.bits |= capability.bit();
    }

    /// Remove a capability from the set.
    pub fn remove(&mut self, capability: Capability) {
        self.bits &= !capability.bit();
    }

    /// Return whether every capability in this set is present in `allowed`.
    #[must_use]
    pub const fn is_subset(self, allowed: Self) -> bool {
        self.bits & !allowed.bits == 0
    }

    /// Iterate over enabled capabilities in stable display order.
    pub fn iter(self) -> impl Iterator<Item = Capability> {
        Capability::ALL
            .into_iter()
            .filter(move |capability| self.contains(*capability))
    }
}

impl FromIterator<Capability> for CapabilitySet {
    fn from_iter<T: IntoIterator<Item = Capability>>(iter: T) -> Self {
        Self::from_capabilities(iter)
    }
}

/// Metadata supplied to render backend plugins.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderBackendMetadata {
    /// Optional human-readable diagram title.
    pub title: Option<String>,
    /// Optional source path for diagnostics or provenance.
    pub source_path: Option<String>,
}

impl RenderBackendMetadata {
    /// Return metadata with no optional fields.
    #[must_use]
    pub const fn empty() -> Self {
        Self {
            title: None,
            source_path: None,
        }
    }
}

impl Default for RenderBackendMetadata {
    fn default() -> Self {
        Self::empty()
    }
}

/// Request passed to a render backend plugin.
#[derive(Debug)]
pub struct RenderBackendRequest<'timeline, 'metadata> {
    /// Host ABI used for this request.
    pub abi: AbiVersion,
    /// Requested output format identifier.
    pub format: &'static str,
    /// Requested theme name.
    pub theme: &'static str,
    /// Timeline to render.
    pub timeline: &'timeline Timeline,
    /// Source metadata for the render.
    pub metadata: &'metadata RenderBackendMetadata,
}

/// Bytes returned by a render backend.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderArtifact {
    /// Encoded output bytes.
    pub bytes: Vec<u8>,
    /// MIME media type for the bytes.
    pub media_type: String,
    /// Preferred filename extension without a leading dot.
    pub extension: String,
}

impl RenderArtifact {
    /// Create a render artifact from encoded bytes and content metadata.
    #[must_use]
    pub fn new(
        bytes: Vec<u8>,
        media_type: impl Into<String>,
        extension: impl Into<String>,
    ) -> Self {
        Self {
            bytes,
            media_type: media_type.into(),
            extension: extension.into(),
        }
    }
}

/// Error returned by render backend validation or execution.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RenderBackendError {
    /// The plugin requires an ABI unsupported by the host.
    IncompatibleAbi {
        /// ABI supported by the host.
        host: AbiVersion,
        /// ABI required by the plugin.
        required: AbiVersion,
    },
    /// The plugin requested capabilities that were not granted.
    MissingCapabilities(CapabilitySet),
    /// The requested render format is unsupported.
    UnsupportedFormat(String),
    /// Rendering failed with a backend-specific message.
    RenderFailed(String),
}

/// Opaque parsed diagram payload returned by diagram-type plugins.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedDiagram {
    /// Encoded plugin-specific diagram bytes.
    pub bytes: Vec<u8>,
    /// MIME-like media type for the encoded diagram.
    pub media_type: String,
}

impl ParsedDiagram {
    /// Create a parsed diagram payload.
    #[must_use]
    pub fn new(bytes: Vec<u8>, media_type: impl Into<String>) -> Self {
        Self {
            bytes,
            media_type: media_type.into(),
        }
    }
}

/// Request passed to a diagram-type parser plugin.
#[derive(Debug)]
pub struct DiagramParseRequest<'source> {
    /// Host ABI used for this request.
    pub abi: AbiVersion,
    /// Mermaid source to parse.
    pub source: &'source str,
}

/// Request passed to a diagram-type layout plugin.
#[derive(Debug)]
pub struct DiagramLayoutRequest<'diagram> {
    /// Host ABI used for this request.
    pub abi: AbiVersion,
    /// Parsed diagram payload produced by the same plugin.
    pub diagram: &'diagram ParsedDiagram,
}

/// Error returned by diagram-type plugins.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiagramTypeError {
    /// The plugin requires an ABI unsupported by the host.
    IncompatibleAbi {
        /// ABI supported by the host.
        host: AbiVersion,
        /// ABI required by the plugin.
        required: AbiVersion,
    },
    /// The plugin requested capabilities that were not granted.
    MissingCapabilities(CapabilitySet),
    /// The source header is not supported by this plugin.
    UnsupportedHeader(String),
    /// Parsing failed with a plugin-specific message.
    ParseFailed(String),
    /// Layout failed with a plugin-specific message.
    LayoutFailed(String),
}

/// Extension point for custom diagram parsers and layout engines.
pub trait DiagramType {
    /// Stable plugin identifier.
    fn id(&self) -> &'static str;

    /// ABI required by this plugin.
    fn abi_version(&self) -> AbiVersion {
        KUMEYURI_ABI_VERSION
    }

    /// Mermaid root headers accepted by this plugin.
    fn headers(&self) -> &'static [&'static str];

    /// Runtime capabilities required by this plugin.
    fn required_capabilities(&self) -> CapabilitySet {
        CapabilitySet::empty()
    }

    /// Validate ABI and capability compatibility before executing the plugin.
    fn validate(
        &self,
        host_abi: AbiVersion,
        granted: CapabilitySet,
    ) -> Result<(), DiagramTypeError> {
        let required_abi = self.abi_version();
        if !host_abi.supports(required_abi) {
            return Err(DiagramTypeError::IncompatibleAbi {
                host: host_abi,
                required: required_abi,
            });
        }
        let required_capabilities = self.required_capabilities();
        if !required_capabilities.is_subset(granted) {
            return Err(DiagramTypeError::MissingCapabilities(required_capabilities));
        }
        Ok(())
    }

    /// Parse source into a plugin-owned diagram payload.
    fn parse(&self, request: DiagramParseRequest<'_>) -> Result<ParsedDiagram, DiagramTypeError>;

    /// Layout a parsed diagram into a kumeyuri frame.
    fn layout(&self, request: DiagramLayoutRequest<'_>) -> Result<Frame, DiagramTypeError>;
}

/// Request passed to a theme transform plugin.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThemeTransformRequest {
    /// Host ABI used for this request.
    pub abi: AbiVersion,
    /// Theme to transform.
    pub theme: Theme,
}

/// Error returned by theme transform plugins.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ThemeTransformError {
    /// The plugin requires an ABI unsupported by the host.
    IncompatibleAbi {
        /// ABI supported by the host.
        host: AbiVersion,
        /// ABI required by the plugin.
        required: AbiVersion,
    },
    /// The plugin requested capabilities that were not granted.
    MissingCapabilities(CapabilitySet),
    /// The input theme is unsupported by this plugin.
    UnsupportedTheme(String),
    /// Transformation failed with a plugin-specific message.
    TransformFailed(String),
}

/// Extension point for transforming themes before rendering.
pub trait ThemeTransform {
    /// Stable plugin identifier.
    fn id(&self) -> &'static str;

    /// ABI required by this plugin.
    fn abi_version(&self) -> AbiVersion {
        KUMEYURI_ABI_VERSION
    }

    /// Runtime capabilities required by this plugin.
    fn required_capabilities(&self) -> CapabilitySet {
        CapabilitySet::empty()
    }

    /// Validate ABI and capability compatibility before executing the plugin.
    fn validate(
        &self,
        host_abi: AbiVersion,
        granted: CapabilitySet,
    ) -> Result<(), ThemeTransformError> {
        let required_abi = self.abi_version();
        if !host_abi.supports(required_abi) {
            return Err(ThemeTransformError::IncompatibleAbi {
                host: host_abi,
                required: required_abi,
            });
        }
        let required_capabilities = self.required_capabilities();
        if !required_capabilities.is_subset(granted) {
            return Err(ThemeTransformError::MissingCapabilities(
                required_capabilities,
            ));
        }
        Ok(())
    }

    /// Transform a theme.
    fn transform(&self, request: ThemeTransformRequest) -> Result<Theme, ThemeTransformError>;
}

/// Extension point for custom render backends.
pub trait RenderBackend {
    /// Stable plugin identifier.
    fn id(&self) -> &'static str;

    /// ABI required by this plugin.
    fn abi_version(&self) -> AbiVersion {
        KUMEYURI_ABI_VERSION
    }

    /// Output format handled by this backend.
    fn format(&self) -> &'static str;

    /// MIME media type emitted by this backend.
    fn media_type(&self) -> &'static str;

    /// Default filename extension emitted by this backend.
    fn extension(&self) -> &'static str;

    /// Runtime capabilities required by this backend.
    fn required_capabilities(&self) -> CapabilitySet {
        CapabilitySet::empty()
    }

    /// Validate ABI and capability compatibility before executing the backend.
    fn validate(
        &self,
        host_abi: AbiVersion,
        granted: CapabilitySet,
    ) -> Result<(), RenderBackendError> {
        let required_abi = self.abi_version();
        if !host_abi.supports(required_abi) {
            return Err(RenderBackendError::IncompatibleAbi {
                host: host_abi,
                required: required_abi,
            });
        }
        let required_capabilities = self.required_capabilities();
        if !required_capabilities.is_subset(granted) {
            return Err(RenderBackendError::MissingCapabilities(
                required_capabilities,
            ));
        }
        Ok(())
    }

    /// Render a timeline into an artifact.
    fn render(
        &self,
        request: RenderBackendRequest<'_, '_>,
    ) -> Result<RenderArtifact, RenderBackendError>;
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{
        AbiVersion, Capability, CapabilitySet, DiagramLayoutRequest, DiagramParseRequest,
        DiagramType, DiagramTypeError, KUMEYURI_ABI_VERSION, ParsedDiagram, RenderArtifact,
        RenderBackend, RenderBackendError, RenderBackendMetadata, RenderBackendRequest,
        ThemeTransform, ThemeTransformError, ThemeTransformRequest,
    };
    use crate::theme::{RgbColor, Theme};
    use crate::{animator::Timeline, frame::Frame};

    #[test]
    fn abi_version_parses_and_formats_major_minor() {
        let version: AbiVersion = "1.2".parse().unwrap();

        assert_eq!(version, AbiVersion::new(1, 2));
        assert_eq!(version.to_string(), "1.2");
        assert!("1".parse::<AbiVersion>().is_err());
        assert!("1.2.3".parse::<AbiVersion>().is_err());
    }

    #[test]
    fn abi_version_supports_same_major_and_older_or_equal_minor() {
        assert!(KUMEYURI_ABI_VERSION.supports(AbiVersion::new(1, 0)));
        assert!(!KUMEYURI_ABI_VERSION.supports(AbiVersion::new(1, 1)));
        assert!(!KUMEYURI_ABI_VERSION.supports(AbiVersion::new(2, 0)));
    }

    #[test]
    fn capabilities_parse_to_stable_names() {
        for capability in Capability::ALL {
            assert_eq!(
                capability.as_str().parse::<Capability>().unwrap(),
                capability
            );
            assert_eq!(capability.to_string(), capability.as_str());
        }
        assert!("fs.delete".parse::<Capability>().is_err());
    }

    #[test]
    fn capability_set_is_deny_by_default_and_checks_subsets() {
        let mut granted = CapabilitySet::empty();
        assert!(!granted.contains(Capability::FsRead));

        granted.insert(Capability::FsRead);
        granted.insert(Capability::CacheRead);

        let requested = CapabilitySet::from_iter([Capability::FsRead]);
        let denied = CapabilitySet::from_iter([Capability::FsRead, Capability::NetFetch]);

        assert!(requested.is_subset(granted));
        assert!(!denied.is_subset(granted));

        granted.remove(Capability::FsRead);
        assert!(!granted.contains(Capability::FsRead));
        assert_eq!(CapabilitySet::all().iter().count(), Capability::ALL.len());
    }

    #[test]
    fn render_backend_surface_validates_abi_and_capabilities() {
        let backend = FakeRenderBackend;
        let granted = CapabilitySet::from_iter([Capability::FsWrite]);

        assert!(backend.validate(KUMEYURI_ABI_VERSION, granted).is_ok());
        assert_eq!(
            backend
                .validate(KUMEYURI_ABI_VERSION, CapabilitySet::empty())
                .unwrap_err(),
            RenderBackendError::MissingCapabilities(CapabilitySet::from_iter([
                Capability::FsWrite
            ]))
        );
        assert!(matches!(
            backend
                .validate(AbiVersion::new(0, 9), granted)
                .unwrap_err(),
            RenderBackendError::IncompatibleAbi { .. }
        ));
    }

    #[test]
    fn render_backend_surface_returns_artifacts() {
        let backend = FakeRenderBackend;
        let timeline = Timeline::from_frame(Frame::new(2, 1), Duration::from_millis(1));
        let metadata = RenderBackendMetadata {
            title: Some("diagram".to_owned()),
            source_path: Some("docs/diagram.mmd".to_owned()),
        };
        let request = RenderBackendRequest {
            abi: KUMEYURI_ABI_VERSION,
            format: "fake",
            theme: "github",
            timeline: &timeline,
            metadata: &metadata,
        };

        let artifact = backend.render(request).unwrap();

        assert_eq!(artifact.media_type, "application/x-kumeyuri-test");
        assert_eq!(artifact.extension, "fake");
        assert_eq!(artifact.bytes, b"fake:1:diagram".to_vec());
    }

    #[test]
    fn diagram_type_surface_validates_abi_and_capabilities() {
        let diagram_type = FakeDiagramType;
        let granted = CapabilitySet::from_iter([Capability::CacheRead]);

        assert!(diagram_type.validate(KUMEYURI_ABI_VERSION, granted).is_ok());
        assert_eq!(
            diagram_type
                .validate(KUMEYURI_ABI_VERSION, CapabilitySet::empty())
                .unwrap_err(),
            DiagramTypeError::MissingCapabilities(CapabilitySet::from_iter([
                Capability::CacheRead
            ]))
        );
        assert!(matches!(
            diagram_type
                .validate(AbiVersion::new(0, 9), granted)
                .unwrap_err(),
            DiagramTypeError::IncompatibleAbi { .. }
        ));
    }

    #[test]
    fn diagram_type_surface_parses_and_lays_out() {
        let diagram_type = FakeDiagramType;
        let parsed = diagram_type
            .parse(DiagramParseRequest {
                abi: KUMEYURI_ABI_VERSION,
                source: "fake\nalpha",
            })
            .unwrap();

        assert_eq!(parsed.media_type, "application/x-kumeyuri-fake-ast");
        assert_eq!(parsed.bytes, b"alpha".to_vec());

        let frame = diagram_type
            .layout(DiagramLayoutRequest {
                abi: KUMEYURI_ABI_VERSION,
                diagram: &parsed,
            })
            .unwrap();

        assert_eq!(frame.width(), 5);
        assert_eq!(frame.height(), 1);
    }

    #[test]
    fn theme_transform_surface_validates_abi_and_capabilities() {
        let transform = FakeThemeTransform;
        let granted = CapabilitySet::from_iter([Capability::ClockNow]);

        assert!(transform.validate(KUMEYURI_ABI_VERSION, granted).is_ok());
        assert_eq!(
            transform
                .validate(KUMEYURI_ABI_VERSION, CapabilitySet::empty())
                .unwrap_err(),
            ThemeTransformError::MissingCapabilities(CapabilitySet::from_iter([
                Capability::ClockNow
            ]))
        );
        assert!(matches!(
            transform
                .validate(AbiVersion::new(0, 9), granted)
                .unwrap_err(),
            ThemeTransformError::IncompatibleAbi { .. }
        ));
    }

    #[test]
    fn theme_transform_surface_returns_theme() {
        let transform = FakeThemeTransform;
        let theme = transform
            .transform(ThemeTransformRequest {
                abi: KUMEYURI_ABI_VERSION,
                theme: Theme::github(),
            })
            .unwrap();

        assert_eq!(theme.name, "github");
        assert_eq!(theme.colors.foreground, RgbColor::new(0x11, 0x11, 0x11));
        assert_eq!(theme.colors.background, Theme::github().colors.background);
    }

    struct FakeRenderBackend;

    impl RenderBackend for FakeRenderBackend {
        fn id(&self) -> &'static str {
            "fake"
        }

        fn format(&self) -> &'static str {
            "fake"
        }

        fn media_type(&self) -> &'static str {
            "application/x-kumeyuri-test"
        }

        fn extension(&self) -> &'static str {
            "fake"
        }

        fn required_capabilities(&self) -> CapabilitySet {
            CapabilitySet::from_iter([Capability::FsWrite])
        }

        fn render(
            &self,
            request: RenderBackendRequest<'_, '_>,
        ) -> Result<RenderArtifact, RenderBackendError> {
            if request.format != self.format() {
                return Err(RenderBackendError::UnsupportedFormat(
                    request.format.to_owned(),
                ));
            }
            Ok(RenderArtifact::new(
                format!(
                    "{}:{}:{}",
                    self.id(),
                    request.timeline.len(),
                    request.metadata.title.as_deref().unwrap_or("untitled")
                )
                .into_bytes(),
                self.media_type(),
                self.extension(),
            ))
        }
    }

    struct FakeDiagramType;

    impl DiagramType for FakeDiagramType {
        fn id(&self) -> &'static str {
            "fake-diagram"
        }

        fn headers(&self) -> &'static [&'static str] {
            &["fake"]
        }

        fn required_capabilities(&self) -> CapabilitySet {
            CapabilitySet::from_iter([Capability::CacheRead])
        }

        fn parse(
            &self,
            request: DiagramParseRequest<'_>,
        ) -> Result<ParsedDiagram, DiagramTypeError> {
            let Some(body) = request.source.strip_prefix("fake\n") else {
                return Err(DiagramTypeError::UnsupportedHeader(
                    request.source.lines().next().unwrap_or("").to_owned(),
                ));
            };
            Ok(ParsedDiagram::new(
                body.as_bytes().to_vec(),
                "application/x-kumeyuri-fake-ast",
            ))
        }

        fn layout(&self, request: DiagramLayoutRequest<'_>) -> Result<Frame, DiagramTypeError> {
            Ok(Frame::new(request.diagram.bytes.len(), 1))
        }
    }

    struct FakeThemeTransform;

    impl ThemeTransform for FakeThemeTransform {
        fn id(&self) -> &'static str {
            "fake-theme-transform"
        }

        fn required_capabilities(&self) -> CapabilitySet {
            CapabilitySet::from_iter([Capability::ClockNow])
        }

        fn transform(&self, request: ThemeTransformRequest) -> Result<Theme, ThemeTransformError> {
            if request.theme.name != "github" {
                return Err(ThemeTransformError::UnsupportedTheme(
                    request.theme.name.to_owned(),
                ));
            }
            let mut theme = request.theme;
            theme.colors.foreground = RgbColor::new(0x11, 0x11, 0x11);
            Ok(theme)
        }
    }
}
