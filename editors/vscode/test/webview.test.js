const assert = require("node:assert/strict");
const {
  buildWebviewHtml,
  isMermaidDocument,
  normalizeOptions,
  serializeForScript,
} = require("../webview");

assert.equal(isMermaidDocument({ languageId: "mermaid", uri: { fsPath: "/tmp/file.txt" } }), true);
assert.equal(isMermaidDocument({ languageId: "plaintext", uri: { fsPath: "/tmp/file.mmd" } }), true);
assert.equal(isMermaidDocument({ languageId: "plaintext", uri: { fsPath: "/tmp/file.md" } }), false);

assert.deepEqual(normalizeOptions({
  theme: "github",
  darkTheme: "dracula",
  animate: "trace",
  speed: 1.5,
  controls: false,
  autoplay: true,
}), {
  theme: "github",
  darkTheme: "dracula",
  animate: "trace",
  speed: 1.5,
  controls: false,
  autoplay: true,
});

assert.equal(serializeForScript({ source: "</script><img>" }).includes("</script>"), false);

const html = buildWebviewHtml({
  nonce: "abc123",
  cspSource: "vscode-resource:",
  assetUris: {
    player: "vscode-resource:/kumeyuri.js",
    wasmJs: "vscode-resource:/kumeyuri_render_wasm.js",
    wasmBg: "vscode-resource:/kumeyuri_render_wasm_bg.wasm",
  },
  source: "graph TD\nA --> B\n</script>",
  fileName: "flow.mmd",
  options: {
    animate: "default",
    controls: true,
  },
});

assert.match(html, /<kumeyuri-diagram><\/kumeyuri-diagram>/);
assert.match(html, /Content-Security-Policy/);
assert.match(html, /initKumeyuri/);
assert.equal(html.includes("graph TD\\nA --> B\\n</script>"), false);

console.log("ok");
