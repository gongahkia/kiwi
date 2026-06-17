let activeClient;
export function createKumeyuri(wasm) {
    return {
        render(source, options = {}) {
            return normalizeRenderOutput(wasm.render(source, options));
        },
    };
}
export async function initKumeyuri(moduleOrLoader, initInput) {
    const wasm = await resolveWasmModule(moduleOrLoader);
    if (typeof wasm.default === "function") {
        await wasm.default(initInput);
    }
    activeClient = createKumeyuri(wasm);
    return activeClient;
}
export function render(source, options = {}) {
    if (!activeClient) {
        throw new Error("kumeyuri WASM module is not initialized; call initKumeyuri() first");
    }
    return activeClient.render(source, options);
}
export function defineKumeyuriElement(options = {}) {
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
        static get observedAttributes() {
            return ["src", "inline", "animate", "theme", "dark-theme", "speed", "autoplay", "controls"];
        }
        #inlineSource = null;
        #playbackTimer;
        #queued = false;
        connectedCallback() {
            this.#inlineSource ??= this.textContent ?? "";
            this.#queueRender();
        }
        disconnectedCallback() {
            this.#stopPlayback();
        }
        attributeChangedCallback() {
            if (this.isConnected) {
                this.#queueRender();
            }
        }
        #queueRender() {
            if (this.#queued) {
                return;
            }
            this.#queued = true;
            queueMicrotask(() => {
                this.#queued = false;
                void this.#renderNow();
            });
        }
        async #renderNow() {
            try {
                this.#stopPlayback();
                const source = await this.#source();
                if (source.trim().length === 0) {
                    return;
                }
                const output = render(withAnimationDirective(source, this.getAttribute("animate")), this.#renderOptions());
                this.dataset.autoplay = String(this.hasAttribute("autoplay"));
                this.dataset.controls = String(this.hasAttribute("controls"));
                this.removeAttribute("data-error");
                this.innerHTML = output.svg;
                if (this.hasAttribute("controls")) {
                    this.#mountControls(output);
                }
            }
            catch (error) {
                this.dataset.error = error instanceof Error ? error.message : String(error);
            }
        }
        async #source() {
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
        #renderOptions() {
            const options = {};
            const theme = this.getAttribute("theme");
            if (theme) {
                options.theme = theme;
            }
            const darkTheme = this.getAttribute("dark-theme");
            if (darkTheme) {
                options.darkTheme = darkTheme;
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
        #mountControls(output) {
            if (output.frames.length === 0) {
                return;
            }
            if (!this.style.position) {
                this.style.position = "relative";
            }
            const svg = this.querySelector("svg");
            svg?.pauseAnimations?.();
            const controls = document.createElement("div");
            controls.dataset.kumeyuriControls = "true";
            controls.style.cssText =
                "position:absolute;right:0.5rem;bottom:0.5rem;display:flex;gap:0.25rem;align-items:center;padding:0.25rem;background:rgba(255,255,255,0.9);border:1px solid currentColor;font:12px system-ui,sans-serif;";
            const play = document.createElement("button");
            play.type = "button";
            play.dataset.action = "play";
            const restart = document.createElement("button");
            restart.type = "button";
            restart.dataset.action = "restart";
            restart.textContent = "restart";
            const scrub = document.createElement("input");
            scrub.type = "range";
            scrub.min = "0";
            scrub.max = String(output.frames.length - 1);
            scrub.step = "1";
            scrub.value = "0";
            controls.append(play, scrub, restart);
            this.append(controls);
            let index = 0;
            let playing = this.hasAttribute("autoplay");
            const setPlaying = (next) => {
                playing = next;
                play.textContent = playing ? "pause" : "play";
                this.#stopPlayback();
                if (playing) {
                    schedule();
                }
            };
            const showFrame = (next) => {
                index = Math.max(0, Math.min(output.frames.length - 1, next));
                scrub.value = String(index);
                for (const group of this.querySelectorAll("svg > g[id^='frame-']")) {
                    group.setAttribute("opacity", group.id === `frame-${index}` ? "1" : "0");
                }
            };
            const schedule = () => {
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
        #stopPlayback() {
            if (this.#playbackTimer !== undefined) {
                window.clearTimeout(this.#playbackTimer);
                this.#playbackTimer = undefined;
            }
        }
    }
    registry.define(tagName, KumeyuriDiagramElement);
    return KumeyuriDiagramElement;
}
async function resolveWasmModule(moduleOrLoader) {
    if (typeof moduleOrLoader === "function") {
        return moduleOrLoader();
    }
    return moduleOrLoader;
}
function normalizeRenderOutput(value) {
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
function normalizeFrame(value) {
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
function isRecord(value) {
    return typeof value === "object" && value !== null;
}
function withAnimationDirective(source, animate) {
    if (!animate) {
        return source;
    }
    if (!["trace", "playback", "transitions", "none"].includes(animate)) {
        throw new Error(`invalid animate ${JSON.stringify(animate)}`);
    }
    return `%%{ animate: '${animate}' }%%\n${source}`;
}
