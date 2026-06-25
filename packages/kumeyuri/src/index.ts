export type KumeyuriTheme =
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
export type KumeyuriCharset = "ascii" | "unicode";
export type KumeyuriSvgAnimation = "smil" | "css-keyframes";
export type KumeyuriAnimation = "trace" | "playback" | "transitions" | "none";
export type KumeyuriReducedMotion = "auto" | "reduce" | "no-preference";

export interface KumeyuriRenderOptions {
  theme?: KumeyuriTheme;
  darkTheme?: KumeyuriTheme;
  charset?: KumeyuriCharset;
  width?: number;
  padding?: number;
  font?: string;
  speed?: number;
  repeat?: boolean;
  svgAnimation?: KumeyuriSvgAnimation;
}

export interface KumeyuriFrame {
  text: string;
  durationMs: number;
}

export interface KumeyuriRenderOutput {
  svg: string;
  frames: KumeyuriFrame[];
}

export interface KumeyuriWasmBindings {
  render(source: string, options: KumeyuriRenderOptions): unknown;
  renderCast?: (source: string, options: KumeyuriRenderOptions) => unknown;
}

export type KumeyuriWasmModule = KumeyuriWasmBindings & {
  default?: (input?: unknown) => unknown | Promise<unknown>;
};

export interface KumeyuriClient {
  render(source: string, options?: KumeyuriRenderOptions): KumeyuriRenderOutput;
  renderCast(source: string, options?: KumeyuriRenderOptions): KumeyuriRenderOutput;
}

export interface KumeyuriElementOptions {
  tagName?: string;
  registry?: CustomElementRegistry;
}

export interface KumeyuriDiagramElement extends HTMLElement {
  play(): void;
  pause(): void;
  seek(frameIndex: number): void;
  exportSvg(): string;
}

let activeClient: KumeyuriClient | undefined;

export function createKumeyuri(wasm: KumeyuriWasmBindings): KumeyuriClient {
  return {
    render(source: string, options: KumeyuriRenderOptions = {}): KumeyuriRenderOutput {
      return normalizeRenderOutput(wasm.render(source, options));
    },
    renderCast(source: string, options: KumeyuriRenderOptions = {}): KumeyuriRenderOutput {
      if (typeof wasm.renderCast !== "function") {
        throw new Error("kumeyuri WASM module does not expose renderCast");
      }
      return normalizeRenderOutput(wasm.renderCast(source, options));
    },
  };
}

export async function initKumeyuri(
  moduleOrLoader: KumeyuriWasmModule | Promise<KumeyuriWasmModule> | (() => Promise<KumeyuriWasmModule>),
  initInput?: unknown,
): Promise<KumeyuriClient> {
  const wasm = await resolveWasmModule(moduleOrLoader);
  if (typeof wasm.default === "function") {
    await wasm.default(initInput);
  }
  activeClient = createKumeyuri(wasm);
  return activeClient;
}

export function render(source: string, options: KumeyuriRenderOptions = {}): KumeyuriRenderOutput {
  if (!activeClient) {
    throw new Error("kumeyuri WASM module is not initialized; call initKumeyuri() first");
  }
  return activeClient.render(source, options);
}

export function renderCast(source: string, options: KumeyuriRenderOptions = {}): KumeyuriRenderOutput {
  if (!activeClient) {
    throw new Error("kumeyuri WASM module is not initialized; call initKumeyuri() first");
  }
  return activeClient.renderCast(source, options);
}

