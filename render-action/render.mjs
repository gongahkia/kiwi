import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";

const workspace = resolve(process.env.GITHUB_WORKSPACE || process.cwd());
const sourcePatterns = splitList(input("SOURCE", "**/*.mmd"));
const outputDir = resolve(workspace, input("OUTPUT_DIR", "kumeyuri-output"));
const formats = splitList(input("FORMATS", "svg,gif")).map((format) => format.toLowerCase());
const kumeyuriCommand = input("KUMEYURI_COMMAND", "kumeyuri");
const failOnEmpty = input("FAIL_ON_EMPTY", "true") === "true";

const files = findSourceFiles(sourcePatterns);
if (!files.length) {
  const message = `No .mmd files matched: ${sourcePatterns.join(", ")}`;
  if (failOnEmpty) {
    throw new Error(message);
  }
  console.log(message);
  writeOutputs(0, 0);
  process.exit(0);
}

let renderedCount = 0;
for (const file of files) {
  const relativeFile = relative(workspace, file);
  for (const format of formats) {
    const outputFile = join(outputDir, replaceExtension(relativeFile, `.${format}`));
    mkdirSync(dirname(outputFile), { recursive: true });
    const result = runKumeyuri(file, format);
    if (result.status !== 0) {
      throw new Error(
        `kumeyuri failed for ${relativeFile} (${format})\n${result.stderr || result.stdout}`,
      );
    }
    writeFileSync(outputFile, result.stdout);
    renderedCount += 1;
    console.log(`${relativeFile} -> ${relative(workspace, outputFile)}`);
  }
}

writeOutputs(files.length, renderedCount);

function runKumeyuri(file, format) {
  const args = ["render", file, "--format", format];
  addOption(args, "--theme", input("THEME", "github"));
  addOption(args, "--charset", input("CHARSET", ""));
  addOption(args, "--width", input("WIDTH", ""));
  addOption(args, "--padding", input("PADDING", "12"));
  addOption(args, "--font", input("FONT", ""));
  if (format === "svg") {
    addOption(args, "--dark-theme", input("DARK_THEME", ""));
  }
  return spawnSync(`${kumeyuriCommand} ${args.map(shellQuote).join(" ")}`, {
    cwd: workspace,
    encoding: format === "svg" || format === "text" ? "utf8" : "buffer",
    shell: true,
    maxBuffer: 64 * 1024 * 1024,
  });
}

function findSourceFiles(patterns) {
  const allFiles = walk(workspace)
    .filter((file) => extname(file) === ".mmd")
    .sort((left, right) => left.localeCompare(right));
  const regexes = patterns.map(globToRegExp);
  return allFiles.filter((file) => {
    const rel = relative(workspace, file).replaceAll("\\", "/");
    return regexes.some((regex) => regex.test(rel));
  });
}

function walk(root) {
  if (!existsSync(root)) {
    return [];
  }
  const entries = readdirSync(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    if (entry.name === ".git" || entry.name === "node_modules" || entry.name === "target") {
      continue;
    }
    const path = join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(path));
    } else if (entry.isFile()) {
      files.push(path);
    }
  }
  return files;
}

function globToRegExp(pattern) {
  const normalized = pattern.replaceAll("\\", "/").replace(/^\.\//, "");
  let regex = "^";
  for (let index = 0; index < normalized.length; index += 1) {
    const char = normalized[index];
    const next = normalized[index + 1];
    const afterNext = normalized[index + 2];
    if (char === "*" && next === "*" && afterNext === "/") {
      regex += "(?:.*/)?";
      index += 2;
    } else if (char === "*" && next === "*") {
      regex += ".*";
      index += 1;
    } else if (char === "*") {
      regex += "[^/]*";
    } else if (char === "?") {
      regex += "[^/]";
    } else {
      regex += escapeRegex(char);
    }
  }
  regex += "$";
  return new RegExp(regex);
}

function splitList(value) {
  return value
    .split(/[\s,]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function replaceExtension(file, extension) {
  const current = extname(file);
  return current ? file.slice(0, -current.length) + extension : file + extension;
}

function addOption(args, name, value) {
  if (value) {
    args.push(name, value);
  }
}

function input(name, fallback) {
  const value = process.env[`INPUT_${name}`];
  return value === undefined || value === "" ? fallback : value;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function escapeRegex(value) {
  return value.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
}

function writeOutputs(fileCount, renderedCount) {
  const output = process.env.GITHUB_OUTPUT;
  const lines = [
    `file-count=${fileCount}`,
    `rendered-count=${renderedCount}`,
    `output-dir=${outputDir}`,
  ];
  if (output) {
    writeFileSync(output, `${lines.join("\n")}\n`, { flag: "a" });
  }
}
