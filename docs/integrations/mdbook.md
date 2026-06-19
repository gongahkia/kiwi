# mdBook

`crates/mdbook-kumeyuri` is an mdBook preprocessor for Mermaid fences.

Install from a local checkout:

```sh
cargo install --path crates/mdbook-kumeyuri
```

Configure `book.toml`:

```toml
[preprocessor.kumeyuri]
command = "mdbook-kumeyuri"
format = "svg"
replace = false
theme = "github"
```

Supported options: `format`, `replace`, `theme`, `dark-theme`, `charset`,
`width`, `padding`, and `font`.
