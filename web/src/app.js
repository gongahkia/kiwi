import {
  DEFAULTS,
  EFFECTS,
  PALETTES,
  normalizeOptions,
  rendererOptions,
  cellsToText,
  cameraErrorMessage,
  fitRect,
} from "./model.js";
import { paintCells, makePrint } from "./paint.js";
import { paintDemo } from "./demo.js";

const $ = (id) => document.getElementById(id);
const output = $("output"),
  video = $("video"),
  input = document.createElement("canvas");
const inputContext = input.getContext("2d", { willReadFrequently: true });
let options = { ...DEFAULTS };
let ready = false,
  busy = false,
  failed = false,
  paused = false,
  dirty = true;
let source = "demo",
  photo = null,
  stream = null,
  cameraPending = false,
  facing = "user";
let epoch = 0,
  sourceToken = 0,
  frameId = 0,
  lastFrame = null,
  captureController = null,
  strip = false;
let renderTime = 80,
  loopTimer,
  frameTimeout,
  loadingTimeout,
  number = 0,
  uploadUrl = null;
const gallery = [];
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
let worker;

function notify(message = "", kind = "info") {
  $("notice").textContent = message;
  $("notice").dataset.kind = kind;
  $("notice").hidden = !message;
}

function setSourceLabels() {
  $("source-label").textContent =
    source === "camera"
      ? "LIVE CAMERA"
      : source === "photo"
        ? "YOUR PHOTO"
        : "DEMO STUDIO";
  $("source-dot").classList.toggle("live", source === "camera");
  $("camera-label").textContent = cameraPending
    ? "Opening camera…"
    : source === "camera"
      ? "Stop camera"
      : "Start camera";
  $("camera-tools").hidden = source !== "camera";
  $("preview-info").textContent =
    source === "camera"
      ? "Live from your camera. Never leaves this device."
      : source === "photo"
        ? "Your photo, processed on this device."
        : "A generated demo. Your camera is off.";
  output.setAttribute(
    "aria-label",
    `${EFFECTS[options.effect]} character art preview from ${source === "camera" ? "your camera" : source === "photo" ? "your uploaded photo" : "a generated animated still life"}.`,
  );
}

function updateButtons() {
  const capturing = Boolean(captureController);
  $("camera").disabled = !ready || capturing || cameraPending;
  $("upload").disabled = !ready || capturing;
  $("switch-camera").disabled = !ready || capturing || cameraPending;
  $("pause").disabled = !ready || !lastFrame || capturing;
  $("shutter").disabled = !ready || !lastFrame;
  $("capture-format").disabled = capturing;
  $("timer").disabled = capturing;
  for (const element of document.querySelectorAll(
    ".controls fieldset button, .controls fieldset input, #mirror, #demo",
  ))
    element.disabled = !ready || capturing;
  const structural = options.effect === 0 || options.effect === 2;
  $("edge").disabled = !ready || capturing || !structural;
  $("contrast").disabled = !ready || capturing || !structural;
  $("stable").disabled = !ready || capturing || options.effect !== 0;
  $("shutter-label").textContent = capturing
    ? "Cancel"
    : strip
      ? "Take a photo strip"
      : "Take a photo";
  $("pause").setAttribute("aria-pressed", String(paused));
  $("pause-label").textContent = paused ? "Unfreeze" : "Freeze";
  $("pause-symbol").textContent = paused ? "▷" : "Ⅱ";
  setSourceLabels();
}

function invalidate() {
  epoch++;
  dirty = true;
  lastFrame = null;
  if (ready) worker.postMessage({ type: "reset" });
  updateButtons();
}

function stopTracks() {
  const active = stream;
  stream = null;
  if (active) active.getTracks().forEach((track) => track.stop());
  video.pause();
  video.srcObject = null;
}

function cancelCapture() {
  captureController?.abort();
}

