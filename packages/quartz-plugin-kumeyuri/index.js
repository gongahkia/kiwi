const DEFAULT_OPTIONS = {
  className: "kumeyuri-quartz-cast",
  autoplay: false,
  controls: true,
  loop: false,
  scriptUrl: "https://cdn.kumeyuri.dev/player.js",
  cssUrl: "",
};

export default function Kumeyuri(options = {}) {
  const config = normalizeOptions(options);
  return {
    name: "Kumeyuri",
    markdownPlugins() {
      return [remarkKumeyuri(config)];
    },
    externalResources() {
      return {
        js: config.scriptUrl
          ? [{ src: config.scriptUrl, loadTime: "afterDOMReady", contentType: "external" }]
          : [],
        css: config.cssUrl ? [config.cssUrl] : [],
      };
    },
  };
}

export function remarkKumeyuri(options = {}) {
  const config = normalizeOptions(options);
  return (tree) => visit(tree, (node) => {
    if (node.type !== "code" || node.lang !== "kumecast") {
      return;
    }
    const src = String(node.meta || node.value || "").trim();
    node.type = "html";
    node.value = src ? renderCastHtml(src, config) : renderError("missing kumecast URL");
    delete node.lang;
    delete node.meta;
  });
}

export function normalizeOptions(options = {}) {
  if (!isPlainObject(options)) {
    throw new Error("quartz-plugin-kumeyuri options must be an object");
  }
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (typeof config.className !== "string" || config.className.length === 0) {
    throw new Error("quartz-plugin-kumeyuri className must be a non-empty string");
  }
  for (const key of ["autoplay", "controls", "loop"]) {
    if (typeof config[key] !== "boolean") {
      throw new Error(`quartz-plugin-kumeyuri ${key} must be a boolean`);
    }
  }
  for (const key of ["scriptUrl", "cssUrl"]) {
    if (typeof config[key] !== "string") {
      throw new Error(`quartz-plugin-kumeyuri ${key} must be a string`);
    }
  }
  return config;
}

export function renderCastHtml(src, options = {}) {
  const config = normalizeOptions(options);
  const attrs = [
    ["class", config.className],
    ["data-kumeyuri-cast", src],
    config.autoplay ? ["data-autoplay", "true"] : null,
    ["data-controls", config.controls ? "true" : "false"],
    config.loop ? ["data-loop", "true"] : null,
  ].filter(Boolean);
  return `<div${attrs.map(([name, value]) => ` ${name}="${escapeAttribute(value)}"`).join("")}></div>`;
}

function renderError(message) {
  return `<pre class="kumeyuri-quartz-error">${escapeHtml(message)}</pre>`;
}

function visit(node, callback) {
  if (!node || typeof node !== "object") {
    return;
  }
  callback(node);
  if (!Array.isArray(node.children)) {
    return;
  }
  for (const child of node.children) {
    visit(child, callback);
  }
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

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
