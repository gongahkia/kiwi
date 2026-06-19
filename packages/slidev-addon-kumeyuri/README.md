# slidev-addon-kumeyuri

Slidev addon exposing `<KumeyuriDiagram>` for `.kumecast` timelines.

Install the addon in a Slidev deck:

```yaml
---
addons:
  - slidev-addon-kumeyuri
---
```

Use the component in `slides.md`:

```md
<KumeyuriDiagram src="/casts/oauth-login.kumecast" caption="OAuth login" autoplay controls />
```

Props:

| Prop | Required | Default | Purpose |
| --- | --- | --- | --- |
| `src` | Yes | none | `.kumecast` JSON URL |
| `caption` | No | empty | Optional caption |
| `autoplay` | No | `false` | Start playback after loading |
| `controls` | No | `true` | Show play/restart/scrub controls |
| `loop` | No | `false` | Loop playback even when cast metadata does not repeat |
