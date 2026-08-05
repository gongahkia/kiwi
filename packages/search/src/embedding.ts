import { pipeline } from "@huggingface/transformers";

const defaultModel = "Xenova/bge-small-en-v1.5";
const embeddingSize = 384;

type Extractor = Awaited<ReturnType<typeof pipeline<"feature-extraction">>>;

let extractorPromise: Promise<Extractor> | null = null;

async function getExtractor(model = defaultModel): Promise<Extractor> {
  extractorPromise ??= pipeline("feature-extraction", model, { dtype: "fp32" });
  return extractorPromise;
}

export function toFloat32Vector(data: Float32Array | Iterable<number>): Float32Array {
  return data instanceof Float32Array ? data : Float32Array.from(data);
}

export async function embed(text: string): Promise<Float32Array> {
  const extractor = await getExtractor();
  const output = await extractor(text, { normalize: true, pooling: "mean" });
  const vector = toFloat32Vector(output.data as Float32Array | Iterable<number>);

  if (vector.length !== embeddingSize) {
    throw new Error(`expected ${embeddingSize} dimensions, got ${vector.length}`);
  }

  return vector;
}
