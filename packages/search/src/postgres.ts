import type {
  ConfidenceTier,
  EntryLayer,
  SearchEntry,
  SearchRequest,
  SearchResponse,
  SearchResult,
  SearchSource
} from "./api.js";

export interface QueryClient {
  query<TRow extends Record<string, unknown>>(
    sql: string,
    values?: readonly unknown[]
  ): Promise<{ rows: TRow[] }>;
}

type SearchRow = {
  aliases: string[];
  bm25_rank: number;
  confidence_tier: ConfidenceTier;
  domains: string[];
  expansions: string[];
  id: string;
  layer: EntryLayer;
  meaning_short: string;
  sources: SearchSource[];
  term: string;
  term_normalized: string;
};

const confidenceRank: Record<ConfidenceTier, number> = {
  T1: 1,
  T2: 2,
  T3: 3,
  T4: 4
};

const defaultLayers: EntryLayer[] = ["public", "team", "personal"];

export async function searchPostgresEntries(
  client: QueryClient,
  request: SearchRequest
): Promise<SearchResponse> {
  const query = request.query.trim();
  if (!query) return { matches: [] };

  const limit = normalizeLimit(request.limit);
  const minConfidence = request.min_confidence ?? "T4";
  const layers = request.layers?.length ? request.layers : defaultLayers;
  const rows = await client.query<SearchRow>(
    `
    with search_query as (
      select websearch_to_tsquery('english'::regconfig, $1) as query
    )
    select
      e.id,
      e.term,
      e.term_normalized,
      e.expansions,
      e.domains,
      e.meaning_short,
      e.confidence_tier,
      e.layer,
      e.aliases,
      ts_rank_cd(e.tsvector, search_query.query) as bm25_rank,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'url', s.url,
            'title', s.title,
            'publisher', s.publisher,
            'license', s.license,
            'retrieved_at', to_jsonb(s.retrieved_at),
            'snippet', s.snippet,
            'source_quality', s.source_quality
          )
          order by s.position
        ) filter (where s.id is not null),
        '[]'::jsonb
      ) as sources
    from entries e
    cross join search_query
    left join sources s on s.entry_id = e.id
    where
      e.deprecated = false
      and e.layer = any($2::text[])
      and case e.confidence_tier
        when 'T1' then 1
        when 'T2' then 2
        when 'T3' then 3
        when 'T4' then 4
      end <= $3
      and e.tsvector @@ search_query.query
    group by e.id, search_query.query
    order by (e.term_normalized = lower($1)) desc, bm25_rank desc, e.term_normalized asc, e.id asc
    limit $4
    `,
    [query, layers, confidenceRank[minConfidence], limit]
  );

  const matches = rows.rows.map(rowToResult);
  return {
    matches,
    suggest_url: matches.length === 0 ? `/suggest?term=${encodeURIComponent(query)}` : undefined
  };
}

function rowToResult(row: SearchRow): SearchResult {
  const entry: SearchEntry = {
    aliases: row.aliases,
    confidence_tier: row.confidence_tier,
    domains: row.domains,
    expansions: row.expansions,
    id: row.id,
    layer: row.layer,
    meaning_short: row.meaning_short,
    sources: row.sources,
    term: row.term,
    term_normalized: row.term_normalized
  };

  return {
    entry,
    score: row.bm25_rank,
    score_breakdown: {
      bm25: row.bm25_rank
    }
  };
}

function normalizeLimit(limit: number | undefined): number {
  if (!limit || !Number.isFinite(limit)) return 10;
  return Math.min(Math.max(Math.trunc(limit), 1), 50);
}
