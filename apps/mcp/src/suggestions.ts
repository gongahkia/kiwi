import { apiHeaders, type WatApiConfig } from "./auth.js";

export interface SuggestDefinitionInput {
  config: WatApiConfig;
  domains?: string[];
  expansion: string;
  meaning: string;
  source_title: string;
  source_url: string;
  term: string;
}

export interface SuggestedDefinition {
  created_at: string;
  status: "pending";
  suggestion_id: string;
  team_id: string;
}

export async function writeSuggestion(
  input: SuggestDefinitionInput
): Promise<SuggestedDefinition> {
  const response = await fetch(`${input.config.baseUrl}/api/v1/suggestions`, {
    body: JSON.stringify({
      domains: input.domains ?? [],
      expansion: input.expansion,
      meaning: input.meaning,
      source_title: input.source_title,
      source_url: input.source_url,
      term: input.term
    }),
    headers: {
      ...apiHeaders(input.config),
      "content-type": "application/json"
    },
    method: "POST"
  });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`wat API ${response.status}: ${body || response.statusText}`);
  }
  const body = (await response.json()) as {
    suggestion: {
      created_at: string;
      id: string;
      status: "pending";
      team_id: string;
    };
  };
  return {
    created_at: body.suggestion.created_at,
    status: body.suggestion.status,
    suggestion_id: body.suggestion.id,
    team_id: body.suggestion.team_id
  };
}
