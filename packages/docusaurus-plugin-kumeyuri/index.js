const DEFAULT_SCRIPT_URL = "https://cdn.kumeyuri.dev/player.js";

const DEFAULT_OPTIONS = {
  inject: true,
  preload: false,
  scriptUrl: DEFAULT_SCRIPT_URL,
};

export default function docusaurusKumeyuriPlugin(_context, options = {}) {
  const config = normalizeOptions(options);
  return {
    name: "@docusaurus/plugin-kumeyuri",
    injectHtmlTags() {
      if (!config.inject) {
        return {};
      }
      const script = {
        tagName: "script",
        attributes: scriptAttributes(config),
      };
      const tags = { postBodyTags: [script] };
      if (config.preload) {
        tags.headTags = [
          {
            tagName: "link",
            attributes: preloadAttributes(config),
          },
        ];
      }
      return tags;
    },
  };
}

export function validateOptions({ options }) {
  return normalizeOptions(options);
}

export function normalizeOptions(options = {}) {
  if (!isPlainObject(options)) {
    throw new Error("@docusaurus/plugin-kumeyuri options must be an object");
  }
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (typeof config.inject !== "boolean") {
    throw new Error("@docusaurus/plugin-kumeyuri inject must be a boolean");
  }
  if (typeof config.preload !== "boolean") {
    throw new Error("@docusaurus/plugin-kumeyuri preload must be a boolean");
  }
  if (typeof config.scriptUrl !== "string" || config.scriptUrl.length === 0) {
    throw new Error("@docusaurus/plugin-kumeyuri scriptUrl must be a non-empty string");
  }
  if (config.integrity !== undefined && typeof config.integrity !== "string") {
    throw new Error("@docusaurus/plugin-kumeyuri integrity must be a string");
  }
  if (
    config.crossorigin !== undefined &&
    typeof config.crossorigin !== "string" &&
    typeof config.crossorigin !== "boolean"
  ) {
    throw new Error("@docusaurus/plugin-kumeyuri crossorigin must be a string or boolean");
  }
  return config;
}

function scriptAttributes(config) {
  return withOptionalAttributes(
    {
      type: "module",
      src: config.scriptUrl,
    },
    config,
  );
}

function preloadAttributes(config) {
  return withOptionalAttributes(
    {
      rel: "modulepreload",
      href: config.scriptUrl,
    },
    config,
  );
}

function withOptionalAttributes(attributes, config) {
  if (config.integrity) {
    attributes.integrity = config.integrity;
  }
  if (config.crossorigin !== undefined) {
    attributes.crossorigin = config.crossorigin;
  }
  return attributes;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
