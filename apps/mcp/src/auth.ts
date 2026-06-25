export interface WatApiConfig {
  apiKey: string;
  baseUrl: string;
}

export function requireApiConfig(
  env: Record<string, string | undefined> = process.env
): WatApiConfig {
  const baseUrl = env.WAT_API_BASE_URL?.trim();
  const apiKey = env.WAT_API_KEY?.trim();
  if (!baseUrl) throw new Error("WAT_API_BASE_URL is required");
  if (!apiKey) throw new Error("WAT_API_KEY is required");
  return {
    apiKey,
    baseUrl: baseUrl.replace(/\/+$/, "")
  };
}

export function apiHeaders(config: WatApiConfig): HeadersInit {
  return {
    authorization: `Bearer ${config.apiKey}`
  };
}
