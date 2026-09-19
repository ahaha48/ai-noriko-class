import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// Run against a local docs server or the published project URL. No accounts,
// downloads, installations, or external browser navigations are performed.
const root = fileURLToPath(new URL('..', import.meta.url));
const require = createRequire(import.meta.url);
const playwrightLocation = process.env.NORIKO_PLAYWRIGHT_PATH
  || path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const { chromium } = require(playwrightLocation);
const base = new URL(process.argv[2] || 'http://127.0.0.1:3182/');
if (!base.pathname.endsWith('/')) base.pathname += '/';
const guideURL = new URL('codex-install/', base);
const evidence = path.join(root, '.verification', 'codex-install');
await fs.mkdir(evidence, { recursive: true });
const officialDomains = ['openai.com', 'chatgpt.com', 'apple.com', 'microsoft.com', 'oaistatic.com'];
const browser = await chromium.launch({ headless: true, channel: process.env.NORIKO_TEST_BROWSER_CHANNEL || 'chrome' });

async function assertSelected(page, platform) {
  const other = platform === 'mac' ? 'windows' : 'mac';
  await page.locator(`#tab-${platform}[aria-selected="true"]`).waitFor();
  assert.equal(await page.locator(`#tab-${platform}`).getAttribute('role'), 'tab');
  assert.equal(await page.locator(`#tab-${platform}`).getAttribute('aria-selected'), 'true');
  assert.equal(await page.locator(`#tab-${other}`).getAttribute('aria-selected'), 'false');
  assert.equal(await page.locator(`#codex-install-${platform}`).getAttribute('role'), 'tabpanel');
  assert.equal(await page.locator(`#tab-${platform}`).getAttribute('aria-controls'), `codex-install-${platform}`);
  assert.equal(await page.locator(`#codex-install-${platform}`).isVisible(), true);
  assert.equal(await page.locator(`#codex-install-${other}`).isVisible(), false);
}

async function assertNoOverflow(page, label) {
  const sizes = await page.evaluate(() => ({ width: innerWidth, scroll: document.documentElement.scrollWidth }));
  assert.ok(sizes.scroll <= sizes.width + 1, `${label}: page overflow ${JSON.stringify(sizes)}`);
}

async function assertGuideLinks(page, request) {
  const links = await page.locator('a[href]').evaluateAll(nodes => nodes.map(node => ({
    href: node.href,
    source: node.getAttribute('href'),
    text: node.textContent.trim(),
  })));
  assert.ok(links.length > 3, 'Guide should include downloads and official reference links');
  const checked = new Set();
  for (const link of links) {
    const url = new URL(link.href);
    assert.ok(['https:', 'http:'].includes(url.protocol), `Unexpected link protocol: ${link.source}`);
    if (url.origin !== base.origin) {
      assert.equal(url.protocol, 'https:', `Official external link must use HTTPS: ${link.href}`);
      assert.ok(officialDomains.some(domain => url.hostname === domain || url.hostname.endsWith(`.${domain}`)),
        `Non-official external guide link: ${link.href}`);
      continue;
    }
    assert.ok(url.pathname.startsWith(base.pathname), `Local guide link leaves project: ${link.href}`);
    if (url.pathname === new URL(page.url()).pathname && url.hash) {
      // #mac/#windows are tab deep links, not necessarily element IDs.
      if (!['#mac', '#windows'].includes(url.hash)) {
        assert.ok(await page.locator(`[id=${JSON.stringify(decodeURIComponent(url.hash.slice(1)))}]`).count(),
          `Missing anchor target: ${link.href}`);
      }
    }
    url.hash = '';
    if (checked.has(url.href)) continue;
    checked.add(url.href);
    const response = await request.get(url.href);
    assert.equal(response.status(), 200, `Broken local guide link: ${link.href}`);
  }
}

