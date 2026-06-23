# wat Browser Extension

Browser extension surface for looking up acronyms and team jargon from the current page.

## Install

The extension package is scaffolded in `extensions/browser`.

```sh
pnpm install
pnpm --filter @wat/ext dev
```

WXT opens a browser profile with the unpacked extension installed. Production builds write to `.output/`.

```sh
pnpm --filter @wat/ext build
pnpm --filter @wat/ext zip
```

The options page stores API base URL, account email/token, hover mode, auto-highlight mode, and domain filters in extension storage. When hover or auto-highlight mode is enabled, the content script asks the background worker for uppercase-token lookups and renders a sourced tooltip. The action button opens a Chrome side panel that searches through the same background lookup path using the active tab hostname as context.

## Target Permissions

- `activeTab`: read the current tab only after user interaction
- `storage`: cache options and recent lookups locally
- `contextMenus`: add selected-text lookup actions
- `scripting`: inject hover and highlight behavior when enabled

## Privacy Notes

Fresh installs should not send page content automatically. Lookups should happen after explicit user action or after enabling hover/highlight modes.

Hover and highlight lookups send only the acronym token, lookup limit, and a bounded context string to the background worker. API requests use `q`, `limit`, and optional `context` query parameters.

The hover/highlight context is limited to the current hostname, document title, and up to 12 heading texts, truncated to 1200 characters. It does not include paragraph text, form fields, inputs, or full-page body text.

Local cache data should stay in browser storage and be bounded by an LRU limit. Telemetry should be off by default.

Team entries require account sync. Authentication tokens should be stored through browser extension storage APIs and scoped to wat API calls only.
