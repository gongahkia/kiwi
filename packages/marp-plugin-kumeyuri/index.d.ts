export interface MarpKumeyuriOptions {
  className?: string;
  autoplay?: boolean;
  controls?: boolean;
  loop?: boolean;
  scriptUrl?: string;
}

export interface MarkdownItLike {
  core: {
    ruler: {
      after(afterName: string, ruleName: string, fn: (state: { tokens: MarkdownItToken[] }) => void): void;
    };
  };
}

export interface MarkdownItToken {
  type: string;
  tag?: string;
  nesting?: number;
  info?: string;
  content: string;
  children?: unknown;
  attrs?: unknown;
  map?: unknown;
}

export default function marpEngine(context: { marp: { use(plugin: unknown, options?: MarpKumeyuriOptions): unknown } }, options?: MarpKumeyuriOptions): unknown;
export function marpKumeyuriPlugin(md: MarkdownItLike, options?: MarpKumeyuriOptions): MarkdownItLike;
export function renderCastHtml(src: string, options?: MarpKumeyuriOptions): string;
export function normalizeOptions(options?: MarpKumeyuriOptions): Required<Omit<MarpKumeyuriOptions, "scriptUrl">> & {
  scriptUrl?: string;
};
