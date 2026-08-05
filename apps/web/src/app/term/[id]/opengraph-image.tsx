import { ImageResponse } from "next/og";

import { formatOpenGraphAlternatives } from "@/lib/og-alternatives";
import { getPublicCorpusEntries } from "@/lib/public-corpus";

export const alt = "wat entry";
export const contentType = "image/png";
export const runtime = "nodejs";
export const size = {
  width: 1200,
  height: 630
};

interface Entry {
  contemporaries: string[];
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
  const entries = await getPublicCorpusEntries();
  return entries.find((entry) => entry.id === id);
}

export default async function Image({ params }: ImageProps) {
  const { id } = await params;
  const entry = await getEntry(id);
  const term = entry?.term ?? "wat";
  const expansion = entry?.expansions[0] ?? "Layered glossary lookup";
  const domains = entry?.domains ?? ["glossary"];
  const alternatives = formatOpenGraphAlternatives(entry?.contemporaries ?? []);

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
        {alternatives ? (
          <div style={{ color: "#64748b", fontSize: 36, lineHeight: 1.2 }}>{alternatives}</div>
        ) : null}
      </div>
      <div style={{ color: "#64748b", fontSize: 30 }}>wat</div>
    </div>,
    size
  );
}
