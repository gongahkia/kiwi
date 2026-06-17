export interface RehypeKumeyuriOptions {
  format?: "svg" | "text";
  kumeyuri?: string;
  replace?: boolean;
  theme?: "default" | "mono" | "tokyo-night" | "github" | "dracula";
  darkTheme?: "default" | "mono" | "tokyo-night" | "github" | "dracula";
  charset?: "ascii" | "unicode";
  width?: number;
  padding?: number;
  font?: string;
  maxBuffer?: number;
}

export default function rehypeKumeyuri(options?: RehypeKumeyuriOptions): (tree: unknown) => Promise<void>;
