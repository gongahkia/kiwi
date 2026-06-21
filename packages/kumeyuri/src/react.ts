import { Fragment, createElement, forwardRef, useEffect } from "react";
import type { ForwardedRef, HTMLAttributes, ReactElement, ReactNode } from "react";
import { defineKumeyuriElement, initKumeyuri } from "./index.js";
import type { KumeyuriTheme, KumeyuriWasmModule } from "./index.js";

export type KumeyuriAnimation = "trace" | "playback" | "transitions" | "none";

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
  inline?: string;
  animate?: KumeyuriAnimation;
  theme?: KumeyuriTheme;
  darkTheme?: KumeyuriTheme;
  speed?: number | string;
  autoplay?: boolean;
  controls?: boolean;
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
    inline,
    animate,
    theme,
    darkTheme,
    speed,
    autoplay,
    controls,
    children,
    ...rest
  } = props;
  const attrs: CustomElementProps = { ...rest, ref };
  if (src !== undefined) {
    attrs.src = src;
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
  if (speed !== undefined) {
    attrs.speed = String(speed);
  }
  if (autoplay) {
    attrs.autoplay = "";
  }
  if (controls) {
    attrs.controls = "";
  }
  return createElement(tagName, attrs, children);
});
