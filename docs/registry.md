# Fried Apple Pie Share Registry

`/pie share` is offline-first. It writes a bundle under `assets/share/<timestamp>/`:

- `pie-ui.json` — effective config only.
- `payload.json` — registry payload.
- `screenshot.<ext>` — copied preview asset when one exists.

Payload schema:

```json
{
  "version": 1,
  "package": "fried-apple-pie",
  "createdAt": "2026-06-24T01:02:03.000Z",
  "preset": "codex-inspired",
  "theme": "fried-apple-pie-codex",
  "screenshotPath": "screenshot.gif",
  "config": {}
}
```

Future hosted registry:

- `POST /api/share` accepts the payload plus files as multipart form data.
- Response: `{ "slug": "author/name", "url": "https://fried-apple-pie.dev/s/author/name" }`.
- `fap:<slug>` install resolution is future Pi/package-manager work; current bundles print a `gh gist create ...` fallback.
