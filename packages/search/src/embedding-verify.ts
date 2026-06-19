import { embed } from "./embedding.js";

await embed("warmup");

const startedAt = performance.now();
const vector = await embed("CAP theorem");
const elapsedMs = performance.now() - startedAt;

if (!(vector instanceof Float32Array)) {
  throw new Error("embedding is not Float32Array");
}
if (vector.length !== 384) {
  throw new Error(`expected 384 dimensions, got ${vector.length}`);
}
if (elapsedMs >= 100) {
  throw new Error(`warm embedding took ${Math.round(elapsedMs)}ms`);
}

console.log(
  JSON.stringify({
    dims: vector.length,
    elapsed_ms: Math.round(elapsedMs),
    model: "Xenova/bge-small-en-v1.5",
    type: "Float32Array"
  })
);
