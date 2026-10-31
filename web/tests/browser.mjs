import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium, webkit } from 'playwright';
import AxeBuilder from '@axe-core/playwright';

process.env.BASE_PATH = '/strok/';
const { createServer } = await import('../scripts/serve.mjs');
const server = createServer();
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://localhost:${server.address().port}/strok/`;
await mkdir(new URL('../test-results/', import.meta.url), { recursive: true });
const errors = [];
let browser;

async function open(context) {
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => { if (!request.url().startsWith(base) && !request.url().startsWith('blob:') && !request.url().startsWith('data:')) errors.push(`Unexpected external request: ${request.url()}`); });
  await page.goto(base);
  await page.locator('body[data-engine=ready]').waitFor({ timeout: 30000 });
  await page.locator('#output[data-frame]').waitFor({ timeout: 30000 });
  return page;
}

async function changedFrame(page, action) {
  const previous = await page.locator('#output').getAttribute('data-frame');
  await action();
  await page.waitForFunction(id => document.querySelector('#output').dataset.frame !== id, previous, { timeout: 15000 });
}

try {
  browser = await chromium.launch({ headless: true, args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'] });
  const desktop = await browser.newContext({ viewport: { width: 1440, height: 1100 }, permissions: ['camera'], acceptDownloads: true });
  await desktop.addInitScript(() => {
    window.__testStreams = [];
    const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia = async constraints => { const stream = await original(constraints); window.__testStreams.push(stream); return stream; };
  });
  const page = await open(desktop);
  assert.equal(await page.locator('#source-label').textContent(), 'DEMO STUDIO');
  assert.equal(await page.evaluate(() => window.__testStreams.length), 0, 'camera permission is never requested on load');
  await page.locator('#pause').click();
  const still = await page.locator('#output').getAttribute('data-frame');
  await page.waitForTimeout(800);
  // One already in-flight frame may finish after freeze; a second interval must hold.
  const frozen = await page.locator('#output').getAttribute('data-frame');
  await page.waitForTimeout(500);
  assert.equal(await page.locator('#output').getAttribute('data-frame'), frozen);
  assert.ok(Number(frozen) >= Number(still));

  for (let effect = 0; effect < 6; effect++) {
    await changedFrame(page, () => page.locator(`[data-effect="${effect}"]`).click());
    assert.equal(await page.locator(`[data-effect="${effect}"]`).getAttribute('aria-pressed'), 'true');
    assert.equal(await page.locator('#notice').isVisible(), false, `effect ${effect} rendered without errors`);
  }
  for (const palette of ['paper', 'amber', 'green', 'pink', 'original']) {
    await page.locator(`[data-palette="${palette}"]`).click();
    assert.equal(await page.locator(`[data-palette="${palette}"]`).getAttribute('aria-pressed'), 'true');
  }
  await changedFrame(page, () => page.locator('#detail').fill('144'));
  assert.match(await page.locator('#render-label').textContent(), /144 × 54/);
  await page.locator('summary').click();
  await changedFrame(page, () => page.locator('#edge').fill('80'));
  await changedFrame(page, () => page.locator('#contrast').fill('25'));
  await changedFrame(page, () => page.locator('#reset').click());
  await page.locator('summary').click();
  await page.locator('#timer').selectOption('0');
  await page.locator('#shutter').click();
  await page.locator('.photo-card').waitFor();
  assert.equal(await page.locator('.photo-card').count(), 1);
  const downloadEvent = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Save photo 1 as PNG' }).click();
  const download = await downloadEvent;
  assert.match(download.suggestedFilename(), /strok-photo-001\.png/);
  const textDownloadEvent = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Save photo 1 as text' }).click();
  assert.match((await textDownloadEvent).suggestedFilename(), /\.txt$/);
  await page.locator('#capture-format').click();
  await page.locator('#shutter').click();
  await page.waitForFunction(() => document.querySelectorAll('.photo-card').length === 2, { timeout: 15000 });
  assert.match(await page.locator('.photo-card img').first().getAttribute('alt'), /three-photo strip/);
  const dimensions = await page.locator('.photo-card img').first().evaluate(image => ({ w: image.naturalWidth, h: image.naturalHeight }));
  assert.ok(dimensions.h > dimensions.w * 2, 'strip stacks three photos');
  await page.locator('#capture-format').click();
  await page.locator('#timer').selectOption('3');
  await page.locator('#shutter').click();
  await page.locator('#countdown').waitFor();
  await page.locator('#shutter').click();
  await page.waitForFunction(() => document.querySelector('#shutter-label').textContent === 'Take a photo');
  assert.equal(await page.locator('.photo-card').count(), 2, 'cancel does not create a photo');
  await page.locator('#camera').click();
  await page.waitForFunction(() => document.querySelector('#source-label').textContent === 'LIVE CAMERA');
  assert.ok(await page.evaluate(() => window.__testStreams.some(stream => stream.getVideoTracks().some(track => track.readyState === 'live'))));
  await changedFrame(page, () => page.locator('#mirror').uncheck());
  await page.locator('#switch-camera').click();
  await page.waitForFunction(() => window.__testStreams.length === 2 && document.querySelector('#source-label').textContent === 'LIVE CAMERA');
  assert.ok(await page.evaluate(() => window.__testStreams[0].getTracks().every(track => track.readyState === 'ended')), 'switch releases old camera');
  await page.locator('#camera').click();
  assert.ok(await page.evaluate(() => window.__testStreams.every(stream => stream.getTracks().every(track => track.readyState === 'ended'))), 'stop releases all tracks');

  const pngBuffer = Buffer.from(await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width = 240; canvas.height = 320;
    const ctx = canvas.getContext('2d'); ctx.fillStyle = '#db825b'; ctx.fillRect(0, 0, 240, 320); ctx.fillStyle = '#e8dfa2'; ctx.beginPath(); ctx.arc(120, 145, 75, 0, Math.PI * 2); ctx.fill();
    return canvas.toDataURL('image/png').split(',')[1];
  }), 'base64');
  await page.locator('#file').setInputFiles({ name: 'portrait.png', mimeType: 'image/png', buffer: pngBuffer });
  await page.waitForFunction(() => document.querySelector('#source-label').textContent === 'YOUR PHOTO');
  await page.locator('#file').setInputFiles({ name: 'broken.png', mimeType: 'image/png', buffer: Buffer.from('not an image') });
  await page.waitForFunction(() => document.querySelector('#notice').textContent.includes('couldn’t open'));
  assert.equal(await page.locator('#source-label').textContent(), 'YOUR PHOTO', 'bad upload preserves the working source');
  await page.locator('#demo').click();
  await page.locator('#clear-photos').click();
  assert.equal(await page.locator('#photos').isVisible(), false);
  await page.locator('#pause').click();
  await page.screenshot({ path: new URL('../test-results/desktop.png', import.meta.url).pathname, fullPage: true });
  const accessibility = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  assert.deepEqual(accessibility.violations.map(v => ({ id: v.id, nodes: v.nodes.map(n => n.target) })), [], 'desktop accessibility');
  console.log('PASS Chromium: all effects, palettes, density, advanced controls, capture, strip, cancellation, downloads, fake camera, flip, release, upload, and accessibility');
  await desktop.close();

  const denied = await browser.newContext();
  await denied.addInitScript(() => { navigator.mediaDevices.getUserMedia = async () => { throw new DOMException('Denied', 'NotAllowedError'); }; });
  const deniedPage = await open(denied);
  await deniedPage.locator('#camera').click();
  await deniedPage.waitForFunction(() => document.querySelector('#notice').textContent.includes('permission'));
  assert.equal(await deniedPage.locator('#source-label').textContent(), 'DEMO STUDIO');
  await denied.close();

  const failure = await browser.newContext();
  const failurePage = await failure.newPage();
  await failurePage.route('**/*.wasm', route => route.abort());
  await failurePage.goto(base);
  await failurePage.locator('body[data-engine=error]').waitFor({ timeout: 15000 });
  assert.equal(await failurePage.getByRole('button', { name: 'Reload the booth' }).isVisible(), true);
  assert.equal(await failurePage.locator('#camera').isDisabled(), true);
  await failure.close();
  console.log('PASS camera-denied and missing-WebAssembly recovery');

  for (const width of [320, 390, 768]) {
    const context = await browser.newContext({ viewport: { width, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2, reducedMotion: 'reduce' });
    const mobile = await open(context);
    assert.ok(await mobile.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), `no overflow at ${width}px`);
    await mobile.locator('#timer').selectOption('0');
    await mobile.locator('#shutter').click();
    await mobile.locator('.photo-card').waitFor();
    await mobile.screenshot({ path: new URL(`../test-results/mobile-${width}.png`, import.meta.url).pathname, fullPage: true });
    const result = await new AxeBuilder({ page: mobile }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    assert.deepEqual(result.violations.map(v => v.id), [], `accessibility at ${width}px`);
    await context.close();
  }
  console.log('PASS 320px / 390px / 768px layouts, reduced motion, photo capture, and accessibility');
  await browser.close(); browser = null;

  browser = await webkit.launch({ headless: true });
  const safari = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, reducedMotion: 'reduce' });
  const safariPage = await open(safari);
  await changedFrame(safariPage, () => safariPage.locator('[data-effect="3"]').click());
  await safariPage.locator('#timer').selectOption('0');
  await safariPage.locator('#shutter').click();
  await safariPage.locator('.photo-card').waitFor();
  assert.ok(await safariPage.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await safariPage.screenshot({ path: new URL('../test-results/webkit-mobile.png', import.meta.url).pathname, fullPage: true });
  console.log('PASS WebKit mobile: native renderer, Braille, photo capture, and layout');
  assert.deepEqual(errors, [], 'no uncaught application errors or remote asset requests');
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
