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
const release = JSON.parse(await fs.readFile(path.join(output, 'downloads/release.json'), 'utf8'));
const course = JSON.parse(await fs.readFile(path.join(guide, 'course/prompts.json'), 'utf8'));
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
const pageRequire = createRequire(pagePath);
vm.runInNewContext(compiled, { module, exports: module.exports, require: (name) => name === './prompts.json' ? course : pageRequire(name) }, { filename: 'resources-page.cjs' });
let markup = renderToStaticMarkup(React.createElement(module.exports.default));
markup = markup.replaceAll('キット v1.1.0', `キット v${release.version}`)
  .replaceAll('全員共通 / v1.1.0', `全員共通 / v${release.version}`)
  .replaceAll('2026.09.18 改訂', '2026.09.19 改訂');

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
  let from = path.join(source, 'public', name);
  if (documentMap[name]) from = path.join(guide, 'docs', documentMap[name]);
  if (name.endsWith('.zip')) from = path.join(output, 'downloads', name);
  if (name === 'AI-NORIKO-Copy-Paste-Prompts.txt') from = path.join(guide, 'docs/PROMPTS.md');
  const bytes = await fs.readFile(from);
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
const multiBytes = await fs.readFile(path.join(guide, 'docs/MULTIPLE_INSTALLS.md'));
manifest.push({ name: 'AI-NORIKO-Multiple-Installs.md', path: 'downloads/guide/docs/MULTIPLE_INSTALLS.md', bytes: multiBytes.length, sha256: crypto.createHash('sha256').update(multiBytes).digest('hex') });

// The Windows helper is outside the ZIP so a student need not extract it first.
const starter = manifest.find(asset => asset.name === 'AI-NORIKO-Starter-Kit.zip');
if (starter.sha256 !== release.sha256) throw new Error('Run package-downloads.py before export: release/ZIP mismatch');
const helperTemplate = await fs.readFile(path.join(root, 'scripts/windows-setup.cmd.in'), 'utf8');
if ((helperTemplate.match(/__STARTER_KIT_SHA256__/g) || []).length !== 1) throw new Error('Expected one pinned ZIP hash');
const helper = helperTemplate.replace('__STARTER_KIT_SHA256__', starter.sha256)
  .replace('__STARTER_KIT_URL__', `https://ahaha48.github.io/ai-noriko-class/${release.starterKit}`).replace(/\r?\n/g, '\r\n');