function useDemo({ message = "" } = {}) {
  sourceToken++;
  cameraPending = false;
  cancelCapture();
  stopTracks();
  if (photo) photo.close?.();
  photo = null;
  if (uploadUrl) {
    URL.revokeObjectURL(uploadUrl);
    uploadUrl = null;
  }
  source = "demo";
  paused = false;
  invalidate();
  notify(message);
}

async function openCamera(switching = false) {
  if (!ready || captureController || cameraPending) return;
  if (source === "camera" && !switching) {
    useDemo();
    return;
  }
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    notify(
      "Camera access needs a browser with camera support over HTTPS (or localhost). You can upload a photo instead.",
      "error",
    );
    return;
  }
  const token = ++sourceToken;
  if (switching) {
    stopTracks();
    source = "demo";
    invalidate();
  }
  cameraPending = true;
  updateButtons();
  notify("Waiting for camera access. Your browser may ask for permission.");
  let candidate;
  try {
    candidate = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: { ideal: facing },
        width: { ideal: 640 },
        height: { ideal: 480 },
      },
    });
    if (token !== sourceToken) {
      candidate.getTracks().forEach((track) => track.stop());
      return;
    }
    stopTracks();
    stream = candidate;
    video.srcObject = candidate;
    await Promise.race([
      video.play(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Camera playback timed out")), 15000),
      ),
    ]);
    if (token !== sourceToken) {
      candidate.getTracks().forEach((track) => track.stop());
      return;
    }
    const track = stream.getVideoTracks()[0];
    track.addEventListener(
      "ended",
      () => {
        if (stream === candidate)
          useDemo({
            message:
              "Your camera disconnected. You can reconnect it or upload a photo.",
          });
      },
      { once: true },
    );
    if (photo) photo.close?.();
    photo = null;
    source = "camera";
    paused = false;
    cameraPending = false;
    $("mirror").checked = facing === "user";
    invalidate();
    notify();
  } catch (error) {
    candidate?.getTracks().forEach((track) => track.stop());
    if (token !== sourceToken) return;
    stopTracks();
    cameraPending = false;
    if (source === "camera") source = "demo";
    updateButtons();
    notify(cameraErrorMessage(error), "error");
  }
}

async function loadPhoto(file) {
  if (!file || !ready || captureController) return;
  if (
    !file.type.startsWith("image/") &&
    !/\.(jpe?g|png|webp|gif|avif|heic|heif)$/i.test(file.name)
  ) {
    notify("Choose an image such as a JPEG, PNG, or WebP photo.", "error");
    return;
  }
  if (file.size > 25 * 1024 * 1024) {
    notify("That photo is larger than 25 MB. Choose a smaller image.", "error");
    return;
  }
  const token = ++sourceToken;
  cameraPending = false;
  const url = URL.createObjectURL(file);
  let image;
  notify("Opening your photo on this device…");
  try {
    image = new Image();
    image.src = url;
    await image.decode();
    if (token !== sourceToken) return;
    if (image.naturalWidth * image.naturalHeight > 60_000_000)
      throw new Error("image-too-large");
    stopTracks();
    if (photo) photo.close?.();
    photo = image;
    source = "photo";
    paused = false;
    if (uploadUrl) URL.revokeObjectURL(uploadUrl);
    uploadUrl = url;
    invalidate();
    notify();
  } catch (error) {
    if (token === sourceToken)
      notify(
        error.message === "image-too-large"
          ? "That image is too large to process comfortably. Choose a photo under 60 megapixels."
          : "This browser couldn’t open that image. Try a JPEG, PNG, or WebP photo. Animated images are used as a still.",
        "error",
      );
  } finally {
    if (uploadUrl !== url) URL.revokeObjectURL(url);
    $("file").value = "";
    updateButtons();
  }
}