export function defineKumeyuriElement(options: KumeyuriElementOptions = {}): CustomElementConstructor {
  const tagName = options.tagName ?? "kumeyuri-diagram";
  const registry = options.registry ?? globalThis.customElements;
  if (!registry) {
    throw new Error("customElements registry is unavailable");
  }
  const existing = registry.get(tagName);
  if (existing) {
    return existing;
  }
  class KumeyuriDiagramElement extends HTMLElement {
    static get observedAttributes(): string[] {
      return [
        "src",
        "source",
        "inline",
        "animate",
        "theme",
        "dark-theme",
        "charset",
        "width",
        "padding",
        "font",
        "speed",
        "loop",
        "autoplay",
        "controls",
        "reduced-motion",
        "svg-animation",
        "csp",
      ];
    }

    #inlineSource: string | null = null;
    #fallbackHtml: string | null = null;
    #lastSvg = "";
    #output: KumeyuriRenderOutput | null = null;
    #frameIndex = 0;
    #playing = false;
    #playbackTimer: number | undefined;
    #playButton: HTMLButtonElement | null = null;
    #scrub: HTMLInputElement | null = null;
    #queued = false;

    connectedCallback(): void {
      this.#fallbackHtml ??= this.innerHTML;
      this.#inlineSource ??= this.textContent ?? "";
      this.#queueRender();
    }

    disconnectedCallback(): void {
      this.#stopPlayback();
    }

    attributeChangedCallback(): void {
      if (this.isConnected) {
        this.#queueRender();
      }
    }

    play(): void {
      this.#setPlaying(true);
    }

    pause(): void {
      this.#setPlaying(false);
    }

    seek(frameIndex: number): void {
      if (!Number.isFinite(frameIndex)) {
        throw new Error(`invalid frame index ${JSON.stringify(frameIndex)}`);
      }
      this.#setPlaying(false);
      this.#showFrame(Math.trunc(frameIndex));
    }

    exportSvg(): string {
      return this.#lastSvg;
    }

    #queueRender(): void {
      if (this.#queued) {
        return;
      }
      this.#queued = true;
      queueMicrotask(() => {
        this.#queued = false;
        void this.#renderNow();
      });
    }

    async #renderNow(): Promise<void> {
      try {
        this.#stopPlayback();
        this.#output = null;
        this.#frameIndex = 0;
        this.#playing = false;
        this.#playButton = null;
        this.#scrub = null;
        const source = await this.#source();
        if (source.text.trim().length === 0) {
          return;
        }
        const renderOptions = this.#renderOptions();
        const output = source.cast
          ? renderCast(source.text, renderOptions)
          : render(withAnimationDirective(source.text, this.#animationMode()), renderOptions);
        this.dataset.autoplay = String(this.hasAttribute("autoplay"));
        this.dataset.controls = String(this.hasAttribute("controls"));
        this.dataset.loop = String(this.hasAttribute("loop"));
        this.dataset.reducedMotion = String(this.#shouldReduceMotion());
        this.removeAttribute("data-error");
        this.#output = output;
        this.#lastSvg = output.svg;
        this.innerHTML = output.svg;
        if (this.hasAttribute("controls")) {
          this.#mountControls(output);
        }
      } catch (error) {
        this.dataset.error = error instanceof Error ? error.message : String(error);
        this.#lastSvg = "";
        this.#output = null;
        this.#playButton = null;
        this.#scrub = null;
        this.#restoreFallback(error);
      }
    }

    async #source(): Promise<{ text: string; cast: boolean }> {
      const src = this.getAttribute("src");
      if (src) {
        const response = await fetch(src);
        if (!response.ok) {
          throw new Error(`failed to fetch ${src}: ${response.status}`);
        }
        return { text: await response.text(), cast: isKumecastSrc(src) };
      }
      const source = this.getAttribute("source");
      if (source !== null && source.length > 0) {
        return { text: source, cast: false };
      }
      const inline = this.getAttribute("inline");
      if (inline !== null && inline.length > 0) {
        return { text: inline, cast: false };
      }
      const script = this.querySelector<HTMLScriptElement>("script[type='text/plain'][data-kumeyuri-source]");
      if (script?.textContent) {
        this.#inlineSource = script.textContent;
        return { text: script.textContent, cast: false };
      }
      return { text: this.#inlineSource ?? "", cast: false };
    }

    #renderOptions(): KumeyuriRenderOptions {
      const options: KumeyuriRenderOptions = {};
      const theme = this.getAttribute("theme");
      if (theme) {
        options.theme = theme as KumeyuriTheme;
      }
      const darkTheme = this.getAttribute("dark-theme");
      if (darkTheme) {
        options.darkTheme = darkTheme as KumeyuriTheme;
      }
      const charset = this.getAttribute("charset");
      if (charset) {
        if (charset !== "ascii" && charset !== "unicode") {
          throw new Error(`invalid charset ${JSON.stringify(charset)}: expected ascii or unicode`);
        }
        options.charset = charset;
      }
      const width = this.#positiveNumberAttribute("width");
      if (width !== undefined) {
        options.width = width;
      }
      const padding = this.#nonNegativeNumberAttribute("padding");
      if (padding !== undefined) {
        options.padding = padding;
      }
      const font = this.getAttribute("font");
      if (font) {
        options.font = font;
      }
      const speed = this.getAttribute("speed");
      if (speed) {
        const parsed = Number(speed);
        if (!Number.isFinite(parsed) || parsed <= 0) {
          throw new Error(`invalid speed ${JSON.stringify(speed)}: expected finite number > 0`);
        }
        options.speed = parsed;
      }
      if (this.hasAttribute("loop")) {
        options.repeat = true;
      }
      const svgAnimation = this.getAttribute("svg-animation");
      if (svgAnimation) {
        if (svgAnimation !== "smil" && svgAnimation !== "css-keyframes") {
          throw new Error(`invalid svg-animation ${JSON.stringify(svgAnimation)}: expected smil or css-keyframes`);
        }
        options.svgAnimation = svgAnimation;
      }
      return options;
    }

    #positiveNumberAttribute(name: string): number | undefined {
      const value = this.getAttribute(name);
      if (!value) {
        return undefined;
      }
      const parsed = Number(value);
      if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new Error(`invalid ${name} ${JSON.stringify(value)}: expected finite number > 0`);
      }
      return parsed;
    }

    #nonNegativeNumberAttribute(name: string): number | undefined {
      const value = this.getAttribute(name);
      if (!value) {
        return undefined;
      }
      const parsed = Number(value);
      if (!Number.isFinite(parsed) || parsed < 0) {
        throw new Error(`invalid ${name} ${JSON.stringify(value)}: expected finite number >= 0`);
      }
      return parsed;
    }

    #mountControls(output: KumeyuriRenderOutput): void {
      if (output.frames.length === 0) {
        return;
      }
      const cspMode = this.hasAttribute("csp");
      if (!cspMode && !this.style.position) {
        this.style.position = "relative";
      }
      const svg = this.querySelector("svg") as SVGSVGElement | null;
      svg?.pauseAnimations?.();
      const controls = document.createElement("div");
      controls.dataset.kumeyuriControls = "true";
      controls.setAttribute("part", "controls");
      if (cspMode) {
        controls.dataset.kumeyuriCsp = "true";
      } else {
        controls.style.cssText =
          "position:absolute;right:0.5rem;bottom:0.5rem;display:flex;gap:0.25rem;align-items:center;padding:0.25rem;background:rgba(255,255,255,0.9);border:1px solid currentColor;font:12px system-ui,sans-serif;";
      }
      const play = document.createElement("button");
      play.type = "button";
      play.dataset.action = "play";
      play.setAttribute("part", "play-button");
      if (!cspMode) {
        play.style.cssText = controlButtonStyle();
      }
      const restart = document.createElement("button");
      restart.type = "button";
      restart.dataset.action = "restart";
      restart.textContent = "restart";
      restart.setAttribute("aria-label", "Restart animation");
      restart.setAttribute("part", "restart-button");
      if (!cspMode) {
        restart.style.cssText = controlButtonStyle();
      }
      const scrub = document.createElement("input");
      scrub.type = "range";
      scrub.setAttribute("aria-label", "Animation frame");
      scrub.setAttribute("part", "scrubber");
      if (!cspMode) {
        scrub.style.cssText = "box-sizing:border-box;min-width:8rem;min-height:44px;";
      }
      scrub.min = "0";
      scrub.max = String(output.frames.length - 1);
      scrub.step = "1";
      scrub.value = "0";
      controls.append(play, scrub, restart);
      this.append(controls);

      this.#playButton = play;
      this.#scrub = scrub;
      play.addEventListener("click", () => this.#setPlaying(!this.#playing));
      restart.addEventListener("click", () => {
        this.#showFrame(0);
        this.#setPlaying(this.hasAttribute("autoplay") && !this.#shouldReduceMotion());
      });
      scrub.addEventListener("input", () => {
        this.#setPlaying(false);
        this.#showFrame(Number(scrub.value));
      });
      this.#showFrame(0);
      this.#setPlaying(this.hasAttribute("autoplay") && !this.#shouldReduceMotion());
    }

    #showFrame(next: number): void {
      const output = this.#output;
      if (!output || output.frames.length === 0) {
        return;
      }
      this.#frameIndex = Math.max(0, Math.min(output.frames.length - 1, next));
      if (this.#scrub) {
        this.#scrub.value = String(this.#frameIndex);
      }
      for (const group of this.querySelectorAll<SVGGElement>("svg > g[id^='frame-']")) {
        group.setAttribute("opacity", group.id === `frame-${this.#frameIndex}` ? "1" : "0");
      }
    }

    #setPlaying(next: boolean): void {
      this.#playing = next && !!this.#output && this.#output.frames.length > 1;
      if (this.#playButton) {
        this.#playButton.textContent = this.#playing ? "pause" : "play";
        this.#playButton.setAttribute("aria-label", this.#playing ? "Pause animation" : "Play animation");
      }
      this.#stopPlayback();
      if (this.#playing) {
        this.#schedulePlayback();
      }
    }

    #schedulePlayback(): void {
      const output = this.#output;
      if (!this.#playing || !output || output.frames.length < 2) {
        return;
      }
      const delay = Math.max(1, output.frames[this.#frameIndex]?.durationMs ?? 1);
      this.#playbackTimer = window.setTimeout(() => {
        const next = this.#frameIndex + 1;
        if (next >= output.frames.length && !this.hasAttribute("loop")) {
          this.#showFrame(output.frames.length - 1);
          this.#setPlaying(false);
          return;
        }
        this.#showFrame(next >= output.frames.length ? 0 : next);
        this.#schedulePlayback();
      }, delay);
    }

    #stopPlayback(): void {
      if (this.#playbackTimer !== undefined) {
        window.clearTimeout(this.#playbackTimer);
        this.#playbackTimer = undefined;
      }
    }

    #animationMode(): KumeyuriAnimation | null {
      const animate = this.getAttribute("animate");
      if (!animate) {
        return null;
      }
      if (!["trace", "playback", "transitions", "none"].includes(animate)) {
        throw new Error(`invalid animate ${JSON.stringify(animate)}`);
      }
      return animate as KumeyuriAnimation;
    }

    #shouldReduceMotion(): boolean {
      const preference = this.getAttribute("reduced-motion") ?? "auto";
      if (preference === "reduce") {
        return true;
      }
      if (preference === "no-preference") {
        return false;
      }
      if (preference !== "auto") {
        throw new Error(`invalid reduced-motion ${JSON.stringify(preference)}: expected auto, reduce, or no-preference`);
      }
      return globalThis.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    }

    #restoreFallback(error: unknown): void {
      if (this.#fallbackHtml !== null && this.#fallbackHtml.trim().length > 0) {
        this.innerHTML = this.#fallbackHtml;
        return;
      }
      const message = error instanceof Error ? error.message : String(error);
      const pre = document.createElement("pre");
      pre.dataset.kumeyuriError = "true";
      pre.setAttribute("role", "alert");
      pre.textContent = message;
      this.replaceChildren(pre);
    }
  }
  registry.define(tagName, KumeyuriDiagramElement);
  return KumeyuriDiagramElement;
}

