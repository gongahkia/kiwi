const DEFAULT_SCRIPT_URL = "https://cdn.kumeyuri.dev/player.js";
const DEFAULT_STAGE = "head-inline";
const STAGES = new Set(["head-inline", "before-hydration", "page"]);

const DEFAULT_OPTIONS = {
  inject: true,
  scriptUrl: DEFAULT_SCRIPT_URL,
  stage: DEFAULT_STAGE,
};

export default function kumeyuri(options = {}) {
  const config = normalizeOptions(options);
  return {
    name: "@kumeyuri/astro",
    hooks: {
      "astro:config:setup": ({ injectScript }) => {
        if (config.inject) {
          injectScript(config.stage, browserImport(config.scriptUrl));
        }
      },
    },
  };
}

export function normalizeOptions(options = {}) {
  if (!isPlainObject(options)) {
    throw new Error("@kumeyuri/astro options must be an object");
  }
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (typeof config.inject !== "boolean") {
    throw new Error("@kumeyuri/astro inject must be a boolean");
  }
  if (typeof config.scriptUrl !== "string" || config.scriptUrl.length === 0) {
    throw new Error("@kumeyuri/astro scriptUrl must be a non-empty string");
  }
  if (!STAGES.has(config.stage)) {
    throw new Error(`@kumeyuri/astro stage must be one of ${Array.from(STAGES).join(", ")}`);
  }
  return config;
}

export function browserImport(scriptUrl) {
  return `import(${JSON.stringify(scriptUrl)});`;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
