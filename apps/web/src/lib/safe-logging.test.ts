import { describe, expect, it } from "vitest";

import { redactLogText, safeLogFields } from "./safe-logging";

describe("safe logging", () => {
  it("redacts sensitive keys and private payload fields", () => {
    expect(
      safeLogFields({
        authorization: "Bearer secret",
        nested: {
          cookie: "wat_session=secret",
          definition: "private definition",
          message: "private error text",
          query: "private acronym"
        },
        request_id: "req_123"
      })
    ).toEqual({
      authorization: "[redacted]",
      nested: {
        cookie: "[redacted]",
        definition: "[redacted]",
        message: "[redacted]",
        query: "[redacted]"
      },
      request_id: "req_123"
    });
  });

  it("strips query strings from route-like fields", () => {
    expect(
      safeLogFields({
        path: "/api/v1/search?q=private&token=secret",
        route: "/team/admin/entries/api?query=private"
      })
    ).toEqual({
      path: "/api/v1/search",
      route: "/team/admin/entries/api"
    });
  });

  it("redacts token-shaped substrings from free text", () => {
    expect(
      redactLogText("Authorization=Bearer abc123 token=xoxb-secret api_key=wat_api_key_secret")
    ).toBe("Authorization=[redacted] token=[redacted] api_key=[redacted]");
  });
});
