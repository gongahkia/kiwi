# Zola kumeyuri shortcode

Zola shortcode for `.kumecast` embeds.

Install:

```bash
cp integrations/zola/templates/shortcodes/kumeyuri.html templates/shortcodes/kumeyuri.html
cp integrations/zola/static/kumeyuri-player.js static/kumeyuri-player.js
cp integrations/zola/static/kumeyuri.css static/kumeyuri.css
```

Add assets to your base template:

```html
<link rel="stylesheet" href="/kumeyuri.css">
<script type="module" src="/kumeyuri-player.js"></script>
```

Use the shortcode:

```md
{{ kumeyuri(src="/casts/oauth-login.kumecast") }}
{{ kumeyuri(src="/casts/oauth-login.kumecast", autoplay=true, loop=true) }}
{{ kumeyuri(src="/casts/oauth-login.kumecast", controls=false, class="diagram") }}
```

Arguments:

| Argument | Required | Default | Purpose |
| --- | --- | --- | --- |
| `src` | Yes | none | `.kumecast` JSON URL |
| `class` | No | `kumeyuri-zola-cast` | Wrapper class |
| `autoplay` | No | `false` | Start playback after loading |
| `controls` | No | `true` | Show play/restart/scrub controls |
| `loop` | No | `false` | Loop playback |
| `script` | No | empty | Optional per-embed module script URL |