function prepareSource() {
  // Bound camera readback and native analysis work independently of export size.
  const width = Math.min(288, options.columns * 2),
    height = Math.round(width * 0.75);
  if (input.width !== width || input.height !== height) {
    input.width = width;
    input.height = height;
  }
  if (source === "demo") {
    paintDemo(input, reducedMotion ? 1.8 : performance.now() / 1000);
    return;
  }
  const item = source === "camera" ? video : photo;
  const sourceWidth =
    source === "camera" ? video.videoWidth : photo?.naturalWidth;
  const sourceHeight =
    source === "camera" ? video.videoHeight : photo?.naturalHeight;
  if (!item || !sourceWidth || !sourceHeight)
    throw new Error("Waiting for a source image");
  const rect = fitRect(
    sourceWidth,
    sourceHeight,
    width,
    height,
    source === "camera",
  );
  inputContext.fillStyle = "#000";
  inputContext.fillRect(0, 0, width, height);
  inputContext.save();
  if (source === "camera" && $("mirror").checked) {
    inputContext.translate(width, 0);
    inputContext.scale(-1, 1);
  }
  inputContext.drawImage(item, rect.x, rect.y, rect.width, rect.height);
  inputContext.restore();
}

function requestFrame() {
  if (
    !ready ||
    busy ||
    document.hidden ||
    (!dirty &&
      (paused || source === "photo" || (source === "demo" && reducedMotion)))
  )
    return;
  try {
    prepareSource();
    const rgba = inputContext.getImageData(0, 0, input.width, input.height).data
      .buffer;
    busy = true;
    dirty = false;
    worker.postMessage(
      {
        type: "render",
        id: ++frameId,
        epoch,
        rgba,
        width: input.width,
        height: input.height,
        options,
      },
      [rgba],
    );
    frameTimeout = setTimeout(
      () =>
        fatal(
          "The character engine stopped responding. Try reloading the booth.",
        ),
      30000,
    );
  } catch (error) {
    if (source !== "camera") notify(error.message, "error");
  }
}

function loop() {
  requestFrame();
  loopTimer = setTimeout(loop, Math.max(65, Math.min(350, renderTime * 1.2)));
}

function fatal(message) {
  if (failed) return;
  failed = true;
  ready = false;
  busy = false;
  clearTimeout(loadingTimeout);
  clearTimeout(frameTimeout);
  clearTimeout(loopTimer);
  cancelCapture();
  stopTracks();
  worker?.terminate();
  const loading = $("engine-loading");
  loading.hidden = false;
  loading.classList.add("failed");
  loading.replaceChildren();
  const text = document.createElement("p");
  text.textContent = message;
  const retry = document.createElement("button");
  retry.type = "button";
  retry.textContent = "Reload the booth";
  retry.addEventListener("click", () => location.reload());
  const link = document.createElement("a");
  link.href = "https://github.com/gongahkia/strok";
  link.textContent = "Explore the native SDK ↗";
  loading.append(text, retry, link);
  document.body.dataset.engine = "error";
  updateButtons();
}

function delay(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(new DOMException("Cancelled", "AbortError"));
      return;
    }
    const cancel = () => {
      clearTimeout(timer);
      reject(new DOMException("Cancelled", "AbortError"));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", cancel);
      resolve();
    }, ms);
    signal.addEventListener("abort", cancel, { once: true });
  });
}

async function awaitCurrentFrame(signal) {
  for (let attempt = 0; attempt < 200; attempt++) {
    if (lastFrame?.epoch === epoch) return lastFrame;
    dirty = true;
    requestFrame();
    await delay(50, signal);
  }
  throw new Error(
    "We couldn’t capture a frame. Try again or choose a lower character density.",
  );
}

async function countdown(seconds, signal, shot, total) {
  for (let remaining = seconds; remaining > 0; remaining--) {
    $("countdown").hidden = false;
    $("countdown").textContent = String(remaining);
    if (total > 1)
      $("study-number").textContent = `strip / ${shot} of ${total}`;
    await delay(1000, signal);
  }
  $("countdown").hidden = true;
}

