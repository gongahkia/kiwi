export type KumeyuriAstroStage = "head-inline" | "before-hydration" | "page";

export interface KumeyuriAstroOptions {
  inject?: boolean;
  scriptUrl?: string;
  stage?: KumeyuriAstroStage;
}

export interface AstroIntegration {
  name: "@kumeyuri/astro";
  hooks: {
    "astro:config:setup": (options: {
      injectScript: (stage: KumeyuriAstroStage, content: string) => void;
    }) => void;
  };
}

export default function kumeyuri(options?: KumeyuriAstroOptions): AstroIntegration;

export function normalizeOptions(options?: KumeyuriAstroOptions): Required<KumeyuriAstroOptions>;
export function browserImport(scriptUrl: string): string;
