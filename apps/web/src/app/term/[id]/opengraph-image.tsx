import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { ImageResponse } from "next/og";

export const alt = "wat entry";
export const contentType = "image/png";
export const runtime = "nodejs";
export const size = {
  width: 1200,
  height: 630
};

interface Entry {
  domains: string[];
  expansions: string[];
  id: string;
  layer: string;
  term: string;
}

interface ImageProps {
  params: Promise<{ id: string }>;
}

async function getEntry(id: string): Promise<Entry | undefined> {
  const seedJson = await readSeedJson();
  const parsed = JSON.parse(seedJson) as { entries: Entry[] };
  return parsed.entries.find((entry) => entry.layer === "public" && entry.id === id);
}

async function readSeedJson(): Promise<string> {
  for (const seedPath of [
    join(process.cwd(), "packages/ingest/seeds/manual.json"),
    join(process.cwd(), "../../packages/ingest/seeds/manual.json")
  ]) {
    try {
      return await readFile(seedPath, "utf8");
    } catch {
      continue;
    }
  }

  throw new Error("manual seed file not found");
}

export default async function Image({ params }: ImageProps) {
  const { id } = await params;
  const entry = await getEntry(id);
  const term = entry?.term ?? "wat";
  const expansion = entry?.expansions[0] ?? "Layered glossary lookup";
  const domains = entry?.domains ?? ["glossary"];

  return new ImageResponse(
    <div
      style={{
        alignItems: "stretch",
        background: "#f8fafc",
        color: "#111827",
        display: "flex",
        flexDirection: "column",
        height: "100%",
        justifyContent: "space-between",
        padding: 72,
        width: "100%"
      }}
    >
      <div style={{ display: "flex", gap: 16 }}>
        {domains.slice(0, 3).map((domain) => (
          <div
            key={domain}
            style={{
              background: "#e2e8f0",
              borderRadius: 8,
              color: "#334155",
              fontSize: 28,
              padding: "10px 18px"
            }}
          >
            {domain}
          </div>
        ))}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
        <div style={{ fontSize: 126, fontWeight: 800, letterSpacing: 0, lineHeight: 0.9 }}>
          {term}
        </div>
        <div style={{ color: "#334155", fontSize: 52, lineHeight: 1.15 }}>{expansion}</div>
      </div>
      <div style={{ color: "#64748b", fontSize: 30 }}>wat</div>
    </div>,
    size
  );
}
