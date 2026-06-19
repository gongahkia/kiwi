const DEFAULT_OPTIONS = {
  className: "kumeyuri-marp-cast",
  autoplay: false,
  controls: true,
  loop: false,
};

export default function marpEngine({ marp }, options = {}) {
  return marp.use(marpKumeyuriPlugin, options);
}

export function marpKumeyuriPlugin(md, options = {}) {
  const config = normalizeOptions(options);
  md.core.ruler.after("block", "kumeyuri_cast_fences", (state) => {
    for (const token of state.tokens) {
      if (token.type !== "fence") {
        continue;
      }
      const [lang, ...rest] = String(token.info ?? "").trim().split(/\s+/u);
      if (lang !== "kumecast") {
        continue;
      }
      const src = rest.join(" ") || token.content.trim();
      token.type = "html_block";
      token.tag = "";
      token.nesting = 0;
      token.children = null;
      token.attrs = null;
      token.content = renderCastHtml(src, config);
    }
  });
  return md;
}

export function normalizeOptions(options = {}) {
  if (!isPlainObject(options)) {
    throw new Error("@kumeyuri/marp-plugin options must be an object");
  }
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (typeof config.className !== "string" || config.className.length === 0) {
    throw new Error("@kumeyuri/marp-plugin className must be a non-empty string");
  }
  if (typeof config.autoplay !== "boolean") {
    throw new Error("@kumeyuri/marp-plugin autoplay must be a boolean");
  }
  if (typeof config.controls !== "boolean") {
    throw new Error("@kumeyuri/marp-plugin controls must be a boolean");
  }
  if (typeof config.loop !== "boolean") {
    throw new Error("@kumeyuri/marp-plugin loop must be a boolean");
  }
  if (config.scriptUrl !== undefined && (typeof config.scriptUrl !== "string" || config.scriptUrl.length === 0)) {
    throw new Error("@kumeyuri/marp-plugin scriptUrl must be a non-empty string");
  }
  return config;
}

export function renderCastHtml(src, options = {}) {
  const config = normalizeOptions(options);
  const attrs = [
    ["class", config.className],
    ["data-kumeyuri-cast", src],
    config.autoplay ? ["data-autoplay", ""] : null,
    config.controls ? ["data-controls", ""] : null,
    config.loop ? ["data-loop", ""] : null,
  ].filter(Boolean);
  const element = `<div${attrs.map(([name, value]) => attribute(name, value)).join("")}></div>`;
  if (!config.scriptUrl) {
    return element;
  }
  return `${element}\n<script type="module" src="${escapeAttribute(config.scriptUrl)}"></script>`;
}

function attribute(name, value) {
  if (value === "") {
    return ` ${name}`;
  }
  return ` ${name}="${escapeAttribute(value)}"`;
}

function escapeAttribute(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
