import type { EntryLayer, GlossaryEntry, SourceCitation } from "./schema.js";
import { normalizeDisplayTermKey, normalizeDisplayTermList } from "./normalize.js";

const priority: EntryLayer[] = ["personal", "team", "public"];

export interface LayerProvenance {
  id: string;
  layer: EntryLayer;
  sources: SourceCitation[];
  term: string;
}

export interface MergedLayeredEntry {
  entry: GlossaryEntry;
  overriddenLayers: EntryLayer[];
  provenance: LayerProvenance[];
  winningLayer: EntryLayer;
}

export interface LayeredEntryInput {
  personal?: GlossaryEntry;
  public?: GlossaryEntry;
  team?: GlossaryEntry;
}

export function mergeLayeredEntry(input: LayeredEntryInput): MergedLayeredEntry | null {
  const selectedLayer = priority.find((layer) => input[layer]);
  if (!selectedLayer) {
    return null;
  }

  const selectedEntry = input[selectedLayer];
  if (!selectedEntry) {
    return null;
  }

  const provenance = [...priority].reverse().flatMap((layer): LayerProvenance[] => {
    const entry = input[layer];
    return entry ? [{ id: entry.id, layer, sources: entry.sources, term: entry.term }] : [];
  });

  return {
    entry: {
      ...structuredClone(selectedEntry),
      contemporaries: mergeContemporaries(input)
    },
    overriddenLayers: provenance
      .filter((item) => item.layer !== selectedLayer)
      .map((item) => item.layer),
    provenance,
    winningLayer: selectedLayer
  };
}

function mergeContemporaries(input: LayeredEntryInput): string[] {
  const seen = new Set<string>();
  const output: string[] = [];

  for (const layer of priority) {
    const entry = input[layer];
    if (!entry) {
      continue;
    }

    for (const value of normalizeDisplayTermList(entry.contemporaries)) {
      const key = normalizeDisplayTermKey(value);
      if (seen.has(key)) {
        continue;
      }

      seen.add(key);
      output.push(value);
    }
  }

  return output;
}
