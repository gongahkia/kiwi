const ESC = "\x1b";
const BEL = "\x07";

const ANSI_16 = [
  "#000000", "#800000", "#008000", "#808000", "#000080", "#800080", "#008080", "#c0c0c0",
  "#808080", "#ff0000", "#00ff00", "#ffff00", "#0000ff", "#ff00ff", "#00ffff", "#ffffff",
];

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");
}

function xterm256Color(index) {
  const n = clamp(Number(index) || 0, 0, 255);
  if (n < 16) {
    return ANSI_16[n];
  }
  if (n >= 232) {
    const level = 8 + (n - 232) * 10;
    const hex = level.toString(16).padStart(2, "0");
    return `#${hex}${hex}${hex}`;
  }
  const offset = n - 16;
  const r = Math.floor(offset / 36);
  const g = Math.floor((offset % 36) / 6);
  const b = offset % 6;
  const component = (v) => (v === 0 ? 0 : 55 + v * 40).toString(16).padStart(2, "0");
  return `#${component(r)}${component(g)}${component(b)}`;
}

function parseParams(raw) {
  const clean = raw.replace(/^[?>!]/, "");
  if (clean === "") {
    return [0];
  }
  return clean.split(";").flatMap((part) => part.split(":")).map((part) => {
    if (part === "") {
      return 0;
    }
    const parsed = Number.parseInt(part, 10);
    return Number.isFinite(parsed) ? parsed : 0;
  });
}

function sameStyle(a, b) {
  return a.fg === b.fg && a.bg === b.bg && a.bold === b.bold && a.inverse === b.inverse;
}

function cloneStyle(style) {
  return {
    fg: style.fg ?? null,
    bg: style.bg ?? null,
    bold: Boolean(style.bold),
    inverse: Boolean(style.inverse),
  };
}

function styleToCss(style) {
  let fg = style.fg;
  let bg = style.bg;
  if (style.inverse) {
    [fg, bg] = [bg, fg];
  }
  const css = [];
  if (fg) {
    css.push(`color:${fg}`);
  }
  if (bg) {
    css.push(`background-color:${bg}`);
  }
  if (style.bold) {
    css.push("font-weight:700");
  }
  return css.join(";");
}

function blankCell(style = {}) {
  return {
    ch: " ",
    style: cloneStyle(style),
  };
}

export class AnsiScreen {
  constructor(cols = 80, rows = 24) {
    this.resize(cols, rows);
    this.resetStyle();
    this.savedCursor = { row: 0, col: 0 };
  }

  resize(cols = 80, rows = 24) {
    this.cols = Math.max(1, Number.parseInt(cols, 10) || 80);
    this.rows = Math.max(1, Number.parseInt(rows, 10) || 24);
    this.cursor = { row: 0, col: 0 };
    this.cells = Array.from({ length: this.rows }, () => Array.from({ length: this.cols }, () => blankCell()));
    return this;
  }

  resetStyle() {
    this.style = { fg: null, bg: null, bold: false, inverse: false };
  }

  clear() {
    for (let row = 0; row < this.rows; row += 1) {
      this.clearLine(row, 0, this.cols - 1);
    }
  }

  clearLine(row, from = 0, to = this.cols - 1) {
    if (row < 0 || row >= this.rows) {
      return;
    }
    const start = clamp(from, 0, this.cols - 1);
    const end = clamp(to, 0, this.cols - 1);
    for (let col = start; col <= end; col += 1) {
      this.cells[row][col] = blankCell();
    }
  }

  scrollUp() {
    this.cells.shift();
    this.cells.push(Array.from({ length: this.cols }, () => blankCell()));
    this.cursor.row = this.rows - 1;
  }

  putChar(ch) {
    if (this.cursor.row < 0 || this.cursor.row >= this.rows) {
      return;
    }
    if (this.cursor.col >= this.cols) {
      this.cursor.col = 0;
      this.cursor.row += 1;
    }
    if (this.cursor.row >= this.rows) {
      this.scrollUp();
    }
    this.cells[this.cursor.row][this.cursor.col] = { ch, style: cloneStyle(this.style) };
    this.cursor.col += 1;
  }

  newline() {
    this.cursor.row += 1;
    if (this.cursor.row >= this.rows) {
      this.scrollUp();
    }
  }

