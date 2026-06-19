function init() {
  for (const element of document.querySelectorAll("[data-kumeyuri-cast]:not([data-kumeyuri-ready])")) {
    element.dataset.kumeyuriReady = "true";
    void mount(element);
  }
}

async function mount(element) {
  try {
    const response = await fetch(element.dataset.kumeyuriCast, {
      headers: { Accept: "application/json, */*;q=0.1" },
    });
    if (!response.ok) throw new Error(`failed to fetch cast: ${response.status}`);
    renderPlayer(element, validateCast(await response.json()));
  } catch (error) {
    element.classList.add("kumeyuri-zola-error");
    element.textContent = error instanceof Error ? error.message : String(error);
  }
}

export function validateCast(value) {
  if (!value || typeof value !== "object") throw new Error("cast must be an object");
  if (value.version !== 1) throw new Error(`unsupported cast version ${JSON.stringify(value.version)}`);
  if (!Array.isArray(value.timeline?.frames) || value.timeline.frames.length === 0) {
    throw new Error("cast timeline.frames must be non-empty");
  }
  for (const [index, frame] of value.timeline.frames.entries()) {
    if (!Number.isInteger(frame.width) || !Number.isInteger(frame.height)) {
      throw new Error(`frame ${index} has invalid dimensions`);
    }
    if (!Array.isArray(frame.cells) || frame.cells.length !== frame.width * frame.height) {
      throw new Error(`frame ${index} cell count does not match dimensions`);
    }
    if (!Number.isFinite(frame.durationMs)) throw new Error(`frame ${index} durationMs is invalid`);
  }
  return value;
}

function renderPlayer(element, cast) {
  let index = 0;
  let timer = 0;
  let playing = false;
  const loop = element.dataset.loop === "true" || cast.timeline.repeat === true;
  const controls = element.dataset.controls !== "false";
  const pre = document.createElement("pre");
  pre.className = "kumeyuri-zola-frame";
  pre.setAttribute("aria-live", "polite");
  const toolbar = document.createElement("div");
  toolbar.className = "kumeyuri-zola-controls";
  const play = document.createElement("button");
  play.type = "button";
  const restart = document.createElement("button");
  restart.type = "button";
  restart.textContent = "Restart";
  const scrub = document.createElement("input");
  scrub.type = "range";
  scrub.min = "0";
  scrub.max = String(cast.timeline.frames.length - 1);
  scrub.step = "1";
  scrub.value = "0";
  scrub.setAttribute("aria-label", "Frame");
  toolbar.append(play, restart, scrub);
  element.replaceChildren(pre);
  if (controls) element.append(toolbar);
  show(0);
  play.addEventListener("click", () => setPlaying(!playing));
  restart.addEventListener("click", () => {
    show(0);
    setPlaying(true);
  });
  scrub.addEventListener("input", () => {
    setPlaying(false);
    show(Number(scrub.value));
  });
  if (element.dataset.autoplay === "true") setPlaying(true);

  function show(next) {
    index = Math.max(0, Math.min(cast.timeline.frames.length - 1, next));
    scrub.value = String(index);
    pre.textContent = frameText(cast.timeline.frames[index]);
  }

  function setPlaying(next) {
    playing = next && cast.timeline.frames.length > 1;
    play.textContent = playing ? "Pause" : "Play";
    clearTimeout(timer);
    if (playing) schedule();
  }

  function schedule() {
    if (!playing) return;
    const frame = cast.timeline.frames[index];
    timer = setTimeout(() => {
      const next = index + 1;
      if (next >= cast.timeline.frames.length && !loop) {
        setPlaying(false);
        return;
      }
      show(next % cast.timeline.frames.length);
      schedule();
    }, Math.max(1, frame.durationMs));
  }
}

export function frameText(frame) {
  const rows = [];
  for (let y = 0; y < frame.height; y += 1) {
    let row = "";
    for (let x = 0; x < frame.width; x += 1) row += frame.cells[y * frame.width + x].glyph;
    rows.push(row.replace(/\s+$/u, ""));
  }
  return rows.join("\n").replace(/\n+$/u, "");
}

if (typeof document !== "undefined") {
  init();
  new MutationObserver(init).observe(document.body, { childList: true, subtree: true });
}
