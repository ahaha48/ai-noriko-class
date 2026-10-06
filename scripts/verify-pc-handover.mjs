import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('..', import.meta.url));
const docs = path.join(root, 'docs');
const source = await fs.readFile(path.join(root, 'scripts/pc-handover.html'), 'utf8');
const sha = text => createHash('sha256').update(text).digest('hex');
const base = process.argv[2] ? new URL(process.argv[2]) : null;
if (base && !base.pathname.endsWith('/')) base.pathname += '/';
async function read(relative) {
  if (!base) return fs.readFile(path.join(docs, relative), 'utf8');
  const url = new URL(relative, base);
  const result = await fetch(url, {signal:AbortSignal.timeout(20000)});
  assert.equal(result.status, 200, `${url}: HTTP status`);
  assert.match(result.headers.get('content-type'), /text\/html/i);
  return result.text();
}

for (const file of ['pc-handover/index.html', 'downloads/AI-NORIKO-PC-Handover.html']) {
  const html = await read(file);
  assert.equal(sha(html), sha(source), `${file}: source and output must match`);
  assert(!/\/Users\/|sk-proj-[A-Za-z0-9_-]{12}|AIza[A-Za-z0-9_-]{20}|-----BEGIN .*PRIVATE KEY-----/.test(html), 'No credentials or private paths');
  assert(!/<(?:script|img|iframe)[^>]+src=|<link[^>]+rel="stylesheet"/i.test(html), 'Standalone with no external runtime assets');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(ids.length, new Set(ids).size, 'Unique IDs');
  assert.equal([...html.matchAll(/data-copy="/g)].length,8);
  for (const match of html.matchAll(/href="#([^"]+)"/g)) assert(ids.includes(match[1]), `Missing anchor ${match[1]}`);
}
for (const [file, prefix] of [['index.html','./'],['resources/index.html','../']]) {
  const html = await read(file);
  for (const marker of ['data-pc-handover-nav','data-pc-handover-card','data-pc-handover-download']) {
    assert.equal(html.split(marker).length - 1,1, `${file}: one ${marker}`);
  }
  assert(html.includes(`href="${prefix}pc-handover/"`));
  assert(html.includes(`href="${prefix}downloads/AI-NORIKO-PC-Handover.html" download=`));
  assert(html.includes('AI-NORIKO-Starter-Kit.zip'), 'Original starter kit link retained');
  assert(html.includes('id="P21"'), 'Original prompts retained');
}
console.log(JSON.stringify({status:'PASS',scope:base?.href || 'local',guideSHA256:sha(source),checks:['public guide','standalone download','root links','resources links','no private paths or credential patterns','21 original prompts retained']},null,2));
