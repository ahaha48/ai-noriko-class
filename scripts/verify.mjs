import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('..', import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.NORIKO_PLAYWRIGHT_PATH || 'playwright');
const base = process.argv[2] || 'http://127.0.0.1:3181/';
const expected = JSON.parse(await fs.readFile(path.join(root, 'docs/downloads/guide/course/prompts.json'), 'utf8')).prompts;
const manifest = JSON.parse(await fs.readFile(path.join(root, 'docs/downloads/manifest.json'), 'utf8'));
const evidence = path.join(root, '.verification');
await fs.mkdir(evidence, { recursive: true });
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
try {
  for (const width of [1440, 375, 768]) {
    const context = await browser.newContext({ viewport: { width, height: 1000 }, permissions: ['clipboard-read', 'clipboard-write'] });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    assert.equal((await page.goto(base)).status(), 200);
    assert.equal(await page.locator('.resource-prompt').count(), 21);
    assert.equal(await page.locator('#P01').getAttribute('open'), '');
    for (const prompt of expected) assert.equal(await page.locator(`#${prompt.id} pre code`).textContent(), prompt.text);
    assert.ok(await page.locator('.resource-index a').first().isVisible(), 'Mobile navigation must remain visible');
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'No page overflow');
    await page.screenshot({ path: path.join(evidence, `home-${width}.png`) });
    await page.locator('a[href="#P21"]').click();
    await page.locator('#P21[open]').waitFor();
    assert.equal(await page.locator('#P21').getAttribute('open'), '');
    await page.locator('#P21 button').click();
    await page.getByRole('status').filter({ hasText: 'コピーしました' }).waitFor();
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), expected.find(p => p.id === 'P21').text);
    await page.locator('#P21').screenshot({ path: path.join(evidence, `p21-${width}.png`) });
    if (width === 1440) {
      for (const asset of manifest.assets) {
        const response = await context.request.get(new URL(asset.path, base).href);
        assert.equal(response.status(), 200, asset.path);
        assert.equal(crypto.createHash('sha256').update(await response.body()).digest('hex'), asset.sha256, asset.path);
      }
      const alias = new URL('resources/', base).href;
      assert.equal((await page.goto(alias)).status(), 200);
      assert.equal(await page.locator('.resource-prompt').count(), 21);
      for (const href of await page.locator('a[download]').evaluateAll(els => [...new Set(els.map(el => el.href))])) {
        assert.equal((await context.request.get(href)).status(), 200, href);
      }
      await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { value: { writeText: async () => { throw Error('test denial'); } }, configurable: true }));
      await page.locator('#P01 button').click();
      await page.locator('#P01 [role="status"]').filter({ hasText: 'コピーできませんでした' }).waitFor();
    }
    assert.deepEqual(errors, []);
    await context.close();
    console.log(`${width}px: prompts, navigation, clipboard and layout PASS`);
  }
  console.log('All 9 downloads match verified files; compatibility route and copy fallback PASS');
} finally { await browser.close(); }
