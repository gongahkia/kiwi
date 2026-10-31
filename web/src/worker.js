import createStrok from '../wasm/strok.mjs';
import { rendererOptions } from './model.js';

let module;
let handle = 0;
let buffer = 0;
let capacity = 0;
let key = '';
let lastDimensions = '';

const ready = createStrok({ locateFile: file => new URL(`../wasm/${file}`, import.meta.url).href }).then(instance => {
  module = instance;
  self.postMessage({ type: 'ready' });
}).catch(error => { self.postMessage({ type: 'error', fatal: true, message: 'The character engine could not load. Check your connection and reload the page.', detail: String(error) }); });

function errorMessage() { return module.UTF8ToString(module._strok_web_error()) || 'The frame could not be rendered.'; }

self.onmessage = async ({ data }) => {
  await ready;
  if (!module) return;
  try {
    if (data.type === 'reset') {
      if (handle) module._strok_web_reset(handle);
      return;
    }
    if (data.type !== 'render') return;
    const { width, height, rgba, options, id, epoch } = data;
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 || width > 1024 || height > 1024 || !(rgba instanceof ArrayBuffer) || rgba.byteLength !== width * height * 4) throw new Error('Invalid source image');
    const config = rendererOptions(options), nextKey = JSON.stringify(config);
    if (nextKey !== key || !handle) {
      const next = module._strok_web_create(config.columns, config.rows, config.effect, config.edge, config.contrast, Number(config.stable));
      if (!next) throw new Error(errorMessage());
      if (handle) module._strok_web_destroy(handle);
      handle = next;
      key = nextKey;
    }
    const dimensions = `${width}x${height}`;
    if (lastDimensions !== dimensions) module._strok_web_reset(handle);
    lastDimensions = dimensions;
    if (rgba.byteLength > capacity) {
      const next = module._malloc(rgba.byteLength);
      if (!next) throw new Error('Not enough memory to process this frame. Try a lower character density.');
      if (buffer) module._free(buffer);
      buffer = next; capacity = rgba.byteLength;
    }
    module.HEAPU8.set(new Uint8Array(rgba), buffer);
    const start = performance.now();
    if (!module._strok_web_render(handle, buffer, width, height, rgba.byteLength)) throw new Error(errorMessage());
    const count = module._strok_web_cell_count(handle), pointer = module._strok_web_cells(handle);
    const cells = module.HEAPU32.slice(pointer >>> 2, (pointer >>> 2) + count * 3);
    self.postMessage({ type: 'frame', id, epoch, cells: cells.buffer, columns: config.columns, rows: config.rows, renderMs: performance.now() - start }, [cells.buffer]);
  } catch (error) {
    self.postMessage({ type: 'error', id: data.id, epoch: data.epoch, fatal: false, message: error.message || 'The frame could not be rendered.' });
  }
};
