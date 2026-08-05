import type { SearchResponse } from "./api.js";

export function createNoMatchResponse(query: string, suggestPath = "/suggest"): SearchResponse {
  const params = new URLSearchParams({ term: query });

  return {
    matches: [],
    suggest_url: `${suggestPath}?${params.toString()}`
  };
}
