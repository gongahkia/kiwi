//! Plugin manifest loading, runtime policy, and cache path helpers.

use std::{
    collections::BTreeMap,
    env, fmt, fs,
    path::{Component, Path, PathBuf},
    str::FromStr,
};

use serde::Deserialize;

use crate::abi::{AbiVersion, Capability, CapabilitySet, KUMEYURI_ABI_VERSION};

/// Expected filename for a kumeyuri plugin manifest.
pub const PLUGIN_MANIFEST_FILE: &str = "kumeyuri.plugin.json";
/// XDG application directory used by the plugin cache.
pub const PLUGIN_CACHE_APP_DIR: &str = "kumeyuri";
/// Subdirectory under the application cache root that stores plugins.
pub const PLUGIN_CACHE_PLUGINS_DIR: &str = "plugins";

/// Plugin extension category.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PluginKind {
    /// Renderer plugin implementing a custom output backend.
    RenderBackend,
    /// Diagram plugin implementing parser and layout hooks.
    DiagramType,
    /// Theme plugin transforming built-in or user themes.
    ThemeTransform,
}

impl PluginKind {
    /// Return the manifest spelling for this plugin kind.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::RenderBackend => "render-backend",
            Self::DiagramType => "diagram-type",
            Self::ThemeTransform => "theme-transform",
        }
    }

    /// Return the export name required in the plugin manifest.
    #[must_use]
    pub const fn required_export(self) -> &'static str {
        match self {
            Self::RenderBackend => "renderBackend",
            Self::DiagramType => "diagramType",
            Self::ThemeTransform => "themeTransform",
        }
    }
}

impl fmt::Display for PluginKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for PluginKind {
    type Err = PluginKindParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "render-backend" => Ok(Self::RenderBackend),
            "diagram-type" => Ok(Self::DiagramType),
            "theme-transform" => Ok(Self::ThemeTransform),
            _ => Err(PluginKindParseError),
        }
    }
}

/// Error returned when a plugin kind string cannot be parsed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PluginKindParseError;

/// Parsed `kumeyuri.plugin.json` manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginManifest {
    /// Package name.
    pub name: String,
    /// Package version.
    pub version: String,
    /// ABI required by the plugin.
    pub abi: AbiVersion,
    /// Relative path to the plugin WASM component.
    pub entry: PathBuf,
    /// Extension category.
    pub kind: PluginKind,
    /// Runtime capabilities requested by the plugin.
    pub capabilities: CapabilitySet,
    /// Export map advertised by the plugin package.
    pub exports: BTreeMap<String, String>,
}

/// Plugin package loaded from disk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadedPlugin {
    /// Parsed package manifest.
    pub manifest: PluginManifest,
    /// Directory containing the plugin package.
    pub package_dir: PathBuf,
    /// Raw WASM component bytes.
    pub component: Vec<u8>,
}

/// Loader for plugin packages compatible with a host ABI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PluginLoader {
    host_abi: AbiVersion,
}

impl PluginLoader {
    /// Create a loader for a specific host ABI.
    #[must_use]
    pub const fn new(host_abi: AbiVersion) -> Self {
        Self { host_abi }
    }

    /// Load a plugin manifest and WASM component from a package directory.
    pub fn load_package(
        &self,
        package_dir: impl AsRef<Path>,
    ) -> Result<LoadedPlugin, PluginLoadError> {
        let package_dir = package_dir.as_ref();
        let manifest_path = package_dir.join(PLUGIN_MANIFEST_FILE);
        let manifest_source =
            fs::read_to_string(&manifest_path).map_err(|source| PluginLoadError::ReadManifest {
                path: manifest_path.clone(),
                source: source.to_string(),
            })?;
        let manifest = self.parse_manifest_json(&manifest_source)?;
        let entry_path = package_dir.join(&manifest.entry);
        let component = fs::read(&entry_path).map_err(|source| PluginLoadError::ReadEntry {
            path: entry_path,
            source: source.to_string(),
        })?;

        Ok(LoadedPlugin {
            manifest,
            package_dir: package_dir.to_path_buf(),
            component,
        })
    }

    /// Parse and validate a plugin manifest JSON document.
    pub fn parse_manifest_json(&self, source: &str) -> Result<PluginManifest, PluginLoadError> {
        let raw: RawPluginManifest =
            serde_json::from_str(source).map_err(|error| PluginLoadError::ParseManifest {
                source: error.to_string(),
            })?;
        let abi = raw
            .abi
            .parse()
            .map_err(|_| PluginLoadError::InvalidAbi(raw.abi.clone()))?;
        if !self.host_abi.supports(abi) {
            return Err(PluginLoadError::UnsupportedAbi {
                host: self.host_abi,
                required: abi,
            });
        }
        let kind: PluginKind = raw
            .kind
            .parse()
            .map_err(|_| PluginLoadError::UnknownKind(raw.kind.clone()))?;
        if !raw.exports.contains_key(kind.required_export()) {
            return Err(PluginLoadError::MissingExport(kind.required_export()));
        }
        let entry = validate_entry(&raw.entry)?;
        let capabilities = parse_capabilities(raw.capabilities)?;

        Ok(PluginManifest {
            name: raw.name,
            version: raw.version,
            abi,
            entry,
            kind,
            capabilities,
            exports: raw.exports,
        })
    }
}

