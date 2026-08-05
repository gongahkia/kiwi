import type { SearchRequest, SearchResult } from "./api.js";

function tokenize(input: string): Set<string> {
  return new Set(
    input
      .toLowerCase()
      .replace(/[^\p{Letter}\p{Number}\s]+/gu, " ")
      .split(/\s+/)
      .filter(Boolean)
  );
}

function contextText(result: SearchResult): string {
  return [
    ...result.entry.domains,
    ...result.entry.expansions,
    result.entry.meaning_short,
    result.entry.term
  ].join(" ");
}

export function applyDomainContextBoost(
  results: SearchResult[],
  request: SearchRequest
): SearchResult[] {
  const contextTokens = tokenize(request.context ?? "");

  return results
    .map((result) => {
      const resultTokens = tokenize(contextText(result));
      const contextOverlap = Array.from(contextTokens).filter((token) =>
        resultTokens.has(token)
      ).length;
      const domainBoost = request.context
        ? result.entry.domains.some((domain) =>
            request.context?.toLowerCase().includes(domain.toLowerCase())
          )
          ? 1
          : 0
        : 0;
      const contextBoost = contextOverlap * 0.25 + domainBoost;

      return {
        ...result,
        score: result.score + contextBoost,
        score_breakdown: {
          ...result.score_breakdown,
          context: contextBoost,
          domain: domainBoost
        }
      };
    })
    .sort((left, right) => right.score - left.score || left.entry.id.localeCompare(right.entry.id));
}
