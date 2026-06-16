import createDOMPurify from "dompurify";
import { JSDOM } from "jsdom";

const input = await readStdin();
const fixtures = parseFixtures(input);
const window = new JSDOM("").window;
const purify = createDOMPurify(window);

const githubSvgAllowlist = {
  ALLOWED_TAGS: ["svg", "rect", "g", "text", "animate", "style"],
  ALLOWED_ATTR: [
    "xmlns",
    "width",
    "height",
    "viewBox",
    "viewbox",
    "role",
    "id",
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
  if (mode === "smil") {
    assertIncludes(mode, sanitized, /<animate\b/i, "SMIL animate element stripped");
    assertIncludes(
      mode,
      sanitized,
      /attributeName="opacity"|attributename="opacity"/i,
      "SMIL opacity attribute stripped"
    );
  } else if (mode === "css") {
    assertIncludes(mode, sanitized, /<style\b/i, "CSS style element stripped");
    assertIncludes(mode, sanitized, /@keyframes\s+kumeyuri-frame-0/i, "CSS keyframes stripped");
  } else {
    throw new Error(`unknown fixture mode: ${mode}`);
  }
}

function parseFixtures(source) {
  const marker = /^--kumeyuri-svg-mode:([a-z]+)--$/gm;
  const fixtures = new Map();
  const matches = [...source.matchAll(marker)];
  for (let index = 0; index < matches.length; index += 1) {
    const mode = matches[index][1];
    const start = matches[index].index + matches[index][0].length;
    const end = matches[index + 1]?.index ?? source.length;
    fixtures.set(mode, source.slice(start, end).trim());
  }
  for (const mode of ["smil", "css"]) {
    if (!fixtures.has(mode)) {
      throw new Error(`missing ${mode} SVG fixture`);
    }
  }
  return fixtures;
}

function assertClean(mode, sanitized) {
  assertIncludes(mode, sanitized, /<svg\b/i, "SVG root stripped");
  assertIncludes(mode, sanitized, /<g\b/i, "frame groups stripped");
  assertIncludes(mode, sanitized, /<text\b/i, "text output stripped");
}

function assertIncludes(mode, value, pattern, message) {
  if (!pattern.test(value)) {
    throw new Error(`${mode}: ${message}\nSanitized SVG:\n${value}`);
  }
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