  applySgr(params) {
    if (params.length === 0) {
      this.resetStyle();
      return;
    }
    for (let i = 0; i < params.length; i += 1) {
      const code = params[i];
      if (code === 0) {
        this.resetStyle();
      } else if (code === 1) {
        this.style.bold = true;
      } else if (code === 22) {
        this.style.bold = false;
      } else if (code === 7) {
        this.style.inverse = true;
      } else if (code === 27) {
        this.style.inverse = false;
      } else if (code === 39) {
        this.style.fg = null;
      } else if (code === 49) {
        this.style.bg = null;
      } else if (code >= 30 && code <= 37) {
        this.style.fg = ANSI_16[code - 30];
      } else if (code >= 90 && code <= 97) {
        this.style.fg = ANSI_16[code - 90 + 8];
      } else if (code >= 40 && code <= 47) {
        this.style.bg = ANSI_16[code - 40];
      } else if (code >= 100 && code <= 107) {
        this.style.bg = ANSI_16[code - 100 + 8];
      } else if ((code === 38 || code === 48) && params[i + 1] === 5) {
        const color = xterm256Color(params[i + 2]);
        if (code === 38) {
          this.style.fg = color;
        } else {
          this.style.bg = color;
        }
        i += 2;
      } else if ((code === 38 || code === 48) && params[i + 1] === 2) {
        const r = clamp(params[i + 2] || 0, 0, 255).toString(16).padStart(2, "0");
        const g = clamp(params[i + 3] || 0, 0, 255).toString(16).padStart(2, "0");
        const b = clamp(params[i + 4] || 0, 0, 255).toString(16).padStart(2, "0");
        if (code === 38) {
          this.style.fg = `#${r}${g}${b}`;
        } else {
          this.style.bg = `#${r}${g}${b}`;
        }
        i += 4;
      }
    }
  }

  applyCsi(raw, final) {
    const params = parseParams(raw);
    const first = params[0] || 0;
    if (final === "m") {
      this.applySgr(params);
    } else if (final === "H" || final === "f") {
      this.cursor.row = clamp((params[0] || 1) - 1, 0, this.rows - 1);
      this.cursor.col = clamp((params[1] || 1) - 1, 0, this.cols - 1);
    } else if (final === "A") {
      this.cursor.row = clamp(this.cursor.row - (first || 1), 0, this.rows - 1);
    } else if (final === "B") {
      this.cursor.row = clamp(this.cursor.row + (first || 1), 0, this.rows - 1);
    } else if (final === "C") {
      this.cursor.col = clamp(this.cursor.col + (first || 1), 0, this.cols - 1);
    } else if (final === "D") {
      this.cursor.col = clamp(this.cursor.col - (first || 1), 0, this.cols - 1);
    } else if (final === "G") {
      this.cursor.col = clamp((first || 1) - 1, 0, this.cols - 1);
    } else if (final === "J") {
      if (first === 2 || first === 3) {
        this.clear();
      } else if (first === 1) {
        for (let row = 0; row < this.cursor.row; row += 1) {
          this.clearLine(row);
        }
        this.clearLine(this.cursor.row, 0, this.cursor.col);
      } else {
        this.clearLine(this.cursor.row, this.cursor.col, this.cols - 1);
        for (let row = this.cursor.row + 1; row < this.rows; row += 1) {
          this.clearLine(row);
        }
      }
    } else if (final === "K") {
      if (first === 2) {
        this.clearLine(this.cursor.row);
      } else if (first === 1) {
        this.clearLine(this.cursor.row, 0, this.cursor.col);
      } else {
        this.clearLine(this.cursor.row, this.cursor.col, this.cols - 1);
      }
    } else if (final === "s") {
      this.savedCursor = { ...this.cursor };
    } else if (final === "u") {
      this.cursor = { ...this.savedCursor };
    }
  }

  write(input) {
    const text = String(input ?? "");
    for (let i = 0; i < text.length;) {
      const ch = text[i];
      if (ch === ESC) {
        const next = text[i + 1];
        if (next === "[") {
          let j = i + 2;
          while (j < text.length && !/[\x40-\x7e]/.test(text[j])) {
            j += 1;
          }
          if (j < text.length) {
            this.applyCsi(text.slice(i + 2, j), text[j]);
            i = j + 1;
            continue;
          }
        } else if (next === "]") {
          const bel = text.indexOf(BEL, i + 2);
          const st = text.indexOf(`${ESC}\\`, i + 2);
          const end = bel === -1 ? st : st === -1 ? bel : Math.min(bel, st);
          i = end === -1 ? text.length : end + (end === st ? 2 : 1);
          continue;
        } else if (next === "(" || next === ")" || next === "%") {
          i += 3;
          continue;
        }
        i += 2;
        continue;
      }
      if (ch === "\r") {
        this.cursor.col = 0;
        i += 1;
      } else if (ch === "\n") {
        this.newline();
        i += 1;
      } else if (ch === "\b") {
        this.cursor.col = Math.max(0, this.cursor.col - 1);
        i += 1;
      } else if (ch === "\t") {
        this.cursor.col = Math.min(this.cols - 1, this.cursor.col + (8 - (this.cursor.col % 8)));
        i += 1;
      } else if (ch < " " || ch === "\x7f") {
        i += 1;
      } else {
        const code = text.codePointAt(i);
        const char = String.fromCodePoint(code);
        this.putChar(char);
        i += char.length;
      }
    }
    return this;
  }

