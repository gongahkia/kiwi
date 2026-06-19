export interface KumeyuriRevealPluginOptions {
  selector?: string;
  autoplay?: boolean;
  controls?: boolean;
  loop?: boolean;
  fetcher?: typeof fetch;
}

export interface KumeyuriCastFrame {
  width: number;
  height: number;
  durationMs: number;
  cells: Array<{ glyph: string }>;
}

export interface KumeyuriCast {
  version: 1;
  source: { diagramType: string };
  timeline: {
    repeat?: boolean;
    frames: KumeyuriCastFrame[];
  };
}

export interface RevealPlugin {
  id: string;
  init(deck: unknown): Promise<void>;
  destroy(): void;
}

export default function kumeyuriRevealPlugin(options?: KumeyuriRevealPluginOptions): RevealPlugin;
export function normalizeOptions(options?: KumeyuriRevealPluginOptions): Required<Omit<KumeyuriRevealPluginOptions, "fetcher">> & {
  fetcher?: typeof fetch;
};
export function validateCast(value: unknown): KumeyuriCast;
export function frameText(frame: KumeyuriCastFrame): string;
