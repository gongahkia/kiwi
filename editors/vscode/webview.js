const ANIMATIONS = new Set(["default", "none", "trace", "playback", "transitions"]);

function isMermaidDocument(document) {
  const fileName = document?.uri?.fsPath || document?.fileName || "";
  return document?.languageId === "mermaid" || hasMermaidExtension(fileName);
}

function hasMermaidExtension(fileName) {
  const lower = fileName.toLowerCase();
  return lower.endsWith(".mmd") || lower.endsWith(".mermaid");
}

function normalizeOptions(options = {}) {
  const animate = ANIMATIONS.has(options.animate) ? options.animate : "default";
  const speed = Number(options.speed);
  return {
    theme: options.theme || "default",
    darkTheme: options.darkTheme || "",
    animate: animate === "default" ? "" : animate,
    speed: Number.isFinite(speed) && speed > 0 ? speed : 1,
    controls: options.controls !== false,
    autoplay: options.autoplay === true,
  };
}

function buildWebviewHtml({ nonce, cspSource, assetUris, source, fileName, options }) {
  const payload = {
    source,
    fileName,
    options: normalizeOptions(options),
  };

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${cspSource} data:; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}' ${cspSource}; connect-src ${cspSource};">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <style nonce="${nonce}">
    :root {
      color-scheme: light dark;
      font-family: var(--vscode-font-family);
      background: var(--vscode-editor-background);
      color: var(--vscode-editor-foreground);
    }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      grid-template-rows: auto 1fr;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      padding: 0.5rem 0.75rem;
      border-bottom: 1px solid var(--vscode-panel-border);
      font-size: 12px;
    }
    main {
      overflow: auto;
      padding: 1rem;
    }
    kumeyuri-diagram {
      display: block;
      min-width: max-content;
    }
    [data-status="error"] {
      color: var(--vscode-errorForeground);
    }
  </style>
</head>
<body>
  <header>
    <strong id="file"></strong>
    <span id="status">loading</span>
  </header>
  <main>
    <kumeyuri-diagram></kumeyuri-diagram>
  </main>
  <script nonce="${nonce}" type="module">
    import initWasm, * as wasm from ${JSON.stringify(assetUris.wasmJs)};
    import { initKumeyuri, defineKumeyuriElement } from ${JSON.stringify(assetUris.player)};

    const payload = ${serializeForScript(payload)};
    const status = document.getElementById("status");
    const file = document.getElementById("file");
    const diagram = document.querySelector("kumeyuri-diagram");

    function setOptionalAttribute(name, value) {
      if (value === undefined || value === null || value === "" || value === false) {
        diagram.removeAttribute(name);
        return;
      }
      diagram.setAttribute(name, value === true ? "" : String(value));
    }

    function render(next) {
      file.textContent = next.fileName;
      setOptionalAttribute("theme", next.options.theme);
      setOptionalAttribute("dark-theme", next.options.darkTheme);
      setOptionalAttribute("animate", next.options.animate);
      setOptionalAttribute("speed", next.options.speed);
      setOptionalAttribute("controls", next.options.controls);
      setOptionalAttribute("autoplay", next.options.autoplay);
      diagram.setAttribute("inline", next.source);
      status.dataset.status = "ok";
      status.textContent = "rendered";
    }

    try {
      await initKumeyuri(wasm, ${JSON.stringify(assetUris.wasmBg)});
      defineKumeyuriElement();
      render(payload);
    } catch (error) {
      status.dataset.status = "error";
      status.textContent = error instanceof Error ? error.message : String(error);
    }
  </script>
</body>
</html>`;
}

function serializeForScript(value) {
  let output = "";
  for (const char of JSON.stringify(value)) {
    if (char === "<") {
      output += "\\u003c";
    } else if (char === ">") {
      output += "\\u003e";
    } else if (char === "&") {
      output += "\\u0026";
    } else if (char === "\u2028") {
      output += "\\u2028";
    } else if (char === "\u2029") {
      output += "\\u2029";
    } else {
      output += char;
    }
  }
  return output;
}

module.exports = {
  buildWebviewHtml,
  isMermaidDocument,
  normalizeOptions,
  serializeForScript,
};
