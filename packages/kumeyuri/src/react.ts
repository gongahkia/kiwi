import { Fragment, createElement, forwardRef, useEffect } from "react";
import type { ForwardedRef, HTMLAttributes, ReactElement, ReactNode } from "react";
import { defineKumeyuriElement, initKumeyuri } from "./index.js";
import type {
  KumeyuriAnimation,
  KumeyuriCharset,
  KumeyuriReducedMotion,
  KumeyuriSvgAnimation,
  KumeyuriTheme,
  KumeyuriWasmModule,
} from "./index.js";

export interface KumeyuriProviderProps {
  moduleOrLoader?: KumeyuriWasmModule | Promise<KumeyuriWasmModule> | (() => Promise<KumeyuriWasmModule>);
  initInput?: unknown;
  tagName?: string;
  defineElement?: boolean;
  onReady?: () => void;
  onError?: (error: unknown) => void;
  children?: ReactNode;
}

export interface KumeyuriDiagramProps extends Omit<HTMLAttributes<HTMLElement>, "children"> {
  tagName?: string;
  src?: string;
  source?: string;
  inline?: string;
  animate?: KumeyuriAnimation;
  theme?: KumeyuriTheme;
  darkTheme?: KumeyuriTheme;
  charset?: KumeyuriCharset;
  width?: number | string;
  padding?: number | string;
  font?: string;
  speed?: number | string;
  loop?: boolean;
  autoplay?: boolean;
  controls?: boolean;
  reducedMotion?: KumeyuriReducedMotion;
  svgAnimation?: KumeyuriSvgAnimation;
  csp?: boolean;
  maxSourceBytes?: number | string;
  fetchTimeoutMs?: number | string;
  lazy?: boolean;
  children?: string;
}

type CustomElementProps = HTMLAttributes<HTMLElement> &
  Record<string, unknown> & {
    ref?: ForwardedRef<HTMLElement>;
  };

export function KumeyuriProvider(props: KumeyuriProviderProps): ReactElement {
  const { moduleOrLoader, initInput, tagName, defineElement = true, onReady, onError, children } = props;
  useEffect(() => {
    let cancelled = false;
    const initialize = async (): Promise<void> => {
      if (moduleOrLoader !== undefined) {
        await initKumeyuri(moduleOrLoader, initInput);
      }
      if (defineElement) {
        defineKumeyuriElement(tagName === undefined ? {} : { tagName });
      }
      if (!cancelled) {
        onReady?.();
      }
    };
    void initialize().catch((error: unknown) => {
      if (cancelled) {
        return;
      }
      if (onError) {
        onError(error);
        return;
      }
      throw error;
    });
    return () => {
      cancelled = true;
    };
  }, [defineElement, initInput, moduleOrLoader, onError, onReady, tagName]);
  return createElement(Fragment, null, children);
}

export const KumeyuriDiagram = forwardRef<HTMLElement, KumeyuriDiagramProps>(function KumeyuriDiagram(
  props,
  ref,
): ReactElement {
  const {
    tagName = "kumeyuri-diagram",
    src,
    source,
    inline,
    animate,
    theme,
    darkTheme,
    charset,
    width,
    padding,
    font,
    speed,
    loop,
    autoplay,
    controls,
    reducedMotion,
    svgAnimation,
    csp,
    maxSourceBytes,
    fetchTimeoutMs,
    lazy,
    children,
    ...rest
  } = props;
  const attrs: CustomElementProps = { ...rest, ref };
  if (src !== undefined) {
    attrs.src = src;
  }
  if (source !== undefined) {
    attrs.source = source;
  }
  if (inline !== undefined) {
    attrs.inline = inline;
  }
  if (animate !== undefined) {
    attrs.animate = animate;
  }
  if (theme !== undefined) {
    attrs.theme = theme;
  }
  if (darkTheme !== undefined) {
    attrs["dark-theme"] = darkTheme;
  }
  if (charset !== undefined) {
    attrs.charset = charset;
  }
  if (width !== undefined) {
    attrs.width = String(width);
  }
  if (padding !== undefined) {
    attrs.padding = String(padding);
  }
  if (font !== undefined) {
    attrs.font = font;
  }
  if (speed !== undefined) {
    attrs.speed = String(speed);
  }
  if (loop) {
    attrs.loop = "";
  }
  if (autoplay) {
    attrs.autoplay = "";
  }
  if (controls) {
    attrs.controls = "";
  }
  if (reducedMotion !== undefined) {
    attrs["reduced-motion"] = reducedMotion;
  }
  if (svgAnimation !== undefined) {
    attrs["svg-animation"] = svgAnimation;
  }
  if (csp) {
    attrs.csp = "";
  }
  if (maxSourceBytes !== undefined) {
    attrs["max-source-bytes"] = String(maxSourceBytes);
  }
  if (fetchTimeoutMs !== undefined) {
    attrs["fetch-timeout-ms"] = String(fetchTimeoutMs);
  }
  if (lazy) {
    attrs.lazy = "";
  }
  return createElement(tagName, attrs, children);
});
