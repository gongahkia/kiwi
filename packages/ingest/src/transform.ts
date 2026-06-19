import type { RawEntry, RawSourceCitation } from "./scraper.js";

export interface CanonicalSourceCitation {
  license: string;
  publisher: string;
  retrieved_at: string;
  snippet: string;
  source_quality: "canonical" | "secondary" | "community";
  title: string;
  url: string;
}

export interface CanonicalEntry {
  dedup_key: string;
  domains: string[];
  examples: string[];
  expansion_normalized: string;
  expansions: string[];
  meaning_short: string;
  sources: CanonicalSourceCitation[];
  term: string;
  term_normalized: string;
}

function normalizeText(input: string): string {
  return input
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function toCanonicalSource(source: RawSourceCitation): CanonicalSourceCitation {
  return {
    license: source.license,
    publisher: source.publisher,
    retrieved_at: source.retrieved_at,
    snippet: source.snippet ?? "",
    source_quality: source.source_quality ?? "secondary",
    title: source.title ?? source.publisher,
    url: source.url
  };
}

export function transformRawEntry(raw: RawEntry): CanonicalEntry {
  const expansion = raw.expansion ?? raw.term;
  const termNormalized = normalizeText(raw.term);
  const expansionNormalized = normalizeText(expansion);

  return {
    dedup_key: `${termNormalized}:${expansionNormalized}`,
    domains: raw.domains ?? [],
    examples: raw.examples ?? [],
    expansion_normalized: expansionNormalized,
    expansions: [expansion],
    meaning_short: raw.meaning ?? expansion,
    sources: raw.sources.map(toCanonicalSource),
    term: raw.term,
    term_normalized: termNormalized
  };
}
