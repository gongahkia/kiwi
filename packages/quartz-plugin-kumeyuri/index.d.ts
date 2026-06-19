export interface QuartzKumeyuriOptions {
  className?: string;
  autoplay?: boolean;
  controls?: boolean;
  loop?: boolean;
  scriptUrl?: string;
  cssUrl?: string;
}

export interface QuartzTransformerPluginInstance {
  name: string;
  markdownPlugins?: () => unknown[];
  externalResources?: () => {
    js?: Array<{ src: string; loadTime: "afterDOMReady"; contentType: "external" }>;
    css?: string[];
  };
}

export default function Kumeyuri(options?: QuartzKumeyuriOptions): QuartzTransformerPluginInstance;
export function remarkKumeyuri(options?: QuartzKumeyuriOptions): (tree: unknown) => void;
export function renderCastHtml(src: string, options?: QuartzKumeyuriOptions): string;
export function normalizeOptions(options?: QuartzKumeyuriOptions): Required<QuartzKumeyuriOptions>;