impl Default for PluginLoader {
    fn default() -> Self {
        Self::new(KUMEYURI_ABI_VERSION)
    }
}

/// Runtime capability grant policy for plugin execution.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PluginRuntimePolicy {
    granted: CapabilitySet,
}

impl PluginRuntimePolicy {
    /// Create a policy that grants no capabilities.
    #[must_use]
    pub const fn deny_all() -> Self {
        Self {
            granted: CapabilitySet::empty(),
        }
    }

    /// Create a policy with explicit capability grants.
    #[must_use]
    pub const fn with_grants(granted: CapabilitySet) -> Self {
        Self { granted }
    }

    /// Return capabilities granted by this policy.
    #[must_use]
    pub const fn granted(self) -> CapabilitySet {
        self.granted
    }

    /// Return whether this policy grants a capability.
    #[must_use]
    pub const fn allows(self, capability: Capability) -> bool {
        self.granted.contains(capability)
    }

    /// Validate that a manifest requests only granted capabilities.
    pub fn validate_manifest(&self, manifest: &PluginManifest) -> Result<(), PluginPolicyError> {
        if !manifest.capabilities.is_subset(self.granted) {
            return Err(PluginPolicyError::CapabilityDenied(manifest.capabilities));
        }
        Ok(())
    }
}

impl Default for PluginRuntimePolicy {
    fn default() -> Self {
        Self::deny_all()
    }
}

/// Error returned when a plugin violates runtime policy.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginPolicyError {
    /// A manifest requested capabilities not granted by policy.
    CapabilityDenied(CapabilitySet),
}

/// Filesystem layout helper for the plugin cache.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginCache {
    root: PathBuf,
}

impl PluginCache {
    /// Create a cache rooted at an explicit path.
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// Create a cache below an XDG data-home directory.
    #[must_use]
    pub fn from_data_home(data_home: impl AsRef<Path>) -> Self {
        Self::new(
            data_home
                .as_ref()
                .join(PLUGIN_CACHE_APP_DIR)
                .join(PLUGIN_CACHE_PLUGINS_DIR),
        )
    }

    /// Create a cache from `XDG_DATA_HOME` or `HOME`.
    pub fn from_env() -> Result<Self, PluginCacheError> {
        if let Some(data_home) = non_empty_env_path("XDG_DATA_HOME") {
            return Ok(Self::from_data_home(data_home));
        }
        if let Some(home) = non_empty_env_path("HOME") {
            return Ok(Self::from_data_home(home.join(".local/share")));
        }
        Err(PluginCacheError::MissingDataHome)
    }

    /// Return the cache root directory.
    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Return the cache directory for a manifest and content hash.
    pub fn package_dir(
        &self,
        manifest: &PluginManifest,
        content_hash: &str,
    ) -> Result<PathBuf, PluginCacheError> {
        self.package_dir_for(
            &manifest.name,
            &manifest.version,
            manifest.abi.major,
            content_hash,
        )
    }

    /// Return the cache directory for package identity and content hash parts.
    pub fn package_dir_for(
        &self,
        name: &str,
        version: &str,
        abi_major: u16,
        content_hash: &str,
    ) -> Result<PathBuf, PluginCacheError> {
        validate_content_hash(content_hash)?;
        Ok(self
            .root
            .join(encode_cache_component(name))
            .join(encode_cache_component(version))
            .join(format!("abi-{abi_major}"))
            .join(content_hash))
    }

    /// Create and return the cache directory for a package if needed.
    pub fn ensure_package_dir(
        &self,
        manifest: &PluginManifest,
        content_hash: &str,
    ) -> Result<PathBuf, PluginCacheError> {
        let package_dir = self.package_dir_for(
            &manifest.name,
            &manifest.version,
            manifest.abi.major,
            content_hash,
        )?;
        fs::create_dir_all(&package_dir).map_err(|source| PluginCacheError::CreateDir {
            path: package_dir.clone(),
            source: source.to_string(),
        })?;
        Ok(package_dir)
    }
}

