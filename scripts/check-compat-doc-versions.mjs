import { readFile } from "node:fs/promises";

const coverage = await readFile(new URL("../COVERAGE.md", import.meta.url), "utf8");
const compat = await readFile(new URL("../docs/compat.md", import.meta.url), "utf8");

const coverageVersion = extractCoverageVersion(coverage);
const compatVersion = extractCompatVersion(compat);

if (!coverageVersion || !compatVersion) {
  console.error(
    `Could not read Mermaid versions: COVERAGE.md=${coverageVersion ?? "<missing>"} docs/compat.md=${compatVersion ?? "<missing>"}`,
  );
  process.exit(1);
}

if (coverageVersion !== compatVersion) {
  console.error(
    `Mermaid compatibility docs version mismatch: COVERAGE.md=${coverageVersion} docs/compat.md=${compatVersion}`,
  );
  process.exit(1);
}

console.log(`Mermaid compatibility docs versions match (${coverageVersion}).`);

function extractCoverageVersion(markdown) {
  const marker = "official Mermaid docs sidebar for Mermaid ";
  const flattened = collapseWhitespace(markdown);
  const start = flattened.indexOf(marker);
  return start === -1 ? undefined : readDottedVersion(flattened, start + marker.length);
}

function extractCompatVersion(markdown) {
  const marker = "Upstream reference: Mermaid docs `";
  const start = markdown.indexOf(marker);
  if (start === -1) {
    return undefined;
  }
  const versionStart = start + marker.length;
  const versionEnd = markdown.indexOf("`.", versionStart);
  return versionEnd === -1 ? undefined : markdown.slice(versionStart, versionEnd);
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

function readDottedVersion(value, start) {
  let end = start;
  let dotCount = 0;
  while (end < value.length) {
    const char = value[end];
    if (char >= "0" && char <= "9") {
      end += 1;
    } else if (char === "." && end + 1 < value.length && isAsciiDigit(value[end + 1])) {
      dotCount += 1;
      end += 1;
    } else {
      break;
    }
  }
  return dotCount > 0 ? value.slice(start, end) : undefined;
}

function isAsciiDigit(char) {
  return char >= "0" && char <= "9";
}
