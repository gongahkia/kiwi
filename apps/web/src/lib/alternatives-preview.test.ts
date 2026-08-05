import { describe, expect, it } from "vitest";

import { formatAlternativesPreview } from "./alternatives-preview";

describe("formatAlternativesPreview", () => {
  it("returns null without alternatives", () => {
    expect(formatAlternativesPreview([])).toBeNull();
  });

  it("formats a compact one-line alternatives preview", () => {
    expect(formatAlternativesPreview(["SSR", "MPA"])).toBe("Alt: SSR, MPA");
  });

  it("truncates long alternative lists", () => {
    expect(formatAlternativesPreview(["RabbitMQ", "NATS", "Redpanda", "Pulsar"])).toBe(
      "Alt: RabbitMQ, NATS, Redpanda, +1 more"
    );
  });
});
