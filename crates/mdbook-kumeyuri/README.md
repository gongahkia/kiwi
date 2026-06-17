# mdbook-kumeyuri

mdBook preprocessor that renders Mermaid fenced code blocks with kumeyuri.

## Install

```sh
cargo install --path crates/mdbook-kumeyuri
```

## Configure

```toml
[preprocessor.kumeyuri]
command = "mdbook-kumeyuri"
format = "svg" # svg | text
replace = false
theme = "default"
```

Supported options: `format`, `replace`, `theme`, `dark-theme`, `charset`, `width`, `padding`, and `font`.
