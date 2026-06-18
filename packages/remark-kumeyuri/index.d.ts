export interface RemarkKumeyuriOptions {
  format?: "svg" | "text";
  kumeyuri?: string;
  replace?: boolean;
  theme?: "default" | "mono" | "tokyo-night" | "github" | "dracula" | "print-mono";
  darkTheme?: "default" | "mono" | "tokyo-night" | "github" | "dracula" | "print-mono";
  charset?: "ascii" | "unicode";
  width?: number;
  padding?: number;
  font?: string;
  maxBuffer?: number;
}

export default function remarkKumeyuri(options?: RemarkKumeyuriOptions): (tree: unknown) => Promise<void>;
