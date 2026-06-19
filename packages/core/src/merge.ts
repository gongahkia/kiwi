import type { EntryLayer, GlossaryEntry, SourceCitation } from "./schema.js";

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
    entry: structuredClone(selectedEntry),
    overriddenLayers: provenance
      .filter((item) => item.layer !== selectedLayer)
      .map((item) => item.layer),
    provenance,
    winningLayer: selectedLayer
  };
}
