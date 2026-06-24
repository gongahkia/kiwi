import { describe, expect, it } from "vitest";

import {
  connectedDatabaseChecks,
  getHealthSnapshot,
  getReadinessSnapshot,
  readinessStatus
} from "./health";

describe("health snapshots", () => {
  it("reports health without dependency checks", () => {
    expect(getHealthSnapshot()).toMatchObject({
      service: "web",
      status: "ok"
    });
  });

  it("marks readiness unavailable without a database URL", async () => {
    const snapshot = await getReadinessSnapshot({ NODE_ENV: "test" });

    expect(snapshot.status).toBe("not_ready");
    expect(snapshot.checks).toEqual({
      database: "missing_url",
      migrations: "unknown",
      seed_corpus: "unknown"
    });
  });

  it("requires every readiness check to pass", () => {
    expect(
      readinessStatus({
        database: "ok",
        migrations: "ok",
        seed_corpus: "ok"
      })
    ).toBe("ok");
    expect(
      readinessStatus({
        database: "ok",
        migrations: "missing",
        seed_corpus: "ok"
      })
    ).toBe("not_ready");
  });

  it("marks missing migrations before checking seed rows", async () => {
    const client = queryable([{ ready: false }]);

    await expect(connectedDatabaseChecks(client)).resolves.toEqual({
      migrations: "missing",
      seed_corpus: "unknown"
    });
    expect(client.calls).toHaveLength(1);
  });

  it("marks missing DB seed corpus after migrations pass", async () => {
    const client = queryable([{ ready: true }, { ready: false }]);

    await expect(connectedDatabaseChecks(client)).resolves.toEqual({
      migrations: "ok",
      seed_corpus: "missing"
    });
    expect(client.calls).toHaveLength(2);
  });
});

function queryable(rowsByCall: Array<{ ready: boolean }>) {
  return {
    calls: [] as string[],
    async query<T>(sql: string): Promise<{ rows: T[] }> {
      this.calls.push(sql);
      const row = rowsByCall[this.calls.length - 1] ?? { ready: false };
      return { rows: [row as T] };
    }
  };
}