function canvasBlob(canvas) {
  return new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) =>
        blob ? resolve(blob) : reject(new Error("Unable to save this photo")),
      "image/png",
    ),
  );
}

async function capture() {
  if (captureController) {
    cancelCapture();
    return;
  }
  if (!ready || !lastFrame) return;
  const controller = new AbortController(),
    { signal } = controller;
  captureController = controller;
  const frames = [],
    total = strip ? 3 : 1,
    look = { ...options };
  updateButtons();
  notify();
  try {
    for (let shot = 1; shot <= total; shot++) {
      await countdown(
        shot === 1
          ? Number($("timer").value)
          : Math.max(1, Number($("timer").value)),
        signal,
        shot,
        total,
      );
      const current = await awaitCurrentFrame(signal);
      if (signal.aborted) throw new DOMException("Cancelled", "AbortError");
      frames.push({ ...current, cells: current.cells.slice() });
      $("flash").classList.remove("fired");
      void $("flash").offsetWidth;
      $("flash").classList.add("fired");
      if (shot < total) await delay(200, signal);
    }
    const printNumber = number + 1,
      date = new Date();
    const canvas = makePrint(frames, {
      palette: look.palette,
      effect: EFFECTS[look.effect],
      number: printNumber,
      date,
    });
    const blob = await canvasBlob(canvas);
    if (signal.aborted) throw new DOMException("Cancelled", "AbortError");
    number = printNumber;
    const text = frames
      .map((frame) => cellsToText(frame.cells, frame.columns, frame.rows))
      .join("\n\n");
    const entry = {
      number,
      blob,
      url: URL.createObjectURL(blob),
      textUrl: URL.createObjectURL(
        new Blob([text], { type: "text/plain;charset=utf-8" }),
      ),
      effect: EFFECTS[look.effect],
      strip: total > 1,
      filename: `strok-${total > 1 ? "strip" : "photo"}-${String(number).padStart(3, "0")}.png`,
    };
    gallery.unshift(entry);
    if (gallery.length > 12) releaseEntry(gallery.pop());
    renderGallery();
    notify(
      total > 1
        ? "Three little moments, one photo strip. Your strip is ready below."
        : "A little more character, captured. Your photo is ready below.",
    );
  } catch (error) {
    if (error.name === "AbortError")
      notify("Capture cancelled. Ready when you are.");
    else
      notify(
        error.message || "We couldn’t save that photo. Please try again.",
        "error",
      );
  } finally {
    captureController = null;
    $("countdown").hidden = true;
    $("study-number").textContent =
      `study no. ${String(number + 1).padStart(3, "0")}`;
    updateButtons();
  }
}

function releaseEntry(entry) {
  URL.revokeObjectURL(entry.url);
  URL.revokeObjectURL(entry.textUrl);
}

async function sharePhoto(entry, button) {
  const file = new File([entry.blob], entry.filename, { type: "image/png" });
  try {
    if (navigator.canShare?.({ files: [file] }))
      await navigator.share({
        files: [file],
        title: "A little more character — strok",
      });
    else {
      const link = document.createElement("a");
      link.href = entry.url;
      link.download = entry.filename;
      link.click();
    }
  } catch (error) {
    if (error.name !== "AbortError") {
      button.textContent = "Try PNG instead";
      notify(
        "Sharing isn’t available here. Use the PNG download to save your photo.",
        "error",
      );
    }
  }
}

