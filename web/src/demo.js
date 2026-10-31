// A generated still life, processed by the exact same C++ path as a camera frame.
// It uses no remote photo, stock asset, or permission request.
export function paintDemo(canvas, time) {
  const ctx = canvas.getContext("2d"),
    w = canvas.width,
    h = canvas.height;
  ctx.fillStyle = "#111812";
  ctx.fillRect(0, 0, w, h);
  const centerX = w * (0.5 + Math.sin(time * 0.3) * 0.06),
    centerY = h * 0.48;
  const radius = h * 0.34;
  const gradient = ctx.createRadialGradient(
    centerX - radius * 0.4,
    centerY - radius * 0.5,
    radius * 0.04,
    centerX + radius * 0.3,
    centerY + radius * 0.2,
    radius * 1.2,
  );
  gradient.addColorStop(0, "#fffbd2");
  gradient.addColorStop(0.36, "#ffd99a");
  gradient.addColorStop(0.74, "#edb87d");
  gradient.addColorStop(1, "#b47c4b");
  ctx.save();
  ctx.beginPath();
  ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
  ctx.clip();
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = "#181e17";
  ctx.lineWidth = Math.max(1.2, w * 0.006);
  for (let line = -9; line <= 9; line++) {
    ctx.beginPath();
    for (let step = 0; step <= 80; step++) {
      const y = centerY - radius + (step / 40) * radius;
      const relativeY = (y - centerY) / radius;
      const bend = Math.sqrt(Math.max(0, 1 - relativeY ** 2));
      const x = centerX + Math.sin(line * 0.16 + time * 0.22) * radius * bend;
      step === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
  ctx.restore();
  ctx.save();
  ctx.translate(w * 0.51, h * 0.51);
  ctx.rotate(-0.38);
  ctx.strokeStyle = "#ecf0c5";
  ctx.lineWidth = w * 0.012;
  ctx.beginPath();
  ctx.ellipse(0, 0, radius * 1.51, radius * 0.31, 0, 0, Math.PI);
  ctx.stroke();
  ctx.strokeStyle = "#789675";
  ctx.lineWidth = w * 0.005;
  ctx.beginPath();
  ctx.ellipse(0, 0, radius * 1.59, radius * 0.36, 0, 0, Math.PI);
  ctx.stroke();
  ctx.restore();
  ctx.fillStyle = "#c4d2b2";
  [
    [0.19, 0.27],
    [0.78, 0.25],
    [0.81, 0.72],
    [0.24, 0.72],
  ].forEach(([x, y], i) => {
    const shift = Math.sin(time * 0.4 + i) * h * 0.01;
    ctx.fillRect(w * x - 1, h * y + shift, 3, 1);
    ctx.fillRect(w * x, h * y + shift - 1, 1, 3);
  });
}
