import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  buildSymmetricReview,
  lintContemporaries,
  writeSymmetricReview
} from "./contemporaries-lint.js";

describe("lintContemporaries", () => {
  it("reports unresolved contemporaries", () => {
    expect(
      lintContemporaries([
        { contemporaries: ["Missing"], id: "seed-api", term: "API", term_normalized: "api" }
      ])
    ).toEqual([
      {
        code: "unresolved_contemporary",
        contemporary: "Missing",
        entry_id: "seed-api",
        term: "API"
      }
    ]);
  });

  it("reports asymmetric contemporaries", () => {
    expect(
      lintContemporaries([
        { contemporaries: ["NATS"], id: "seed-kafka", term: "Kafka", term_normalized: "kafka" },
        { contemporaries: [], id: "seed-nats", term: "NATS", term_normalized: "nats" }
      ])
    ).toEqual([
      {
        code: "asymmetric_contemporary",
        contemporary: "NATS",
        entry_id: "seed-kafka",
        target_entry_id: "seed-nats",
        target_term: "NATS",
        term: "Kafka"
      }
    ]);
  });

  it("resolves aliases and symmetric pairs", () => {
    expect(
      lintContemporaries([
        { contemporaries: ["Vue"], id: "seed-react", term: "React", term_normalized: "react" },
        {
          aliases: ["Vue"],
          contemporaries: ["React"],
          id: "seed-vuejs",
          term: "Vue.js",
          term_normalized: "vue js"
        }
      ])
    ).toEqual([]);
  });

  it("reports self references", () => {
    expect(
      lintContemporaries([
        { contemporaries: [" kafka "], id: "seed-kafka", term: "Kafka", term_normalized: "kafka" }
      ])
    ).toEqual([
      {
        code: "contemporary_self_reference",
        contemporary: " kafka ",
        entry_id: "seed-kafka",
        term: "Kafka"
      }
    ]);
  });

  it("builds symmetric review suggestions", () => {
    const issues = lintContemporaries([
      { contemporaries: ["NATS"], id: "seed-kafka", term: "Kafka", term_normalized: "kafka" },
      { contemporaries: [], id: "seed-nats", term: "NATS", term_normalized: "nats" }
    ]);

    expect(buildSymmetricReview(issues).suggestions).toEqual([
      {
        add_contemporaries: ["Kafka"],
        entry_id: "seed-nats",
        source_entries: [{ entry_id: "seed-kafka", term: "Kafka" }],
        term: "NATS"
      }
    ]);
  });

  it("writes symmetric review sidecars", async () => {
    const dir = await mkdtemp(join(tmpdir(), "wat-contemporaries-"));
    const path = join(dir, "review.json");
    try {
      await writeSymmetricReview(path, {
        generated_at: "2026-06-23T00:00:00.000Z",
        suggestions: [
          {
            add_contemporaries: ["Kafka"],
            entry_id: "seed-nats",
            source_entries: [{ entry_id: "seed-kafka", term: "Kafka" }],
            term: "NATS"
          }
        ]
      });

      expect(JSON.parse(await readFile(path, "utf8"))).toEqual({
        generated_at: "2026-06-23T00:00:00.000Z",
        suggestions: [
          {
            add_contemporaries: ["Kafka"],
            entry_id: "seed-nats",
            source_entries: [{ entry_id: "seed-kafka", term: "Kafka" }],
            term: "NATS"
          }
        ]
      });
    } finally {
      await rm(dir, { force: true, recursive: true });
    }
  });
});
