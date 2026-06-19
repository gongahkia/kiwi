# Obsidian kumeyuri plugin

Community-plugin scaffold that replaces Obsidian's built-in Mermaid preview for
fenced `mermaid` blocks by rendering them through the local `kumeyuri` CLI.

Supported fences:

````md
```mermaid
graph TD
  A --> B
```

```kumeyuri
sequenceDiagram
  Alice->>Bob: hello
```
````

Install for local testing:

```bash
mkdir -p /path/to/vault/.obsidian/plugins/kumeyuri
cp editors/obsidian/{manifest.json,main.js,styles.css} /path/to/vault/.obsidian/plugins/kumeyuri/
```

The plugin is desktop-only because it shells out to `kumeyuri render`. Configure
the executable path, theme, and width in plugin settings.
