import { access } from "node:fs/promises";
import { join } from "node:path";

export interface HealthSnapshot {
  checked_at: string;
  service: "web";
  status: "ok";
}

export interface ReadinessSnapshot extends Omit<HealthSnapshot, "status"> {
  checks: {
    seed_corpus: "ok" | "missing";
  };
  status: "not_ready" | "ok";
}

export function getHealthSnapshot(): HealthSnapshot {
  return {
    checked_at: new Date().toISOString(),
    service: "web",
    status: "ok"
  };
}

export async function getReadinessSnapshot(): Promise<ReadinessSnapshot> {
  const seedReady = await seedCorpusExists();

  return {
    checked_at: new Date().toISOString(),
    checks: {
      seed_corpus: seedReady ? "ok" : "missing"
    },
    service: "web",
    status: seedReady ? "ok" : "not_ready"
  };
}

async function seedCorpusExists(): Promise<boolean> {
  for (const seedPath of [
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    try {
      await access(seedPath);
      return true;
    } catch {
      continue;
    }
  }

  return false;
}
