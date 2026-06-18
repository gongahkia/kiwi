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
}

impl AiProvider {
    #[must_use]
    pub const fn env_var(self) -> &'static str {
        match self {
            Self::OpenAi => "OPENAI_API_KEY",
            Self::Anthropic => "ANTHROPIC_API_KEY",
            Self::OpenRouter => "OPENROUTER_API_KEY",
        }
    }
}

impl fmt::Display for AiProvider {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::OpenAi => formatter.write_str("OpenAI"),
            Self::Anthropic => formatter.write_str("Anthropic"),
            Self::OpenRouter => formatter.write_str("OpenRouter"),
        }
    }
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
    let env_var = provider.env_var();
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
        AiError, AiProvider, LayoutDiagnostic, LayoutRewrite, LayoutRewriteRequest,
        resolve_api_key_with, validate_rewrite,
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
        assert_eq!(AiProvider::Anthropic.env_var(), "ANTHROPIC_API_KEY");
        assert_eq!(AiProvider::OpenRouter.env_var(), "OPENROUTER_API_KEY");
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
}
