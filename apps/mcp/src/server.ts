import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod/v4";

import { requireApiKey } from "./auth.js";
import { listAlternatives, listTeamEntries, lookupEntries, resultText } from "./search.js";
import { writeSuggestion } from "./suggestions.js";

const confidenceSchema = z.enum(["T1", "T2", "T3", "T4"]);

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

export function createWatMcpServer(): McpServer {
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
        api_key: z.string().min(1),
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
    async ({ api_key, context, limit, min_confidence, term }) => {
      const auth = requireApiKey(api_key, undefined);
      const matches = await lookupEntries({ auth, context, limit, min_confidence, term });

      return {
        content: [{ type: "text", text: resultText(matches) }],
        structuredContent: {
          matches,
          team_id: auth.team_id
        }
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
        api_key: z.string().min(1),
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
    async ({ api_key, cursor, domain, limit }) => {
      const auth = requireApiKey(api_key, domain);
      const page = listTeamEntries({ auth, cursor, domain, limit });

      return {
        content: [{ type: "text", text: resultText(page.entries) }],
        structuredContent: {
          ...page,
          team_id: auth.team_id
        }
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
        api_key: z.string().min(1),
        term: z.string().min(1)
      }),
      outputSchema: alternativesSchema
    },
    async ({ api_key, term }) => {
      const auth = requireApiKey(api_key, undefined);
      const result = await listAlternatives({ auth, term });

      return {
        content: [{ type: "text", text: resultText(result.alternatives) }],
        structuredContent: {
          ...result,
          team_id: auth.team_id
        }
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
        api_key: z.string().min(1),
        domains: z.array(z.string().min(1)).optional(),
        expansion: z.string().min(1),
        meaning: z.string().min(1),
        source_title: z.string().min(1),
        source_url: z.string().url(),
        term: z.string().min(1)
      }),
      outputSchema: suggestionSchema
    },
    async ({ api_key, domains, expansion, meaning, source_title, source_url, term }) => {
      const auth = requireApiKey(api_key, undefined);
      const suggestion = await writeSuggestion({
        auth,
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
        structuredContent: {
          created_at: suggestion.created_at,
          status: suggestion.status,
          suggestion_id: suggestion.suggestion_id,
          team_id: suggestion.team_id
        }
      };
    }
  );

  return server;
}