/// Error returned while resolving or creating plugin cache paths.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginCacheError {
    /// Neither `XDG_DATA_HOME` nor `HOME` was available.
    MissingDataHome,
    /// The content hash is not a safe lowercase hexadecimal cache component.
    InvalidContentHash(String),
    /// Creating a cache directory failed.
    CreateDir {
        /// Directory path that could not be created.
        path: PathBuf,
        /// I/O error message.
        source: String,
    },
}

/// Error returned while loading a plugin package.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginLoadError {
    /// Reading the manifest file failed.
    ReadManifest {
        /// Manifest path.
        path: PathBuf,
        /// I/O error message.
        source: String,
    },
    /// Parsing the manifest JSON failed.
    ParseManifest {
        /// Parser error message.
        source: String,
    },
    /// The manifest ABI string was invalid.
    InvalidAbi(String),
    /// The manifest requires an ABI unsupported by the host.
    UnsupportedAbi {
        /// ABI supported by the host.
        host: AbiVersion,
        /// ABI required by the plugin.
        required: AbiVersion,
    },
    /// The manifest plugin kind was not recognized.
    UnknownKind(String),
    /// A requested capability was not recognized.
    UnknownCapability(String),
    /// The entry path was absolute, unsafe, or not a WASM file.
    InvalidEntry(String),
    /// A required export was missing from the manifest.
    MissingExport(&'static str),
    /// Reading the WASM entry file failed.
    ReadEntry {
        /// Entry path.
        path: PathBuf,
        /// I/O error message.
        source: String,
    },
}

#[derive(Debug, Deserialize)]
struct RawPluginManifest {
    name: String,
    version: String,
    abi: String,
    entry: String,
    kind: String,
    #[serde(default)]
    capabilities: Vec<String>,
    exports: BTreeMap<String, String>,
}

fn parse_capabilities(values: Vec<String>) -> Result<CapabilitySet, PluginLoadError> {
    let mut capabilities = CapabilitySet::empty();
    for value in values {
        let capability = value
            .parse()
            .map_err(|_| PluginLoadError::UnknownCapability(value.clone()))?;
        capabilities.insert(capability);
    }
    Ok(capabilities)
}

fn validate_entry(value: &str) -> Result<PathBuf, PluginLoadError> {
    let path = Path::new(value);
    if value.is_empty()
        || path.is_absolute()
        || path.extension().and_then(|ext| ext.to_str()) != Some("wasm")
    {
        return Err(PluginLoadError::InvalidEntry(value.to_owned()));
    }
    if path.components().any(|component| {
        matches!(
            component,
            Component::ParentDir | Component::Prefix(_) | Component::RootDir
        )
    }) {
        return Err(PluginLoadError::InvalidEntry(value.to_owned()));
    }
    Ok(path.to_path_buf())
}

fn non_empty_env_path(name: &str) -> Option<PathBuf> {
    let value = env::var_os(name)?;
    if value.is_empty() {
        return None;
    }
    Some(PathBuf::from(value))
}

fn validate_content_hash(value: &str) -> Result<(), PluginCacheError> {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(PluginCacheError::InvalidContentHash(value.to_owned()));
    }
    Ok(())
}

fn encode_cache_component(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-') {
            encoded.push(char::from(byte));
        } else {
            encoded.push('%');
            encoded.push(hex_digit(byte >> 4));
            encoded.push(hex_digit(byte & 0x0f));
        }
    }
    encoded
}

fn hex_digit(value: u8) -> char {
    match value {
        0..=9 => char::from(b'0' + value),
        10..=15 => char::from(b'a' + value - 10),
        _ => unreachable!("hex digit input is masked to four bits"),
    }
}

#[cfg(test)]
mod tests {
    use std::{env, fs, process, time::SystemTime};

    use super::{
        PLUGIN_MANIFEST_FILE, PluginCache, PluginCacheError, PluginKind, PluginLoadError,
        PluginLoader, PluginPolicyError, PluginRuntimePolicy,
    };
    use crate::abi::{AbiVersion, Capability, CapabilitySet};

    #[test]
    fn plugin_loader_loads_manifest_and_component() {
        let package_dir = unique_temp_dir("load");
        fs::create_dir_all(&package_dir).unwrap();
        fs::write(package_dir.join("plugin.wasm"), b"\0asm").unwrap();
        fs::write(
            package_dir.join(PLUGIN_MANIFEST_FILE),
            r#"{
  "name": "kumeyuri-render-pdf",
  "version": "0.1.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "render-backend",
  "capabilities": ["fs.write"],
  "exports": { "renderBackend": "pdf" }
}"#,
        )
        .unwrap();

        let plugin = PluginLoader::default().load_package(&package_dir).unwrap();

