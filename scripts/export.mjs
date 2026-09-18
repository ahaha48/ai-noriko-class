import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const root = fileURLToPath(new URL('..', import.meta.url));
const source = path.resolve(root, '../AI-HAYATO-Zoom-LP');
const guide = path.resolve(root, '../AI-NORIKO-Learning-Guide');
const output = path.join(root, 'docs');
const sourceRequire = createRequire(path.join(source, 'package.json'));
const ts = sourceRequire('typescript');
const React = sourceRequire('react');
const { renderToStaticMarkup } = sourceRequire('react-dom/server');
const pagePath = path.join(source, 'app/resources/page.tsx');
const text = await fs.readFile(pagePath, 'utf8');
const compiled = ts.transpileModule(text, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, esModuleInterop: true, target: ts.ScriptTarget.ES2022 },
}).outputText;
const module = { exports: {} };
vm.runInNewContext(compiled, { module, exports: module.exports, require: createRequire(pagePath) }, { filename: 'resources-page.cjs' });
let markup = renderToStaticMarkup(React.createElement(module.exports.default));

const documentMap = {
  'AI-NORIKO-Course-Guide.md': 'COURSE_GUIDE.md',
  'AI-NORIKO-Knowledge-Setup.md': 'NORIKO_KNOWLEDGE_SETUP.md',
  'AI-NORIKO-Personal-Playbook.md': 'PERSONAL_PLAYBOOK.md',
  'AI-NORIKO-Team-Playbook.md': 'TEAM_PLAYBOOK.md',
  'AI-NORIKO-Service-Design.md': 'SERVICE_DESIGN.md',
};
const files = [...new Set([...markup.matchAll(/href="\/(AI-NORIKO-[^"/]+)"/g)].map(match => match[1]))];
if (files.length !== 9) throw new Error('Review changed download inventory before publishing');
await fs.mkdir(path.join(output, 'downloads'), { recursive: true });
const manifest = [];
for (const name of files) {
  const bytes = await fs.readFile(path.join(source, 'public', name));
  const target = documentMap[name] ? `downloads/guide/docs/${documentMap[name]}` : `downloads/${name}`;
  await fs.mkdir(path.dirname(path.join(output, target)), { recursive: true });
  await fs.writeFile(path.join(output, target), bytes);
  manifest.push({ name, path: target, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
}
// These are the same reviewed documents/templates already inside the guide ZIP.
// Keeping their relative layout also makes Markdown cross-references resolve.
async function copyGuide(directory, relative = '') {
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const rel = path.join(relative, entry.name);
    if (entry.isDirectory()) { await copyGuide(path.join(directory, entry.name), rel); continue; }
    if (!entry.isFile() || !(entry.name.endsWith('.md') || rel === path.join('course', 'prompts.json'))) throw new Error(`Unexpected guide asset: ${rel}`);
    const destination = path.join(output, 'downloads/guide', rel);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.copyFile(path.join(directory, entry.name), destination);
  }
}
await copyGuide(guide);

// The Windows helper is outside the ZIP so a student need not extract it first.
const starter = manifest.find(asset => asset.name === 'AI-NORIKO-Starter-Kit.zip');
const helperTemplate = await fs.readFile(path.join(root, 'scripts/windows-setup.cmd.in'), 'utf8');
if ((helperTemplate.match(/__STARTER_KIT_SHA256__/g) || []).length !== 1) throw new Error('Expected one pinned ZIP hash');
const helper = helperTemplate.replace('__STARTER_KIT_SHA256__', starter.sha256).replace(/\r?\n/g, '\r\n');
const help = await fs.readFile(path.join(root, 'scripts/windows-download-help.md'), 'utf8');
for (const [name, content] of [['AI-NORIKO-Windows-Setup.cmd', helper], ['AI-NORIKO-Windows-Help.md', help]]) {
  const bytes = Buffer.from(content, 'utf8');
  const target = `downloads/${name}`;
  await fs.writeFile(path.join(output, target), bytes);
  manifest.push({ name, path: target, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
}
const panel = await fs.readFile(path.join(root, 'scripts/windows-panel.html'), 'utf8');
const setupMarker = '<section class="resource-section" id="setup">';
if (!markup.includes(setupMarker)) throw new Error('Setup section moved; review Windows panel placement');
markup = markup.replace(setupMarker, panel + setupMarker)
  .replace('<a href="#setup">共通導入</a>', '<a href="#windows-setup">Windows展開</a><a href="#setup">共通導入</a>')
  .replace('<div class="download-grid">', '<div class="download-grid"><a class="download-card featured" href="#windows-setup"><small>Windows 10・11 / ZIP展開が難しい方へ</small><strong>ダブルクリックでキットを準備</strong><p>補助ファイルがZIPのダウンロードと展開を行います。展開後の本体フォルダをCodexで開きます。</p><span>Windows向けの手順へ →</span></a>');

let css = await fs.readFile(path.join(source, 'app/globals.css'), 'utf8');
css = css.replace('@import "tailwindcss";', '')
  .replaceAll('nav a:not(.nav-cta)', '.site-header nav a:not(.nav-cta)');
css += '\n#windows-setup .button.secondary { color: #08313b; border-color: #78949a; background: transparent; }\n#windows-setup .button:focus-visible { outline: 3px solid #007b8c; outline-offset: 4px; }\n';
const reset = `:root { --font-sans: "Noto Sans JP", "Hiragino Kaku Gothic ProN", "Yu Gothic", Meiryo; --font-display: "Noto Sans JP", "Hiragino Kaku Gothic ProN", "Yu Gothic", Meiryo; }\nhtml { line-height: 1.5; -webkit-text-size-adjust: 100%; } button, input { font: inherit; } button { cursor: pointer; } button:disabled { cursor: wait; } summary { display: list-item; } img { max-width: 100%; }\n`;
await fs.writeFile(path.join(output, 'styles.css'), reset + css);
await fs.copyFile(path.join(root, 'scripts/client.js'), path.join(output, 'script.js'));
function html(prefix) {
  const body = markup.replace(/href="\/(AI-NORIKO-[^"/]+)"/g, (_, name) => {
    const item = manifest.find(asset => asset.name === name);
    if (!item) throw new Error('Unknown download');
    return `href="${prefix}${item.path}"`;
  }).replaceAll('href="/"', 'href="#top"').replace('講義案内へ戻る', '教材ページの先頭へ');
  if (/href="\//.test(body)) throw new Error('Root-relative URL remains');
  return `<!doctype html>\n<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>AI NORIKO｜生徒用 講義資料・導入ガイド</title><meta name="description" content="AI NORIKOの導入手順、21本のコピペ用プロンプト、スターターキット、講義スライド、NORIKOナレッジ導入ガイド。"><meta name="color-scheme" content="light"><link rel="stylesheet" href="${prefix}styles.css"><script src="${prefix}script.js" defer></script></head><body>${body}</body></html>\n`;
}
await fs.writeFile(path.join(output, 'index.html'), html('./'));
await fs.mkdir(path.join(output, 'resources'), { recursive: true });
await fs.writeFile(path.join(output, 'resources/index.html'), html('../'));
await fs.writeFile(path.join(output, '.nojekyll'), '');
await fs.writeFile(path.join(output, 'downloads/manifest.json'), JSON.stringify({ version: '2026-09-19', assets: manifest }, null, 2) + '\n');
console.log(`Exported student page, 21 prompts, ${manifest.length} downloads including the pinned Windows helper, and the reviewed guide documents.`);
