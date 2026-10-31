export const EFFECTS = ['Structure', 'Classic', 'Crosshatch', 'Braille', 'Blocks', 'Stipple'];
export const PALETTES = {
  original: { name: 'Original', background: '#111711' },
  paper: { name: 'Ink on paper', background: '#eee9da', ink: '#2c352c' },
  amber: { name: 'Amber terminal', background: '#201b12', ink: '#f1ba66' },
  green: { name: 'Green phosphor', background: '#111a13', ink: '#b4d38b' },
  pink: { name: 'Pink & plum', background: '#291c2b', ink: '#f0a9cb' },
};
export const DEFAULTS = Object.freeze({ effect: 0, columns: 96, edge: 50, contrast: 0, stable: true, palette: 'original' });

export function normalizeOptions(options = {}) {
  const number = (value, fallback, min, max) => Number.isFinite(Number(value)) ? Math.min(max, Math.max(min, Number(value))) : fallback;
  return {
    effect: Math.round(number(options.effect, 0, 0, 5)),
    columns: Math.round(number(options.columns, 96, 48, 144) / 12) * 12,
    edge: number(options.edge, 50, 0, 100),
    contrast: number(options.contrast, 0, 0, 100),
    stable: options.stable !== false,
    palette: Object.hasOwn(PALETTES, options.palette) ? options.palette : 'original',
  };
}

export function rendererOptions(options) {
  const normalized = normalizeOptions(options);
  const columns = normalized.columns;
  return {
    columns,
    rows: Math.round(columns * 3 / 8),
    effect: normalized.effect,
    edge: 0.3 - normalized.edge * 0.0028,
    contrast: normalized.contrast * 0.025,
    stable: normalized.stable,
  };
}

export function cellsToText(cells, columns, rows) {
  const lines = [];
  for (let y = 0; y < rows; y++) {
    let line = '';
    for (let x = 0; x < columns; x++) line += String.fromCodePoint(cells[(y * columns + x) * 3]);
    lines.push(line);
  }
  return lines.join('\n');
}

export function cameraErrorMessage(error) {
  switch (error?.name) {
    case 'NotAllowedError': case 'PermissionDeniedError': return 'Camera permission wasn’t granted. Allow camera access in your browser’s site settings, or upload a photo instead.';
    case 'NotFoundError': case 'DevicesNotFoundError': return 'No camera was found. Connect a camera or upload a photo to use the booth.';
    case 'NotReadableError': case 'TrackStartError': return 'Your camera is busy or unavailable. Close other apps using it, then try again. You can also upload a photo.';
    case 'OverconstrainedError': return 'That camera isn’t available. Try the other camera or upload a photo.';
    case 'SecurityError': return 'Your browser blocked camera access. Open this page directly over HTTPS, or upload a photo.';
    default: return 'We couldn’t start your camera. Try again, or upload a photo instead.';
  }
}

export function fitRect(sourceWidth, sourceHeight, width, height, cover = false) {
  if (![sourceWidth, sourceHeight, width, height].every(value => Number.isFinite(value) && value > 0)) throw new RangeError('Image dimensions must be positive');
  const scale = (cover ? Math.max : Math.min)(width / sourceWidth, height / sourceHeight);
  return { x: (width - sourceWidth * scale) / 2, y: (height - sourceHeight * scale) / 2, width: sourceWidth * scale, height: sourceHeight * scale };
}