const help = await fs.readFile(path.join(root, 'scripts/windows-download-help.md'), 'utf8');
for (const [name, content] of [['AI-NORIKO-Windows-Setup.cmd', helper], ['AI-NORIKO-Windows-Help.md', help]]) {
  const bytes = Buffer.from(content, 'utf8');
  const target = `downloads/${name}`;
  await fs.writeFile(path.join(output, target), bytes);
  manifest.push({ name, path: target, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
}
const panel = await fs.readFile(path.join(root, 'scripts/windows-panel.html'), 'utf8');
const instancesPanel = await fs.readFile(path.join(root, 'scripts/instances-panel.html'), 'utf8');
const setupMarker = '<section class="resource-section" id="setup">';
if (!markup.includes(setupMarker)) throw new Error('Setup section moved; review Windows panel placement');
markup = markup.replace(setupMarker, panel + instancesPanel + setupMarker)
  .replace('<a href="#setup">共通導入</a>', '<a href="#windows-setup">Windows展開</a><a href="#setup">共通導入</a>')
  .replace('<a href="#noriko-knowledge">', '<a href="#multiple-installs">複数導入</a><a href="#noriko-knowledge">')
  .replace('本体、導入説明、個人・企業の発展資料、21本のプロンプト、記入テンプレートを同梱。', 'v1.2.0：フォルダ別データ分離に対応。本体・複数導入ガイド・21本のプロンプトを同梱。旧ZIPは取り直してください。')
  .replace('基本操作、個人秘書、会社の相談役、追加開発、導入支援の考え方を説明します。', '基本操作の9月18日版。複数導入と保存先については、このページのv1.2補足と最新版ガイドを優先してください。')
  .replace('<div class="download-grid">', '<div class="download-grid"><a class="download-card featured" href="#windows-setup"><small>Windows 10・11 / ZIP展開が難しい方へ</small><strong>ダブルクリックでキットを準備</strong><p>補助ファイルがZIPのダウンロードと展開を行います。展開後の本体フォルダをCodexで開きます。</p><span>Windows向けの手順へ →</span></a>');

const appCard = /<a class="download-card featured" href="https:\/\/learn\.chatgpt\.com\/docs\/app"[^>]*>[\s\S]*?<\/a>/g;
if ([...markup.matchAll(appCard)].length !== 1) throw new Error('Review Codex app card before replacing its guide link');
markup = markup.replace(appCard, '<a class="download-card featured" href="__CODEX_INSTALL_GUIDE__"><small>はじめての方は、ここから / Mac・Windows別</small><strong>Codexをインストールして開く</strong><p>ダウンロード後の操作、アプリ一覧からの起動、ログインまで。OSをタブで切り替え、図付きの手順で確認できます。</p><span>インストール・起動ガイド →</span></a>')
  .replace('<a href="#downloads">準備</a>', '<a href="__CODEX_INSTALL_GUIDE__">Codex導入</a><a href="#downloads">準備</a>')
  .replace('<a class="button primary" href="#downloads">教材を準備する</a>', '<a class="button primary" href="__CODEX_INSTALL_GUIDE__">まずCodexを準備する</a><a class="button secondary" href="#downloads">教材をダウンロード</a>');

let css = await fs.readFile(path.join(source, 'app/globals.css'), 'utf8');
css = css.replace('@import "tailwindcss";', '')
  .replaceAll('nav a:not(.nav-cta)', '.site-header nav a:not(.nav-cta)');
css += '\n#windows-setup .button.secondary { color: #08313b; border-color: #78949a; background: transparent; }\n#windows-setup .button:focus-visible { outline: 3px solid #007b8c; outline-offset: 4px; }\n';
const reset = `:root { --font-sans: "Noto Sans JP", "Hiragino Kaku Gothic ProN", "Yu Gothic", Meiryo; --font-display: "Noto Sans JP", "Hiragino Kaku Gothic ProN", "Yu Gothic", Meiryo; }\nhtml { line-height: 1.5; -webkit-text-size-adjust: 100%; } button, input { font: inherit; } button { cursor: pointer; } button:disabled { cursor: wait; } summary { display: list-item; } img { max-width: 100%; }\n`;
await fs.writeFile(path.join(output, 'styles.css'), reset + css);
await fs.copyFile(path.join(root, 'scripts/client.js'), path.join(output, 'script.js'));
const installGuide = path.join(output, 'codex-install');
await fs.mkdir(installGuide, { recursive: true });
for (const [from, to] of [['codex-install.html', 'index.html'], ['codex-install.css', 'style.css'], ['codex-install.js', 'script.js']]) {
  await fs.copyFile(path.join(root, 'scripts', from), path.join(installGuide, to));
}
function html(prefix) {
  const body = markup.replace(/href="\/(AI-NORIKO-[^"/]+)"/g, (_, name) => {
    const item = manifest.find(asset => asset.name === name);
    if (!item) throw new Error('Unknown download');
    return `href="${prefix}${item.path}"`;
  }).replaceAll('__CODEX_INSTALL_GUIDE__', `${prefix}codex-install/`)
    .replaceAll('href="/"', 'href="#top"').replace('講義案内へ戻る', '教材ページの先頭へ');
  if (/href="\//.test(body)) throw new Error('Root-relative URL remains');
  return `<!doctype html>\n<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>AI NORIKO｜生徒用 講義資料・導入ガイド</title><meta name="description" content="AI NORIKOの導入手順、21本のコピペ用プロンプト、スターターキット、講義スライド、NORIKOナレッジ導入ガイド。"><meta name="color-scheme" content="light"><link rel="stylesheet" href="${prefix}styles.css"><script src="${prefix}script.js" defer></script></head><body>${body}</body></html>\n`;
}
await fs.writeFile(path.join(output, 'index.html'), html('./'));
await fs.mkdir(path.join(output, 'resources'), { recursive: true });
await fs.writeFile(path.join(output, 'resources/index.html'), html('../'));
await fs.writeFile(path.join(output, '.nojekyll'), '');
await fs.writeFile(path.join(output, 'downloads/manifest.json'), JSON.stringify({ version: '2026-09-19', kitVersion: release.version, release: release.starterKit, assets: manifest }, null, 2) + '\n');
console.log(`Exported student page, 21 prompts, ${manifest.length} downloads including the pinned Windows helper, and the reviewed guide documents.`);
