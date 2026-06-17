import assert from "node:assert/strict";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import rehypeKumeyuri from "../index.js";

const dir = await mkdtemp(path.join(tmpdir(), "rehype-kumeyuri-test-"));
try {
  const fake = path.join(dir, "kumeyuri");
  await writeFile(fake, `#!/usr/bin/env node
const format = process.argv[process.argv.indexOf("--format") + 1]
process.stdout.write(format === "svg" ? "<svg data-test=\\"kumeyuri\\"></svg>\\n" : "rendered text\\n")
`, "utf8");
  await chmod(fake, 0o755);

  const tree = rootWithMermaid();
  await rehypeKumeyuri({ kumeyuri: fake, format: "text" })(tree);
  assert.equal(tree.children.length, 2);
  assert.equal(tree.children[1].tagName, "pre");
  assert.equal(tree.children[1].children[0].children[0].value, "rendered text");

  const svgTree = rootWithMermaid();
  await rehypeKumeyuri({ kumeyuri: fake, format: "svg", replace: true })(svgTree);
  assert.equal(svgTree.children.length, 1);
  assert.equal(svgTree.children[0].tagName, "div");
  assert.equal(svgTree.children[0].children[0].type, "raw");
  assert.match(svgTree.children[0].children[0].value, /<svg/);
} finally {
  await rm(dir, { recursive: true, force: true });
}

function rootWithMermaid() {
  return {
    type: "root",
    children: [
      {
        type: "element",
        tagName: "pre",
        properties: {},
        children: [
          {
            type: "element",
            tagName: "code",
            properties: { className: ["language-mermaid"] },
            children: [{ type: "text", value: "graph TD\nA --> B" }],
          },
        ],
      },
    ],
  };
}

console.log("ok");
