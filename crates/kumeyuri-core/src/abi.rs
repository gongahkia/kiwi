use std::{fmt, str::FromStr};

use crate::animator::Timeline;

pub const KUMEYURI_ABI_VERSION: AbiVersion = AbiVersion::new(1, 0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct AbiVersion {
    pub major: u16,
    pub minor: u16,
}

impl AbiVersion {
    #[must_use]
    pub const fn new(major: u16, minor: u16) -> Self {
        Self { major, minor }
    }

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AbiVersionParseError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Capability {
    FsRead = 0,
    FsWrite = 1,
    NetFetch = 2,
    EnvRead = 3,
    CacheRead = 4,
    CacheWrite = 5,
    ClockNow = 6,
    RandomBytes = 7,
}

impl Capability {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapabilityParseError;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct CapabilitySet {
    bits: u64,
}

impl CapabilitySet {
    #[must_use]
    pub const fn empty() -> Self {
        Self { bits: 0 }
    }

    #[must_use]
    pub fn all() -> Self {
        Self::from_iter(Capability::ALL)
    }

    #[must_use]
    pub fn from_iter(capabilities: impl IntoIterator<Item = Capability>) -> Self {
        let mut set = Self::empty();
        for capability in capabilities {
            set.insert(capability);
        }
        set
    }

    #[must_use]
    pub const fn contains(self, capability: Capability) -> bool {
        self.bits & capability.bit() != 0
    }

    pub fn insert(&mut self, capability: Capability) {
        self.bits |= capability.bit();
    }

    pub fn remove(&mut self, capability: Capability) {
        self.bits &= !capability.bit();
    }

    #[must_use]
    pub const fn is_subset(self, allowed: Self) -> bool {
        self.bits & !allowed.bits == 0
    }

    pub fn iter(self) -> impl Iterator<Item = Capability> {
        Capability::ALL
            .into_iter()
            .filter(move |capability| self.contains(*capability))
    }
}

impl FromIterator<Capability> for CapabilitySet {
    fn from_iter<T: IntoIterator<Item = Capability>>(iter: T) -> Self {
        Self::from_iter(iter)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderBackendMetadata {
    pub title: Option<String>,
    pub source_path: Option<String>,
}

impl RenderBackendMetadata {
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

#[derive(Debug)]
pub struct RenderBackendRequest<'timeline, 'metadata> {
    pub abi: AbiVersion,
    pub format: &'static str,
    pub theme: &'static str,
    pub timeline: &'timeline Timeline,
    pub metadata: &'metadata RenderBackendMetadata,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderArtifact {
    pub bytes: Vec<u8>,
    pub media_type: String,
    pub extension: String,
}

impl RenderArtifact {
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RenderBackendError {
    IncompatibleAbi {
        host: AbiVersion,
        required: AbiVersion,
    },
    MissingCapabilities(CapabilitySet),
    UnsupportedFormat(String),
    RenderFailed(String),
}

pub trait RenderBackend {
    fn id(&self) -> &'static str;

    fn abi_version(&self) -> AbiVersion {
        KUMEYURI_ABI_VERSION
    }

    fn format(&self) -> &'static str;

    fn media_type(&self) -> &'static str;

    fn extension(&self) -> &'static str;

    fn required_capabilities(&self) -> CapabilitySet {
        CapabilitySet::empty()
    }

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

    fn render(
        &self,
        request: RenderBackendRequest<'_, '_>,
    ) -> Result<RenderArtifact, RenderBackendError>;
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{
        AbiVersion, Capability, CapabilitySet, KUMEYURI_ABI_VERSION, RenderArtifact, RenderBackend,
        RenderBackendError, RenderBackendMetadata, RenderBackendRequest,
    };
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
}
