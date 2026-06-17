import assert from "node:assert/strict";
import {
  findMermaidBlocks,
  injectRenderedBlocks,
  parseArgs,
} from "../skills/kumeyuri-render/scripts/render-mermaid-blocks.mjs";

const markdown = `Intro

\`\`\`mermaid
graph TD
  A --> B
\`\`\`

\`\`\`text
not a diagram
\`\`\`

\`\`\`mmd
sequenceDiagram
  A->>B: hi
\`\`\`
`;

const blocks = findMermaidBlocks(markdown);
assert.equal(blocks.length, 2);
assert.equal(blocks[0].index, 1);
assert.match(blocks[0].source, /graph TD/);
assert.match(blocks[1].source, /sequenceDiagram/);

const rendered = new Map([
  [1, "rendered graph"],
  [2, "rendered sequence"],
]);

const appended = injectRenderedBlocks(markdown, blocks, rendered, { format: "text" });
assert.match(appended, /```mermaid/);
assert.match(appended, /```text\nrendered graph\n```/);
assert.match(appended, /```text\nrendered sequence\n```/);

const replaced = injectRenderedBlocks(markdown, blocks, rendered, { format: "svg", replace: true });
assert.equal(replaced.includes("```mermaid"), false);
assert.match(replaced, /```svg\nrendered graph\n```/);

assert.deepEqual(parseArgs(["--format", "svg", "--replace", "--kumeyuri", "/bin/kumeyuri", "doc.md"]), {
  input: "doc.md",
  format: "svg",
  kumeyuri: "/bin/kumeyuri",
  replace: true,
});

console.log("ok");
