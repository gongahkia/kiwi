use fluent_bundle::{FluentBundle, FluentResource};
use unic_langid::LanguageIdentifier;

const EN_US_FTL: &str = "compat-title = Mermaid compatibility\n";

pub struct I18n {
    bundle: FluentBundle<FluentResource>,
}

impl I18n {
    pub fn en_us() -> Result<Self, String> {
        let locale = "en-US"
            .parse::<LanguageIdentifier>()
            .map_err(|error| format!("invalid locale en-US: {error}"))?;
        let resource = FluentResource::try_new(EN_US_FTL.to_owned())
            .map_err(|errors| format!("invalid en-US Fluent resource: {errors:?}"))?;
        let mut bundle = FluentBundle::new(vec![locale]);
        bundle
            .add_resource(resource)
            .map_err(|errors| format!("failed to add en-US Fluent resource: {errors:?}"))?;
        Ok(Self { bundle })
    }

    pub fn message(&self, id: &str) -> Result<String, String> {
        let message = self
            .bundle
            .get_message(id)
            .ok_or_else(|| format!("missing Fluent message `{id}`"))?;
        let pattern = message
            .value()
            .ok_or_else(|| format!("missing Fluent value for `{id}`"))?;
        let mut errors = Vec::new();
        let value = self.bundle.format_pattern(pattern, None, &mut errors);
        if errors.is_empty() {
            Ok(value.into_owned())
        } else {
            Err(format!(
                "failed to format Fluent message `{id}`: {errors:?}"
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::I18n;

    #[test]
    fn formats_en_us_message() {
        assert_eq!(
            I18n::en_us().unwrap().message("compat-title").unwrap(),
            "Mermaid compatibility"
        );
    }
}
