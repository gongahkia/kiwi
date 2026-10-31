// Stylized, procedural planets. These source pixels go through the real C++
// renderer, just like camera frames; no images or external requests are used.
export const PLANETS = [
  { name: "Saturn", color: [221, 185, 124], kind: "saturn" },
  { name: "Mercury", color: [165, 157, 143], kind: "rock" },
  { name: "Venus", color: [231, 181, 103], kind: "cloud" },
  { name: "Earth", color: [51, 120, 187], kind: "earth" },
  { name: "Mars", color: [199, 97, 59], kind: "mars" },
  { name: "Jupiter", color: [219, 175, 137], kind: "gas" },
  { name: "Uranus", color: [133, 211, 218], kind: "ice" },
  { name: "Neptune", color: [55, 99, 220], kind: "blue" },
];
export const PLANET_SECONDS = 10;
const TRANSITION_SECONDS = 1.4;
const surfaces = new WeakMap();

export function demoState(time) {
  const elapsed = Math.max(0, time);
  const index = Math.floor(elapsed / PLANET_SECONDS) % PLANETS.length;
  const phase = elapsed % PLANET_SECONDS;
  const blend = Math.max(
    0,
    (phase - (PLANET_SECONDS - TRANSITION_SECONDS)) / TRANSITION_SECONDS,
  );
  return {
    index,
    next: (index + 1) % PLANETS.length,
    blend: blend * blend * (3 - 2 * blend),
  };
}

function texture(planet, latitude, longitude) {
  const wave = Math.sin(latitude * 19 + Math.sin(longitude * 3) * 0.8);
  const detail =
    Math.sin(longitude * 13 + Math.cos(latitude * 11)) *
    Math.cos(latitude * 23);
  let color = planet.color;
  let brightness = 1;
  switch (planet.kind) {
    case "saturn":
      brightness = 0.87 + 0.13 * Math.sin(latitude * 27) + 0.04 * detail;
      break;
    case "rock":
      brightness =
        0.77 + 0.18 * detail + 0.14 * Math.sin(longitude * 23 + latitude * 31);
      break;
    case "cloud":
      brightness =
        0.85 +
        0.12 *
          Math.sin(latitude * 13 + Math.sin(longitude * 4 + latitude * 5) * 2);
      break;
    case "earth": {
      const land =
        Math.sin(longitude * 3 + Math.cos(latitude * 4)) +
        0.6 * Math.sin(longitude * 7 - latitude * 6) +
        0.3 * detail;
      color = land > 0.35 ? [93, 143, 83] : [42, 111, 195];
      if (
        Math.abs(latitude) > 1.18 ||
        Math.sin(longitude * 11 + latitude * 17 + Math.sin(longitude * 3) * 3) >
          0.86
      )
        color = [222, 232, 222];
      break;
    }
    case "mars":
      brightness =
        0.79 + 0.16 * detail + 0.15 * Math.sin(longitude * 5 - latitude * 7);
      if (Math.abs(latitude) > 1.34) color = [224, 209, 186];
      break;
    case "gas": {
      brightness = 0.82 + 0.15 * wave + 0.05 * detail;
      const spot =
        Math.sin(longitude + 0.5) ** 2 / 0.08 + (latitude - 0.28) ** 2 / 0.015;
      if (spot < 1) color = [188, 91, 55];
      break;
    }
    case "ice":
      brightness = 0.93 + 0.06 * Math.sin(latitude * 13 + longitude);
      break;
    case "blue":
      brightness = 0.84 + 0.13 * wave + 0.06 * detail;
      break;
  }
  return color.map((channel) => channel * brightness);
}

function ring(ctx, cx, cy, radius, front) {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(-0.38);
  for (let band = 0; band < 8; band++) {
    ctx.strokeStyle = ["#d6bd8d", "#b7a078", "#ead6a7", "#85765e"][band % 4];
    ctx.lineWidth = Math.max(0.7, radius * 0.014);
    ctx.beginPath();
    ctx.ellipse(
      0,
      0,
      radius * (1.31 + band * 0.042),
      radius * (0.31 + band * 0.011),
      0,
      front ? 0 : Math.PI,
      front ? Math.PI : Math.PI * 2,
    );
    ctx.stroke();
  }
  ctx.restore();
}

function planetFrame(ctx, surface, planet, time, width, height, opacity) {
  if (!opacity) return;
  ctx.save();
  ctx.globalAlpha = opacity;
  const radius = height * (planet.kind === "saturn" ? 0.32 : 0.35);
  const cx = width * 0.5,
    cy = height * 0.49;
  if (planet.kind === "saturn") ring(ctx, cx, cy, radius, false);
  const size = Math.ceil(radius * 2) + 2;
  if (surface.width !== size) surface.width = surface.height = size;
  const source = surface.getContext("2d");
  const image = source.createImageData(size, size);
  const rotation = time * 0.22;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const nx = (x - size / 2) / radius,
        ny = (y - size / 2) / radius;
      const squared = nx * nx + ny * ny;
      if (squared >= 1) continue;
      const nz = Math.sqrt(1 - squared);
      const longitude = Math.atan2(nx, nz) + rotation;
      const latitude = Math.asin(ny);
      const color = texture(planet, latitude, longitude);
      const light =
        0.19 + 0.81 * Math.max(0, -0.48 * nx - 0.36 * ny + 0.8 * nz);
      const index = (y * size + x) * 4;
      image.data[index] = color[0] * light;
      image.data[index + 1] = color[1] * light;
      image.data[index + 2] = color[2] * light;
      image.data[index + 3] = Math.min(1, (1 - squared) * radius) * 255;
    }
  }
  source.putImageData(image, 0, 0);
  ctx.drawImage(surface, cx - size / 2, cy - size / 2);
  if (planet.kind === "saturn") ring(ctx, cx, cy, radius, true);
  ctx.restore();
}

export function paintDemo(canvas, time) {
  const ctx = canvas.getContext("2d"),
    w = canvas.width,
    h = canvas.height;
  let surface = surfaces.get(canvas);
  if (!surface) {
    surface = document.createElement("canvas");
    surfaces.set(canvas, surface);
  }
  ctx.fillStyle = "#111711";
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = "#748475";
  [
    [0.15, 0.23],
    [0.83, 0.18],
    [0.19, 0.73],
    [0.81, 0.77],
  ].forEach(([x, y]) => {
    ctx.fillRect(w * x - 1, h * y, 3, 1);
    ctx.fillRect(w * x, h * y - 1, 1, 3);
  });
  const { index, next, blend } = demoState(time);
  planetFrame(ctx, surface, PLANETS[index], time, w, h, 1);
  planetFrame(ctx, surface, PLANETS[next], time, w, h, blend);
  return PLANETS[blend > 0.5 ? next : index].name;
}
