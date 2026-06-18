use serde::{Deserialize, Serialize};
use std::{error::Error, fmt};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LayoutRewriteRequest {
    pub source: String,
    pub diagnostics: Vec<LayoutDiagnostic>,
}

impl LayoutRewriteRequest {
    #[must_use]
    pub fn new(source: impl Into<String>) -> Self {
        Self {
            source: source.into(),
            diagnostics: Vec::new(),
        }
    }

    #[must_use]
    pub fn with_diagnostic(mut self, diagnostic: LayoutDiagnostic) -> Self {
        self.diagnostics.push(diagnostic);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LayoutDiagnostic {
    pub code: String,
    pub message: String,
    pub suggestion: Option<String>,
}

impl LayoutDiagnostic {
    #[must_use]
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            suggestion: None,
        }
    }

    #[must_use]
    pub fn with_suggestion(mut self, suggestion: impl Into<String>) -> Self {
        self.suggestion = Some(suggestion.into());
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LayoutRewrite {
    pub rewritten_source: String,
    pub summary: String,
}

impl LayoutRewrite {
    #[must_use]
    pub fn new(rewritten_source: impl Into<String>, summary: impl Into<String>) -> Self {
        Self {
            rewritten_source: rewritten_source.into(),
            summary: summary.into(),
        }
    }
}

pub trait LayoutAssistant {
    fn rewrite(&self, request: &LayoutRewriteRequest) -> Result<LayoutRewrite, AiError>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AiProvider {
    OpenAi,
    Anthropic,
    OpenRouter,
    LlamaCpp,
}

impl AiProvider {
    pub const ALL: [Self; 4] = [
        Self::OpenAi,
        Self::Anthropic,
        Self::OpenRouter,
        Self::LlamaCpp,
    ];

    #[must_use]
    pub const fn api_key_env_var(self) -> Option<&'static str> {
        match self {
            Self::OpenAi => Some("OPENAI_API_KEY"),
            Self::Anthropic => Some("ANTHROPIC_API_KEY"),
            Self::OpenRouter => Some("OPENROUTER_API_KEY"),
            Self::LlamaCpp => None,
        }
    }

    #[must_use]
    pub const fn requires_api_key(self) -> bool {
        self.api_key_env_var().is_some()
    }
}

impl fmt::Display for AiProvider {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::OpenAi => formatter.write_str("OpenAI"),
            Self::Anthropic => formatter.write_str("Anthropic"),
            Self::OpenRouter => formatter.write_str("OpenRouter"),
            Self::LlamaCpp => formatter.write_str("llama.cpp"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub provider: AiProvider,
    pub endpoint: Option<String>,
    pub model: Option<String>,
}

impl ProviderConfig {
    #[must_use]
    pub const fn new(provider: AiProvider) -> Self {
        Self {
            provider,
            endpoint: None,
            model: None,
        }
    }

    #[must_use]
    pub fn with_endpoint(mut self, endpoint: impl Into<String>) -> Self {
        self.endpoint = Some(endpoint.into());
        self
    }

    #[must_use]
    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = Some(model.into());
        self
    }

    pub fn resolve_api_key_with(
        &self,
        lookup: impl FnMut(&str) -> Option<String>,
    ) -> Result<Option<ApiKey>, AiError> {
        if self.provider.requires_api_key() {
            return resolve_api_key_with(self.provider, lookup).map(Some);
        }
        Ok(None)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderRequest {
    pub config: ProviderConfig,
    pub prompt: String,
}

impl ProviderRequest {
    #[must_use]
    pub fn new(config: ProviderConfig, prompt: impl Into<String>) -> Self {
        Self {
            config,
            prompt: prompt.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderResponse {
    pub text: String,
}

impl ProviderResponse {
    #[must_use]
    pub fn new(text: impl Into<String>) -> Self {
        Self { text: text.into() }
    }
}

pub trait ProviderClient {
    fn provider(&self) -> AiProvider;
    fn complete(&self, request: &ProviderRequest) -> Result<ProviderResponse, AiError>;
}

#[derive(Clone, PartialEq, Eq)]
pub struct ApiKey {
    provider: AiProvider,
    env_var: &'static str,
    secret: String,
}

impl ApiKey {
    #[must_use]
    pub const fn provider(&self) -> AiProvider {
        self.provider
    }

    #[must_use]
    pub const fn env_var(&self) -> &'static str {
        self.env_var
    }

    #[must_use]
    pub fn expose_secret(&self) -> &str {
        &self.secret
    }
}

impl fmt::Debug for ApiKey {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ApiKey")
            .field("provider", &self.provider)
            .field("env_var", &self.env_var)
            .field("secret", &"<redacted>")
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AiError {
    ApiKeyNotRequired {
        provider: AiProvider,
    },
    MissingApiKey {
        provider: AiProvider,
        env_var: &'static str,
    },
    ProviderUnavailable(String),
    InvalidResponse(String),
}

impl fmt::Display for AiError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ApiKeyNotRequired { provider } => {
                write!(formatter, "{provider} does not use an API key")
            }
            Self::MissingApiKey { provider, env_var } => {
                write!(formatter, "missing {provider} API key in {env_var}")
            }
            Self::ProviderUnavailable(message) => {
                write!(formatter, "provider unavailable: {message}")
            }
            Self::InvalidResponse(message) => write!(formatter, "invalid response: {message}"),
        }
    }
}

impl Error for AiError {}

pub fn resolve_api_key(provider: AiProvider) -> Result<ApiKey, AiError> {
    resolve_api_key_with(provider, |name| std::env::var(name).ok())
}

pub fn resolve_api_key_with(
    provider: AiProvider,
    mut lookup: impl FnMut(&str) -> Option<String>,
) -> Result<ApiKey, AiError> {
    let Some(env_var) = provider.api_key_env_var() else {
        return Err(AiError::ApiKeyNotRequired { provider });
    };
    let Some(raw) = lookup(env_var) else {
        return Err(AiError::MissingApiKey { provider, env_var });
    };
    let secret = raw.trim();
    if secret.is_empty() {
        return Err(AiError::MissingApiKey { provider, env_var });
    }
    Ok(ApiKey {
        provider,
        env_var,
        secret: secret.to_owned(),
    })
}

pub fn validate_rewrite(rewrite: &LayoutRewrite) -> Result<(), AiError> {
    if rewrite.rewritten_source.trim().is_empty() {
        return Err(AiError::InvalidResponse(
            "rewritten source must not be empty".to_owned(),
        ));
    }
    if rewrite.summary.trim().is_empty() {
        return Err(AiError::InvalidResponse(
            "rewrite summary must not be empty".to_owned(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        AiError, AiProvider, LayoutDiagnostic, LayoutRewrite, LayoutRewriteRequest, ProviderConfig,
        ProviderRequest, ProviderResponse, resolve_api_key_with, validate_rewrite,
    };

    #[test]
    fn request_collects_diagnostics() {
        let request = LayoutRewriteRequest::new("graph TD\nA\n").with_diagnostic(
            LayoutDiagnostic::new("flowchart.orphan_node", "A has no edges")
                .with_suggestion("add A --> B"),
        );

        assert_eq!(request.source, "graph TD\nA\n");
        assert_eq!(request.diagnostics.len(), 1);
        assert_eq!(request.diagnostics[0].code, "flowchart.orphan_node");
        assert_eq!(
            request.diagnostics[0].suggestion.as_deref(),
            Some("add A --> B")
        );
    }

    #[test]
    fn validates_rewrite_shape() {
        assert!(
            validate_rewrite(&LayoutRewrite::new(
                "graph LR\nA --> B",
                "swapped direction"
            ))
            .is_ok()
        );
        assert_eq!(
            validate_rewrite(&LayoutRewrite::new("", "empty")).unwrap_err(),
            AiError::InvalidResponse("rewritten source must not be empty".to_owned())
        );
        assert_eq!(
            validate_rewrite(&LayoutRewrite::new("graph TD\nA", "")).unwrap_err(),
            AiError::InvalidResponse("rewrite summary must not be empty".to_owned())
        );
    }

    #[test]
    fn resolves_provider_api_keys_from_expected_envvars() {
        let key = resolve_api_key_with(AiProvider::OpenAi, |name| {
            (name == "OPENAI_API_KEY").then(|| " sk-openai ".to_owned())
        })
        .unwrap();

        assert_eq!(key.provider(), AiProvider::OpenAi);
        assert_eq!(key.env_var(), "OPENAI_API_KEY");
        assert_eq!(key.expose_secret(), "sk-openai");
        assert!(format!("{key:?}").contains("<redacted>"));
        assert_eq!(
            AiProvider::Anthropic.api_key_env_var(),
            Some("ANTHROPIC_API_KEY")
        );
        assert_eq!(
            AiProvider::OpenRouter.api_key_env_var(),
            Some("OPENROUTER_API_KEY")
        );
    }

    #[test]
    fn rejects_missing_or_blank_api_keys() {
        assert_eq!(
            resolve_api_key_with(AiProvider::Anthropic, |_| None).unwrap_err(),
            AiError::MissingApiKey {
                provider: AiProvider::Anthropic,
                env_var: "ANTHROPIC_API_KEY",
            }
        );
        assert_eq!(
            resolve_api_key_with(AiProvider::OpenRouter, |_| Some(" ".to_owned())).unwrap_err(),
            AiError::MissingApiKey {
                provider: AiProvider::OpenRouter,
                env_var: "OPENROUTER_API_KEY",
            }
        );
    }

    #[test]
    fn provider_catalog_covers_cloud_and_local_backends() {
        assert_eq!(
            AiProvider::ALL,
            [
                AiProvider::OpenAi,
                AiProvider::Anthropic,
                AiProvider::OpenRouter,
                AiProvider::LlamaCpp,
            ]
        );
        assert!(AiProvider::OpenAi.requires_api_key());
        assert!(!AiProvider::LlamaCpp.requires_api_key());
        assert_eq!(AiProvider::LlamaCpp.api_key_env_var(), None);
    }

    #[test]
    fn provider_config_resolves_optional_api_keys() {
        let openai = ProviderConfig::new(AiProvider::OpenAi)
            .with_endpoint("https://example.invalid")
            .with_model("layout-model");
        let key = openai
            .resolve_api_key_with(|name| (name == "OPENAI_API_KEY").then(|| "sk".to_owned()))
            .unwrap()
            .unwrap();
        assert_eq!(key.expose_secret(), "sk");

        let local =
            ProviderConfig::new(AiProvider::LlamaCpp).with_endpoint("http://127.0.0.1:8080");
        assert_eq!(local.resolve_api_key_with(|_| None).unwrap(), None);
        assert_eq!(
            resolve_api_key_with(AiProvider::LlamaCpp, |_| Some("unused".to_owned())).unwrap_err(),
            AiError::ApiKeyNotRequired {
                provider: AiProvider::LlamaCpp,
            }
        );
    }

    #[test]
    fn provider_request_and_response_hold_transport_payloads() {
        let request = ProviderRequest::new(
            ProviderConfig::new(AiProvider::OpenRouter).with_model("layout-model"),
            "rewrite this diagram",
        );
        let response = ProviderResponse::new("graph LR\nA --> B");

        assert_eq!(request.config.provider, AiProvider::OpenRouter);
        assert_eq!(request.prompt, "rewrite this diagram");
        assert_eq!(response.text, "graph LR\nA --> B");
    }
}