async function resolveWasmModule(
  moduleOrLoader: KumeyuriWasmModule | Promise<KumeyuriWasmModule> | (() => Promise<KumeyuriWasmModule>),
): Promise<KumeyuriWasmModule> {
  if (typeof moduleOrLoader === "function") {
    return moduleOrLoader();
  }
  return moduleOrLoader;
}

function normalizeRenderOutput(value: unknown): KumeyuriRenderOutput {
  if (!isRecord(value)) {
    throw new TypeError("kumeyuri render output must be an object");
  }
  if (typeof value.svg !== "string") {
    throw new TypeError("kumeyuri render output svg must be a string");
  }
  if (!Array.isArray(value.frames)) {
    throw new TypeError("kumeyuri render output frames must be an array");
  }
  return {
    svg: value.svg,
    frames: value.frames.map(normalizeFrame),
  };
}

function normalizeFrame(value: unknown): KumeyuriFrame {
  if (!isRecord(value)) {
    throw new TypeError("kumeyuri frame must be an object");
  }
  if (typeof value.text !== "string") {
    throw new TypeError("kumeyuri frame text must be a string");
  }
  if (typeof value.durationMs !== "number" || !Number.isFinite(value.durationMs)) {
    throw new TypeError("kumeyuri frame durationMs must be a finite number");
  }
  return {
    text: value.text,
    durationMs: value.durationMs,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function withAnimationDirective(source: string, animate: string | null): string {
  if (!animate) {
    return source;
  }
  if (!["trace", "playback", "transitions", "none"].includes(animate)) {
    throw new Error(`invalid animate ${JSON.stringify(animate)}`);
  }
  return `%%{ animate: '${animate}' }%%\n${source}`;
}

function isKumecastSrc(src: string): boolean {
  try {
    return new URL(src, globalThis.document?.baseURI).pathname.endsWith(".kumecast");
  } catch {
    return src.split(/[?#]/, 1)[0]?.endsWith(".kumecast") ?? false;
  }
}

function controlButtonStyle(): string {
  return "box-sizing:border-box;min-width:44px;min-height:44px;padding:0 0.75rem;";
}
