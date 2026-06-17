import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const DEFAULT_OPTIONS = {
  format: "svg",
  kumeyuri: "kumeyuri",
  replace: false,
};

export default function rehypeKumeyuri(options = {}) {
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (!["svg", "text"].includes(config.format)) {
    throw new Error(`rehype-kumeyuri unsupported format: ${config.format}`);
  }

  return async function transformer(tree) {
    const jobs = [];
    visitParents(tree, (node, parent, index) => {
      if (!parent || typeof index !== "number" || !isMermaidPre(node)) {
        return;
      }
      const code = node.children?.[0];
      const source = textContent(code);
      if (source.trim().length === 0) {
        return;
      }
      jobs.push({ parent, index, source });
    });

    let offset = 0;
    for (const job of jobs) {
      const rendered = await renderWithKumeyuri(job.source, config);
      const renderedNode = renderedHast(rendered, config.format);
      const target = job.index + offset;
      if (config.replace) {
        job.parent.children.splice(target, 1, renderedNode);
      } else {
        job.parent.children.splice(target + 1, 0, renderedNode);
        offset += 1;
      }
    }
  };
}

function visitParents(node, visitor, parent, index) {
  visitor(node, parent, index);
  if (!Array.isArray(node.children)) {
    return;
  }
  for (let childIndex = 0; childIndex < node.children.length; childIndex += 1) {
    visitParents(node.children[childIndex], visitor, node, childIndex);
  }
}

function isMermaidPre(node) {
  if (node?.type !== "element" || node.tagName !== "pre") {
    return false;
  }
  const code = node.children?.[0];
  if (code?.type !== "element" || code.tagName !== "code") {
    return false;
  }
  return classNames(code).some((name) => name === "language-mermaid" || name === "language-mmd");
}

function classNames(node) {
  const value = node.properties?.className;
  if (Array.isArray(value)) {
    return value.map(String);
  }
  if (typeof value === "string") {
    return value.split(/\s+/).filter(Boolean);
  }
  return [];
}

function textContent(node) {
  if (!node) {
    return "";
  }
  if (node.type === "text") {
    return node.value || "";
  }
  if (!Array.isArray(node.children)) {
    return "";
  }
  return node.children.map(textContent).join("");
}

async function renderWithKumeyuri(source, config) {
  const dir = await mkdtemp(path.join(tmpdir(), "rehype-kumeyuri-"));
  try {
    const input = path.join(dir, "diagram.mmd");
    await writeFile(input, source, "utf8");
    const args = ["render", input, "--format", config.format];
    appendOption(args, "--theme", config.theme);
    appendOption(args, "--dark-theme", config.darkTheme);
    appendOption(args, "--charset", config.charset);
    appendOption(args, "--width", config.width);
    appendOption(args, "--padding", config.padding);
    appendOption(args, "--font", config.font);
    const { stdout } = await execFileAsync(config.kumeyuri, args, {
      encoding: "buffer",
      maxBuffer: config.maxBuffer || 10 * 1024 * 1024,
    });
    return stdout.toString("utf8").trimEnd();
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function appendOption(args, flag, value) {
  if (value !== undefined && value !== null && value !== "") {
    args.push(flag, String(value));
  }
}

function renderedHast(rendered, format) {
  if (format === "text") {
    return {
      type: "element",
      tagName: "pre",
      properties: { className: ["kumeyuri-render", "kumeyuri-render-text"] },
      children: [
        {
          type: "element",
          tagName: "code",
          properties: { className: ["language-text"] },
          children: [{ type: "text", value: rendered }],
        },
      ],
    };
  }

  return {
    type: "element",
    tagName: "div",
    properties: { className: ["kumeyuri-render", "kumeyuri-render-svg"] },
    children: [{ type: "raw", value: rendered }],
  };
}
