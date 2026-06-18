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
  const globs = patterns.map(normalizeGlob);
  return allFiles.filter((file) => {
    const rel = relative(workspace, file).replaceAll("\\", "/");
    return globs.some((glob) => matchesGlob(glob, rel));
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

function normalizeGlob(pattern) {
  let normalized = pattern.replaceAll("\\", "/");
  while (normalized.startsWith("./")) {
    normalized = normalized.slice(2);
  }
  return normalized.split("/").filter(Boolean);
}

function matchesGlob(glob, file) {
  const parts = file.split("/").filter(Boolean);
  const memo = new Map();
  return matchesGlobParts(glob, parts, 0, 0, memo);
}

function matchesGlobParts(glob, parts, globIndex, partIndex, memo) {
  const key = `${globIndex}:${partIndex}`;
  if (memo.has(key)) {
    return memo.get(key);
  }
  let matched;
  if (globIndex === glob.length) {
    matched = partIndex === parts.length;
  } else if (glob[globIndex] === "**") {
    matched = false;
    for (let next = partIndex; next <= parts.length; next += 1) {
      if (matchesGlobParts(glob, parts, globIndex + 1, next, memo)) {
        matched = true;
        break;
      }
    }
  } else {
    matched =
      partIndex < parts.length &&
      matchesGlobSegment(glob[globIndex], parts[partIndex]) &&
      matchesGlobParts(glob, parts, globIndex + 1, partIndex + 1, memo);
  }
  memo.set(key, matched);
  return matched;
}

function matchesGlobSegment(pattern, value) {
  const patternChars = Array.from(pattern);
  const valueChars = Array.from(value);
  let previous = Array(valueChars.length + 1).fill(false);
  previous[0] = true;
  for (const char of patternChars) {
    const current = Array(valueChars.length + 1).fill(false);
    for (let index = 0; index <= valueChars.length; index += 1) {
      if (char === "*") {
        current[index] = previous[index] || (index > 0 && current[index - 1]);
      } else if (char === "?") {
        current[index] = index > 0 && previous[index - 1];
      } else {
        current[index] = index > 0 && previous[index - 1] && valueChars[index - 1] === char;
      }
    }
    previous = current;
  }
  return previous[valueChars.length];
}

function splitList(value) {
  const items = [];
  let item = "";
  for (const char of value) {
    if (char === "," || char.trim() === "") {
      if (item) {
        items.push(item);
        item = "";
      }
    } else {
      item += char;
    }
  }
  if (item) {
    items.push(item);
  }
  return items;
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
