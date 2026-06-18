import createDOMPurify from "dompurify";
import { JSDOM } from "jsdom";

const input = await readStdin();
const fixtures = parseFixtures(input);
const window = new JSDOM("").window;
const purify = createDOMPurify(window);

const githubSvgAllowlist = {
  ALLOWED_TAGS: ["svg", "title", "desc", "metadata", "rect", "g", "text", "animate", "style"],
  ALLOWED_ATTR: [
    "xmlns",
    "width",
    "height",
    "viewBox",
    "viewbox",
    "role",
    "aria-labelledby",
    "id",
    "data-format",
    "opacity",
    "x",
    "y",
    "xml:space",
    "font-family",
    "font-size",
    "fill",
    "attributeName",
    "attributename",
    "values",
    "keyTimes",
    "keytimes",
    "dur",
    "repeatCount",
    "repeatcount",
    "calcMode",
    "calcmode"
  ],
  KEEP_CONTENT: true
};

for (const [mode, svg] of fixtures) {
  const sanitized = purify.sanitize(svg, githubSvgAllowlist);
  assertClean(mode, sanitized);
  const folded = collapseWhitespace(sanitized.toLowerCase());
  if (mode === "smil") {
    assertIncludes(mode, folded, "<animate", "SMIL animate element stripped");
    assertIncludes(mode, folded, 'attributename="opacity"', "SMIL opacity attribute stripped");
  } else if (mode === "css") {
    assertIncludes(mode, folded, "<style", "CSS style element stripped");
    assertIncludes(mode, folded, "@keyframes kumeyuri-frame-0", "CSS keyframes stripped");
  } else {
    throw new Error(`unknown fixture mode: ${mode}`);
  }
}

function parseFixtures(source) {
  const fixtures = new Map();
  let mode = undefined;
  let buffer = [];
  for (const line of source.split("\n")) {
    const nextMode = parseFixtureMarker(line);
    if (nextMode) {
      if (mode) {
        fixtures.set(mode, buffer.join("\n").trim());
      }
      mode = nextMode;
      buffer = [];
    } else if (mode) {
      buffer.push(line);
    }
  }
  if (mode) {
    fixtures.set(mode, buffer.join("\n").trim());
  }
  for (const mode of ["smil", "css"]) {
    if (!fixtures.has(mode)) {
      throw new Error(`missing ${mode} SVG fixture`);
    }
  }
  return fixtures;
}

function assertClean(mode, sanitized) {
  const folded = sanitized.toLowerCase();
  assertIncludes(mode, folded, "<svg", "SVG root stripped");
  assertIncludes(mode, folded, "<title", "title stripped");
  assertIncludes(mode, folded, "<desc", "description stripped");
  assertIncludes(mode, folded, "<metadata", "text fallback stripped");
  assertIncludes(mode, folded, "<g", "frame groups stripped");
  assertIncludes(mode, folded, "<text", "text output stripped");
  assertIncludes(mode, folded, "prefers-color-scheme", "colour-scheme CSS stripped");
}

function assertIncludes(mode, value, needle, message) {
  if (!value.includes(needle)) {
    throw new Error(`${mode}: ${message}\nSanitized SVG:\n${value}`);
  }
}

function parseFixtureMarker(line) {
  const prefix = "--kumeyuri-svg-mode:";
  const suffix = "--";
  if (!line.startsWith(prefix) || !line.endsWith(suffix)) {
    return undefined;
  }
  const mode = line.slice(prefix.length, -suffix.length);
  return mode && Array.from(mode).every((char) => char >= "a" && char <= "z") ? mode : undefined;
}

function collapseWhitespace(value) {
  let output = "";
  let pendingSpace = false;
  for (const char of value) {
    if (char.trim() === "") {
      pendingSpace = output.length > 0;
    } else {
      if (pendingSpace) {
        output += " ";
        pendingSpace = false;
      }
      output += char;
    }
  }
  return output;
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}
