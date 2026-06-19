const form = document.querySelector("#cast-form");
const input = document.querySelector("#cast-url");
const status = document.querySelector("#player-status");
const count = document.querySelector("#player-count");
const frameView = document.querySelector("#player-frame");
const playToggle = document.querySelector("#play-toggle");
const restart = document.querySelector("#restart");
const scrub = document.querySelector("#scrub");

let cast = null;
let index = 0;
let playing = false;
let timer = 0;

const initialCast = new URL(location.href).searchParams.get("cast");
if (initialCast) {
  input.value = initialCast;
  queueLoad(initialCast);
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const url = input.value.trim();
  if (!url) {
    setError("Enter a cast URL");
    return;
  }
  const next = new URL(location.href);
  next.searchParams.set("cast", url);
  history.replaceState(null, "", next);
  queueLoad(url);
});

playToggle.addEventListener("click", () => setPlaying(!playing));
restart.addEventListener("click", () => {
  showFrame(0);
  setPlaying(true);
});
scrub.addEventListener("input", () => {
  setPlaying(false);
  showFrame(Number(scrub.value));
});

async function loadCast(url) {
  setPlaying(false);
  setStatus("Loading cast");
  const response = await fetch(url, { headers: { Accept: "application/json, application/gzip;q=0.8, */*;q=0.1" } });
  if (!response.ok) {
    throwError(`failed to fetch cast: ${response.status}`);
  }
  const parsed = validateCast(await response.json());
  cast = parsed;
  index = 0;
  scrub.max = String(parsed.timeline.frames.length - 1);
  scrub.value = "0";
  count.textContent = `${parsed.source.diagramType} · ${parsed.timeline.frames.length} frames`;
  setStatus("Ready");
  showFrame(0);
}

function queueLoad(url) {
  void loadCast(url).catch((error) => {
    setError(error instanceof Error ? error.message : String(error));
  });
}

function validateCast(value) {
  if (!value || typeof value !== "object") {
    throwError("cast must be an object");
  }
  if (value.version !== 1) {
    throwError(`unsupported cast version ${JSON.stringify(value.version)}`);
  }
  if (!value.source || typeof value.source.diagramType !== "string") {
    throwError("cast source.diagramType is required");
  }
  const frames = value.timeline?.frames;
  if (!Array.isArray(frames) || frames.length === 0) {
    throwError("cast timeline.frames must be non-empty");
  }
  for (const [frameIndex, frame] of frames.entries()) {
    if (!Number.isInteger(frame.width) || !Number.isInteger(frame.height)) {
      throwError(`frame ${frameIndex} has invalid dimensions`);
    }
    if (!Array.isArray(frame.cells) || frame.cells.length !== frame.width * frame.height) {
      throwError(`frame ${frameIndex} cell count does not match dimensions`);
    }
    if (!Number.isFinite(frame.durationMs)) {
      throwError(`frame ${frameIndex} durationMs is invalid`);
    }
  }
  return value;
}

function showFrame(next) {
  if (!cast) {
    return;
  }
  index = Math.max(0, Math.min(cast.timeline.frames.length - 1, next));
  scrub.value = String(index);
  frameView.textContent = frameText(cast.timeline.frames[index]);
  status.textContent = `Frame ${index + 1}`;
}

function frameText(frame) {
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

function setPlaying(next) {
  playing = next && Boolean(cast);
  playToggle.textContent = playing ? "Pause" : "Play";
  clearTimeout(timer);
  if (playing) {
    schedule();
  }
}

function schedule() {
  if (!playing || !cast) {
    return;
  }
  const frame = cast.timeline.frames[index];
  timer = window.setTimeout(() => {
    const next = index + 1;
    if (next >= cast.timeline.frames.length && !cast.timeline.repeat) {
      setPlaying(false);
      return;
    }
    showFrame(next % cast.timeline.frames.length);
    schedule();
  }, Math.max(1, frame.durationMs));
}

function setStatus(message) {
  status.textContent = message;
  delete frameView.dataset.error;
}

function setError(message) {
  setPlaying(false);
  status.textContent = message;
  count.textContent = "";
  frameView.textContent = "";
  frameView.dataset.error = "true";
}

function throwError(message) {
  setError(message);
  throw new Error(message);
}
