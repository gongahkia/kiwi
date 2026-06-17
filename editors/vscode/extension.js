const path = require("path");
const vscode = require("vscode");
const {
  buildWebviewHtml,
  isMermaidDocument,
  normalizeOptions,
} = require("./webview");

function activate(context) {
  const manager = new PreviewManager(context);
  context.subscriptions.push(
    vscode.commands.registerCommand("kumeyuri.preview", (uri) => manager.open(uri)),
    vscode.workspace.onDidSaveTextDocument((document) => manager.refreshOnSave(document)),
  );
}

function deactivate() {}

class PreviewManager {
  constructor(context) {
    this.context = context;
    this.panel = undefined;
    this.documentKey = undefined;
  }

  async open(uri) {
    const document = await this.resolveDocument(uri);
    if (!document) {
      vscode.window.showWarningMessage("Open a Mermaid .mmd file before running Kumeyuri preview.");
      return;
    }
    if (!isMermaidDocument(document)) {
      vscode.window.showWarningMessage("Kumeyuri preview expects a .mmd or .mermaid document.");
      return;
    }
    this.render(document);
  }

  async resolveDocument(uri) {
    if (uri && uri.scheme) {
      return vscode.workspace.openTextDocument(uri);
    }
    return vscode.window.activeTextEditor?.document;
  }

  refreshOnSave(document) {
    const config = vscode.workspace.getConfiguration("kumeyuri.preview", document.uri);
    if (!config.get("autoRenderOnSave", true)) {
      return;
    }
    if (!this.panel || this.documentKey !== document.uri.toString()) {
      return;
    }
    if (isMermaidDocument(document)) {
      this.render(document);
    }
  }

  render(document) {
    const panel = this.ensurePanel(document);
    const options = readOptions(document);
    panel.title = `Kumeyuri: ${path.basename(document.uri.fsPath || document.fileName)}`;
    panel.webview.html = buildWebviewHtml({
      nonce: nonce(),
      cspSource: panel.webview.cspSource,
      assetUris: this.assetUris(panel.webview),
      source: document.getText(),
      fileName: vscode.workspace.asRelativePath(document.uri, false),
      options,
    });
    this.documentKey = document.uri.toString();
  }

  ensurePanel(document) {
    if (this.panel) {
      this.panel.reveal(vscode.ViewColumn.Beside);
      return this.panel;
    }
    const mediaRoot = vscode.Uri.joinPath(this.context.extensionUri, "media");
    this.panel = vscode.window.createWebviewPanel(
      "kumeyuriPreview",
      `Kumeyuri: ${path.basename(document.uri.fsPath || document.fileName)}`,
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [mediaRoot],
      },
    );
    this.panel.onDidDispose(() => {
      this.panel = undefined;
      this.documentKey = undefined;
    });
    return this.panel;
  }

  assetUris(webview) {
    const media = (...parts) => webview.asWebviewUri(vscode.Uri.joinPath(this.context.extensionUri, "media", ...parts)).toString();
    return {
      player: media("kumeyuri.js"),
      wasmJs: media("kumeyuri_render_wasm.js"),
      wasmBg: media("kumeyuri_render_wasm_bg.wasm"),
    };
  }
}

function readOptions(document) {
  const config = vscode.workspace.getConfiguration("kumeyuri.preview", document.uri);
  return normalizeOptions({
    theme: config.get("theme", "default"),
    darkTheme: config.get("darkTheme", ""),
    animate: config.get("animate", "default"),
    speed: config.get("speed", 1),
    controls: config.get("controls", true),
    autoplay: config.get("autoplay", false),
  });
}

function nonce() {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let value = "";
  for (let index = 0; index < 32; index += 1) {
    value += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return value;
}

module.exports = {
  activate,
  deactivate,
};
