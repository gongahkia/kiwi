export interface DocusaurusKumeyuriOptions {
  inject?: boolean;
  preload?: boolean;
  scriptUrl?: string;
  integrity?: string;
  crossorigin?: string | boolean;
}

export interface DocusaurusLoadContext {
  siteDir: string;
  generatedFilesDir: string;
  siteConfig: unknown;
  outDir: string;
  baseUrl: string;
}

export interface DocusaurusHtmlTag {
  tagName: string;
  attributes?: Record<string, string | boolean>;
  innerHTML?: string;
}

export interface DocusaurusKumeyuriPlugin {
  name: "@docusaurus/plugin-kumeyuri";
  injectHtmlTags(): {
    headTags?: DocusaurusHtmlTag[];
    postBodyTags?: DocusaurusHtmlTag[];
  };
}

export default function docusaurusKumeyuriPlugin(
  context: DocusaurusLoadContext,
  options?: DocusaurusKumeyuriOptions,
): DocusaurusKumeyuriPlugin;

export function validateOptions(args: { options?: DocusaurusKumeyuriOptions }): DocusaurusKumeyuriOptions;
export function normalizeOptions(options?: DocusaurusKumeyuriOptions): Required<
  Pick<DocusaurusKumeyuriOptions, "inject" | "preload" | "scriptUrl">
> &
  Omit<DocusaurusKumeyuriOptions, "inject" | "preload" | "scriptUrl">;
