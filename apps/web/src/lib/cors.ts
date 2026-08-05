export interface CorsEnv {
  [key: string]: string | undefined;
  WAT_ALLOWED_ORIGINS?: string;
  WAT_EXTENSION_ORIGINS?: string;
}

interface CorsOptions {
  allowHeaders?: string;
  env?: CorsEnv;
  methods: string;
}

const defaultAllowHeaders = "authorization, content-type, x-api-key, x-wat-team-id, x-wat-user-id";

function configuredOrigins(env: CorsEnv): Set<string> {
  return new Set(
    [env.WAT_ALLOWED_ORIGINS, env.WAT_EXTENSION_ORIGINS]
      .flatMap((value) => value?.split(/[,\s]+/) ?? [])
      .map((origin) => origin.trim())
      .filter(Boolean)
  );
}

export function corsHeadersForRequest(
  request: Request,
  { allowHeaders = defaultAllowHeaders, env = process.env, methods }: CorsOptions
): Headers {
  const headers = new Headers();
  headers.set("access-control-allow-headers", allowHeaders);
  headers.set("access-control-allow-methods", methods);

  const origin = request.headers.get("origin")?.trim();
  if (origin && configuredOrigins(env).has(origin)) {
    headers.set("access-control-allow-credentials", "true");
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
  }

  return headers;
}

export function applyCorsHeaders(response: Response, request: Request, options: CorsOptions): void {
  const headers = corsHeadersForRequest(request, options);
  for (const [key, value] of headers.entries()) response.headers.set(key, value);
}
