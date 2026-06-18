use std::{
    collections::BTreeMap,
    env, fmt, fs,
    path::{Component, Path, PathBuf},
    str::FromStr,
};

use serde::Deserialize;

use crate::abi::{AbiVersion, Capability, CapabilitySet, KUMEYURI_ABI_VERSION};

pub const PLUGIN_MANIFEST_FILE: &str = "kumeyuri.plugin.json";
pub const PLUGIN_CACHE_APP_DIR: &str = "kumeyuri";
pub const PLUGIN_CACHE_PLUGINS_DIR: &str = "plugins";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PluginKind {
    RenderBackend,
    DiagramType,
    ThemeTransform,
}

impl PluginKind {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::RenderBackend => "render-backend",
            Self::DiagramType => "diagram-type",
            Self::ThemeTransform => "theme-transform",
        }
    }

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PluginKindParseError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginManifest {
    pub name: String,
    pub version: String,
    pub abi: AbiVersion,
    pub entry: PathBuf,
    pub kind: PluginKind,
    pub capabilities: CapabilitySet,
    pub exports: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadedPlugin {
    pub manifest: PluginManifest,
    pub package_dir: PathBuf,
    pub component: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PluginLoader {
    host_abi: AbiVersion,
}

impl PluginLoader {
    #[must_use]
    pub const fn new(host_abi: AbiVersion) -> Self {
        Self { host_abi }
    }

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PluginRuntimePolicy {
    granted: CapabilitySet,
}

impl PluginRuntimePolicy {
    #[must_use]
    pub const fn deny_all() -> Self {
        Self {
            granted: CapabilitySet::empty(),
        }
    }

    #[must_use]
    pub const fn with_grants(granted: CapabilitySet) -> Self {
        Self { granted }
    }

    #[must_use]
    pub const fn granted(self) -> CapabilitySet {
        self.granted
    }

    #[must_use]
    pub const fn allows(self, capability: Capability) -> bool {
        self.granted.contains(capability)
    }

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginPolicyError {
    CapabilityDenied(CapabilitySet),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginCache {
    root: PathBuf,
}

impl PluginCache {
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    #[must_use]
    pub fn from_data_home(data_home: impl AsRef<Path>) -> Self {
        Self::new(
            data_home
                .as_ref()
                .join(PLUGIN_CACHE_APP_DIR)
                .join(PLUGIN_CACHE_PLUGINS_DIR),
        )
    }

    pub fn from_env() -> Result<Self, PluginCacheError> {
        if let Some(data_home) = non_empty_env_path("XDG_DATA_HOME") {
            return Ok(Self::from_data_home(data_home));
        }
        if let Some(home) = non_empty_env_path("HOME") {
            return Ok(Self::from_data_home(home.join(".local/share")));
        }
        Err(PluginCacheError::MissingDataHome)
    }

    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginCacheError {
    MissingDataHome,
    InvalidContentHash(String),
    CreateDir { path: PathBuf, source: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginLoadError {
    ReadManifest {
        path: PathBuf,
        source: String,
    },
    ParseManifest {
        source: String,
    },
    InvalidAbi(String),
    UnsupportedAbi {
        host: AbiVersion,
        required: AbiVersion,
    },
    UnknownKind(String),
    UnknownCapability(String),
    InvalidEntry(String),
    MissingExport(&'static str),
    ReadEntry {
        path: PathBuf,
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
