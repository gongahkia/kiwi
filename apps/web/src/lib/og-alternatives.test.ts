import { describe, expect, it } from "vitest";

import { formatOpenGraphAlternatives } from "./og-alternatives";

describe("formatOpenGraphAlternatives", () => {
  it("formats Kafka alternatives for OG subtitles", () => {
    expect(formatOpenGraphAlternatives(["RabbitMQ", "NATS", "Redpanda"])).toBe(
      "Alternatives: RabbitMQ · NATS · Redpanda"
    );
  });

  it("hides empty alternatives", () => {
    expect(formatOpenGraphAlternatives([])).toBeNull();
  });
});