try {
  for (const width of [1440, 768, 375]) {
    const context = await browser.newContext({ viewport: { width, height: 1000 } });
    const page = await context.newPage();
    const errors = [];
    const failedLocalResponses = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => {
      if (new URL(response.url()).origin === base.origin && response.status() >= 400) {
        failedLocalResponses.push(`${response.status()} ${response.url()}`);
      }
    });

    assert.equal((await page.goto(guideURL.href)).status(), 200);
    await assertSelected(page, 'mac');
    await assertNoOverflow(page, `${width}px Mac`);
    await page.screenshot({ path: path.join(evidence, `mac-${width}.png`), fullPage: true });
    await page.locator('#tab-mac').scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(evidence, `mac-tabs-${width}.png`) });
    await page.locator('#codex-install-mac .install-diagram').screenshot({ path: path.join(evidence, `mac-diagram-${width}.png`) });

    await page.locator('#tab-windows').click();
    await assertSelected(page, 'windows');
    assert.equal(new URL(page.url()).hash, '#windows');
    await assertNoOverflow(page, `${width}px Windows`);
    await page.screenshot({ path: path.join(evidence, `windows-${width}.png`), fullPage: true });
    await page.locator('#tab-windows').scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(evidence, `windows-tabs-${width}.png`) });
    await page.locator('#codex-install-windows .install-diagram').screenshot({ path: path.join(evidence, `windows-diagram-${width}.png`) });

    for (const platform of ['mac', 'windows']) {
      await page.locator(`#tab-${platform}`).click();
      const panel = page.locator(`#codex-install-${platform}`);
      const checks = panel.locator('[data-install-check]');
      const progress = panel.locator('[data-install-progress]');
      assert.equal(await checks.count(), 4, `${platform}: four completion checks`);
      assert.equal(await progress.count(), 1, `${platform}: one progress indicator`);
      assert.match(await progress.textContent(), /0\s*\/\s*4\s*完了/);
      await checks.first().check();
      assert.match(await progress.textContent(), /1\s*\/\s*4\s*完了/);
      const other = platform === 'mac' ? 'windows' : 'mac';
      assert.match(await page.locator(`#codex-install-${other} [data-install-progress]`).textContent(), /0\s*\/\s*4\s*完了/);
      await checks.first().uncheck();
      assert.match(await progress.textContent(), /0\s*\/\s*4\s*完了/);
      for (const check of await checks.all()) await check.check();
      assert.match(await progress.textContent(), /4\s*\/\s*4\s*完了/);
      for (const check of await checks.all()) await check.uncheck();
    }

    // Enter also works if a future revision chooses manual tab activation.
    await page.locator('#tab-mac').focus();
    await page.keyboard.press('ArrowRight');
    assert.equal(await page.locator('#tab-windows').evaluate(node => node === document.activeElement), true);
    await page.keyboard.press('Enter');
    await assertSelected(page, 'windows');
    await page.keyboard.press('Home');
    assert.equal(await page.locator('#tab-mac').evaluate(node => node === document.activeElement), true);
    await page.keyboard.press('Enter');
    await assertSelected(page, 'mac');
    await page.keyboard.press('End');
    assert.equal(await page.locator('#tab-windows').evaluate(node => node === document.activeElement), true);
    await page.keyboard.press('Enter');
    await assertSelected(page, 'windows');
    await page.keyboard.press('ArrowLeft');
    assert.equal(await page.locator('#tab-mac').evaluate(node => node === document.activeElement), true);
    await page.keyboard.press('Enter');
    await assertSelected(page, 'mac');

    for (const platform of ['windows', 'mac']) {
      const response = await page.goto(`${guideURL.href}#${platform}`);
      if (response) assert.equal(response.status(), 200);
      assert.equal(new URL(page.url()).hash, `#${platform}`);
      await assertSelected(page, platform);
      await page.reload();
      await assertSelected(page, platform);
    }

    await page.evaluate(() => {
      window.__norikoPrintCalled = false;
      window.print = () => { window.__norikoPrintCalled = true; };
    });
    await page.locator('[data-print-guide]').click();
    assert.equal(await page.evaluate(() => window.__norikoPrintCalled), true, 'Print control calls window.print');
    await page.emulateMedia({ media: 'print' });
    assert.equal(await page.locator('#codex-install-mac').isVisible(), true, 'Print includes Mac guide');
    assert.equal(await page.locator('#codex-install-windows').isVisible(), true, 'Print includes Windows guide');
    await page.emulateMedia({ media: 'screen' });
    await assertSelected(page, 'mac');

    if (width === 1440) {
      await assertGuideLinks(page, context.request);
      for (const route of [base.href, new URL('resources/', base).href]) {
        assert.equal((await page.goto(route)).status(), 200);
        const entry = page.locator('a[href]').filter({ hasText: /Codex|インストール|アプリ/ });
        const matching = [];
        for (const candidate of await entry.all()) {
          if (new URL(await candidate.getAttribute('href'), page.url()).pathname === guideURL.pathname) matching.push(candidate);
        }
        assert.ok(matching.length, `${route}: visible guide entry`);
        assert.ok(await matching[0].isVisible(), `${route}: guide entry must be visible`);
        await matching[0].click();
        assert.equal(new URL(page.url()).pathname, guideURL.pathname, `${route}: relative guide route`);
        await assertSelected(page, 'mac');
      }
    }

    assert.deepEqual(errors, [], `${width}px: no JavaScript page errors`);
    assert.deepEqual(failedLocalResponses, [], `${width}px: no failed local assets`);
    await context.close();
    console.log(`${width}px: tabs, checklist, deep links, keyboard, print and layout PASS`);
  }

  const fallback = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 375, height: 1000 } });
  const page = await fallback.newPage();
  assert.equal((await page.goto(guideURL.href)).status(), 200);
  assert.equal(await page.locator('#codex-install-mac').isVisible(), true, 'Without JavaScript, Mac guide stays readable');
  assert.equal(await page.locator('#codex-install-windows').isVisible(), true, 'Without JavaScript, Windows guide stays readable');
  assert.ok((await page.locator('#codex-install-mac').textContent()).trim().length > 300);
  assert.ok((await page.locator('#codex-install-windows').textContent()).trim().length > 300);
  await assertNoOverflow(page, '375px without JavaScript');
  await page.screenshot({ path: path.join(evidence, 'no-javascript-375.png'), fullPage: true });
  await fallback.close();
  console.log('No-JavaScript fallback, official links and homepage/resources entries PASS');
} finally {
  await browser.close();
}
