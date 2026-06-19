use std::cell::RefCell;

use fluent_bundle::{FluentArgs, FluentBundle, FluentResource};
use unic_langid::LanguageIdentifier;

const DEFAULT_LOCALE: &str = "en-US";
const EN_US_FTL: &str = include_str!("../../../locales/en-US.ftl");

thread_local! {
    static CURRENT: RefCell<I18n> = RefCell::new(I18n::en_us().expect("embedded Fluent resources must be valid"));
}

pub fn message(id: &str) -> String {
    format_message(id, &[])
}

pub fn format_message(id: &str, args: &[(&str, String)]) -> String {
    CURRENT.with(|current| {
        current
            .borrow()
            .format(id, args)
            .expect("embedded Fluent message exists")
    })
}

pub fn configure(
    override_locale: Option<&str>,
    lookup_env: impl FnMut(&str) -> Option<String>,
) -> Result<(), String> {
    let locale = resolve_locale(override_locale, lookup_env)?;
    CURRENT.with(|current| {
        *current.borrow_mut() = I18n::for_locale(locale)?;
        Ok(())
    })
}

pub fn resolve_locale(
    override_locale: Option<&str>,
    mut lookup_env: impl FnMut(&str) -> Option<String>,
) -> Result<LanguageIdentifier, String> {
    if let Some(locale) = override_locale {
        return parse_locale(locale);
    }
    for name in ["LC_ALL", "LANG"] {
        if let Some(locale) = lookup_env(name).and_then(|value| normalize_locale_tag(&value)) {
            return parse_locale(&locale);
        }
    }
    parse_locale(DEFAULT_LOCALE)
}

pub fn canonical_locale(value: &str) -> Result<String, String> {
    let normalized = normalize_locale_tag(value)
        .ok_or_else(|| format_message("locale-empty", &[("value", format!("{value:?}"))]))?;
    parse_locale(&normalized)?;
    Ok(normalized)
}

pub fn normalize_locale_tag(value: &str) -> Option<String> {
    let tag = value
        .trim()
        .split('.')
        .next()
        .unwrap_or_default()
        .split('@')
        .next()
        .unwrap_or_default();
    if tag.is_empty() || tag.eq_ignore_ascii_case("C") || tag.eq_ignore_ascii_case("POSIX") {
        return None;
    }
    Some(tag.replace('_', "-"))
}

fn parse_locale(value: &str) -> Result<LanguageIdentifier, String> {
    value.parse::<LanguageIdentifier>().map_err(|error| {
        format_message(
            "locale-invalid",
            &[
                ("value", format!("{value:?}")),
                ("error", error.to_string()),
            ],
        )
    })
}

pub struct I18n {
    bundle: FluentBundle<FluentResource>,
}

impl I18n {
    pub fn en_us() -> Result<Self, String> {
        Self::for_locale(parse_locale(DEFAULT_LOCALE)?)
    }

    fn for_locale(locale: LanguageIdentifier) -> Result<Self, String> {
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
    use super::{I18n, canonical_locale, normalize_locale_tag, resolve_locale};

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

    #[test]
    fn canonicalizes_posix_locale_tags() {
        assert_eq!(canonical_locale("en_US.UTF-8").unwrap(), "en-US");
    }

    #[test]
    fn resolves_override_before_environment() {
        let locale = resolve_locale(Some("fr-FR"), |_| Some("ja_JP.UTF-8".to_owned())).unwrap();
        assert_eq!(locale.to_string(), "fr-FR");
    }

    #[test]
    fn resolves_lc_all_before_lang() {
        let locale = resolve_locale(None, |name| match name {
            "LC_ALL" => Some("ko_KR.UTF-8".to_owned()),
            "LANG" => Some("ja_JP.UTF-8".to_owned()),
            _ => None,
        })
        .unwrap();
        assert_eq!(locale.to_string(), "ko-KR");
    }

    #[test]
    fn falls_back_to_default_for_c_locale() {
        let locale = resolve_locale(None, |name| match name {
            "LC_ALL" => Some("C.UTF-8".to_owned()),
            "LANG" => None,
            _ => None,
        })
        .unwrap();
        assert_eq!(locale.to_string(), "en-US");
    }

    #[test]
    fn normalizes_locale_tags_and_ignores_empty_posix_values() {
        assert_eq!(
            normalize_locale_tag(" fr_CA.UTF-8@calendar "),
            Some("fr-CA".to_owned())
        );
        assert_eq!(normalize_locale_tag("POSIX"), None);
        assert_eq!(normalize_locale_tag(""), None);
    }

    #[test]
    fn reports_invalid_and_missing_messages() {
        assert!(
            canonical_locale("not a locale")
                .unwrap_err()
                .contains("invalid locale")
        );
        assert!(
            I18n::en_us()
                .unwrap()
                .format("missing-message", &[])
                .unwrap_err()
                .contains("missing Fluent message")
        );
    }
}
