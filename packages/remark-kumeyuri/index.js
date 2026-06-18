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

export default function remarkKumeyuri(options = {}) {
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (!["svg", "text"].includes(config.format)) {
    throw new Error(`remark-kumeyuri unsupported format: ${config.format}`);
  }

  return async function transformer(tree) {
    const jobs = [];
    visitParents(tree, (node, parent, index) => {
      if (!parent || typeof index !== "number" || !isMermaidCode(node)) {
        return;
      }
      const source = node.value || "";
      if (source.trim().length === 0) {
        return;
      }
      jobs.push({ parent, index, source });
    });

    const offsets = new WeakMap();
    for (const job of jobs) {
      const rendered = await renderWithKumeyuri(job.source, config);
      const renderedNode = renderedMdast(rendered, config.format);
      const offset = offsets.get(job.parent) || 0;
      const target = job.index + offset;
      if (config.replace) {
        job.parent.children.splice(target, 1, renderedNode);
      } else {
        job.parent.children.splice(target + 1, 0, renderedNode);
        offsets.set(job.parent, offset + 1);
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

function isMermaidCode(node) {
  if (node?.type !== "code") {
    return false;
  }
  return node.lang === "mermaid" || node.lang === "mmd";
}

async function renderWithKumeyuri(source, config) {
  const dir = await mkdtemp(path.join(tmpdir(), "remark-kumeyuri-"));
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

function renderedMdast(rendered, format) {
  if (format === "text") {
    return {
      type: "code",
      lang: "text",
      meta: null,
      value: rendered,
    };
  }

  return {
    type: "html",
    value: `<div class="kumeyuri-render kumeyuri-render-svg">\n${rendered}\n</div>`,
  };
}
