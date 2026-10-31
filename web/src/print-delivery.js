// A single capture delivery: camera jitter, paper feed, then placement in the gallery.
// The saved photo already exists; cancelling motion never discards the capture.
async function play(element, frames, options, signal) {
  if (signal.aborted) return;
  const animation = element.animate(frames, options);
  const cancel = () => animation.cancel();
  signal.addEventListener("abort", cancel, { once: true });
  try {
    await animation.finished;
  } catch {
    /* Motion can be interrupted. */
  } finally {
    signal.removeEventListener("abort", cancel);
  }
}

export async function deliverPrint({
  url,
  width,
  height,
  card,
  signal,
  reducedMotion,
}) {
  if (reducedMotion || signal.aborted) return;
  const stage = document.createElement("div");
  stage.className = "print-delivery";
  stage.setAttribute("aria-hidden", "true");
  const window = document.createElement("div");
  window.className = "print-window";
  const receipt = new Image();
  receipt.className = "print-receipt";
  receipt.alt = "";
  receipt.src = url;
  const paperWidth = Math.min(
    240,
    innerWidth - 64,
    (innerHeight * 0.52 * width) / height,
  );
  stage.style.setProperty("--receipt-width", `${paperWidth}px`);
  window.append(receipt);
  const slot = document.createElement("div");
  slot.className = "print-slot";
  stage.append(window, slot);
  let flying;
  card.classList.add("delivering");
  document.body.dataset.printing = "jitter";
  try {
    await receipt.decode();
    if (signal.aborted) return;
    document.body.append(stage);
    await play(
      document.querySelector("#output"),
      [
        { transform: "translate(0,0)" },
        { transform: "translate(-2px,1px)" },
        { transform: "translate(2px,-1px)" },
        { transform: "translate(-1px,0)" },
        { transform: "translate(0,0)" },
      ],
      { duration: 180, easing: "linear" },
      signal,
    );
    document.body.dataset.printing = "feeding";
    await play(
      receipt,
      [{ transform: "translateY(105%)" }, { transform: "translateY(0)" }],
      { duration: 1100, easing: "steps(24, end)", fill: "forwards" },
      signal,
    );
    document.body.dataset.printing = "deposited";
    await play(
      window,
      [
        { transform: "translateX(0)" },
        { transform: "translateX(-1px)" },
        { transform: "translateX(1px)" },
        { transform: "translateX(0)" },
      ],
      { duration: 180, easing: "linear" },
      signal,
    );
    if (signal.aborted) return;
    document
      .querySelector("#photos")
      .scrollIntoView({ block: "start", behavior: "instant" });
    const destination = card.querySelector("img");
    await destination.decode();
    if (signal.aborted) return;
    const from = receipt.getBoundingClientRect();
    const bounds = destination.getBoundingClientRect();
    // Mobile strips use object-fit: contain inside a bounded preview. Land on
    // the painted paper, not the surrounding letterbox, to avoid a final jump.
    const scale = Math.min(
      bounds.width / destination.naturalWidth,
      bounds.height / destination.naturalHeight,
    );
    const to = {
      width: destination.naturalWidth * scale,
      height: destination.naturalHeight * scale,
    };
    to.left = bounds.left + (bounds.width - to.width) / 2;
    to.top = bounds.top + (bounds.height - to.height) / 2;
    flying = receipt.cloneNode();
    flying.className = "print-flight";
    Object.assign(flying.style, {
      left: `${from.left}px`,
      top: `${from.top}px`,
      width: `${from.width}px`,
      height: `${from.height}px`,
    });
    document.body.append(flying);
    stage.remove();
    document.body.dataset.printing = "placing";
    await play(
      flying,
      [
        { transform: "translate(0,0) scale(1,1)" },
        {
          transform: `translate(${to.left - from.left}px,${to.top - from.top}px) scale(${to.width / from.width},${to.height / from.height})`,
        },
      ],
      { duration: 460, easing: "cubic-bezier(.2,.7,.2,1)", fill: "forwards" },
      signal,
    );
  } finally {
    card.classList.remove("delivering");
    stage.remove();
    flying?.remove();
    delete document.body.dataset.printing;
  }
}
