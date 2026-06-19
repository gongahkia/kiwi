# Logseq kumeyuri plugin

Logseq plugin that renders `.kumecast` timelines through renderer macros.

Use this in a block:

```text
{{renderer :kumeyuri, ./casts/oauth-login.kumecast}}
```

Optional flags:

```text
{{renderer :kumeyuri, ./casts/oauth-login.kumecast, autoplay, loop}}
{{renderer :kumeyuri, ./casts/oauth-login.kumecast, no-controls}}
```

The plugin uses Logseq's `onMacroRendererSlotted` hook and injects a placeholder
with `data-kumeyuri-cast`. `player.js` loads the cast JSON and renders frames
inside the block.

Local install:

```bash
cp -R editors/logseq /path/to/logseq/plugins/kumeyuri
```
