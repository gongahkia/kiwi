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

The options page stores API base URL, account email/token, hover mode, auto-highlight mode, acronym density heatmap mode, and domain filters in extension storage. When hover or auto-highlight mode is enabled, the content script asks the background worker for uppercase-token lookups and renders a sourced tooltip. When heatmap mode is enabled, the content script adds a visual acronym-density indicator to acronym-heavy paragraphs without sending paragraph text to the API. The action button opens a Chrome side panel that searches through the same background lookup path using the active tab hostname as context.

## Enterprise Deployment

Managed Chrome and Edge deployments can preconfigure shared extension settings through read-only managed storage. The extension declares `managed-schema.json` through `storage.managed_schema` and reads these policy keys over local user settings:

- `apiBaseUrl`
- `teamId`
- `teams`
- `domainFilters`
- `hoverMode`
- `highlightMode`
- `heatmapMode`

Use the browser extension ID assigned by Chrome Web Store, Edge Add-ons, or the self-hosted CRX. Force-install examples:

```json
{
  "<extension-id>": {
    "installation_mode": "force_installed",
    "update_url": "https://clients2.google.com/service/update2/crx"
  }
}
```

```json
{
  "<extension-id>": {
    "installation_mode": "force_installed",
    "update_url": "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
  }
}
```

Managed settings example:

```json
{
  "3rdparty": {
    "extensions": {
      "<extension-id>": {
        "apiBaseUrl": "https://wat.example.com",
        "teamId": "team_123",
        "teams": [{ "id": "team_123", "name": "Platform" }],
        "domainFilters": ["example.com"],
        "hoverMode": true,
        "highlightMode": false,
        "heatmapMode": false
      }
    }
  }
}
```

Verify policy load in `chrome://policy` or `edge://policy`, then inspect `chrome.storage.managed.get(null)` from the extension service worker. Reference docs: Chrome managed storage manifest (`https://developer.chrome.com/docs/extensions/reference/manifest/storage`), Chrome `ExtensionSettings` (`https://support.google.com/chrome/a/answer/9867568`), and Edge `ExtensionSettings` (`https://learn.microsoft.com/en-us/deployedge/microsoft-edge-manage-extensions-ref-guide`).

## Target Permissions

- `activeTab`: read the current tab only after user interaction
- `storage`: cache options and recent lookups locally
- `contextMenus`: add selected-text lookup actions
- `scripting`: inject hover and highlight behavior when enabled

## Privacy Notes

Fresh installs should not send page content automatically. Lookups should happen after explicit user action or after enabling hover/highlight modes.

Hover and highlight lookups send only the acronym token, lookup limit, and a bounded context string to the background worker. API requests use `q`, `limit`, and optional `context` query parameters.

The hover/highlight context is limited to the current hostname, document title, and up to 12 heading texts, truncated to 1200 characters. It does not include paragraph text, form fields, inputs, or full-page body text.

Custom-entry saves send the selected term, expansion, meaning, scope, domains, source URL, and source title only after user confirmation.

Heatmap mode runs locally and uses only paragraph text already present in the page DOM. It does not call the wat API.

The extension stores `apiBaseUrl`, `accountEmail`, `apiToken`, `teamId`, known `teams`, domain filters, hover/highlight/heatmap settings, and recent lookup cache in browser storage. Local cache data should be bounded by an LRU limit. Telemetry should be off by default.

Team entries require account sync. Authentication tokens should be stored through browser extension storage APIs and scoped to wat API calls only.
