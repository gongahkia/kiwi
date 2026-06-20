import { describe, expect, it, vi } from "vitest";

import { buildErrorReport, reportError } from "./error-reporting";

describe("buildErrorReport", () => {
  it("normalizes thrown errors with request metadata", () => {
    const report = buildErrorReport(
      new TypeError("boom"),
      { method: "GET", route: "/api/test", source: "route" },
      new Date("2026-06-20T00:00:00.000Z")
    );

    expect(report).toMatchObject({
      message: "boom",
      method: "GET",
      name: "TypeError",
      route: "/api/test",
      runtime: "server",
      source: "route",
      timestamp: "2026-06-20T00:00:00.000Z"
    });
  });
});

describe("reportError", () => {
  it("posts error reports to the configured webhook", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 202 }));

    await expect(
      reportError(
        new Error("tracked"),
        { route: "/api/tracked" },
        { ERROR_TRACKING_WEBHOOK_URL: "https://errors.example.test/events" },
        fetchImpl
      )
    ).resolves.toEqual({ delivered: true, status: 202 });

    expect(fetchImpl).toHaveBeenCalledWith(
      "https://errors.example.test/events",
      expect.objectContaining({ method: "POST" })
    );
    const [, requestInit] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(String(requestInit.body))).toMatchObject({
      message: "tracked",
      route: "/api/tracked"
    });
  });

  it("does not require a webhook in local development", async () => {
    const fetchImpl = vi.fn();

    await expect(reportError("missing webhook", {}, {}, fetchImpl)).resolves.toEqual({
      delivered: false
    });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
