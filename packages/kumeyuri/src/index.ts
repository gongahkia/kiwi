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
      return ["src", "inline", "animate", "theme", "dark-theme", "speed", "autoplay", "controls"];
    }

    #inlineSource: string | null = null;
    #playbackTimer: number | undefined;
    #queued = false;

    connectedCallback(): void {
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
        const source = await this.#source();
        if (source.text.trim().length === 0) {
          return;
        }
        const output = source.cast
          ? renderCast(source.text, this.#renderOptions())
          : render(withAnimationDirective(source.text, this.getAttribute("animate")), this.#renderOptions());
        this.dataset.autoplay = String(this.hasAttribute("autoplay"));
        this.dataset.controls = String(this.hasAttribute("controls"));
        this.removeAttribute("data-error");
        this.innerHTML = output.svg;
        if (this.hasAttribute("controls")) {
          this.#mountControls(output);
        }
      } catch (error) {
        this.dataset.error = error instanceof Error ? error.message : String(error);
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
      const inline = this.getAttribute("inline");
      if (inline !== null && inline.length > 0) {
        return { text: inline, cast: false };
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
      const speed = this.getAttribute("speed");
      if (speed) {
        const parsed = Number(speed);
        if (!Number.isFinite(parsed) || parsed <= 0) {
          throw new Error(`invalid speed ${JSON.stringify(speed)}: expected finite number > 0`);
        }
        options.speed = parsed;
      }
      return options;
    }

    #mountControls(output: KumeyuriRenderOutput): void {
      if (output.frames.length === 0) {
        return;
      }
      if (!this.style.position) {
        this.style.position = "relative";
      }
      const svg = this.querySelector("svg") as SVGSVGElement | null;
      svg?.pauseAnimations?.();
      const controls = document.createElement("div");
      controls.dataset.kumeyuriControls = "true";
      controls.style.cssText =
        "position:absolute;right:0.5rem;bottom:0.5rem;display:flex;gap:0.25rem;align-items:center;padding:0.25rem;background:rgba(255,255,255,0.9);border:1px solid currentColor;font:12px system-ui,sans-serif;";
      const play = document.createElement("button");
      play.type = "button";
      play.dataset.action = "play";
      play.style.cssText = controlButtonStyle();
      const restart = document.createElement("button");
      restart.type = "button";
      restart.dataset.action = "restart";
      restart.textContent = "restart";
      restart.setAttribute("aria-label", "Restart animation");
      restart.style.cssText = controlButtonStyle();
      const scrub = document.createElement("input");
      scrub.type = "range";
      scrub.setAttribute("aria-label", "Animation frame");
      scrub.style.cssText = "box-sizing:border-box;min-width:8rem;min-height:44px;";
      scrub.min = "0";
      scrub.max = String(output.frames.length - 1);
      scrub.step = "1";
      scrub.value = "0";
      controls.append(play, scrub, restart);
      this.append(controls);

      let index = 0;
      let playing = this.hasAttribute("autoplay");
      const setPlaying = (next: boolean): void => {
        playing = next;
        play.textContent = playing ? "pause" : "play";
        play.setAttribute("aria-label", playing ? "Pause animation" : "Play animation");
        this.#stopPlayback();
        if (playing) {
          schedule();
        }
      };
      const showFrame = (next: number): void => {
        index = Math.max(0, Math.min(output.frames.length - 1, next));
        scrub.value = String(index);
        for (const group of this.querySelectorAll<SVGGElement>("svg > g[id^='frame-']")) {
          group.setAttribute("opacity", group.id === `frame-${index}` ? "1" : "0");
        }
      };
      const schedule = (): void => {
        if (!playing || output.frames.length < 2) {
          return;
        }
        const delay = Math.max(1, output.frames[index]?.durationMs ?? 1);
        this.#playbackTimer = window.setTimeout(() => {
          showFrame(index + 1 >= output.frames.length ? 0 : index + 1);
          schedule();
        }, delay);
      };

      play.addEventListener("click", () => setPlaying(!playing));
      restart.addEventListener("click", () => {
        showFrame(0);
        setPlaying(this.hasAttribute("autoplay"));
      });
      scrub.addEventListener("input", () => {
        setPlaying(false);
        showFrame(Number(scrub.value));
      });
      showFrame(0);
      setPlaying(playing);
    }

    #stopPlayback(): void {
      if (this.#playbackTimer !== undefined) {
        window.clearTimeout(this.#playbackTimer);
        this.#playbackTimer = undefined;
      }
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
