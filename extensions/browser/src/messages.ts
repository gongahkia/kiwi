export interface LookupMessage {
  context?: string;
  limit?: number;
  term: string;
  type: "wat.lookup";
}

export type LookupResponse =
  | {
      body: unknown;
      cached: boolean;
      ok: true;
    }
  | {
      error: string;
      ok: false;
      status?: number;
    };

export function isLookupMessage(message: unknown): message is LookupMessage {
  if (!message || typeof message !== "object") return false;
  const candidate = message as Partial<LookupMessage>;

  return candidate.type === "wat.lookup" && typeof candidate.term === "string";
}