  toHtml() {
    return this.cells.map((row) => {
      let html = "";
      let run = "";
      let runStyle = null;
      const flush = () => {
        if (run === "") {
          return;
        }
        const css = styleToCss(runStyle);
        html += css ? `<span style="${css}">${escapeHtml(run)}</span>` : escapeHtml(run);
        run = "";
      };
      for (const cell of row) {
        if (runStyle === null) {
          runStyle = cell.style;
        }
        if (!sameStyle(runStyle, cell.style)) {
          flush();
          runStyle = cell.style;
        }
        run += cell.ch;
      }
      flush();
      return html.replace(/\s+$/u, "");
    }).join("\n");
  }
}

export function parseCast(text) {
  const lines = String(text).split(/\r?\n/).filter((line) => line.trim() !== "");
  if (lines.length === 0) {
    throw new Error("empty asciinema cast");
  }
  let header;
  try {
    header = JSON.parse(lines[0]);
  } catch (error) {
    throw new Error(`invalid asciinema header: ${error.message}`);
  }
  if (header.version !== 2) {
    throw new Error(`unsupported asciinema version: ${header.version}`);
  }
  const events = [];
  for (let i = 1; i < lines.length; i += 1) {
    let event;
    try {
      event = JSON.parse(lines[i]);
    } catch (error) {
      throw new Error(`invalid asciinema event line ${i + 1}: ${error.message}`);
    }
    if (!Array.isArray(event) || event.length < 3 || event[1] !== "o") {
      continue;
    }
    events.push({ time: Number(event[0]) || 0, output: String(event[2]) });
  }
  return {
    format: "cast",
    cols: Math.max(1, Number.parseInt(header.width, 10) || 80),
    rows: Math.max(1, Number.parseInt(header.height, 10) || 24),
    duration: events.length === 0 ? 0 : events[events.length - 1].time,
    events,
  };
}

export function parseAnsi(text, options = {}) {
  return {
    format: "ansi",
    cols: Math.max(1, Number.parseInt(options.cols, 10) || 80),
    rows: Math.max(1, Number.parseInt(options.rows, 10) || 24),
    duration: 0,
    events: [{ time: 0, output: String(text ?? "") }],
  };
}

export function parseRecording(text, options = {}) {
  const format = options.format || "auto";
  if (format === "cast" || (format === "auto" && String(text).trimStart().startsWith("{\"version\""))) {
    return parseCast(text);
  }
  return parseAnsi(text, options);
}

export function renderRecordingFrame(recording, time = 0) {
  const screen = new AnsiScreen(recording.cols, recording.rows);
  const t = Math.max(0, Number(time) || 0);
  for (const event of recording.events) {
    if (event.time > t) {
      break;
    }
    screen.write(event.output);
  }
  return screen;
}

export function recordingToHtml(recording, time = 0) {
  return renderRecordingFrame(recording, time).toHtml();
}

const templateCss = `
:host{display:block;contain:content;color-scheme:dark light}
.frame{font:var(--strok-font,12px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace);background:var(--strok-bg,#050505);color:var(--strok-fg,#f4f4f4);border:1px solid var(--strok-border,#262626);border-radius:6px;overflow:auto}
pre{box-sizing:border-box;margin:0;padding:var(--strok-padding,12px);white-space:pre;tab-size:8}
.controls{display:flex;gap:8px;align-items:center;margin-top:6px;font:12px ui-sans-serif,system-ui,sans-serif;color:var(--strok-control-fg,#555)}
button{font:inherit;border:1px solid var(--strok-border,#bbb);border-radius:4px;background:var(--strok-button-bg,#fff);color:inherit;padding:2px 8px}
input[type=range]{flex:1;min-width:80px}
.hidden{display:none}
`;

