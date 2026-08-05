import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { smokeErrorTracking, smokeErrorTrackingConfig } from "./smoke-error-tracking.mjs";

describe("error tracking smoke", () => {
  it("triggers the guarded error route", async () => {
    const result = await smokeErrorTracking({
      fetchImpl: async (url, init) => {
        assert.equal(url, "https://wat.example.com/api/error-test");
        assert.deepEqual(init?.headers, { "x-wat-error-test-token": "smoke-secret" });
        return new Response("wat error tracking smoke test", { status: 500 });
      },
      timeoutMs: 1000,
      token: "smoke-secret",
      url: "https://wat.example.com"
    });

    assert.equal(result.status, 500);
    assert.match(result.body, /smoke test/);
  });

  it("fails when the route does not throw", async () => {
    await assert.rejects(
      () =>
        smokeErrorTracking({
          fetchImpl: async () =>
            new Response(JSON.stringify({ error: "not_found" }), { status: 404 }),
          timeoutMs: 1000,
          token: "bad",
          url: "https://wat.example.com"
        }),
      /expected a server error/
    );
  });

  it("resolves config from args and env", () => {
    assert.deepEqual(
      smokeErrorTrackingConfig(
        ["--", "--url", "https://wat.example.com/", "--token", "cli-token"],
        {}
      ),
      { timeoutMs: 5000, token: "cli-token", url: "https://wat.example.com" }
    );
    assert.deepEqual(
      smokeErrorTrackingConfig([], {
        ERROR_TEST_TOKEN: "env-token",
        NEXT_PUBLIC_SITE_URL: "https://env.example.com",
        WAT_SMOKE_TIMEOUT_MS: "2500"
      }),
      { timeoutMs: 2500, token: "env-token", url: "https://env.example.com" }
    );
  });
});
