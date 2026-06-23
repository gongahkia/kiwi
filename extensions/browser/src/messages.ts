export interface LookupMessage {
  context?: string;
  limit?: number;
  term: string;
  type: "wat.lookup";
}

export interface SaveCustomEntryMessage {
  domains?: string[];
  expansion: string;
  meaning?: string;
  scope?: "personal" | "team";
  sourceTitle?: string;
  sourceUrl?: string;
  term: string;
  type: "wat.customEntry.save";
}

export interface OptionsMessage {
  type: "wat.options.get";
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

export type SaveCustomEntryResponse =
  | {
      body: unknown;
      ok: true;
    }
  | {
      error: string;
      ok: false;
      status?: number;
    };

export const sidePanelCustomEntryStorageKey = "watSidePanelCustomEntry";
export const sidePanelQueryStorageKey = "watSidePanelQuery";

export interface SidePanelQuery {
  context: string;
  createdAt: string;
  term: string;
}

export interface SidePanelCustomEntryDraft {
  context: string;
  createdAt: string;
  sourceTitle?: string;
  sourceUrl?: string;
  term: string;
}

export function isLookupMessage(message: unknown): message is LookupMessage {
  if (!message || typeof message !== "object") return false;
  const candidate = message as Partial<LookupMessage>;

  return candidate.type === "wat.lookup" && typeof candidate.term === "string";
}

export function isSaveCustomEntryMessage(message: unknown): message is SaveCustomEntryMessage {
  if (!message || typeof message !== "object") return false;
  const candidate = message as Partial<SaveCustomEntryMessage>;

  return (
    candidate.type === "wat.customEntry.save" &&
    typeof candidate.term === "string" &&
    typeof candidate.expansion === "string"
  );
}

export function isOptionsMessage(message: unknown): message is OptionsMessage {
  if (!message || typeof message !== "object") return false;
  return (message as Partial<OptionsMessage>).type === "wat.options.get";
}
