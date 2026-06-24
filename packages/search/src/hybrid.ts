import { trigramSimilarity } from "./trigram.js";

export interface HybridSearchCandidate {
  aliases?: string[];
  contemporaries?: string[];
  domains?: string[];
  expansions?: string[];
  id: string;
  meaning_short?: string;
  term: string;
}

export interface HybridSearchMatch<
  TCandidate extends HybridSearchCandidate = HybridSearchCandidate
> {
  candidate: TCandidate;
  score: number;
  score_breakdown: {
    contemporary: number;
    domain: number;
    exact: number;
    lexical: number;
    trigram: number;
  };
}

export interface HybridSearchOptions {
  limit?: number;
}

export function searchHybrid<TCandidate extends HybridSearchCandidate>(
  query: string,
  candidates: readonly TCandidate[],
  options: HybridSearchOptions = {}
): HybridSearchMatch<TCandidate>[] {
  const normalizedQuery = normalizeText(query);
  if (!normalizedQuery) return [];

  const limit = normalizeLimit(options.limit);

  return candidates
    .map((candidate) => scoreCandidate(normalizedQuery, candidate))
    .filter((match) => match.score > 0)
    .sort(
      (left, right) =>
        right.score - left.score || left.candidate.id.localeCompare(right.candidate.id)
    )
    .slice(0, limit);
}

function scoreCandidate<TCandidate extends HybridSearchCandidate>(
  normalizedQuery: string,
  candidate: TCandidate
): HybridSearchMatch<TCandidate> {
  const queryTokens = tokenize(normalizedQuery);
  const termTokens = [candidate.term, ...(candidate.aliases ?? [])].map(normalizeText);
  const expansionTokens = new Set(tokenize(candidate.expansions?.join(" ") ?? ""));
  const contemporaryTokens = new Set(tokenize(candidate.contemporaries?.join(" ") ?? ""));
  const domainTokens = new Set(tokenize(candidate.domains?.join(" ") ?? ""));
  const document = [
    candidate.term,
    ...(candidate.aliases ?? []),
    ...(candidate.expansions ?? []),
    ...(candidate.contemporaries ?? []),
    ...(candidate.domains ?? []),
    candidate.meaning_short ?? ""
  ].join(" ");
  const firstQueryToken = queryTokens[0];
  const exact =
    firstQueryToken && termTokens.includes(firstQueryToken)
      ? 10
      : termTokens.some((term) => queryTokens.includes(term))
        ? 4
        : 0;
  const lexicalOverlap = queryTokens.filter((token) => expansionTokens.has(token)).length;
  const contemporaryOverlap = queryTokens.filter((token) => contemporaryTokens.has(token)).length;
  const domainOverlap = queryTokens.filter((token) => domainTokens.has(token)).length;
  const allQueryTokensMatched = queryTokens.every(
    (token) => termTokens.includes(token) || expansionTokens.has(token)
  );
  const lexical = lexicalOverlap * 3 + (allQueryTokensMatched ? 2 : 0);
  const contemporary = contemporaryOverlap * 1.5;
  const domain = domainOverlap * 2;
  const trigram = trigramSimilarity(normalizedQuery, document) * 2;

  return {
    candidate,
    score: exact + lexical + contemporary + domain + trigram,
    score_breakdown: {
      contemporary,
      domain,
      exact,
      lexical,
      trigram
    }
  };
}

function normalizeText(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokenize(input: string): string[] {
  return normalizeText(input).split(" ").filter(Boolean);
}

function normalizeLimit(limit: number | undefined): number {
  if (!limit || !Number.isFinite(limit)) return 10;
  return Math.min(Math.max(Math.trunc(limit), 1), 100);
}
