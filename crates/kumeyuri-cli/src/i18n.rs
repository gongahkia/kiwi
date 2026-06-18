use fluent_bundle::{FluentArgs, FluentBundle, FluentResource};
use unic_langid::LanguageIdentifier;

const EN_US_FTL: &str = include_str!("../../../locales/en-US.ftl");

thread_local! {
    static EN_US: I18n = I18n::en_us().expect("embedded Fluent resources must be valid");
}

pub fn message(id: &str) -> String {
    format_message(id, &[])
}

pub fn format_message(id: &str, args: &[(&str, String)]) -> String {
    EN_US.with(|i18n| {
        i18n.format(id, args)
            .expect("embedded Fluent message exists")
    })
}

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
        bundle.set_use_isolating(false);
        bundle
            .add_resource(resource)
            .map_err(|errors| format!("failed to add en-US Fluent resource: {errors:?}"))?;
        Ok(Self { bundle })
    }

    pub fn format(&self, id: &str, args: &[(&str, String)]) -> Result<String, String> {
        let message = self
            .bundle
            .get_message(id)
            .ok_or_else(|| format!("missing Fluent message `{id}`"))?;
        let pattern = message
            .value()
            .ok_or_else(|| format!("missing Fluent value for `{id}`"))?;
        let args = if args.is_empty() {
            None
        } else {
            let mut fluent_args = FluentArgs::with_capacity(args.len());
            for (key, value) in args {
                fluent_args.set(*key, value.as_str());
            }
            Some(fluent_args)
        };
        let mut errors = Vec::new();
        let value = self
            .bundle
            .format_pattern(pattern, args.as_ref(), &mut errors);
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
            I18n::en_us().unwrap().format("compat-title", &[]).unwrap(),
            "Mermaid compatibility"
        );
    }

    #[test]
    fn formats_en_us_args() {
        assert_eq!(
            I18n::en_us()
                .unwrap()
                .format(
                    "compat-requested-version",
                    &[("version", "11.15.0".to_owned())]
                )
                .unwrap(),
            "requested Mermaid version: 11.15.0"
        );
    }
}
