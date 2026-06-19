const DEFAULT_OPTIONS = {
  selector: "[data-kumeyuri-cast]",
  autoplay: false,
  controls: true,
  loop: false,
};

export default function kumeyuriRevealPlugin(options = {}) {
  const config = normalizeOptions(options);
  const players = [];
  return {
    id: "kumeyuri",
    async init(deck) {
      const root = deck?.getRevealElement?.() ?? globalThis.document;
      if (!root?.querySelectorAll) {
        return;
      }
      const elements = Array.from(root.querySelectorAll(config.selector));
      const loaded = await Promise.all(elements.map((element) => loadCastElement(element, config)));
      players.push(...loaded.filter(Boolean));
    },
    destroy() {
      while (players.length > 0) {
        players.pop().destroy();
      }
    },
  };
}

export function normalizeOptions(options = {}) {
  if (!isPlainObject(options)) {
    throw new Error("@kumeyuri/reveal-plugin options must be an object");
  }
  const config = { ...DEFAULT_OPTIONS, ...options };
  if (typeof config.selector !== "string" || config.selector.length === 0) {
    throw new Error("@kumeyuri/reveal-plugin selector must be a non-empty string");
  }
  if (typeof config.autoplay !== "boolean") {
    throw new Error("@kumeyuri/reveal-plugin autoplay must be a boolean");
  }
  if (typeof config.controls !== "boolean") {
    throw new Error("@kumeyuri/reveal-plugin controls must be a boolean");
  }
  if (typeof config.loop !== "boolean") {
    throw new Error("@kumeyuri/reveal-plugin loop must be a boolean");
  }
  if (config.fetcher !== undefined && typeof config.fetcher !== "function") {
    throw new Error("@kumeyuri/reveal-plugin fetcher must be a function");
  }
  return config;
}

async function loadCastElement(element, config) {
  const src = castSource(element);
  if (!src) {
    renderError(element, "missing data-kumeyuri-cast source");
    return null;
  }
  try {
    const cast = await fetchCast(src, config.fetcher ?? globalThis.fetch);
    return mountPlayer(element, cast, config);
  } catch (error) {
    renderError(element, error instanceof Error ? error.message : String(error));
    return null;
  }
}

async function fetchCast(src, fetcher) {
  if (typeof fetcher !== "function") {
    throw new Error("fetch is unavailable");
  }
  const response = await fetcher(src, { headers: { Accept: "application/json, */*;q=0.1" } });
  if (!response?.ok) {
    throw new Error(`failed to fetch cast: ${response?.status ?? "unknown"}`);
  }
  return validateCast(await response.json());
}

export function validateCast(value) {
  if (!value || typeof value !== "object") {
    throw new Error("cast must be an object");
  }
  if (value.version !== 1) {
    throw new Error(`unsupported cast version ${JSON.stringify(value.version)}`);
  }
  if (!value.source || typeof value.source.diagramType !== "string") {
    throw new Error("cast source.diagramType is required");
  }
  const frames = value.timeline?.frames;
  if (!Array.isArray(frames) || frames.length === 0) {
    throw new Error("cast timeline.frames must be non-empty");
  }
  for (const [index, frame] of frames.entries()) {
    if (!Number.isInteger(frame.width) || !Number.isInteger(frame.height)) {
      throw new Error(`frame ${index} has invalid dimensions`);
    }
    if (!Array.isArray(frame.cells) || frame.cells.length !== frame.width * frame.height) {
      throw new Error(`frame ${index} cell count does not match dimensions`);
    }
    if (!Number.isFinite(frame.durationMs)) {
      throw new Error(`frame ${index} durationMs is invalid`);
    }
  }
  return value;
}

function mountPlayer(element, cast, config) {
  let index = 0;
  let timer = 0;
  let playing = false;

  element.classList.add("kumeyuri-reveal-cast");
  element.replaceChildren();

  const meta = document.createElement("div");
  meta.className = "kumeyuri-reveal-cast-meta";
  meta.textContent = `${cast.source.diagramType} / ${cast.timeline.frames.length} frames`;

  const pre = document.createElement("pre");
  pre.className = "kumeyuri-reveal-cast-frame";
  pre.setAttribute("aria-live", "polite");

  const controls = document.createElement("div");
  controls.className = "kumeyuri-reveal-cast-controls";
  const play = button("Play");
  const restart = button("Restart");
  const scrub = document.createElement("input");
  scrub.type = "range";
  scrub.min = "0";
  scrub.max = String(cast.timeline.frames.length - 1);
  scrub.step = "1";
  scrub.value = "0";
  scrub.setAttribute("aria-label", "Frame");

  controls.append(play, restart, scrub);
  element.append(meta, pre);
  if (config.controls) {
    element.append(controls);
  }

  play.addEventListener("click", () => setPlaying(!playing));
  restart.addEventListener("click", () => {
    showFrame(0);
    setPlaying(true);
  });
  scrub.addEventListener("input", () => {
    setPlaying(false);
    showFrame(Number(scrub.value));
  });

  showFrame(0);
  if (config.autoplay || element.hasAttribute("data-autoplay")) {
    setPlaying(true);
  }

  return {
    destroy() {
      clearTimeout(timer);
      playing = false;
      play.replaceWith(play.cloneNode(true));
      restart.replaceWith(restart.cloneNode(true));
      scrub.replaceWith(scrub.cloneNode(true));
    },
  };

  function showFrame(next) {
    index = Math.max(0, Math.min(cast.timeline.frames.length - 1, next));
    scrub.value = String(index);
    pre.textContent = frameText(cast.timeline.frames[index]);
  }

  function setPlaying(next) {
    playing = next && cast.timeline.frames.length > 1;
    play.textContent = playing ? "Pause" : "Play";
    clearTimeout(timer);
    if (playing) {
      schedule();
    }
  }

  function schedule() {
    if (!playing) {
      return;
    }
    const frame = cast.timeline.frames[index];
    timer = setTimeout(() => {
      const next = index + 1;
      if (next >= cast.timeline.frames.length && !(config.loop || cast.timeline.repeat)) {
        setPlaying(false);
        return;
      }
      showFrame(next % cast.timeline.frames.length);
      schedule();
    }, Math.max(1, frame.durationMs));
  }
}

export function frameText(frame) {
  const rows = [];
  for (let y = 0; y < frame.height; y += 1) {
    let row = "";
    for (let x = 0; x < frame.width; x += 1) {
      row += frame.cells[y * frame.width + x].glyph;
    }
    rows.push(row.replace(/\s+$/u, ""));
  }
  return rows.join("\n").replace(/\n+$/u, "");
}

function castSource(element) {
  return element.getAttribute("data-kumeyuri-cast") || element.getAttribute("src") || "";
}

function renderError(element, message) {
  element.classList.add("kumeyuri-reveal-cast", "kumeyuri-reveal-cast-error");
  element.textContent = message;
}

function button(label) {
  const element = document.createElement("button");
  element.type = "button";
  element.textContent = label;
  return element;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
