import { appendFile, mkdir } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";
import { randomUUID } from "node:crypto";

import type { AuthContext } from "./types.js";

export interface SuggestDefinitionInput {
  auth: AuthContext;
  domains?: string[];
  expansion: string;
  meaning: string;
  source_title: string;
  source_url: string;
  term: string;
}

export interface SuggestedDefinition {
  api_key_id: string;
  created_at: string;
  domains: string[];
  expansion: string;
  meaning: string;
  source_title: string;
  source_url: string;
  status: "pending";
  suggestion_id: string;
  team_id: string;
  term: string;
}

interface SuggestionEnv {
  WAT_MCP_ALLOW_WRITE?: string;
  WAT_MCP_SUGGESTIONS_PATH?: string;
}

function suggestionsPath(path: string): string {
  return isAbsolute(path) ? path : resolve(process.cwd(), path);
}

export async function writeSuggestion(
  input: SuggestDefinitionInput,
  env: SuggestionEnv = process.env
): Promise<SuggestedDefinition> {
  if (env.WAT_MCP_ALLOW_WRITE !== "true") {
    throw new Error("suggest_definition disabled by team policy");
  }
  if (!env.WAT_MCP_SUGGESTIONS_PATH) {
    throw new Error("WAT_MCP_SUGGESTIONS_PATH is required");
  }

  const suggestion: SuggestedDefinition = {
    api_key_id: input.auth.api_key_id,
    created_at: new Date().toISOString(),
    domains: input.domains ?? [],
    expansion: input.expansion,
    meaning: input.meaning,
    source_title: input.source_title,
    source_url: input.source_url,
    status: "pending",
    suggestion_id: randomUUID(),
    team_id: input.auth.team_id,
    term: input.term
  };
  const path = suggestionsPath(env.WAT_MCP_SUGGESTIONS_PATH);

  await mkdir(dirname(path), { recursive: true });
  await appendFile(path, `${JSON.stringify(suggestion)}\n`, "utf8");

  return suggestion;
}
