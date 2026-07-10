import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod/v4";

import { requireApiConfig } from "./auth.js";
import { listAlternatives, listTeamEntries, lookupEntries, resultText } from "./search.js";
import { writeSuggestion } from "./suggestions.js";

const confidenceSchema = z.enum(["T1", "T2", "T3", "T4"]);

function structured<T extends object>(value: T): T & Record<string, unknown> {
  return value as T & Record<string, unknown>;
}

const resultSourceSchema = z.object({
  license: z.string(),
  publisher: z.string(),
  retrieved_at: z.string(),
  snippet: z.string(),
  source_quality: z.enum(["canonical", "secondary", "community"]),
  title: z.string(),
  url: z.string()
});

const resultSchema = z.object({
  citations: z.array(resultSourceSchema),
  confidence_tier: confidenceSchema,
  contemporaries: z.array(z.string()),
  domains: z.array(z.string()),
  entry_id: z.string(),
  expansion: z.string(),
  layer: z.enum(["public", "team", "personal"]),
  meaning: z.string(),
  score: z.number(),
  term: z.string()
});

const alternativesSchema = z.object({
  alternatives: z.array(resultSchema),
  entry: resultSchema.nullable(),
  team_id: z.string(),
  unresolved_terms: z.array(z.string())
});

const suggestionSchema = z.object({
  created_at: z.string(),
  status: z.literal("pending"),
  suggestion_id: z.string(),
  team_id: z.string()
});

export interface WatMcpServerOptions {
  env?: Record<string, string | undefined>;
}

export function createWatMcpServer(options: WatMcpServerOptions = {}): McpServer {
  const server = new McpServer({
    name: "wat",
    version: "0.0.0"
  });

  server.registerTool(
    "lookup",
    {
      annotations: {
        readOnlyHint: true
      },
      description: "Look up a sourced acronym or technical term in wat.",
      inputSchema: z.object({
        context: z.string().optional(),
        limit: z.number().int().min(1).max(20).optional(),
        min_confidence: confidenceSchema.optional(),
        term: z.string().min(1)
      }),
      outputSchema: z.object({
        matches: z.array(resultSchema),
        team_id: z.string()
      })
    },
    async ({ context, limit, min_confidence, term }) => {
      const config = requireApiConfig(options.env);
      const result = await lookupEntries({ config, context, limit, min_confidence, term });

      return {
        content: [{ type: "text", text: resultText(result.matches) }],
        structuredContent: structured({
          matches: result.matches,
          team_id: result.team_id
        })
      };
    }
  );

  server.registerTool(
    "list_team_acronyms",
    {
      annotations: {
        readOnlyHint: true
      },
      description: "List paged team-scoped wat acronyms for the API key.",
      inputSchema: z.object({
        cursor: z.number().int().min(0).optional(),
        domain: z.string().min(1).optional(),
        limit: z.number().int().min(1).max(100).optional()
      }),
      outputSchema: z.object({
        entries: z.array(resultSchema),
        next_cursor: z.number().nullable(),
        team_id: z.string()
      })
    },
    async ({ cursor, domain, limit }) => {
      const config = requireApiConfig(options.env);
      const page = await listTeamEntries({ config, cursor, domain, limit });

      return {
        content: [{ type: "text", text: resultText(page.entries) }],
        structuredContent: structured({
          ...page
        })
      };
    }
  );

  server.registerTool(
    "list_alternatives",
    {
      annotations: {
        readOnlyHint: true
      },
      description:
        "List resolved peer alternatives for a wat term using the same auth model as lookup.",
      inputSchema: z.object({
        term: z.string().min(1)
      }),
      outputSchema: alternativesSchema
    },
    async ({ term }) => {
      const config = requireApiConfig(options.env);
      const result = await listAlternatives({ config, term });

      return {
        content: [{ type: "text", text: resultText(result.alternatives) }],
        structuredContent: structured(result)
      };
    }
  );

  server.registerTool(
    "suggest_definition",
    {
      annotations: {
        destructiveHint: false,
        idempotentHint: false,
        readOnlyHint: false
      },
      description: "Propose a team-scoped wat definition when team policy allows writes.",
      inputSchema: z.object({
        domains: z.array(z.string().min(1)).optional(),
        expansion: z.string().min(1),
        meaning: z.string().min(1),
        source_title: z.string().min(1),
        source_url: z.string().url(),
        term: z.string().min(1)
      }),
      outputSchema: suggestionSchema
    },
    async ({ domains, expansion, meaning, source_title, source_url, term }) => {
      const config = requireApiConfig(options.env);
      const suggestion = await writeSuggestion({
        config,
        domains,
        expansion,
        meaning,
        source_title,
        source_url,
        term
      });

      return {
        content: [
          {
            type: "text",
            text: `Suggestion ${suggestion.suggestion_id} queued for ${suggestion.team_id}.`
          }
        ],
        structuredContent: structured({
          created_at: suggestion.created_at,
          status: suggestion.status,
          suggestion_id: suggestion.suggestion_id,
          team_id: suggestion.team_id
        })
      };
    }
  );

  return server;
}
