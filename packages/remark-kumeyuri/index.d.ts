type KumeyuriTheme =
  | "default"
  | "mono"
  | "tokyo-night"
  | "github"
  | "dracula"
  | "solarized-light"
  | "solarized-dark"
  | "nord"
  | "catppuccin-mocha"
  | "high-contrast"
  | "print-mono";

export interface RemarkKumeyuriOptions {
  format?: "svg" | "text";
  kumeyuri?: string;
  replace?: boolean;
  theme?: KumeyuriTheme;
  darkTheme?: KumeyuriTheme;
  charset?: "ascii" | "unicode";
  width?: number;
  padding?: number;
  font?: string;
  maxBuffer?: number;
}

export default function remarkKumeyuri(options?: RemarkKumeyuriOptions): (tree: unknown) => Promise<void>;
