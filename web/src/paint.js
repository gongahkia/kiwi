import { resolvePalette } from "./model.js";

const colors = new Map();
function hexRgb(value) {
  return [
    parseInt(value.slice(1, 3), 16),
    parseInt(value.slice(3, 5), 16),
    parseInt(value.slice(5, 7), 16),
  ];
}
function cellColor(color, palette) {
  const key = `${palette}:${color}`;
  if (colors.has(key)) return colors.get(key);
  const selected = resolvePalette(palette);
  let result;
  if (!selected.ink) result = `#${color.toString(16).padStart(6, "0")}`;
  else {
    const r = (color >>> 16) & 255,
      g = (color >>> 8) & 255,
      b = color & 255;
    const luminance = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 255;
    const bg = hexRgb(selected.background),
      ink = hexRgb(selected.ink);
    result = `rgb(${bg.map((v, i) => Math.round(v + (ink[i] - v) * luminance)).join(",")})`;
  }
  if (colors.size > 8192) colors.clear();
  colors.set(key, result);
  return result;
}

function paintBraille(context, glyph, x, y, width, height) {
  const bits = glyph - 0x2800;
  const positions = [
    [0, 0],
    [0, 1],
    [0, 2],
    [1, 0],
    [1, 1],
    [1, 2],
    [0, 3],
    [1, 3],
  ];
  const radius = Math.min(width / 5.5, height / 11);
  for (let bit = 0; bit < 8; bit++) {
    if (!(bits & (1 << bit))) continue;
    context.beginPath();
    context.arc(
      x + width * (positions[bit][0] ? 0.72 : 0.28),
      y + (height * (positions[bit][1] + 0.5)) / 4,
      radius,
      0,
      Math.PI * 2,
    );
    context.fill();
  }
}

export function paintCells(canvas, frame, palette = "original", width = 960) {
  const { cells, columns, rows } = frame;
  const cellWidth = width / columns,
    cellHeight = cellWidth * 2;
  const height = Math.round(rows * cellHeight);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = resolvePalette(palette).background;
  ctx.fillRect(0, 0, width, height);
  ctx.font = `${cellHeight * 0.83}px "Strok Mono", monospace`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  for (let row = 0; row < rows; row++) {
    for (let column = 0; column < columns; column++) {
      const index = (row * columns + column) * 3;
      const glyph = cells[index],
        fg = cells[index + 1],
        bg = cells[index + 2];
      const x = column * cellWidth,
        y = row * cellHeight;
      if (bg !== 0) {
        ctx.fillStyle = cellColor(bg, palette);
        ctx.fillRect(x, y, Math.ceil(cellWidth), Math.ceil(cellHeight));
      }
      if (glyph === 32 || glyph === 0x2800) continue;
      ctx.fillStyle = cellColor(fg, palette);
      if (glyph >= 0x2800 && glyph <= 0x28ff)
        paintBraille(ctx, glyph, x, y, cellWidth, cellHeight);
      else if (glyph === 0x2580)
        ctx.fillRect(x, y, Math.ceil(cellWidth), cellHeight / 2);
      else if (glyph === 0x2584)
        ctx.fillRect(
          x,
          y + cellHeight / 2,
          Math.ceil(cellWidth),
          cellHeight / 2,
        );
      else if (glyph === 0x2588)
        ctx.fillRect(x, y, Math.ceil(cellWidth), Math.ceil(cellHeight));
      else
        ctx.fillText(
          String.fromCodePoint(glyph),
          x + cellWidth / 2,
          y + cellHeight * 0.49,
        );
    }
  }
}

export function makePrint(
  frames,
  { palette, effect, number, date = new Date() },
) {
  const width = frames.length > 1 ? 720 : 1200;
  const padding = Math.round(width * 0.04),
    contentWidth = width - 2 * padding;
  const frameHeight = Math.round(contentWidth * 0.75);
  const footer = Math.round(width * 0.1);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = padding + (frameHeight + padding) * frames.length + footer;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#f4f1e8";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  const image = document.createElement("canvas");
  frames.forEach((frame, index) => {
    paintCells(image, frame, palette, contentWidth);
    ctx.drawImage(
      image,
      padding,
      padding + (frameHeight + padding) * index,
      contentWidth,
      frameHeight,
    );
  });
  const baseline = canvas.height - footer * 0.52;
  ctx.fillStyle = "#333532";
  ctx.textBaseline = "middle";
  ctx.font = `${width * 0.032}px "Strok Mono", monospace`;
  ctx.fillText("[ strok ]", padding, baseline);
  ctx.font = `${width * 0.012}px "Strok Mono", monospace`;
  ctx.textAlign = "right";
  ctx.fillText(
    `${effect.toUpperCase()} / NO. ${String(number).padStart(3, "0")} / ${date.toISOString().slice(0, 10)}`,
    width - padding,
    baseline,
  );
  return canvas;
}
