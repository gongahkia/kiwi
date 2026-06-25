import initWasm, { render as renderWasm } from "./pkg/kumeyuri_render_wasm.js";

const source = document.querySelector("#playground-source");
const output = document.querySelector("#playground-output");
const status = document.querySelector("#playground-status");
const theme = document.querySelector("#playground-theme");
const animate = document.querySelector("#playground-animate");
const speed = document.querySelector("#playground-speed");
const compat = document.querySelector("#playground-compat");
const snippet = document.querySelector("#playground-snippet");
const copy = document.querySelector("#playground-copy");
const download = document.querySelector("#playground-download");
const statusCompat = document.querySelector("#status-compat");
const statusWasm = document.querySelector("#status-wasm");

let renderToken = 0;
let lastSvg = "";
let compatReport;

const params = new URLSearchParams(window.location.search);
const initialSource = params.get("source");
if (initialSource) {
  source.value = initialSource;
}

compatReport = await fetchJson("./compat.json");
const statusData = await fetchJson("./status.json");
updateStatusBoard(statusData);
await initWasm();
renderNow();

for (const control of [source, theme, animate, speed]) {
  control.addEventListener("input", queueRender);
}
copy.addEventListener("click", copyEmbed);
download.addEventListener("click", downloadSvg);

function queueRender() {
  const token = ++renderToken;
  window.setTimeout(() => {
    if (token === renderToken) {
      renderNow();
    }
  }, 80);
}

function renderNow() {
  try {
    const options = {
      theme: theme.value,
      darkTheme: "tokyo-night",
      speed: Number(speed.value),
      svgAnimation: "css-keyframes",
    };
    const result = renderWasm(withAnimationDirective(source.value, animate.value), options);
    lastSvg = result.svg;
    output.innerHTML = result.svg;
    status.textContent = `${result.frames.length} frames`;
    compat.textContent = compatText(source.value);
    snippet.textContent = embedSnippet();
    output.removeAttribute("data-error");
  } catch (error) {
    lastSvg = "";
    output.textContent = "";
    output.dataset.error = "true";
    status.textContent = error instanceof Error ? error.message : String(error);
    compat.textContent = compatText(source.value);
    snippet.textContent = embedSnippet();
  }
}

function withAnimationDirective(value, mode) {
  if (mode === "none") {
    return `%%{ animate: 'none' }%%\n${value}`;
  }
  return `%%{ animate: '${mode}' }%%\n${value}`;
}

async function fetchJson(path) {
  try {
    const response = await fetch(path);
    return response.ok ? await response.json() : undefined;
  } catch {
    return undefined;
  }
}

function updateStatusBoard(data) {
  if (!data) {
    return;
  }
  if (statusCompat && data.compat) {
    statusCompat.textContent = `${data.compat.families} families; ${data.compat.rootSpellings} root spellings; ${data.compat.animatedPartial} animated; ${data.compat.staticOnlyPartial} static-only`;
  }
  if (statusWasm && data.wasm) {
    statusWasm.textContent = `${data.wasm.gzipBytes.toLocaleString()} / ${data.wasm.gzipBudget.toLocaleString()} bytes`;
  }
}

function compatText(value) {
  const root = detectRoot(value);
  if (!root) {
    return "Compatibility: add a Mermaid root to check support.";
  }
  const entry = compatReport?.roots?.find((item) => item.roots.includes(root));
  if (!entry) {
    return `Compatibility: ${root} is not in the tracked matrix.`;
  }
  return `Compatibility: ${entry.label} is ${entry.support}; ${entry.caveat}`;
}

function detectRoot(value) {
  for (const rawLine of value.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("%%") || line.startsWith("---")) {
      continue;
    }
    if (line.startsWith("graph ")) {
      return "graph";
    }
    if (line.startsWith("flowchart ")) {
      return "flowchart";
    }
    return line.split(/\s+/, 1)[0];
  }
  return "";
}

function embedSnippet() {
  return `<kumeyuri-diagram animate="${animate.value}" theme="${theme.value}" speed="${speed.value}" controls csp max-source-bytes="200000" fetch-timeout-ms="5000">
  <script type="text/plain" data-kumeyuri-source>
${source.value.replaceAll("</script", "<\\/script")}
  </script>
</kumeyuri-diagram>`;
}

async function copyEmbed() {
  const text = embedSnippet();
  await navigator.clipboard?.writeText(text);
  status.textContent = "Embed copied";
}

function downloadSvg() {
  if (!lastSvg) {
    status.textContent = "Render a valid diagram before downloading SVG";
    return;
  }
  const url = URL.createObjectURL(new Blob([lastSvg], { type: "image/svg+xml" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "kumeyuri-diagram.svg";
  anchor.click();
  URL.revokeObjectURL(url);
}