function renderGallery() {
  const container = $("gallery");
  container.replaceChildren();
  $("photos").hidden = gallery.length === 0;
  for (const entry of gallery) {
    const card = document.createElement("article");
    card.className = "photo-card";
    const image = new Image();
    image.src = entry.url;
    image.alt = `${entry.effect} character art ${entry.strip ? "three-photo strip" : "photo"}, number ${entry.number}`;
    const meta = document.createElement("div");
    meta.className = "photo-meta";
    const label = document.createElement("span");
    label.textContent = entry.effect.toUpperCase();
    const serial = document.createElement("span");
    serial.textContent = `NO. ${String(entry.number).padStart(3, "0")}`;
    meta.append(label, serial);
    const actions = document.createElement("div");
    actions.className = "photo-actions";
    const png = document.createElement("a");
    png.href = entry.url;
    png.download = entry.filename;
    png.textContent = "Save PNG ↓";
    png.setAttribute("aria-label", `Save photo ${entry.number} as PNG`);
    const text = document.createElement("a");
    text.href = entry.textUrl;
    text.download = entry.filename.replace(".png", ".txt");
    text.textContent = "Text ↓";
    text.setAttribute("aria-label", `Save photo ${entry.number} as text`);
    const share = document.createElement("button");
    share.type = "button";
    share.textContent = "Share ↗";
    share.setAttribute("aria-label", `Share photo ${entry.number}`);
    share.addEventListener("click", () => sharePhoto(entry, share));
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "Remove";
    remove.setAttribute("aria-label", `Remove photo ${entry.number}`);
    remove.addEventListener("click", () => {
      gallery.splice(gallery.indexOf(entry), 1);
      releaseEntry(entry);
      renderGallery();
      $("shutter").focus();
    });
    actions.append(png, text, share, remove);
    card.append(image, meta, actions);
    container.append(card);
  }
}

function setOptions(next, repaintOnly = false) {
  options = normalizeOptions({ ...options, ...next });
  if (repaintOnly) {
    if (lastFrame) paintCells(output, lastFrame, options.palette);
  } else invalidate();
  setSourceLabels();
}

$("camera").addEventListener("click", () => openCamera());
$("switch-camera").addEventListener("click", () => {
  facing = facing === "user" ? "environment" : "user";
  openCamera(true);
});
$("mirror").addEventListener("change", invalidate);
$("upload").addEventListener("click", () => $("file").click());
$("file").addEventListener("change", () => loadPhoto($("file").files?.[0]));
$("demo").addEventListener("click", () => useDemo());
$("pause").addEventListener("click", () => {
  paused = !paused;
  updateButtons();
});
$("effects").addEventListener("click", (event) => {
  const button = event.target.closest("[data-effect]");
  if (!button || button.disabled) return;
  for (const item of $("effects").querySelectorAll("button")) {
    const active = item === button;
    item.classList.toggle("active", active);
    item.setAttribute("aria-pressed", String(active));
  }
  setOptions({ effect: Number(button.dataset.effect) });
});
$("palettes").addEventListener("click", (event) => {
  const button = event.target.closest("[data-palette]");
  if (!button || button.disabled) return;
  for (const item of $("palettes").querySelectorAll("button")) {
    const active = item === button;
    item.classList.toggle("active", active);
    item.setAttribute("aria-pressed", String(active));
  }
  $("palette-name").textContent = PALETTES[button.dataset.palette].name;
  setOptions({ palette: button.dataset.palette }, true);
});
for (const [id, name] of [
  ["detail", "columns"],
  ["edge", "edge"],
  ["contrast", "contrast"],
]) {
  $(id).addEventListener("input", () => {
    $(`${id}-value`).value = $(id).value;
    setOptions({ [name]: Number($(id).value) });
  });
}
$("stable").addEventListener("change", () =>
  setOptions({ stable: $("stable").checked }),
);
$("reset").addEventListener("click", () => {
  options = { ...DEFAULTS };
  for (const [id, value] of [
    ["detail", 96],
    ["edge", 50],
    ["contrast", 0],
  ]) {
    $(id).value = value;
    $(`${id}-value`).value = value;
  }
  $("stable").checked = true;
  for (const item of $("effects").querySelectorAll("button")) {
    const active = item.dataset.effect === "0";
    item.classList.toggle("active", active);
    item.setAttribute("aria-pressed", String(active));
  }
  for (const item of $("palettes").querySelectorAll("button")) {
    const active = item.dataset.palette === "original";
    item.classList.toggle("active", active);
    item.setAttribute("aria-pressed", String(active));
  }
  $("palette-name").textContent = PALETTES.original.name;
  invalidate();
});
$("shutter").addEventListener("click", capture);
$("capture-format").addEventListener("click", () => {
  strip = !strip;
  $("capture-format").setAttribute("aria-pressed", String(strip));
  $("format-label").textContent = strip ? "Strip ×3" : "Single";
  updateButtons();
});
$("clear-photos").addEventListener("click", () => {
  gallery.forEach(releaseEntry);
  gallery.length = 0;
  renderGallery();
  $("shutter").focus();
});
$("fullscreen").addEventListener("click", async () => {
  const finder = $("viewfinder");
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else if (finder.requestFullscreen) await finder.requestFullscreen();
    else finder.classList.toggle("expanded");
  } catch {
    finder.classList.toggle("expanded");
  }
  $("fullscreen").setAttribute(
    "aria-label",
    document.fullscreenElement || finder.classList.contains("expanded")
      ? "Close expanded preview"
      : "Expand preview",
  );
});
document.addEventListener("fullscreenchange", () =>
  $("fullscreen").setAttribute(
    "aria-label",
    document.fullscreenElement ? "Close expanded preview" : "Expand preview",
  ),
);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    $("viewfinder").classList.remove("expanded");
    cancelCapture();
  }
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    cancelCapture();
    if (stream || cameraPending)
      useDemo({
        message:
          "Your camera was stopped while this tab was hidden. Start it again when you’re ready.",
      });
  } else dirty = true;
});
window.addEventListener("pagehide", () => {
  sourceToken++;
  cancelCapture();
  stopTracks();
  clearTimeout(loopTimer);
  worker?.terminate();
});
window.addEventListener("pageshow", (event) => {
  if (event.persisted) location.reload();
});

