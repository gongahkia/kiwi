const rendererName = ":kumeyuri";

function main() {
  logseq.App.onMacroRendererSlotted(({ slot, payload }) => {
    const [type, src, ...flags] = payload.arguments ?? [];
    if (type !== rendererName) {
      return;
    }
    if (!src) {
      logseq.provideUI({
        key: `kumeyuri-${payload.uuid}`,
        slot,
        reset: true,
        template: renderError("missing kumecast URL"),
      });
      return;
    }
    logseq.provideUI({
      key: `kumeyuri-${payload.uuid}`,
      slot,
      reset: true,
      template: renderCastTemplate(src, parseFlags(flags)),
    });
  });

  logseq.provideModel({
    async insertKumeyuriRenderer() {
      await logseq.Editor.insertAtEditingCursor("{{renderer :kumeyuri, ./casts/diagram.kumecast}}");
    },
  });

  logseq.App.registerCommandPalette(
    {
      key: "kumeyuri-insert-renderer",
      label: "Insert kumeyuri renderer macro",
    },
    () => logseq.App.invokeExternalPlugin("kumeyuri.models.insertKumeyuriRenderer"),
  );

  logseq.App.registerUIItem("toolbar", {
    key: "kumeyuri-toolbar",
    template: '<a data-on-click="insertKumeyuriRenderer" title="Insert kumeyuri renderer">kumeyuri</a>',
  });
}

export function renderCastTemplate(src, options = {}) {
  const attributes = [
    ["class", "kumeyuri-logseq-cast"],
    ["data-kumeyuri-cast", src],
    options.autoplay ? ["data-autoplay", "true"] : null,
    options.controls === false ? ["data-controls", "false"] : ["data-controls", "true"],
    options.loop ? ["data-loop", "true"] : null,
  ].filter(Boolean);
  return `<div${attributes.map(([name, value]) => ` ${name}="${escapeAttribute(value)}"`).join("")}>${escapeHtml(src)}</div>`;
}

export function parseFlags(flags = []) {
  const normalized = new Set(flags.map((flag) => String(flag).trim().toLowerCase()));
  return {
    autoplay: normalized.has("autoplay"),
    controls: !normalized.has("no-controls"),
    loop: normalized.has("loop"),
  };
}

function renderError(message) {
  return `<pre class="kumeyuri-logseq-error">${escapeHtml(message)}</pre>`;
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll('"', "&quot;");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

if (globalThis.logseq) {
  logseq.ready(main).catch(console.error);
}
