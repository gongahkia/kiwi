import { reportError } from "./lib/error-reporting";
import { requestIdFromHeaders } from "./lib/request-id";
import { assertValidStartupEnv } from "./lib/startup-env";

type RequestErrorContext = {
  routerKind?: string;
  routePath?: string;
  routeType?: string;
};

type RequestLike = {
  headers?: {
    get(name: string): string | null;
  };
  method?: string;
  path?: string;
};

export function register(): void {
  try {
    assertValidStartupEnv();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message}\n`);
    process.exit(1);
  }
}

export async function onRequestError(
  error: unknown,
  request: RequestLike,
  context: RequestErrorContext
): Promise<void> {
  await reportError(error, {
    method: request.method,
    request_id: requestIdFromHeaders(request.headers),
    route: context.routePath ?? request.path,
    source: context.routeType ?? context.routerKind ?? "next-request"
  });
}
