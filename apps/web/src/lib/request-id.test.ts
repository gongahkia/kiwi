import { describe, expect, it } from "vitest";

import { ensureRequestId, requestIdFromHeaders } from "./request-id";

describe("request id helpers", () => {
  it("reads an inbound request id", () => {
    expect(requestIdFromHeaders(new Headers({ "x-request-id": "req_123" }))).toBe("req_123");
  });

  it("generates an id when missing", () => {
    expect(ensureRequestId(new Headers())).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    );
  });
});
