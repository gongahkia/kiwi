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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AiError {
    ProviderUnavailable(String),
    InvalidResponse(String),
}

impl fmt::Display for AiError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ProviderUnavailable(message) => {
                write!(formatter, "provider unavailable: {message}")
            }
            Self::InvalidResponse(message) => write!(formatter, "invalid response: {message}"),
        }
    }
}

impl Error for AiError {}

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
    use super::{AiError, LayoutDiagnostic, LayoutRewrite, LayoutRewriteRequest, validate_rewrite};

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
}
