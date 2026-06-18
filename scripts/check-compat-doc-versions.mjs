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
  const flattened = markdown.replace(/\s+/g, " ");
  return flattened.match(/official Mermaid docs sidebar for Mermaid ([0-9]+(?:\.[0-9]+)+)\./)?.[1];
}

function extractCompatVersion(markdown) {
  return markdown.match(/Upstream reference: Mermaid docs `([^`]+)`\./)?.[1];
}
