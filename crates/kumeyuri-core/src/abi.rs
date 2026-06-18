use std::{fmt, str::FromStr};

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

#[cfg(test)]
mod tests {
    use super::{AbiVersion, Capability, CapabilitySet, KUMEYURI_ABI_VERSION};

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
}
