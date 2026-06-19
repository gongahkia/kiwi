import initWasm, { render as renderWasm } from "./pkg/kumeyuri_render_wasm.js";

const source = document.querySelector("#playground-source");
const output = document.querySelector("#playground-output");
const status = document.querySelector("#playground-status");
const theme = document.querySelector("#playground-theme");
const animate = document.querySelector("#playground-animate");
const speed = document.querySelector("#playground-speed");

let renderToken = 0;

const params = new URLSearchParams(window.location.search);
const initialSource = params.get("source");
if (initialSource) {
  source.value = initialSource;
}

await initWasm();
renderNow();

for (const control of [source, theme, animate, speed]) {
  control.addEventListener("input", queueRender);
}

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
    output.innerHTML = result.svg;
    status.textContent = `${result.frames.length} frames`;
    output.removeAttribute("data-error");
  } catch (error) {
    output.textContent = "";
    output.dataset.error = "true";
    status.textContent = error instanceof Error ? error.message : String(error);
  }
}

function withAnimationDirective(value, mode) {
  if (mode === "none") {
    return `%%{ animate: 'none' }%%\n${value}`;
  }
  return `%%{ animate: '${mode}' }%%\n${value}`;
}
