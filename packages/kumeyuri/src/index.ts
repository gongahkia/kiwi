export type KumeyuriTheme = "default" | "mono" | "tokyo-night" | "github" | "dracula";
export type KumeyuriCharset = "ascii" | "unicode";
export type KumeyuriSvgAnimation = "smil" | "css-keyframes";

export interface KumeyuriRenderOptions {
  theme?: KumeyuriTheme;
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
}

export type KumeyuriWasmModule = KumeyuriWasmBindings & {
  default?: (input?: unknown) => unknown | Promise<unknown>;
};

export interface KumeyuriClient {
  render(source: string, options?: KumeyuriRenderOptions): KumeyuriRenderOutput;
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
      return ["src", "inline", "animate", "theme", "speed", "autoplay", "controls"];
    }

    #inlineSource: string | null = null;
    #queued = false;

    connectedCallback(): void {
      this.#inlineSource ??= this.textContent ?? "";
      this.#queueRender();
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
        const source = await this.#source();
        if (source.trim().length === 0) {
          return;
        }
        const output = render(withAnimationDirective(source, this.getAttribute("animate")), this.#renderOptions());
        this.dataset.autoplay = String(this.hasAttribute("autoplay"));
        this.dataset.controls = String(this.hasAttribute("controls"));
        this.removeAttribute("data-error");
        this.innerHTML = output.svg;
      } catch (error) {
        this.dataset.error = error instanceof Error ? error.message : String(error);
      }
    }

    async #source(): Promise<string> {
      const src = this.getAttribute("src");
      if (src) {
        const response = await fetch(src);
        if (!response.ok) {
          throw new Error(`failed to fetch ${src}: ${response.status}`);
        }
        return response.text();
      }
      const inline = this.getAttribute("inline");
      if (inline !== null && inline.length > 0) {
        return inline;
      }
      return this.#inlineSource ?? "";
    }

    #renderOptions(): KumeyuriRenderOptions {
      const options: KumeyuriRenderOptions = {};
      const theme = this.getAttribute("theme");
      if (theme) {
        options.theme = theme as KumeyuriTheme;
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
