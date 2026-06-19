const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

let Plugin;
let PluginSettingTab;
let Setting;
let Notice;
try {
  ({ Plugin, PluginSettingTab, Setting, Notice } = require("obsidian"));
} catch {
  Plugin = class {};
  PluginSettingTab = class {};
  Setting = class {};
  Notice = class {};
}

const execFileAsync = promisify(execFile);

const DEFAULT_SETTINGS = {
  cliPath: "kumeyuri",
  theme: "github",
  width: 96,
  timeoutMs: 10000,
};

class KumeyuriPlugin extends Plugin {
  async onload() {
    this.settings = { ...DEFAULT_SETTINGS, ...(await this.loadData()) };
    this.registerMarkdownCodeBlockProcessor("mermaid", (source, el) => this.renderBlock(source, el));
    this.registerMarkdownCodeBlockProcessor("kumeyuri", (source, el) => this.renderBlock(source, el));
    this.addSettingTab(new KumeyuriSettingTab(this.app, this));
  }

  async saveSettings() {
    await this.saveData(this.settings);
  }

  async renderBlock(source, el) {
    el.empty?.();
    el.addClass?.("kumeyuri-obsidian");
    const pre = el.createEl ? el.createEl("pre", { cls: "kumeyuri-obsidian-frame" }) : createPre(el);
    pre.textContent = "Rendering with kumeyuri...";
    try {
      pre.textContent = await renderMermaidWithCli(source, this.settings);
    } catch (error) {
      pre.addClass?.("kumeyuri-obsidian-error");
      pre.textContent = error instanceof Error ? error.message : String(error);
      new Notice(`kumeyuri render failed: ${pre.textContent}`);
    }
  }
}

class KumeyuriSettingTab extends PluginSettingTab {
  constructor(app, plugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display() {
    const { containerEl } = this;
    containerEl.empty();
    containerEl.createEl("h2", { text: "kumeyuri" });
    new Setting(containerEl)
      .setName("CLI path")
      .setDesc("Path to the kumeyuri executable.")
      .addText((text) =>
        text
          .setPlaceholder("kumeyuri")
          .setValue(this.plugin.settings.cliPath)
          .onChange(async (value) => {
            this.plugin.settings.cliPath = value.trim() || DEFAULT_SETTINGS.cliPath;
            await this.plugin.saveSettings();
          }),
      );
    new Setting(containerEl)
      .setName("Theme")
      .setDesc("kumeyuri theme passed to text rendering.")
      .addText((text) =>
        text
          .setPlaceholder("github")
          .setValue(this.plugin.settings.theme)
          .onChange(async (value) => {
            this.plugin.settings.theme = value.trim() || DEFAULT_SETTINGS.theme;
            await this.plugin.saveSettings();
          }),
      );
    new Setting(containerEl)
      .setName("Width")
      .setDesc("Text render width in cells.")
      .addText((text) =>
        text
          .setPlaceholder("96")
          .setValue(String(this.plugin.settings.width))
          .onChange(async (value) => {
            const width = Number(value);
            this.plugin.settings.width = Number.isInteger(width) && width > 0 ? width : DEFAULT_SETTINGS.width;
            await this.plugin.saveSettings();
          }),
      );
  }
}

async function renderMermaidWithCli(source, settings = DEFAULT_SETTINGS) {
  const config = { ...DEFAULT_SETTINGS, ...settings };
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "kumeyuri-obsidian-"));
  const input = path.join(tempDir, "diagram.mmd");
  try {
    await fs.writeFile(input, source, "utf8");
    const { stdout } = await execFileAsync(
      config.cliPath,
      ["render", input, "--format", "text", "--theme", config.theme, "--width", String(config.width)],
      { timeout: config.timeoutMs, maxBuffer: 1024 * 1024 },
    );
    return stdout.trimEnd();
  } finally {
    await fs.rm(tempDir, { force: true, recursive: true });
  }
}

function createPre(el) {
  const pre = el.ownerDocument.createElement("pre");
  el.appendChild(pre);
  return pre;
}

module.exports = KumeyuriPlugin;
module.exports.DEFAULT_SETTINGS = DEFAULT_SETTINGS;
module.exports.renderMermaidWithCli = renderMermaidWithCli;
