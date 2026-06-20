import { reportError } from "./lib/error-reporting";

type RequestErrorContext = {
  routerKind?: string;
  routePath?: string;
  routeType?: string;
};

type RequestLike = {
  method?: string;
  path?: string;
};

export async function onRequestError(
  error: unknown,
  request: RequestLike,
  context: RequestErrorContext
): Promise<void> {
  await reportError(error, {
    method: request.method,
    route: context.routePath ?? request.path,
    source: context.routeType ?? context.routerKind ?? "next-request"
  });
}
