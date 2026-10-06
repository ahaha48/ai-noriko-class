import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Only the reviewed public guide is copied; no personal backup data is used.
export async function exportPCHandover(root) {
  const docs = path.join(root, 'docs');
  const source = await fs.readFile(path.join(root, 'scripts/pc-handover.html'), 'utf8');
  if (!source.includes('M07｜確認結果') || source.includes('/Users/')) {
    throw new Error('Review PC handover guide content before publishing');
  }
  const updates = [];
  for (const [file, prefix] of [['index.html', './'], ['resources/index.html', '../']]) {
    const filename = path.join(docs, file);
    let html = await fs.readFile(filename, 'utf8');
    if (!html.includes('data-pc-handover-nav')) {
      const marker = '<a href="#multiple-installs">複数導入</a>';
      if (!html.includes(marker)) throw new Error(`Missing navigation marker: ${file}`);
      html = html.replace(marker, marker + `<a data-pc-handover-nav href="${prefix}pc-handover/">PC引き継ぎ</a>`);
    }
    if (!html.includes('data-pc-handover-card')) {
      const marker = '<div class="download-grid">';
      if (!html.includes(marker)) throw new Error(`Missing download section: ${file}`);
      const cards = `<a class="download-card" data-pc-handover-card href="${prefix}pc-handover/"><small>PCを買い替えた・旧PCが使えなくなった方へ</small><strong>AI NORIKOのPC引き継ぎガイド</strong><p>旧PC・バックアップの有無で手順を選択。Mac／Windows別の説明と、Codexに貼る指示文を用意しています。</p><span>引き継ぎの手順を見る →</span></a><a class="download-card" data-pc-handover-download href="${prefix}downloads/AI-NORIKO-PC-Handover.html" download="AI-NORIKO-PC-Handover.html"><small>ファイルで受け取りたい方へ / 単体HTML</small><strong>PC引き継ぎガイドを保存</strong><p>保存したファイルをブラウザーで開いて使えます。手順書のみで、個人データや自動復元機能は含みません。</p><span>HTMLファイルをダウンロード ↓</span></a>`;
      html = html.replace(marker, marker + cards);
    }
    updates.push([filename, html]);
  }
  await fs.mkdir(path.join(docs, 'pc-handover'), {recursive:true});
  await fs.mkdir(path.join(docs, 'downloads'), {recursive:true});
  await fs.writeFile(path.join(docs, 'pc-handover/index.html'), source);
  await fs.writeFile(path.join(docs, 'downloads/AI-NORIKO-PC-Handover.html'), source);
  for (const [filename, html] of updates) await fs.writeFile(filename, html);
  console.log('Exported public PC handover guide, standalone HTML download, and student-page links.');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await exportPCHandover(fileURLToPath(new URL('..', import.meta.url)));
}