export const StrokPlayerElement = typeof HTMLElement === "undefined" ? class {} : class extends HTMLElement {
  static observedAttributes = ["src", "format", "cols", "rows", "autoplay", "loop", "controls", "speed"];

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.recording = null;
    this.screen = null;
    this.eventIndex = 0;
    this.renderedTime = -1;
    this.currentTime = 0;
    this.playing = false;
    this.raf = 0;
    this.startedAt = 0;
    this.shadowRoot.innerHTML = `
      <style>${templateCss}</style>
      <div class="frame" part="frame"><pre part="screen" aria-live="off"></pre></div>
      <div class="controls hidden" part="controls">
        <button type="button" part="play">Play</button>
        <input part="timeline" type="range" min="0" max="0" value="0" step="0.001">
        <span part="time">0.000 / 0.000</span>
      </div>
    `;
    this.pre = this.shadowRoot.querySelector("pre");
    this.controlsEl = this.shadowRoot.querySelector(".controls");
    this.playButton = this.shadowRoot.querySelector("button");
    this.timeline = this.shadowRoot.querySelector("input");
    this.timeLabel = this.shadowRoot.querySelector("span");
    this.playButton.addEventListener("click", () => {
      if (this.playing) {
        this.pause();
      } else {
        this.play();
      }
    });
    this.timeline.addEventListener("input", () => {
      this.seek(Number(this.timeline.value) || 0);
    });
  }

  connectedCallback() {
    this.reload();
  }

  disconnectedCallback() {
    this.pause();
  }

  attributeChangedCallback() {
    if (this.isConnected) {
      this.reload();
    }
  }

  get duration() {
    return this.recording?.duration ?? 0;
  }

  get speed() {
    const value = Number(this.getAttribute("speed"));
    return Number.isFinite(value) && value > 0 ? value : 1;
  }

  async reload() {
    const source = this.getAttribute("src");
    try {
      const text = source ? await fetch(source).then((response) => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status} while loading ${source}`);
        }
        return response.text();
      }) : this.textContent;
      await this.load(text, {
        format: this.getAttribute("format") || "auto",
        cols: this.getAttribute("cols"),
        rows: this.getAttribute("rows"),
      });
    } catch (error) {
      this.pre.textContent = String(error?.message ?? error);
      this.dispatchEvent(new CustomEvent("strok-error", { detail: { error } }));
    }
  }

  async load(text, options = {}) {
    this.pause();
    this.recording = parseRecording(text, options);
    if (this.hasAttribute("cols")) {
      this.recording.cols = Math.max(1, Number.parseInt(this.getAttribute("cols"), 10) || this.recording.cols);
    }
    if (this.hasAttribute("rows")) {
      this.recording.rows = Math.max(1, Number.parseInt(this.getAttribute("rows"), 10) || this.recording.rows);
    }
    this.timeline.max = String(this.duration);
    this.controlsEl.classList.toggle("hidden", !this.hasAttribute("controls"));
    this.seek(0);
    this.dispatchEvent(new CustomEvent("strok-load", { detail: { recording: this.recording } }));
    if (this.hasAttribute("autoplay")) {
      this.play();
    }
  }

  renderAt(time) {
    if (!this.recording) {
      return;
    }
    const target = clamp(Number(time) || 0, 0, this.duration);
    if (!this.screen || target < this.renderedTime) {
      this.screen = new AnsiScreen(this.recording.cols, this.recording.rows);
      this.eventIndex = 0;
      this.renderedTime = 0;
    }
    while (this.eventIndex < this.recording.events.length && this.recording.events[this.eventIndex].time <= target) {
      this.screen.write(this.recording.events[this.eventIndex].output);
      this.eventIndex += 1;
    }
    this.currentTime = target;
    this.renderedTime = target;
    this.pre.innerHTML = this.screen.toHtml();
    this.timeline.value = String(target);
    this.timeLabel.textContent = `${target.toFixed(3)} / ${this.duration.toFixed(3)}`;
    this.dispatchEvent(new CustomEvent("strok-timeupdate", { detail: { currentTime: target, duration: this.duration } }));
  }

  play() {
    if (!this.recording || this.playing) {
      return;
    }
    if (this.duration === 0) {
      this.renderAt(0);
      return;
    }
    this.playing = true;
    this.playButton.textContent = "Pause";
    this.startedAt = performance.now() / 1000 - this.currentTime / this.speed;
    const tick = () => {
      if (!this.playing) {
        return;
      }
      const nextTime = (performance.now() / 1000 - this.startedAt) * this.speed;
      if (nextTime >= this.duration) {
        if (this.hasAttribute("loop")) {
          this.seek(0);
          this.startedAt = performance.now() / 1000;
        } else {
          this.seek(this.duration);
          this.pause();
          this.dispatchEvent(new CustomEvent("strok-ended"));
          return;
        }
      } else {
        this.renderAt(nextTime);
      }
      this.raf = requestAnimationFrame(tick);
    };
    this.raf = requestAnimationFrame(tick);
  }

  pause() {
    this.playing = false;
    this.playButton.textContent = "Play";
    if (this.raf) {
      cancelAnimationFrame(this.raf);
      this.raf = 0;
    }
  }

  seek(time) {
    this.renderAt(time);
    if (this.playing) {
      this.startedAt = performance.now() / 1000 - this.currentTime / this.speed;
    }
  }
};

export function defineStrokPlayer(tagName = "strok-player") {
  if (typeof customElements === "undefined") {
    return undefined;
  }
  if (customElements.get(tagName)) {
    return customElements.get(tagName);
  }
  customElements.define(tagName, StrokPlayerElement);
  return StrokPlayerElement;
}

if (typeof window !== "undefined" && typeof window.customElements !== "undefined") {
  defineStrokPlayer();
}
