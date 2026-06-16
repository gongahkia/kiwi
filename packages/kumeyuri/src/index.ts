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