        assert_eq!(plugin.manifest.name, "kumeyuri-render-pdf");
        assert_eq!(plugin.manifest.kind, PluginKind::RenderBackend);
        assert!(plugin.manifest.capabilities.contains(Capability::FsWrite));
        assert_eq!(plugin.manifest.exports["renderBackend"], "pdf");
        assert_eq!(plugin.component, b"\0asm");

        fs::remove_dir_all(package_dir).unwrap();
    }

    #[test]
    fn plugin_loader_rejects_unsupported_abi() {
        let error = PluginLoader::default()
            .parse_manifest_json(
                r#"{
  "name": "future",
  "version": "1.0.0",
  "abi": "2.0",
  "entry": "plugin.wasm",
  "kind": "diagram-type",
  "capabilities": [],
  "exports": { "diagramType": "future" }
}"#,
            )
            .unwrap_err();

        assert_eq!(
            error,
            PluginLoadError::UnsupportedAbi {
                host: AbiVersion::new(1, 0),
                required: AbiVersion::new(2, 0),
            }
        );
    }

    #[test]
    fn plugin_loader_rejects_unknown_capabilities_and_entry_traversal() {
        let unknown_capability = PluginLoader::default()
            .parse_manifest_json(
                r#"{
  "name": "bad-capability",
  "version": "1.0.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "theme-transform",
  "capabilities": ["process.spawn"],
  "exports": { "themeTransform": "bad" }
}"#,
            )
            .unwrap_err();
        assert_eq!(
            unknown_capability,
            PluginLoadError::UnknownCapability("process.spawn".to_owned())
        );

        let bad_entry = PluginLoader::default()
            .parse_manifest_json(
                r#"{
  "name": "bad-entry",
  "version": "1.0.0",
  "abi": "1.0",
  "entry": "../plugin.wasm",
  "kind": "theme-transform",
  "capabilities": [],
  "exports": { "themeTransform": "bad" }
}"#,
            )
            .unwrap_err();
        assert_eq!(
            bad_entry,
            PluginLoadError::InvalidEntry("../plugin.wasm".to_owned())
        );
    }

    #[test]
    fn plugin_loader_requires_kind_export() {
        let error = PluginLoader::default()
            .parse_manifest_json(
                r#"{
  "name": "missing-export",
  "version": "1.0.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "diagram-type",
  "capabilities": [],
  "exports": { "renderBackend": "wrong" }
}"#,
            )
            .unwrap_err();

        assert_eq!(error, PluginLoadError::MissingExport("diagramType"));
    }

    #[test]
    fn plugin_runtime_policy_denies_capabilities_by_default() {
        let manifest = PluginLoader::default()
            .parse_manifest_json(
                r#"{
  "name": "writer",
  "version": "1.0.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "render-backend",
  "capabilities": ["fs.write"],
  "exports": { "renderBackend": "writer" }
}"#,
            )
            .unwrap();
        let denied = PluginRuntimePolicy::default();

        assert!(!denied.allows(Capability::FsWrite));
        assert_eq!(
            denied.validate_manifest(&manifest).unwrap_err(),
            PluginPolicyError::CapabilityDenied(CapabilitySet::from_iter([Capability::FsWrite]))
        );

        let granted =
            PluginRuntimePolicy::with_grants(CapabilitySet::from_iter([Capability::FsWrite]));
        assert!(granted.allows(Capability::FsWrite));
        assert!(granted.validate_manifest(&manifest).is_ok());
    }

    #[test]
    fn plugin_cache_uses_xdg_data_home_namespace() {
        let cache = PluginCache::from_data_home("/tmp/xdg-data");

        assert_eq!(
            cache.root(),
            std::path::Path::new("/tmp/xdg-data/kumeyuri/plugins")
        );
    }

    #[test]
    fn plugin_cache_places_packages_by_name_version_abi_and_hash() {
        let manifest = PluginLoader::default()
            .parse_manifest_json(
                r#"{
  "name": "@scope/render-pdf",
  "version": "0.1.0",
  "abi": "1.0",
  "entry": "plugin.wasm",
  "kind": "render-backend",
  "capabilities": [],
  "exports": { "renderBackend": "pdf" }
}"#,
            )
            .unwrap();
        let cache = PluginCache::new("/tmp/kumeyuri-cache");

        assert_eq!(
            cache.package_dir(&manifest, "abcdef012345").unwrap(),
            std::path::Path::new(
                "/tmp/kumeyuri-cache/%40scope%2frender-pdf/0.1.0/abi-1/abcdef012345"
            )
        );
        assert_eq!(
            cache.package_dir(&manifest, "not-a-hash").unwrap_err(),
            PluginCacheError::InvalidContentHash("not-a-hash".to_owned())
        );
    }

    fn unique_temp_dir(label: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        env::temp_dir().join(format!(
            "kumeyuri-plugin-loader-{label}-{}-{nanos}",
            process::id()
        ))
    }
}
