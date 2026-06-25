/* tslint:disable */
/* eslint-disable */

/**
 * Browser-facing renderer wrapper.
 */
export class WasmRenderer {
    free(): void;
    [Symbol.dispose](): void;
    /**
     * Create a browser renderer.
     */
    constructor();
    /**
     * Render Mermaid source to SVG plus text frames.
     */
    render(source: string, options: any): any;
    /**
     * Render a `.kumecast` JSON payload to SVG plus text frames.
     */
    renderCast(source: string, options: any): any;
}

/**
 * Render Mermaid source to SVG plus text frames.
 */
export function render(source: string, options: any): any;

/**
 * Render a `.kumecast` JSON payload to SVG plus text frames.
 */
export function renderCast(source: string, options: any): any;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly __wbg_wasmrenderer_free: (a: number, b: number) => void;
    readonly render: (a: number, b: number, c: any) => [number, number, number];
    readonly renderCast: (a: number, b: number, c: any) => [number, number, number];
    readonly wasmrenderer_render: (a: number, b: number, c: number, d: any) => [number, number, number];
    readonly wasmrenderer_renderCast: (a: number, b: number, c: number, d: any) => [number, number, number];
    readonly wasmrenderer_new: () => number;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