async function initialize() {
  updateButtons();
  document.body.dataset.engine = "loading";
  if (typeof WebAssembly !== "object" || typeof Worker !== "function") {
    fatal(
      "This browser can’t run the character engine. Try an up-to-date browser, or explore the native SDK.",
    );
    return;
  }
  loadingTimeout = setTimeout(
    () =>
      fatal(
        "The character engine is taking too long to load. Check your connection, then reload the booth.",
      ),
    45000,
  );
  try {
    const fontReady = document.fonts.load('16px "Strok Mono"').catch(() => {
      fatal(
        "The character font could not load. Check your connection and reload the booth.",
      );
    });
    worker = new Worker(new URL("./worker.js", import.meta.url), {
      type: "module",
    });
    worker.onerror = () =>
      fatal(
        "The character engine could not start. Check your connection and reload the booth.",
      );
    worker.onmessage = async ({ data }) => {
      if (failed) return;
      if (data.type === "ready") {
        await fontReady;
        if (failed) return;
        ready = true;
        document.body.dataset.engine = "ready";
        clearTimeout(loadingTimeout);
        updateButtons();
        loop();
      } else if (data.type === "frame") {
        clearTimeout(frameTimeout);
        busy = false;
        if (data.epoch !== epoch) return;
        lastFrame = { ...data, cells: new Uint32Array(data.cells) };
        renderTime = data.renderMs;
        paintCells(output, lastFrame, options.palette);
        $("engine-loading").hidden = true;
        output.dataset.frame = String(data.id);
        const config = rendererOptions(options);
        $("render-label").textContent =
          `${EFFECTS[options.effect].toUpperCase()} / ${config.columns} × ${config.rows}`;
        updateButtons();
      } else if (data.type === "error") {
        clearTimeout(frameTimeout);
        busy = false;
        if (data.fatal) fatal(data.message);
        else if (data.epoch === epoch) {
          notify(data.message, "error");
          paused = true;
          updateButtons();
        }
      }
    };
  } catch {
    fatal(
      "The character engine could not start. Check your connection and reload the booth.",
    );
  }
}

initialize();
